# 测试与回放策略

日期：2026-04-28
项目：War Buddy（Godot 4.6.x）
状态：草案。Spec-only。横切策略文档——不引入产品功能。定义 06–11 行为如何被验证与回放。

> 本文为 [`12-test-and-replay-strategy.md`](12-test-and-replay-strategy.md) 的中文参考版。两份内容保持同步；如发生冲突，以英文版为权威。

母文档：06。
横向引用：07（`.ndjson` order log = 回放输入格式）、08（`MockClient` LLM 测试接口）、09（每单位行为树）、10（UI 冒烟）、11（手感验证日志）。

## 1. 目的

War Buddy 把四类难一起测试的行为揉在一起：

- 确定性 Godot 游戏逻辑（移动、碰撞、命令总线）
- 非确定性 LLM 输出（副官 / 小队长 plan）
- 物理耦合的手感（11）
- 多屏 UI 流程（10）

12 命名每类如何被验证、如何组合成集成与 E2E、保存的对局如何成为可回放 artifact。它**不是**关于加功能的文档；它是关于不退化它们的文档。

12 在 v1 结构上故意做最小——只保留 07–10 落地时的脚手架。更重的表面（性能基准、prompt drift fixture、fuzzer）作为 12+1 条目记录。

## 2. 测试金字塔（三层）

```
                    ┌──────────────┐
                    │ E2E (~5)     │   手动 + 偶尔自动
                    └──────────────┘
                ┌──────────────────────┐
                │ 集成 (~30)           │   GUT、多节点场景 fixture
                └──────────────────────┘
        ┌──────────────────────────────────┐
        │ 单元 (~200+)                     │   GUT、每脚本一份
        └──────────────────────────────────┘
```

| 层 | 数量目标 | 单测时长 | 位置 |
|---|---|---|---|
| **单元** | ~200+（每脚本一份 `test_*.gd`） | < 5 秒 | `godot/tests/unit/` |
| **集成** | ~30（每条跨模块路径一份） | < 30 秒 | `godot/tests/integration/` |
| **E2E** | ~5（完整对局流程） | < 3 分钟 | `godot/tests/e2e/` |

总时长目标：单元套件 < 90 秒；集成 < 10 分钟；E2E 按开关跑，不在每个 PR 上。

## 3. 单元测试（GUT）

### 3.1 每脚本一文件惯例

`godot/scripts/<area>/foo.gd` 下每个脚本必有 `godot/tests/unit/<area>/test_foo.gd`。新脚本无对应测试文件 CI lint 失败。

测试模板：

```gdscript
extends GutTest

const Foo := preload("res://scripts/area/foo.gd")

var _foo: Foo

func before_each() -> void:
    _foo = Foo.new()

func after_each() -> void:
    _foo.queue_free()

func test_default_state() -> void:
    assert_eq(_foo.some_field, expected_default)
```

### 3.2 覆盖率规则

- **纯函数**（验证器、数学、parser）：100% 行 + 分支
- **Resource 类**（`TacticalOrder`、`UnitDef` 等）：`to_dict` / `from_dict` 往返 + 不变量 100%
- **有状态节点**（`CommandBus`、`Deputy` 等）：信号发出路径 100%；其余 ≥70% 行
- **UI 脚本**（10）：仅基本实例化 + 信号连线；可视渲染不做单测

### 3.3 禁止的模式

- 不做真 HTTP 调用（用 08 §5 的 `MockClient`）
- 单测里不用 `await get_tree().create_timer(...)`——时间相关路径用 `gut.simulate(node, frames, delta)`
- 未 mock 时不读 `user://` 路径（测试中 `use_themed_resource_path = true`）
- 不依赖 autoload 加载顺序——直接 `Foo.new()` 实例化

### 3.4 GUT 命令行

```bash
godot4 --headless --path godot -s addons/gut/gut_cmdln.gd \
   -gdir=res://tests/unit -gexit -gjunit_xml_file=res://test-results-unit.xml
```

CI 消费 JUnit XML 暴露失败。

## 4. 集成测试

集成测试验证跨模块路径。每个住在 `godot/tests/integration/test_<path>.gd`，演练：

| 路径 | 涉及模块 |
|---|---|
| `test_utterance_to_order` | ClassifierRouter（mock）→ Deputy → CommandBus → 最近缓冲 |
| `test_pre_plan_match_start` | PrePlanRunner → CommandBus → 最近缓冲 |
| `test_strategic_decomposition` | LLM mock 返回多 order plan → CommandBus 接受每条 + parent_intent_id 链 |
| `test_archon_attached_rejects_llm` | ArchonControlPolicy + LLM 副官 plan → 以 `&"archon_attached"` 拒绝 |
| `test_captain_reinforcement_applied` | MemoryStore 返回 reinforcement → 09 squad 刷出施加轴加成 |
| `test_supply_blocks_production` | 阵营达 supply 上限 → `train` order 拒绝并附 reason |
| `test_command_lifecycle` | submit → classifying → dispatched → executing → completed |
| `test_persona_swap_lock` | match 计数 → 锁 < 5 / 解 ≥ 5 |

每个集成测试启动最小场景 fixture（仅所需 autoload），驱动单条 LLM 边界 mock 的 end-to-end 路径。它们**不**跑完整对局。

## 5. End-to-End 测试

E2E 覆盖完整对局流程。v1 E2E 故意做小（5 个场景），多数手动跑：

| 场景 | 验证什么 |
|---|---|
| `e2e_quick_match_default_persona` | 启动 → 比赛标签 → 开始 → 5 秒对局 → 无脚本错 |
| `e2e_pre_plan_invocation` | 预案触发 `match_start`、副官执行、orders 抵达建筑 |
| `e2e_voice_text_command` | 输 "go to B4" → mock 副官发 move plan → 单位移动 |
| `e2e_archon_handoff` | F2 attach → 人类输入命令 → CommandBus 在 archon 策略下接受 |
| `e2e_match_victory` | 摧毁所有敌方建筑 → MatchState.victory_triggered → 菜单返回 |

E2E 用特殊 `--e2e-mode` 启动 flag：

- 给所有 LLM 席位预绑 `MockClient`，给确定性预制响应
- 禁用 `Time.get_unix_time_from_system()`，改用 tick 计数（确定性）
- 把每次信号 emit 记到 `user://e2e_log.ndjson`，供后续断言用

每次发版打 tag 前手动跑 E2E checklist。Headless 自动化 E2E 是 12+1 增强（Godot --headless 能驱场景但 UI 断言别扭）。

## 6. LLM 测试策略

### 6.1 仅 CI mock

按 Q2 brainstorm 决议：**CI 永不调用真 LLM provider。** 所有测试用 `MockClient`（08 §5）配显式预制响应。

```gdscript
# 一个集成测试里的 mock 设置示例
var mock := MockClient.new()
mock.queue_response(SubmitPlanResponse.new({
    "plans": [some_action_plan],
    "elapsed_seconds": 0.05,
}))
classifier.set_llm_client(mock)
```

这让 CI：

- 快：无网络、无 token 成本
- 稳：API 故障零 flake
- 免费：每个 PR 不花钱
- 受限：对 prompt drift 盲（08 改 prompt 让效果暗中变差不会让 CI 失败）

### 6.2 真 LLM 手动冒烟

`manual/smoke_real_llm.md` checklist 记录 6–10 个发版前要对真 provider 心智健全检查的场景。测试者：

1. 设 `DEEPSEEK_API_KEY`（或 fallback `ANTHROPIC_API_KEY`）
2. 用 `--smoke-real-llm` 启动
3. 走每个场景，肉眼判断响应
4. 在 smoke checklist 里记下偏差

### 6.3 Mock fixture 库

常见测试场景在 `res://tests/fixtures/mock_plans/` 里有可复用 mock 响应。例：

```
res://tests/fixtures/mock_plans/
├── attack_b4.tres            # ActionPlan: deputy=combat, 单 move+attack order
├── eco_boost.tres            # ActionPlan: deputy=combat, 建 supply_depot
├── ambiguous_high_ground.tres  # 含 target_kind=ambiguous 的 ActionPlan
├── refusal_hold_fire.tres    # 仅 rationale 无 orders 的 ActionPlan
└── ...
```

Fixture 用 `preload(...)` 在测试中加载；它们必须经 `to_dict` / `from_dict` 往返，让任何 07 schema break 抓到它们。

## 7. 回放系统

### 7.1 回放 = stub 播放（Q3 = B 决议）

回放**不是**重模拟。它是个 viewer，吞 NDJSON 命令日志（07 §9），把 plan / order / 状态变迁的时间序列对 stub world 渲染出来。

回放显示什么：

- 每个被接受的 plan（时间戳、副官、rationale）
- 每个被接受的 order（时间戳、type、target、force、status）
- 8 状态生命周期变迁
- 被拒 order 的 reason

回放**不**显示什么：

- 重模拟的单位移动（无行为树执行）
- LLM 调用（直接用记录的 plan）
- 物理、粒子、音频
- 实时胜利触发（回放读记录的胜利事件，不重新推导）

### 7.2 回放文件结构

07 §9 的 NDJSON 文件（每场对局一组）：

```
user://order_log/<match_id>.ndjson         # 接受的 orders，每行一条
user://order_log/<match_id>.rejected.ndjson  # 拒绝的 orders + reason
user://order_log/<match_id>.plans.ndjson   # order 抽取前的完整 plans
user://order_log/<match_id>.events.ndjson  # 09 EventBus 事件（unit_died、victory 等）
```

附 manifest：

```json
// user://order_log/<match_id>.manifest.json
{
  "match_id": "match_2026_04_28_abc",
  "started_at": "2026-04-28T14:32:00Z",
  "ended_at": "2026-04-28T14:47:12Z",
  "outcome": "victory",
  "schema_version": 1,
  "deputy_persona": "deputy_veteran",
  "map_id": "forest_lake"
}
```

### 7.3 回放查看场景

`godot/scenes/replay_viewer.tscn`——最小场景，含：

- 地图预览（美术——同局内地图资产）
- 时间轴拖条（拖动跨对局时间）
- 播放/暂停/1×/2×/4× 速度
- Plan 日志（左面板）——按时间显示 plan
- Order 日志（右面板）——显示 order 与状态变迁
- "跳到下一处失败"按钮

Viewer 实例化 stub `CommandBus`，按时间戳从 NDJSON 重发信号；HUD 组件正常订阅，让视觉体验与局内 HUD 一致。

### 7.4 回放调用

```bash
godot4 --path godot scene_replay_viewer.tscn -- --replay <match_id>
```

编辑器中：自定义 dock 列出 `user://order_log/` 下对局，每对局有"播放"按钮。

### 7.5 回放**不**解决什么（12+1）

- 物理耦合 bug 的复现（要完整重模拟——Q3 = A 范畴）
- 联网回放同步（PvP 时代）
- 分支（"如果第 5 分钟我做 X 会发生什么？"）——需要重模拟
- 长对局压缩（NDJSON 啰嗦）

## 8. CI 策略

按 Q4 = C 三级：

### 8.1 Per-PR CI（每次 push，< 5 分钟）

`.github/workflows/ci.yml`（已存在，扩展）：

- Headless boot（已有）
- 文档 lint：禁 Unity 术语 + 验证每份 NN-name.md 有 NN-name.zh.md sibling（新）
- GUT 单元套件（`tests/unit/`）——任何失败即失败
- GUT 集成套件（`tests/integration/`）——任何失败即失败
- 覆盖率门：行 ≥70%，分支 ≥60%（按 Q5）
- Lint：`scripts/` 下每个 `.gd` 必有 sibling 测试文件

失败阻 merge。

### 8.2 Nightly CI（cron `0 3 * * *`）

`.github/workflows/nightly.yml`（新）：

- Per-PR 套件（上方）——重跑求清白
- Headless E2E 套件（`tests/e2e/`）——5 场景以 `--e2e-mode` 跑
- Build artifacts：Linux、Windows、Web 导出——验证 build 成功（不发布）
- 内存泄漏检查：10 分钟 headless 跑，看 RSS 曲线

失败通知（自动开 issue）但不阻进行中的 PR。

### 8.3 Weekly CI（cron `0 5 * * 0`）

`.github/workflows/weekly.yml`（新）：

- 性能基准：目标对局场景，测 tick 速率、帧时间、LLM-mock 延迟、内存峰值
- 多平台 E2E：Linux + Windows + macOS（最后一个延伸；v1 可跳）
- 覆盖率报告：完整 HTML 报告作为 artifact 上传
- 12+1 钩子：prompt-drift fixture 跑（目前为空）

Weekly 结果落到追踪 dashboard（延后——目前先开 issue 附摘要）。

### 8.4 CI **不**跑什么

- 真 LLM 调用（按 Q2）
- 联网测试（暂无联网）
- GPU 渲染测试（CI runner 是无头 / 软件渲染）
- Steam Deck / 移动端验证（延后）

## 9. 覆盖率目标

按 Q5 = (b)：

- **行覆盖：** 在 `godot/scripts/` 全集 ≥ 70%
- **分支覆盖：** 在 `godot/scripts/` 全集 ≥ 60%
- **模块底线：** 核心模块（`scripts/command/`、`scripts/ai/deputy.gd`、`scripts/ai/classifier_router.gd`） ≥ 85% 行

容许的较低层：

- **UI 脚本（`scripts/ui/`）：** ≥ 50% 行——其中很多是视觉，难以有意义地测
- **Persona / 数据 resource：** 无覆盖目标——它们是数据不是代码
- **HTTP client（`scripts/ai/*_client.gd`）：** ≥ 60%——错误路径难 mock，但快乐路径要求

CI lint 检查模块底线，违反即失败。汇总目标作信息（警告但不失败），让正当临时降覆盖的重构不被阻。

## 10. 测试数据与 fixture

### 10.1 Fixture 目录布局

```
godot/tests/fixtures/
├── mock_plans/                 # ActionPlan fixture（§6.3）
├── battlefield_snapshots/      # 冻结快照供 LLM mock 管线测试
├── pre_plans/                  # PrePlan resource 回归测试用
├── replays/                    # 入仓的 replay NDJSON 供 replay-viewer 测试
└── personas/                   # 冻结 persona resource（08 三个的测试变体）
```

### 10.2 Fixture 维护规则

- Fixture 必须经当前 schema 往返（`to_dict` / `from_dict`）
- Schema 变更让 fixture 坏；坏的 PR 同时修 fixture
- Fixture **不**自动重生——人审
- 每个 fixture 有 sibling `.notes.md` 1–3 句解释场景

### 10.3 Mock LLM 预制响应

Mock 响应与回应的 utterance 配对：

```gdscript
# tests/fixtures/mock_plans/attack_b4_response.gd
const UTTERANCE := "alpha 进攻 B4"
const RESPONSE := preload("res://tests/fixtures/mock_plans/attack_b4.tres")
```

`MockClient.from_fixture_dir(...)` 加载所有这样的对，让测试用自然 utterance：

```gdscript
mock_client.from_fixture_dir("res://tests/fixtures/mock_plans/")
classifier.handle_utterance("alpha 进攻 B4", &"text_input")
# 响应自动解析
```

## 11. 测试基础设施文件

### 新文件（本规范定义）

- `godot/tests/unit/` — 目录；每脚本一份 `test_*.gd`
- `godot/tests/integration/` — 8 个集成测试（§4）
- `godot/tests/e2e/` — 5 个 E2E 脚本（§5）
- `godot/tests/fixtures/` — fixture 树（§10）
- `godot/scenes/replay_viewer.tscn` + `godot/scripts/replay/replay_viewer.gd`
- `godot/scripts/replay/replay_loader.gd` — 把 NDJSON 解析到内存流
- `godot/scripts/replay/stub_command_bus.gd` — drop-in CommandBus 从日志重发
- `.github/workflows/nightly.yml`
- `.github/workflows/weekly.yml`
- `manual/smoke_real_llm.md` — 真 LLM 手动 smoke checklist
- `addons/gut/` — GUT 插件（已有——引用）

### 修改文件

- `.github/workflows/ci.yml` — 扩展含单元 + 集成 GUT 跑、覆盖率检查、sibling-test-file lint
- `godot/scripts/bootstrap.gd` — 接受 `--e2e-mode` 与 `--replay <match_id>` flag
- `docs/specs/05-godot-smoke-test-checklist.md` — 与 12 交叉引用作为 checklist 来源

## 12. 边界

- **12 ↔ 07：** 12 读 07 §9 规定的 NDJSON 格式。12 不改 order log 格式。
- **12 ↔ 08：** 12 在所有 CI 测试中用 `MockClient`（08 §5）。Fixture 库住 12 之下。
- **12 ↔ 09：** 12 经集成测试测行为树与单位定义。09 拥有数据；12 拥有"它工作了吗"。
- **12 ↔ 10：** UI 脚本得到 ≥50% 单元测试覆盖；完整 UI E2E 住 12 §5。
- **12 ↔ 11：** 11 的验证日志是与 12 测试**分开**的 artifact。11 是主观 playtest 证据；12 是自动化。它们共存，互不替代。

## 13. 验证（骨架）

12 实现"骨架完成"当且仅当：

1. `addons/gut/` 在位且 `gut_cmdln.gd` 从 headless 启动跑通。
2. `godot/tests/unit/` 含 `godot/scripts/` 下每脚本的测试文件（lint 检查通过）。
3. §4 的 8 个集成测试通过 `gut_cmdln.gd -gdir=res://tests/integration` 全绿。
4. `godot/scenes/replay_viewer.tscn` 启动并接受 `--replay <match_id>` CLI 参数。
5. 录制对局的 NDJSON 在 replay viewer 里加载，时间轴拖条可在它们之间移动。
6. `.github/workflows/ci.yml` 跑单元 + 集成套件，任意测试失败即 fail。
7. 覆盖率 ≥ 70% 行 / ≥ 60% 分支在现有 v0.4.1 codebase 达成（或标记为"目标，尚未达"）。
8. `manual/smoke_real_llm.md` checklist 含至少 6 个场景。

## 14. 开放问题

记录于此，延后到 12+ 修订：

- **Prompt-drift fixture 系统**——Q2 选 A（仅 mock）；未来 Q2 复审可加 nightly 真 LLM fixture 跑检测 prompt 退化。→ 12+1
- **Fuzzer / property test**——随机命令生成测 CommandBus 不变量。→ 12+1
- **完整重模拟回放的确定性**——让回放真重模拟物理 + 行为树，需录 RNG 种子 + LLM 响应。重活；按 Q3 = B 跳过。→ 12+2
- **多人回放同步**——联网时。→ 接联网子文档
- **回放分支**（"如果第 5 分钟..."）——需重模拟。→ 12+2
- **Steam Deck / 移动 / web 平台验证**——发版时。→ 发版准备文档
- **性能基线值**——"tick 速率目标"、"LLM 调用预算"、"内存上限"的实际数字。→ 第一次 weekly CI 跑建立经验基线

## 15. 远期路线图

12+1 故意预留：
- 真 LLM fixture nightly 任务
- 基于性质的测试（命令 schema fuzzer）
- 回放分析工具（热力图、决策树可视化）
- 性能 dashboard
- 测试分片并行 CI

12+2：
- 完整确定性重模拟回放
- 联网回放同步
- 回放分支
- 跨版本回放兼容（回放 schema 迁移工具）
