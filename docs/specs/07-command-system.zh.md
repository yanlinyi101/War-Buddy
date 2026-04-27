# 07 — 命令系统规范

**状态：** 设计于 2026-04-27 通过，等待对应实施计划。
**愿景锚点：** `06-full-gameplay-vision.md` §2.4（三层命令）、§4（空间词汇）。
**姊妹文档：** `08-ai-deputy-architecture.md`（消费本规范的 schema 作为 AI 工具调用契约）。
**引擎：** Godot 4.6.x，仅 GDScript。

> 本文为 [`07-command-system.md`](07-command-system.md) 的中文参考版。两份内容保持同步；如发生冲突，以英文版为权威。

## 1. 目的与范围

愿景 §2.4 把"战术指令 schema"作为 MVP 之后架构的关键产物：每条命令——预案、局内战术、局内战略——在到达执行器之前都要扁平化成同一份数据形态。07 定义这份形态以及分发它的总线。08 定义生产侧 AI；09 定义消费侧执行器。

**范围内：**
- `TacticalOrder` Resource——通用命令记录。
- `ActionPlan` Resource——LLM 输出的包装层，把多条 order 与副官的 rationale、来源信息打包。
- `CommandBus` autoload——所有 order/plan 的单一入口。
- `OrderTypeRegistry` autoload——09 在不改 07 的前提下声明新 order 类型的扩展点。
- `PrePlan` 与 `PrePlanRunner`——备战界面产物的格式与运行时求值器（备战 **UI** 由 10 负责）。
- `ControlPolicy`——决定"谁能下什么命令"的访问规则层。
- 07 寻址字段与 09 实体注册表之间的空间词汇胶合层。
- 来源与回放：每条 order 都能追溯到它的语句 / 预案 / 脚本来源。

**范围外：**
- 行为树与 order 的*执行*语义（09）。
- LLM 服务、prompt、snapshot 构造、副官 persona 文件（08）。
- 备战 UI（10）。
- 语音（待定子文档）。

## 2. 管线（一图、二图）

```
                            ┌─────────────────────────────┐
   玩家语句 ─────►          │ ClassifierRouter (08)       │
   (text/voice/HUD)         │   单次 LLM 工具调用：       │
                            │     submit_plan(json)       │
                            │   返回 ActionPlan{          │
                            │     deputy, tier,           │
                            │     rationale, orders[],    │
                            │     ...                     │
                            │   }                         │
                            └────────────┬────────────────┘
                                         │
   PrePlanRunner ─────► submit_orders   ▼
   (事件触发)               ┌─────────────────────────────┐
                            │ CommandBus (autoload, 07)   │
                            │   校验 (schema +            │
                            │         ControlPolicy +     │
                            │         目标存在性)         │
                            │   路由到 OrderQueue          │
                            │   发出 order_issued /        │
                            │        plan_issued 信号      │
                            └────────────┬────────────────┘
                                         │
                            ┌────────────▼────────────────┐
                            │ Executor (09)               │
                            │   per-unit/squad 行为树      │
                            │   消费队列                    │
                            └─────────────────────────────┘
```

总线只有两个入口：`submit_plan(plan)`（副官 LLM 输出后）与 `submit_orders(orders)`（预案、脚本事件、开发工具）。任何下命令的代码都走其中一个。无替代路径。

**严格 A 链强制（愿景 §2.4）：** 玩家发出的所有 plan 都寻址唯一副官席位。副官分解复杂 plan 时通过再次调用 `submit_plan`（`issuer = DEPUTY` + `target_squad_id` 指向某 captain，每个 captain 带一个 squad）。captain 再通过 `submit_orders`（不是 plan）下发到自己 squad 的单位（`issuer = CAPTAIN`）。总线本身不审查这条链路——这是 `ControlPolicy` 的工作（§9）——但规范流是：

```
玩家语句 ──► ClassifierRouter ──► submit_plan (issuer=PLAYER, deputy="deputy")
                                  │
               Deputy.handle_plan ──► submit_plan (issuer=DEPUTY, target_squad_id=captain_id)
                                      │
                  Captain.handle_plan ──► submit_orders (issuer=CAPTAIN, target_unit_ids=[...])
                                          │
                                    Executor (09)
```

## 3. `TacticalOrder` Resource

字段定义见英文版 §3。中文版只复述要点：

- **身份**：`id`、`type_id`（注册表 key，§7）、`origin`（哪条 §2.4 通道作者）、`issuer`（谁推理）、`deputy`（哪位副官执行）。
- **寻址**：tagged-union 形态——`target_kind` 是判别字段，对应的 `target_*` 字段携带值。fallback 优先级：`position > landmark > grid > squad > units`。
- **类型特化**：`params` 字典，schema 由 `OrderTypeRegistry` 按 type 定义。
- **engagement 修饰**：`posture`（SC2 三档，见 §3.5）。
- **队列与生命周期**：`priority`（用 §3.6 三档常量）、`queue_mode`、`timestamp_ms`、`expires_at_ms`（0 = 永久）。
- **AI 来源**：`rationale`、`confidence`、`parent_intent_id`（命令树根，见 §3.7）。
- **状态**：`status`，唯一可变字段，8 状态线性推进（见 §4）。

### 3.3 `target_kind` 判别字段（tagged-union 语义）

空间词汇 brainstorm 落在了 tagged-union 形状（`{kind, value}`）——LLM 工具调用输出更干净，且 `ambiguous` 这种情况无法用平行字段表达。实现保留平行 `target_*` 字段做向后兼容，并加 `target_kind` 作为标准判别。

| `target_kind` | 携带字段 | 备注 |
|---|---|---|
| `""`（空） | （legacy fallback 链） | 优先级回退 position > landmark > grid > squad > units |
| `position` | `target_position` | 世界坐标 |
| `landmark` | `target_landmark` | 设计师命名地标（由 09 OrderResolver 解析） |
| `grid` | `target_grid` | A1–H8 网格，Vector2i |
| `squad` | `target_squad_id` | 整队 |
| `units` | `target_unit_ids` | 数字 id；执行器快路径 |
| `unit_ref` | `target_unit_ref` | 命名空间字符串，如 `captain:alpha`、`enemy_structure:hq_1` |
| `ambiguous` | `target_ambiguous_candidates` | 多个候选地标/区域；副官自主度（§7 / 08 §11.8）决定如何解析 |
| `self` | （无） | 副官自身（"关注自己"） |
| `hero` | （无） | 指挥官的英雄单位 |
| `param` | `target_param` | 预案参数化占位符，见 §8.4 |

### 3.4 `target_unit_ref` 命名空间

LLM 输出文本而非数字 id，因此对具名实体的引用首选命名空间形式。Resolver（09）在执行时映射到运行时 `target_unit_ids`。

```
captain:<id>             # 具名己方小队长
enemy_unit:<id>          # 具名/已识别的敌方单位
enemy_structure:<id>     # 敌方建筑
friendly_structure:<id>  # 己方建筑
```

匿名普通兵不能直接用 `unit_ref` 引用，要走 `squad`、`grid`、`landmark`。

### 3.5 `posture`——SC2 风格三档姿态

直接抄 SC2：

- `aggressive`——追击并交战射程内敌人
- `stand_ground`——原地驻守，仅还击，不追
- `hold_fire`——即使被攻击也不开火

posture 与 `type_id` 正交：`defend B4 + aggressive` 与 `defend B4 + stand_ground` 都合法且语义不同。默认 `aggressive`。

### 3.6 `priority`——三档语义锚点

`priority: int` 保留开放整数留余地，但标准值就这三个：

| 常量 | 值 | 含义 |
|---|---|---|
| `PRIORITY_ROUTINE` | 0 | 默认。同 captain 上同优先级新命令替换旧命令（旧命令 → `canceled`）。 |
| `PRIORITY_HIGH` | 10 | 立即中断任何 `routine` 命令。 |
| `PRIORITY_EMERGENCY` | 20 | 中断 `routine` 与 `high`；副官可跨 captain 重新分配兵力以满足。 |

副官分解产生的子命令默认继承父命令的 priority，除非显式覆盖。

### 3.7 `parent_intent_id` 与命令树

战略 LLM 把意图分解成多条子 order 时，所有子 order 共享父 `ActionPlan.id`。副官 → captain 分发也用 `parent_intent_id`。回放、HUD 聚合（"5 条子命令完成 3 条"）、局后分析都基于这棵树。状态机（§4）在单条 order 上运行；UI 聚合状态是派生视图。

## 4. 生命周期状态机

8 状态，线性 + 终态分支。**无回退**——状态前进后不能反向。把"换 captain 重派"建模为"取消旧 + 提交新（带 `parent_intent_id` 链接）"，不是反向边。

```
                                              ┌→ completed
                                              │
[pending] → [classifying] → [dispatched] → [executing] ┼→ failed
                                              │
                                              ├→ canceled
                                              │
                                              └→ expired
```

| 状态 | 含义 |
|---|---|
| `pending` | Resource 已构造、`id` 已分配，等待校验/路由 |
| `classifying` | LLM 调用进行中（战术或战略）。预案与脚本 order 跳过此状态。 |
| `dispatched` | 总线已校验、已路由到副官/captain，等待执行器拾取 |
| `executing` | 行为树（09）正在处理 |
| `completed` | 终态：成功 |
| `failed` | 终态：执行中不可恢复错误 |
| `canceled` | 终态：被玩家或更高优先级命令取代 |
| `expired` | 终态：`expires_at_ms` 到期；captain 回退到默认行为，**不**通知玩家 |

**变迁规则：**
- 每次变迁发出 `command_status_changed(order_id, new_state)`（在 `CommandBus` 上）。
- `classifying` 期间被 `canceled` 是允许的（玩家在 LLM 完成前撤回）；LLM 结果到达时丢弃。
- 预案 order 直接 `pending → dispatched`（跳过 `classifying`）。
- 战略 order 在 `classifying` 中可能停留数秒等 LLM 分解完成。

**从 MVP `CommandLogModel` 迁移：** 旧三状态映射为 `submitted→pending`、`received→dispatched`、`pending_execution→executing`。新增 5 个状态（`classifying / completed / failed / canceled / expired`）是叠加的。

## 5–14. 后续章节

英文版包含完整的 `ActionPlan`（§5）、`CommandBus`（§6）、`OrderTypeRegistry`（§7）、Pre-plan format（§8，含 §8.4 参数化与 §8.5 分享码）、`ControlPolicy`（§9）、来源与回放（§10）、空间词汇集成（§11）、边界（§12）、文件清单（§13）、验证骨架（§14）。本中文参考版**只翻译关键概念性章节**（§1–§4），其余以英文版为权威——它们是工程契约，应以代码同语言阅读。

特别提醒中文读者注意以下要点（仍以英文版为准）：

- **§7 OrderTypeRegistry**：v1 出厂注册 `move / attack / stop / hold / use_skill` 五类核心类型。其它愿景级动词（`retreat / regroup / harass / ambush / build / harvest / repair / expand / scout / watch`）由 09 在自己的注册时机加入，不需要改 07。
- **§8.4 预案参数化占位符（4 个，仅此 4 个）**：`<my_main_base>` / `<closest_enemy_base>` / `<hero_position>` / `<deputy_focus>`。再复杂的逻辑写成战略意图（LLM 驱动），不要往参数化里塞。
- **§8.5 分享码**：v1 仅落入 schema 的版本号字段；编解码器是后续单独任务。
- **§9 ControlPolicy**：四种实现 `FullControl / HeroOnly / AssistMode / ArchonControl`。Archon 模式的契约见 08 §11.7。

## 变更控制

- 07 是 06 §2.4 关键产物的兑现。修改 §3 字段集合视为"破坏 schema"，必须连带审查 08（生产侧）与 09（消费侧）。
- §3.5 posture / §3.6 priority / §4 lifecycle / §8.4 占位符 / §8.5 分享码——这些都是本会话 brainstorm 的契约点，改动需重新打开 brainstorm。
