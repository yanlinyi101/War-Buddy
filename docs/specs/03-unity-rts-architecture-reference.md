# Unity AI Agent RTS 游戏架构（底座优先）

> Source: user-provided DOCX (2026-02-28). Extracted to markdown for easier diff/search.

目标：先在 Unity 搭出稳定的 RTS 游戏底座（MVP 期允许人类简单操作所有单位），并在底座内预留标准化接口，支持后续接入 AI Agent（经济副官 / 战斗小队长）。当 AI 可靠后，通过“控制策略”收口玩家权限，仅允许直控单个英雄单位，其余单位由 AI 通过同一套指令系统驱动。

## 1. 设计原则
- 单一指令入口（Single Command Path）
- 执行与决策分离（Decouple Decision & Execution）
- 状态可裁剪（State Summarization First）
- 权限是策略，不是分叉实现（Policy not Fork）
- 事件驱动 AI（Event-driven AI）

## 2. 总体架构概览
### 2.1 逻辑分层
- Presentation（表现层）
- Input（输入层）
- Command Layer（指令层）：Order / CommandBus / 校验器 / 队列管理
- Simulation（模拟层）：固定步长 Tick（移动/战斗/经济/生产）
- State & Events：GameState + EventBus
- AI Orchestration：观测构建、事件触发、计划管理、降级与超时
- Data：ScriptableObject 配置

### 2.2 运行形态（推荐）
- 单机权威模拟（本地 Tick 权威）
- AI 可插拔：先本地规则/行为树，再本地/远端 LLM（Adapter），输出仍受限为 Order

## 3. 核心抽象与职责
### 3.1 GameState（全量状态）
维护世界真实状态（对执行层友好）：
- 单位/建筑实例数据（位置、血量、阵营、订单队列、冷却）
- 资源与人口（矿/气、人口上限、占用）
- 生产队列与科技进度
- 地图静态信息索引（资源点、关键区域、导航/阻挡）

AI 不直接读取 GameState；只读取裁剪后的 GameStateSummary。

### 3.2 Order（统一指令）
典型：Move / Attack / AttackMove / Stop / Hold / Gather / ReturnCargo / Build / Train / Research / UseSkill。

Order 必须具备：
- issuer（Player / AI_Econ / AI_Squad_1 / Script）
- targets（单位列表/小队/建筑）
- priority（覆盖/抢占）
- queueMode（替换/追加/插队）
- timestamp（日志/回放）

### 3.3 CommandBus（指令总线）
唯一写入入口：
- 接收 Order
- 合法性校验（权限/资源/前置/目标有效）
- 写入目标 OrderQueue
- 触发事件 OnOrderIssued

### 3.4 Execution Systems（执行系统）
按 Tick 更新：Movement / Combat / Ability / Economy / Build / Production / Tech。

### 3.5 EventBus（事件总线）
系统间解耦、触发 AI、记录回放。

## 4. Tick 与线程模型
- 固定步长模拟：FixedUpdate 或自建 Fixed Timestep
- AI 推理异步化：事件触发 → 构建 Summary → AgentRunner（Task/Coroutine/线程池）→ PendingActionsQueue → 主线程 Tick 提交到 CommandBus

## 5. 观测与计划：AI 接口契约
- GameStateSummary（裁剪观测）
- ActionPlan（AI 输出）：rationale / confidence / phase_plan / orders[]（白名单）

## 6. Agent 分工
- Commander（全局优先级 + 接玩家意图）
- EconAgent（Build/Train/Research/Gather/Return）
- SquadAgent（Move/Attack/UseSkill/Retreat）

## 7. Squad 系统
- squadId / members[] / role / rallyPoint / currentTask / squadState

## 8. 控制策略 ControlPolicy
- FullControl / AssistMode / HeroOnly
- 策略在 CommandBus 校验阶段生效

## 9. 日志/复盘/可观测性
- 订单日志（必做）+ AI 决策日志 + 指标

## 10. 数据与配置
ScriptableObject 优先；后续可扩展 JSON/表格。

## 12. 推荐工程目录
Scripts/Core, Command, Units, Squads, Economy, Build, Production, AI, UI, Logging, Data/ScriptableObjects, Scenes。

## 13. 最小接口形状（摘录）
```csharp
public interface IOrder { OrderType Type { get; } }
public interface ICommandBus {
    CommandResult IssueOrders(OrderIssuer issuer, IReadOnlyList<int> targetIds, IReadOnlyList<IOrder> orders);
}
public interface IControlPolicy {
    bool CanIssue(OrderIssuer issuer, int targetId, OrderType orderType);
}
public interface IAgent {
    string Name { get; }
    Task<ActionPlan> DecideAsync(GameStateSummary summary, IReadOnlyList<GameEvent> recentEvents, CancellationToken ct);
}
```
