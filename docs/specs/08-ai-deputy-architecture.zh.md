# 08 — AI 副官架构

**状态：** 设计于 2026-04-27 通过，等待对应实施计划。
**愿景锚点：** `06-full-gameplay-vision.md` §2.2（LLM 驱动 AI 副官作为主输入通道）、§2.3（agent 阶梯：英雄 → 副官 → 小队长 → 普通兵）、§2.4（三层命令）、§2.5（混合副官模式：AI 主、人类执政官副）。
**姊妹文档：** `07-command-system.md`（本规范输出的 `ActionPlan` 的消费方）。
**引擎：** Godot 4.6.x + LLM 服务 HTTPS。LLM 服务优先级（成本优先）：
1. **DeepSeek**（默认——OpenAI 兼容 API；`DEEPSEEK_API_KEY`；同质量下每百万 token 约为 Anthropic Sonnet 1/10）。
2. **Anthropic Messages API**（fallback——仅当 `DEEPSEEK_API_KEY` 缺失而 `ANTHROPIC_API_KEY` 存在时）。
3. **Mock**（最终 fallback，CI / 离线开发用）。

> 本文为 [`08-ai-deputy-architecture.md`](08-ai-deputy-architecture.md) 的中文参考版。两份内容保持同步；如发生冲突，以英文版为权威。

## 1. 目的与范围

愿景 §2.3 命名了四档 agent 阶梯，并在愿景 §7 明确**08 覆盖整条阶梯**而不仅仅是副官。所以 08 定义：

- **副官**层（顶级 LLM agent，每阵营一席，跨局持久身份）。
- **小队长**层（更轻的 LLM agent，每局多个，v1 仅局内 + 跨局持久记忆）。
- **执政官（Archon）**混合模式（人类玩家替代 AI 占据副官席，星际2 执政官风格共享控制权）。
- 两层 LLM agent 共享的基础设施：`DeputyLLMClient` / `BattlefieldSnapshotBuilder` / `ClassifierRouter` / `MemoryStore` / `DeputyPersona` / 失败兜底策略。

普通兵在 08 不带 agency；它们的 `agency_tier` 字段与行为树由 09 拥有。

**范围内：**
- `Deputy` Node——每阵营一个（愿景 §2.5 把战斗官 + 经济官合并为单副官席位）。**愿景 §2.3 明确场外**：副官无 `CharacterBody3D`、无碰撞、无 HP，屏幕上仅 HUD 头像 + 名字 + 语音气泡。它不能被攻击、不会死；玩家与副官的"风险面"纯粹是认知层（"我的副官此刻是否真的在理解我？"）。
- `Captain` Node——更轻的 LLM agent，作为战场单位被实体化；每局多个。
- `ArchonController`——人类接管副官席的控制层（愿景 §2.5）。
- `ClassifierRouter`——把语句变成 `ActionPlan` 的单次 LLM 工具调用门面；副官与可寻址 captain 共用。
- `DeputyLLMClient` interface + `DeepseekClient` 默认 + `AnthropicClient` fallback，副官与 captain 在不同模型档使用同一 interface。
- `BattlefieldSnapshotBuilder`——产出送给 LLM 的 cropped observation（captain 用比副官更小的空间范围）。
- 阶段延迟策略（愿景 §2.4）——pre-plan / tactical / strategic——同时套用副官与 captain 调用。
- `DeputyMemory` Resource 与 `MemoryStore` autoload——副官与 captain 的跨局持久化。愿景 §2.3 说 captains 持有**持久记忆 + 每轴 ≤15% 属性强化 + 完全可阵亡**——记忆层归 08（本规范），属性强化层归 09（查询本规范的记忆）。Captain 的记忆**在 captain 死亡后仍然保留**：同一 captain persona 在后续比赛中再被召唤时，记忆向前承接。
- `DeputyPersona` 与 `CaptainPersona` Resource——name / archetype / voice_style / system-prompt 模板 / trait 数值 / quirks。Captain persona 更轻（更小 prompt、更小模型、更少轶事配额）。
- `Agent.speak(text)` 共享接口（HUD 气泡——副官、captain，甚至英雄 ragdoll-soul 死亡台词，按愿景 §2.3 死亡处理）；语音 TTS 后续接入。
- 失败兜底（超时、网络断、LLM 幻觉、schema 违规、archon 断线）。

**范围外：**
- `ActionPlan` / `TacticalOrder` 的 schema（07）。
- order 的行为树执行（09）。
- 备战 UI（10）。
- 语音 STT/TTS 管线——延后到子文档（08.1 或 11）。v1 仅文本。
- 副官"成长"作为玩法机制（副官随使用变强）——愿景 §2.3 描述了它，设计文档为 08+1。

## 2. 管线（玩家语句 → orders）

```
   ┌──────────────────────────────────────────────────────────────┐
   │ HUD CommandPanel                                             │
   │   用户输入/语音 "我们去打中路"                                │
   └────────────────────┬─────────────────────────────────────────┘
                        │ utterance_submitted(text, source)
                        ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ ClassifierRouter                                             │
   │   通过 BattlefieldSnapshotBuilder 构造 snapshot              │
   │   只寻址唯一副官（严格 A 链，愿景 §2.4）                      │
   │   调用 DeputyLLMClient.submit_plan(                          │
   │     persona = combat_persona,                                │
   │     memory = combat_memory_snapshot,                         │
   │     observation = snapshot,                                  │
   │     utterance = "我们去打中路"                                │
   │   )                                                          │
   │   await Anthropic Messages API                               │
   │   解析单次 tool-call → ActionPlan                            │
   └────────────────────┬─────────────────────────────────────────┘
                        │ plan
                        ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ Deputy.handle_plan(plan)                                     │
   │   按 persona 允许的 type 集合校验                              │
   │   调用 CommandBus.submit_plan(plan)  ─── (07)                │
   │   speak(plan.rationale) → HUD 气泡                           │
   │   写 plan.id 到短期记忆                                       │
   └──────────────────────────────────────────────────────────────┘
```

一条玩家语句产生*零或多*条 `ActionPlan`：
- 单条计划寻址副官（典型）。
- 零条计划（语句是会话性质，如"打得漂亮"）——副官仍说话，不发 order。

## 3–11. 工程契约章节

英文版 §3–§11 涵盖工程实现细节：`Deputy` Node、`ClassifierRouter`、`DeputyLLMClient` interface 与四个实现、阶段延迟策略、`BattlefieldSnapshotBuilder`、`DeputyMemory` 与 `MemoryStore`、`DeputyPersona`、语音延后、失败模式表。中文版仅翻译概念关键章节，其余以英文版为权威——它们是工程契约。

## 11.5 Agent 阶梯总览（与愿景 §2.3 对齐）

08 实现四档中的三档；09 拥有第四档（普通兵）。

| 档位 | 08 中的模块 | 实体形态 | LLM 模型档 | 记忆周期 | 死亡 |
|---|---|---|---|---|---|
| **英雄** | 仅 `Agent.speak`（按 §2.3 死亡台词） | 场上单位 | 无——玩家控制 | n/a | 完全可阵亡，ragdoll + 灵魂 |
| **副官** | `Deputy` / `MemoryStore` / 完整 `DeputyPersona` / 完整 snapshot | **场外**——HUD 头像 + 语音 | 顶级（Sonnet 类） | 持久：场次 / 轶事 / traits / 短语 | **无敌**（仅认知失败面） |
| **小队长** | `Captain` / `CaptainMemory` / `CaptainPersona` / 窄化 snapshot | 场上单位 | 中级（Haiku 类） | 跨局持久；每 captain 一个 `.tres`；≤15%/轴属性强化 | 完全可阵亡，ragdoll + 灵魂 |
| **普通兵** | —（09：行为树，无 agent 层） | 场上单位 | n/a | n/a | 完全可阵亡，仅 ragdoll |

共享基础设施（`ClassifierRouter` / `DeputyLLMClient` / `BattlefieldSnapshotBuilder`）通过 agent 档参数化——同一份代码路径，不同的预算。

## 11.6 小队长（`captain.gd`）

愿景 §2.3 把 Captains 描述为"玩家可以与之培养羁绊的、较小的 LLM agent"。它们在比赛中作为 squad 队长出现，接受副官（或玩家直接，受限于 ControlPolicy）发来的战术 plan，并在这些 plan 之内做自己的微决策。

工程接口与代码细节见英文版 §11.6。本中文版强调以下设计要点：

**Captain 何时调用 LLM：**
1. **接收到寻址自身 `captain_id` 或 `squad_id` 的 `ActionPlan`**——与副官同路径。Captain 可向自己 squad 的单位发出子 order，使用 `CommandBus.submit_orders`（`issuer = CAPTAIN`），不再通过 `submit_plan`——captain 不是 LLM 规划器，而是严格 A 链的叶子 agent。
2. **周期 tick**——每 K 秒（默认 8s，按 persona 可配），captain 用空语句 + `tier_hint = &"tactical"` 调用 `ClassifierRouter`，问 LLM "鉴于当前状态，你想做什么？"——LLM 可输出空 plan（什么都不做）或一条小 plan 应对状况。

**成本控制：**
- captain 用更小模型（Haiku 类），按 `CaptainPersona.preferred_model`。
- captain 的 snapshot 严格裁剪：只有自己 squad + 视野内敌人 + 副官当前高层意图（一句话摘要）。500 token 上限 vs 副官 2000。
- 捕获 LLM 调用频率：每 captain 每 K 秒最多一次自主调用 + 被命令时按需调用。一阵营 5 个 captain、K=8s 自主 = 约 37 次/分钟自主 + 反应触发。愿景 §2.4 已说成本是真约束；12 必须测量。

**Captain 记忆（愿景 §2.3）：**

按愿景锁定，Captains 持有**持久记忆 + 每轴 ≤15% 属性强化 + 完全可阵亡**。记忆在 captain 死后仍保留——同一 captain persona 在后续比赛中再被召唤时记忆向前承接。

字段定义见英文版 §11.6。文件路径 `user://captains/<captain_persona_id>.tres`。`MemoryStore`（已 autoload）增加并行方法 `load_captain` / `save_captain` / `snapshot_captain_for` / `consolidate_captain_after_match`。

**与 09 的属性强化接口：** 09 拥有战斗数值。当 09 spawn 一个 captain 时，它查询 `MemoryStore.snapshot_captain_for(persona_id)` 并在单位实例化时把 `reinforcement_pct` 加到 `preferred_axis`。`0.15` 上限在 08 写入端强制（不在 09），保持上限只在一处。

## 11.7 执政官（Archon）模式（`archon_controller.gd`）

愿景 §2.5：人类玩家可以坐进副官席。同一阵营、同一英雄、同一批 captain——但本来填副官席的 LLM 被另一个玩家用文字/语音指挥替代。

工程接口见英文版 §11.7。本中文版强调：

**对 07 的影响：**
- `CommandBus.submit_plan` 接受 `issuer = PLAYER` + `deputy = "combat"` 的 plan。schema 已经允许，无需 07 改动。
- 07 增加 `ArchonControlPolicy`：与 `FullControl` 相同，但**拒绝**附身席位的 AI 副官 plan。CommandBus 拒绝原因 `&"archon_attached"`。
- 07 的 `OrderTypeRegistry` 控制每个 issuer 可用的 order 类型；archon 继承所在席位的允许列表（无特殊权限）。

**Archon 期间的 LLM 成本：** 该席位副官 LLM 沉默（零 token）。captain 照常运行（它们不在副官席）。

**v1 Archon 实施范围：** 仅出厂 seat-attach 接口与 `ArchonControlPolicy`；真正联网第二玩家输入归 12 网络范畴，**延后**。v1 archon 模式仅本地（同键盘，"按 F2 接管副官"调试开关），足以验证 control-policy 接线。

## 11.8 副官自主度与歧义仲裁

副官的 `deputy_autonomy ∈ [0, 1]` 参数（07 §7 数据定义、本规范 §9 落到 `DeputyPersona`）控制副官在歧义、单位缺失、命令冲突时的运行时行为。

### 11.8.1 三段位

| 段位 | 范围 | 歧义/单位缺失时的行为 |
|---|---|---|
| 谨慎（Cautious） | `≤ 0.3` | 发出澄清请求事件（非 `ActionPlan`），等玩家回答。澄清完成前不发 order。 |
| 平衡（Balanced） | `0.3 — 0.7` | 按最可能解释**执行** + **并行**发澄清事件（"我把 alpha 派去 B4，确认？"）。不阻塞。 |
| 大胆（Bold） | `≥ 0.7` | 按最可能解释执行。仅在新颖/危险情境下澄清（定义为：紧急优先级、不可逆动作、`target_kind = ambiguous` 且 > 3 候选）。 |

### 11.8.2 澄清衰减（重复错误容忍度）

无论哪个段位，副官追踪近期玩家命令质量。如果玩家持续给副官需要反复澄清（或随后被自己撤回/相反命令）的命令，澄清频率会**衰减**——副官逐渐转向"按最可能解释行动"，与名义自主度无关。

衰减模型（v1，08+1 可调优）：

```
clarification_score := 1.0      # 比赛开始时

每次澄清请求：
    clarification_score *= 0.85

每次玩家命令推翻副官刚刚澄清后的动作：
    clarification_score *= 0.7

每个正常运行的 tick：
    clarification_score := min(1.0, clarification_score + 0.001)
```

发出澄清的有效阈值是 `nominal_threshold * clarification_score`。低于 `0.3 * autonomy`，副官完全停止澄清，落到尽力执行——即使在低自主度下。**意图：低自主度（"谨慎"）副官搭配长期粗心的玩家，不会因为一直要澄清而把比赛卡死。**

这是愿景 §2.3 说"副官即角色"的认知层兑现——也是玩家随对局推进能"感觉到"副官在变化的少数数值把手之一。

### 11.8.3 与失败模式的交互

澄清事件**不是** order。它们走 `Deputy.speak()`（HUD 气泡），不走 `CommandBus`。它们不进 order 日志；进入并行的 `clarification_log.ndjson`（回放/调试用）。玩家对澄清的回应作为新语句进入 `ClassifierRouter.handle_utterance`，在那里被记录。

如果澄清超时（玩家 30s 没回应），副官按当前段位的默认动作自动解决：Balanced/Bold——按最可能解释执行；Cautious——丢弃命令（status = `failed`）+ 一句"我等不下去了"的台词。

## 12–15. 后续章节

英文版 §12–§15 包含：边界（与 07 / 09 / 10 / 12 的契约）、文件清单、验证骨架、成本与遥测。本中文参考版不再翻译——它们是工程清单，以英文版为权威。

特别提醒中文读者注意：
- **§15 成本上限**：v1 每次 LLM 调用硬上限 **2000 input tokens**（snapshot + memory + persona 必须放得下）。snapshot 超界时 `BattlefieldSnapshotBuilder` 优先裁掉 `recent_events`、然后离焦点最远的 `enemies`、最后离焦点最远的 `units`。

## 变更控制

- 08 是 06 §2.3 / §2.5 的兑现。修改 §11.5 阶梯表 / §11.6 captain 设计 / §11.7 archon 契约 / §11.8 自主度模型，都需要重新打开 brainstorm。
- §11.8 的自主度衰减函数是 v1 起点，08+1 可调；但"重复错误下衰减"这一抽象语义不可改。
