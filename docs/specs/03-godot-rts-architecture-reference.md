# Godot AI Agent RTS 游戏架构（底座优先）

> Source: architecture brief originally authored against a Unity target (2026-02-28), migrated to Godot 4.x on 2026-04-23. The gameplay architecture is engine-agnostic; only the concrete node/signal mappings changed.
>
> **Status (2026-04-26):** This document is **MVP-scoped** and partially superseded by the post-MVP vision in `06-full-gameplay-vision.md`. The `Order` / `CommandBus` / `EconAgent` / `SquadAgent` sketches here remain the engine-level pattern Phase D's MVP scaffolding will follow, but the real long-term contracts will be defined in **doc 07 (Command System Specification)** — including the three-tier shared tactical-order schema — and **doc 08 (AI Deputy Architecture)** — including LLM tool-calling, character persistence, and voice. Treat this 03 doc as the bridge between today's code and those upcoming specs.

目标：在 Godot 4.6.x 上搭出稳定的 RTS 游戏底座（MVP 期允许人类简单操作所有单位），并在底座内预留标准化接口，支持后续接入 AI Agent（经济副官 / 战斗小队长）。当 AI 可靠后，通过"控制策略"收口玩家权限，仅允许直控单个英雄单位，其余单位由 AI 通过同一套指令系统驱动。

## 1. 设计原则
- 单一指令入口（Single Command Path）
- 执行与决策分离（Decouple Decision & Execution）
- 状态可裁剪（State Summarization First）
- 权限是策略，不是分叉实现（Policy not Fork）
- 事件驱动 AI（Event-driven AI，基于 Godot `signal`）

## 2. 总体架构概览
### 2.1 逻辑分层
- Presentation（表现层，`CanvasLayer` / `Node3D`）
- Input（输入层，`_input` / `_unhandled_input` + `InputMap`）
- Command Layer（指令层）：`Order` / `CommandBus` / 校验器 / 队列管理
- Simulation（模拟层）：固定步长 Tick（`_physics_process` 或自定义固定时钟）
- State & Events：`GameState` + 全局 `EventBus`（Autoload `Node`）
- AI Orchestration：观测构建、事件触发、计划管理、降级与超时
- Data：`Resource` / 自定义 `.tres` 配置

### 2.2 运行形态（推荐）
- 单机权威模拟（本地 Tick 权威）
- AI 可插拔：先本地规则/行为树（自实现 BT 或 `AnimationTree` 风格），再本地/远端 LLM（Adapter），输出仍受限为 `Order`

## 3. 核心抽象与职责
### 3.1 GameState（全量状态）
维护世界真实状态（对执行层友好）：
- 单位 / 建筑实例数据（位置、血量、阵营、订单队列、冷却）
- 资源与人口（矿 / 气、人口上限、占用）
- 生产队列与科技进度
- 地图静态信息索引（资源点、关键区域、`NavigationRegion3D` 导航 / 阻挡）

AI 不直接读取 `GameState`；只读取裁剪后的 `GameStateSummary`（纯 Dictionary / Resource）。

### 3.2 Order（统一指令）
典型：Move / Attack / AttackMove / Stop / Hold / Gather / ReturnCargo / Build / Train / Research / UseSkill。

Order 必须具备：
- `issuer`（Player / AI_Econ / AI_Squad_1 / Script）
- `targets`（单位列表 / 小队 / 建筑）
- `priority`（覆盖 / 抢占）
- `queue_mode`（替换 / 追加 / 插队）
- `timestamp`（日志 / 回放）

### 3.3 CommandBus（指令总线）
唯一写入入口（建议作为 Autoload 单例 `Node`）：
- 接收 `Order`
- 合法性校验（权限 / 资源 / 前置 / 目标有效）
- 写入目标 `OrderQueue`
- 触发信号 `order_issued(order)`

### 3.4 Execution Systems（执行系统）
按 Tick 更新：Movement / Combat / Ability / Economy / Build / Production / Tech。建议以独立 `Node` 挂在场景根节点下，通过 `_physics_process` 驱动。

### 3.5 EventBus（事件总线）
以 Autoload `Node` 暴露 `signal`（`unit_died`, `building_destroyed`, `resource_depleted`, …）供系统间解耦、触发 AI、记录回放。

## 4. Tick 与线程模型
- 固定步长模拟：`_physics_process(delta)` 或自建定时器
- AI 推理异步化：事件触发 → 构建 Summary → `AgentRunner`（GDScript `await` / `Thread` / 远端 HTTP）→ `PendingActionsQueue` → 主线程 Tick 提交到 `CommandBus`

## 5. 观测与计划：AI 接口契约
- `GameStateSummary`（裁剪观测，Dictionary / Resource）
- `ActionPlan`（AI 输出）：`rationale` / `confidence` / `phase_plan` / `orders[]`（白名单）

## 6. Agent 分工
- Commander（全局优先级 + 接玩家意图）
- EconAgent（Build / Train / Research / Gather / Return）
- SquadAgent（Move / Attack / UseSkill / Retreat）

## 7. Squad 系统
- `squad_id` / `members[]` / `role` / `rally_point` / `current_task` / `squad_state`

## 8. 控制策略 ControlPolicy
- `FullControl` / `AssistMode` / `HeroOnly`
- 策略在 `CommandBus` 校验阶段生效

## 9. 日志 / 复盘 / 可观测性
- 订单日志（必做，写入 `user://` 目录）+ AI 决策日志 + 指标

## 10. 数据与配置
自定义 `Resource` (`.tres`) 优先；后续可扩展 JSON / CSV。

## 12. 推荐工程目录（Godot 侧）
```
godot/
  scenes/       # .tscn 场景文件
  scripts/
    core/       # GameState, Clock, 常量
    command/    # Order, CommandBus, ControlPolicy
    units/
    squads/
    economy/
    build/
    production/
    ai/         # Agent, GameStateSummary, ActionPlan
    ui/         # HUD, CanvasLayer 控件
    logging/
  data/         # .tres 配置资源
  autoload/     # EventBus, CommandBus, GameState 单例
```

当前 MVP 仓库只实例化了以上目录的一个子集（见 `godot/scripts/`），尚未引入 `command/` 与 `ai/` 分层；这份架构是 MVP 之后扩展的北极星。

## 13. 最小接口形状（GDScript 摘录）
```gdscript
# order.gd
class_name Order
extends Resource

enum OrderType { MOVE, ATTACK, ATTACK_MOVE, STOP, HOLD, GATHER, RETURN_CARGO, BUILD, TRAIN, RESEARCH, USE_SKILL }

@export var type: OrderType
@export var issuer: StringName
@export var targets: Array[int] = []
@export var priority: int = 0
@export var queue_mode: StringName = &"replace"
@export var timestamp_ms: int = 0
```

```gdscript
# command_bus.gd  (Autoload)
class_name CommandBus
extends Node

signal order_issued(order: Order)

func issue_orders(issuer: StringName, target_ids: Array[int], orders: Array[Order]) -> Dictionary:
    # returns { "accepted": Array[Order], "rejected": Array[Dictionary] }
    return {}
```

```gdscript
# control_policy.gd
class_name ControlPolicy
extends RefCounted

func can_issue(issuer: StringName, target_id: int, order_type: int) -> bool:
    return false
```

```gdscript
# agent.gd
class_name Agent
extends Node

func decide(summary: Dictionary, recent_events: Array) -> Dictionary:
    # returns an ActionPlan dictionary
    return {}
```
