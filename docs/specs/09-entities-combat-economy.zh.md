# 实体、战斗、经济规则

日期：2026-04-28
项目：War Buddy（Godot 4.6.x）
状态：草案。Spec-only。**MVP 不实施本文。** 09 是 06 玩法愿景具体化为实体、战斗数学、经济循环、科技树、比赛形态的未来契约。在 07/08 稳定后作为独立任务落地。

> 本文为 [`09-entities-combat-economy.md`](09-entities-combat-economy.md) 的中文参考版。两份内容保持同步；如发生冲突，以英文版为权威。

母文档：06。
兄弟文档：07（`OrderTypeRegistry` 注册扩展由 09 填充）、08（`BattlefieldSnapshotBuilder` 读取 09 的 `GameState`；小队长属性强化对接点）。
子文档：10（备战 UI 基于 09 的单位/建筑列表编排预案）、11（09 单位类的碰撞图层）、12（战斗回放格式）。

## 1. 目的与 06 的关系

06 §2.3 要求每条单位定义都带 `agency_tier`。06 §6 锁定约 50 单位/阵营的部队规模。06 §5 故意延后比赛长度、胜利条件、阵营数。09 把它们都关上，加上让一场比赛能跑通全流程所需的其它一切：

- **单位分类**——战场上有什么实体、它们的角色、agency 层级、战斗属性
- **战斗数学**——伤害类型、护甲类、乘数矩阵、HP/DPS/射程起始值
- **经济**——资源、采集循环、worker 行为、基地饱和度
- **科技树**——三阶进度与每阶解锁内容
- **建筑**——生产、人口、科技、防御
- **比赛形态**——长度目标、胜利条件、人口机制
- **小队长 ↔ squad 绑定**——08 的小队长 persona 与 squad 类的对应关系
- **OrderTypeRegistry 扩展**——07 §6 期望 09 注册的 `gather` / `train` / `build` / `research` 等 order 类型

09 是**结构优先、数值次之**。本文表格里的具体数值都从星际2 同位单位抄过来，继承 15 年免费的平衡迭代成果，每个数字都标"待 playtest 调"。09 锁住*字段*；*数值*活在 `.tres` 文件里，设计师无需碰本文即可迭代。

## 2. 阵营模型

### 2.1 v1：镜像

v1 出厂使用单一共享 roster——双方阵营从同一份单位与建筑列表抽取。差异化靠美术（颜色、小队长 persona 变体）+ 地图驱动的不对称（起始位置、资源布局）。

这是验证整套系统的最小路径：7 单位类型 × 2 阵营 = 14 个单位实例，但只需要编辑和平衡 7 个单位*定义*。

### 2.2 远期：3 阵营不对称

锁定的长期方向（在此记录，让 v1 架构留出空间）：

| 阵营 | 主题 | 调性 | 一阶关键词 |
|---|---|---|---|
| **猫狗** | 家宠联盟 | 朝气、坚韧、忠诚 | 兵种均衡，多面手 |
| **鹅鸭** | 水禽民兵 | 出乎意料地凶悍、阵型重 | 群体增益，强力前线冲锋 |
| **野生动物** | 未驯化第三势力 | 无政府、机会主义、中立倾向 | 不对称工具性、跨派系战术 |

09+1（未来一次修订）落地三个不对称 roster。§3–§7 描述的数据层必须在 schema 不变的前提下容纳每阵营覆盖——`unit_def.faction_id` 与 `build_def.faction_id` 是 v1 起就强制的字段，即使 v1 只出 `&"shared"`。

### 2.3 小队长 persona 主题对齐

08 §9 的三档小队长 persona（`captain_combat` / `captain_econ` / `captain_scout`）在 09+1 获得阵营特化语音变体：猫狗派的 `captain_combat` 与鹅鸭派的 `captain_combat` 在调性、语气、口癖上完全不同。v1 仅出共享变体。

## 3. 单位分类

### 3.1 单位类别

七类。每个单位定义必须恰好属于一类。

| # | 类别 | 角色 | Agency 层级 | 典型部队占比 |
|---|---|---|---|---|
| 1 | `worker` | 采矿、采气、建造 | regular | 8–16 |
| 2 | `frontline` | 近战肉盾、堵口 | regular | 8–15 |
| 3 | `ranged` | 风筝、点射 | regular | 6–12 |
| 4 | `siege` | 反建筑、splash | regular | 2–4 |
| 5 | `caster` | 治疗、增益、debuff、控场 | regular | 1–3 |
| 6 | `scout` | 视野、骚扰 | regular | 2–4 |
| 7 | `hero` | 玩家化身 | hero | 1 |

带队的小队长与所带 squad 的 regular 同类（`agency_tier = captain`），见 §8。

### 3.2 `UnitDef` Resource

```gdscript
class_name UnitDef
extends Resource

# 身份
@export var unit_id: StringName                 # 规范名，如 &"frontline_basic"
@export var display_name: String                # 本地化显示名
@export var faction_id: StringName = &"shared"  # v1 永远 "shared"；09+1 扩展
@export var category: StringName                # §3.1 类别之一
@export var agency_tier: StringName             # &"hero" | &"captain" | &"regular"

# 战斗
@export var max_hp: int
@export var armor: int = 0                      # 平减，乘数前先扣
@export var armor_class: StringName             # §4.2: light | medium | heavy | structure | hero
@export var dmg: int                            # 基础攻击力
@export var dmg_type: StringName                # §4.1: normal | piercing | siege | magic
@export var attack_range: float                 # 米；0 = 近战
@export var attack_period_seconds: float        # 攻击间隔
@export var splash_radius: float = 0.0          # 0 = 单体目标

# 移动
@export var move_speed: float                   # m/s 平地
@export var turn_speed_deg: float = 720.0       # 度/秒；高 = 灵敏

# 视野与侦测
@export var sight_range: float                  # 米；揭开战争迷雾
@export var detection: bool = false             # 是否能侦测隐身（caster 类常用）

# 生产
@export var produced_at: StringName             # 生产此单位的建筑 build_id
@export var supply_cost: int                    # 计入人口（§7.4）
@export var mineral_cost: int
@export var gas_cost: int
@export var build_time_seconds: float
@export var tech_tier: int                      # 1 / 2 / 3——见 §6
@export var prerequisites: Array[StringName] = []  # 需存在的其它 build_id

# 行为钩子（被 09 行为树消费，不进 07 schema）
@export var auto_engage_range: float = 0.0      # 0 = 同 attack_range
@export var auto_pursuit_range: float = 0.0     # 追击距离
@export var idle_behavior: StringName = &"hold" # &"hold" | &"patrol" | &"return_to_squad"
```

### 3.3 v1 单位 roster（每类 1 种）

数值抄星际2 同角色单位。标记**"playtest 目标"**——非终值。

| `unit_id` | 类别 | 灵感 | HP | 护甲/类 | 攻/类型 | 射程 | 速度 | 造价 (M/G) | 造时 (s) | 阶 |
|---|---|---|---|---|---|---|---|---|---|---|
| `worker_basic` | worker | SC2 SCV | 45 | 0/light | 5/normal | 0 (近战) | 2.81 | 50/0 | 12 | 1 |
| `frontline_basic` | frontline | SC2 劫掠者 | 125 | 1/heavy | 10/normal | 6 | 3.15 | 100/25 | 21 | 1 |
| `ranged_basic` | ranged | SC2 陆战队员 | 45 | 0/light | 6/piercing | 5 | 3.15 | 50/0 | 18 | 1 |
| `siege_basic` | siege | SC2 攻城坦克 | 175 | 1/heavy | 35/siege | 7 (架起 13) | 2.62 | 150/125 | 45 | 2 |
| `caster_basic` | caster | SC2 幽灵 | 100 | 0/light | 10/magic | 6 | 3.94 | 150/125 | 39 | 3 |
| `scout_basic` | scout | SC2 死神 | 60 | 0/light | 4×2/piercing | 5 | 5.25 | 50/50 | 32 | 1 |
| `hero_commander` | hero | 自定（无 SC2 1:1） | 600 | 2/hero | 25/normal | 0 (近战) | 4.20 | n/a | n/a | n/a |

英雄不可生产——比赛开始时在玩家主基地刷出。每阵营恰好一个。死亡处理见 §10。

### 3.4 Splash / AOE

Splash 伤害对范围内所有敌方使用 `splash_radius`，每个目标独立应用 dmg-type vs armor 乘数。`siege` 单位对 `friendly_unit` / `friendly_structure` 默认**开启**友军误伤；其它单位**关闭**（设计意图：攻城单位用错该疼，远程不该误杀农民）。

## 4. 战斗数学

### 4.1 伤害类型（4 种）

| `dmg_type` | 解读 | 克制 | 克制理由 |
|---|---|---|---|
| `normal` | 通用近战/动能 | heavy | 近距压制重甲 |
| `piercing` | 子弹/弓箭 | light | 穿透对无甲效率高 |
| `siege` | 火炮/重型弹药 | structure | 设计就是拆墙的 |
| `magic` | 法术/能量 | light | 绕过物理防御 |

### 4.2 护甲类（5 种）

| `armor_class` | 例 | 备注 |
|---|---|---|
| `light` | worker, ranged, caster, scout | 便宜、脆 |
| `medium` | （v1 无单位；预留给 09+1 扩展） | 摇摆档 |
| `heavy` | frontline, siege | 厚血、慢 |
| `structure` | 所有建筑 | 静态、高 HP |
| `hero` | 仅英雄 | 单独类避免被克制单位屠英雄 |

`medium` 故意预留——09+1 扩 roster 时不必重平整张矩阵。

### 4.3 乘数矩阵

| ↓ 攻 \ 甲 → | light | medium | heavy | structure | hero |
|---|---|---|---|---|---|
| `normal` | 1.0× | 1.0× | 1.25× | 0.75× | 1.0× |
| `piercing` | 1.25× | 1.0× | 0.5× | 0.5× | 1.0× |
| `siege` | 0.5× | 0.75× | 1.0× | 1.25× | 0.5× |
| `magic` | 1.25× | 1.0× | 1.0× | 0.5× | 0.75× |

存为 Resource：

```gdscript
class_name DamageMatrix
extends Resource

@export var multipliers: Dictionary = {}  # {dmg_type: {armor_class: float}}

func multiplier(dmg_type: StringName, armor_class: StringName) -> float:
    return multipliers.get(dmg_type, {}).get(armor_class, 1.0)
```

单一文件 `damage_matrix.tres` 出厂在 `res://data/combat/`。

### 4.4 伤害公式

```
final_damage = max(0, (base_dmg * matrix(dmg_type, armor_class)) - armor)
```

- 乘数在平减前应用（避免高护甲让克制乘数失效）。
- `final_damage` 下限 0（永不治疗）。
- 暴击、闪避、偏转、tag-bonus——v1 **不做**。预留给 09+1。

### 4.5 无主角光环乘数

按 brainstorm 决议：英雄使用矩阵表，与其它单位一致（`hero` 护甲类）。**没有**额外的"英雄受所有伤害 0.5×"特殊规则。主角感来自原始 HP 与 DPS（§3.3 中 600 HP / 25 DPS），不是公式特例。

理由：玩家学一张表而非两张；LLM 副官也无需为英雄另开推理路径。

### 4.6 射程、视线、地形高度

- 攻击距离按中心到中心距离判定。
- 视线：`ranged` / `siege` / `caster` 必须有视线。`structure` 与不可走地形阻挡视线；友军不阻挡（无友军遮挡）。
- 高地优势：星际2 风格——高地攻击低地满伤；反向 50% miss（除非攻击者通过 `scout` 取得高地视野）。

## 5. 经济

### 5.1 资源

两类资源，存于阵营状态。

| 资源 | 来源 | Worker 来回 |
|---|---|---|
| `mineral` | `mineral_patch`（每主基地附近 8 块） | ~3 秒 |
| `gas` | `gas_geyser`（每主基地附近 2 个，需建 `refinery`） | ~3 秒 |

### 5.2 `ResourceNode` Resource

```gdscript
class_name ResourceNode
extends Resource

@export var node_id: StringName
@export var resource_type: StringName       # &"mineral" | &"gas"
@export var initial_amount: int             # 矿块会枯竭；气田不会
@export var current_amount: int
@export var harvest_amount_per_cycle: int   # 默认 5 mineral / 4 gas
@export var max_concurrent_workers: int     # 默认每块 3 个 worker
@export var depletes: bool                  # mineral=true, gas=false
```

矿块降到 0 即消失，附近 worker 自动重排队。

### 5.3 Worker 行为（采集循环）

`worker_basic` 周期：

```
[空闲 / 已收命令]
       │
       ▼
[移动到指定 ResourceNode]
       │
       ▼
[采集：1.5s 动画，拾取 harvest_amount_per_cycle]
       │
       ▼
[移动到最近卸货点（HQ 或带 deposit 标记的 supply depot）]
       │
       ▼
[卸货：0.2s，加入阵营资源池]
       │
       └─→ 除非被重派，循环
```

饱和：单主基地 8 矿块在约 16 worker 时饱和（每块 2 个）。24 worker 即过饱和，收益递减。副官的 `captain_econ` 应将此作为软目标。

### 5.4 建筑建造

Worker 也建造。建造流程：

- Worker 走到放置点
- Worker 进入 "constructing" 状态，碰撞体仍在
- 建筑 HP 在 `build_time_seconds` 内线性增长
- HP 达 100% 即可用
- Worker 释放；造价（mineral + gas）在放置时即扣，不在完工时
- 取消建造**退还 75%** 造价（不是 100%）

多 worker 可堆同一工地，**每多一个 +40% 速度**（2 worker = 1.4×；3 = 1.8×）。上限 5 worker。

## 6. 科技树（三阶）

星际2 风格三阶进度。

### 6.1 阶定义

| 阶 | 解锁机制 | 解锁内容 |
|---|---|---|
| **T1** | 比赛开始即默认 | `worker_basic`、`frontline_basic`、`ranged_basic`、`scout_basic`、基础建筑 |
| **T2** | 建一座 **T2 科技建筑**（如 `forge`）；可同时升级 HQ | `siege_basic`、防御建筑（炮塔）、T2 生产建筑 |
| **T3** | 建一座 **T3 科技建筑**（如 `arcanum`）并把 HQ 升到 T3 | `caster_basic`、终极建筑、昂贵研究 |

英雄（`hero_commander`）始终可用，不受阶限制。比赛开始时刷出。

### 6.2 `UnitDef` 中的科技门槛

`UnitDef.tech_tier` 字段声明所需阶。`prerequisites` 数组可额外指定必须存在的建筑（如 `[&"barracks", &"engineering_bay"]`）。

### 6.3 对 snapshot 的影响

`BattlefieldSnapshotBuilder`（08 §7）增加 `tech_state` 字段：

```jsonc
"tech_state": {
  "current_tier": 2,
  "buildings_completed": ["hq", "barracks", "forge"],
  "research_complete": [],
  "next_unlock_eta_seconds": 45  // forge 完工后 siege_basic 解锁
}
```

让 LLM 副官有信息做"升科技 vs 推进"的决策——兑现 06 §2.2 副官的专业化职能。

## 7. 建筑

### 7.1 `BuildingDef` Resource

```gdscript
class_name BuildingDef
extends Resource

@export var build_id: StringName
@export var display_name: String
@export var faction_id: StringName = &"shared"
@export var category: StringName                # §7.2
@export var max_hp: int
@export var armor: int = 1
@export var armor_class: StringName = &"structure"

# 建造
@export var mineral_cost: int
@export var gas_cost: int
@export var build_time_seconds: float
@export var tech_tier: int
@export var prerequisites: Array[StringName] = []
@export var size_grid: Vector2i                 # 占地（网格单位）

# 生产/功能
@export var produces: Array[StringName] = []    # 此建筑生产的 unit_id
@export var supply_provided: int = 0            # supply depot 与 HQ
@export var deposit_point: bool = false         # worker 可在此卸货
@export var research_options: Array[StringName] = []  # 可解锁的 research_id
@export var defensive: bool = false             # 自动攻击范围内敌方
@export var defensive_range: float = 0.0
@export var defensive_dmg: int = 0
@export var defensive_dmg_type: StringName = &"normal"
```

### 7.2 建筑类别

| 类别 | 例 | 阶 |
|---|---|---|
| `hq` | 主基地 / 大本营 / 巢穴 | T1（可升级到 T2/T3） |
| `supply` | Supply depot——提供人口 | T1 |
| `production` | 兵营（frontline）、靶场（ranged）、工厂（siege） | T1/T2 |
| `tech` | 锻造场（T2 解锁）、奥术阵（T3 解锁）、工程站 | T1/T2/T3 |
| `resource` | Refinery（在气田上） | T1 |
| `defense` | 炮塔、导弹塔 | T2 |

### 7.3 v1 建筑 roster（最小可玩）

| `build_id` | 类别 | HP | 造价 (M/G) | 造时 (s) | 提供 |
|---|---|---|---|---|---|
| `hq` | hq | 1500 | 400/0 | 100 | +10 人口、deposit_point、生产 `worker_basic` |
| `supply_depot` | supply | 400 | 100/0 | 21 | +8 人口 |
| `barracks` | production | 1000 | 150/0 | 46 | 生产 `frontline_basic`、`ranged_basic`、`scout_basic` |
| `forge` | tech | 850 | 150/100 | 35 | T2 解锁，护甲/武器升级研究 |
| `factory` | production | 1250 | 200/100 | 43 | T2 限定，生产 `siege_basic` |
| `arcanum` | tech | 850 | 150/200 | 50 | T3 解锁 |
| `temple` | production | 1000 | 150/150 | 50 | T3 限定，生产 `caster_basic` |
| `refinery` | resource | 500 | 75/0 | 21 | 在气田上启用气体采集 |
| `turret` | defense | 250 | 100/0 | 30 | T2 限定，自动攻击 7 射程，12 piercing 伤害 |

共 9 条建筑定义。这是能验证建造、人口、按阶生产、科技门槛、气体、防御的最小集。

### 7.4 人口（supply 系统）

软上限机制，非硬限。每阵营追踪：

```
supply_used = sum(unit.supply_cost) for all alive units
supply_max = sum(building.supply_provided) for all completed buildings
```

`supply_used >= supply_max` 时：
- 生产被阻塞（生产建筑拒绝开始会超上限的单位）。
- 现有单位继续工作。
- HUD 显示"人口阻塞"提示。

默认 supply 消耗：
- `worker_basic`: 1
- `frontline_basic`: 2
- `ranged_basic`: 1
- `siege_basic`: 3
- `caster_basic`: 2
- `scout_basic`: 1
- `hero_commander`: 0（免费、固定）

默认下实战上限：1 hq (10) + 5 supply_depot (40) = 50 人口，与 06 §6 "约 50 单位/阵营"目标契合。

## 8. 小队长 ↔ Squad 绑定

### 8.1 Squad 类别由所含 regular 决定

Squad 的类别由其 regular 的类别决定。v1 不允许混类 squad。Squad 隐式形成：小队长刷出并被分配 n 个 regular 时，所有 regular 共享小队长的类别。

### 8.2 小队长 persona 类别映射

08 §9 出厂三档小队长 persona 原型。09 把它们绑定到类别：

| 小队长 persona | 可带 squad 类别 |
|---|---|
| `captain_combat.tres` | `frontline`、`ranged`、`siege`、`caster` |
| `captain_econ.tres` | `worker` |
| `captain_scout.tres` | `scout` |

`captain_combat` 不能带 worker squad 反之亦然。错配在 09 的 `Squad` 工厂在刷出时强制拒绝。

### 8.3 小队长属性强化（≤15% 规则）

按 06 §2.3 与 08 §11.6，小队长有 `CaptainMemory.preferred_axis` 和 `reinforcement_pct`（钳在 0.15）。09 刷出小队长单位时（小队长是该 squad 类别的单位，非独立 unit kind），读取记忆快照并对一个轴施加加成：

| `preferred_axis` 值 | 对小队长单位的效果 |
|---|---|
| `&"hp"` | `max_hp *= (1 + reinforcement_pct)` |
| `&"dps"` | `dmg *= (1 + reinforcement_pct)` 且 `attack_period_seconds /= (1 + reinforcement_pct)` |
| `&"sight"` | `sight_range *= (1 + reinforcement_pct)` |
| `&"speed"` | `move_speed *= (1 + reinforcement_pct)` |

每次只一个轴；上限钳由 08 写入端（08 §11.6）执行，09 信任输入。

小队长单位本质是同类 regular 重写 `agency_tier = captain`，触发 11 §3 的死亡灵魂特效。

## 9. OrderTypeRegistry 扩展

按 07 §6，09 在 autoload 启动时注册额外 order 类型。v1 扩展：

| `type_id` | 参数 | 允许的副官 | 备注 |
|---|---|---|---|
| `gather` | `{node_id: StringName}` | combat、economy | 校验时强制限定 worker |
| `return_cargo` | `{}` | combat、economy | 强制 worker 立即卸货 |
| `build` | `{build_id: StringName, position: Vector3}` | combat、economy | 仅 worker |
| `train` | `{unit_id: StringName, count: int = 1}` | combat、economy | 给生产建筑下单 |
| `research` | `{research_id: StringName}` | combat、economy | 给科技建筑下单 |
| `set_rally` | `{position: Vector3}` | combat、economy | 生产建筑集结点 |
| `cancel_production` | `{queue_index: int}` | combat、economy | 取消队列中的单位 |

加上 07 v1 核心（`move`、`attack`、`stop`、`hold`、`use_skill`），09 注册后注册表共 12 种 order。brainstorm 列表里那些更细的动词（retreat、regroup、harass、ambush、scout、watch）暂不作为独立 type——它们都能被现有 12 种组合掉（如 `retreat = move 回家 + posture = hold_fire`；`harass = attack 配低 force 占用`）。

## 10. 比赛形态

### 10.1 长度目标

**~15 分钟/局**作为设计目标。决定资源量、科技节奏、人口曲线。

T2 应在约 5 分钟前后到达；T3 在约 10 分钟。15 分钟时双方满科技、成熟部队，胜负决断应已临近。

### 10.2 胜利条件

**摧毁敌方所有建筑。** 与 MVP（`MatchState.victory_triggered`）一致。v1 无其它胜利条件。

这保留现有 MVP 架构原封不动——`MatchState.mark_destroyed` 与 victory trigger 继续工作。09 只是扩大被追踪的建筑列表。

### 10.3 英雄死亡

英雄可以死。死亡时：
- Ragdoll 尸体 + 灵魂特效（11 §3）。
- 复活计时启动（默认 **30 秒**）。
- 在主基地复活。
- 主基地被毁且无其它 `hq` 时，英雄不复活——但此时阵营也接近败局（按胜利条件）。
- 英雄死亡**本身不是失败条件**。

### 10.4 人口

软上限 supply 系统（§7.4）。设计目标 ~50 单位/阵营。设硬天花板 `supply_max` 钳在 100，防止 supply-depot 刷屏。

### 10.5 资源节奏

比赛起点：每阵营**50 mineral、0 gas、1 hq、6 worker_basic、1 hero_commander**。与星际2 1v1 起点一致。

每阵营地图总 mineral：8 块 × 1500 mineral = 12000 mineral。满饱和挖矿约 25 分钟，在 ~15 分钟目标下留有余量。

## 11. GameState Autoload

08 §7 提到未来的 `GameState` autoload 由 `BattlefieldSnapshotBuilder` 查询。09 拥有它的定义。

```gdscript
class_name GameState
extends Node     # autoload

# 阵营状态（按阵营 id 查）
func get_faction(faction_id: StringName) -> FactionState
func all_factions() -> Array[FactionState]

# 实体查询（廉价、基于 group）
func units_in_radius(center: Vector3, radius: float, faction_id: StringName = &"") -> Array
func buildings_in_radius(center: Vector3, radius: float, faction_id: StringName = &"") -> Array
func resource_nodes(resource_type: StringName) -> Array

# 科技/生产
func current_tier(faction_id: StringName) -> int
func is_unit_buildable(faction_id: StringName, unit_id: StringName) -> Dictionary
    # 返回 { ok: bool, missing_prereqs: [...], missing_supply: int, missing_resources: {} }

# 比赛
func match_elapsed_seconds() -> float
func is_victory_triggered() -> bool
```

```gdscript
class_name FactionState
extends Resource

@export var faction_id: StringName
@export var minerals: int
@export var gas: int
@export var supply_used: int
@export var supply_max: int
@export var current_tier: int
@export var alive_units: Array[int]              # node id
@export var alive_buildings: Array[int]
@export var research_complete: Array[StringName]
@export var production_queues: Dictionary        # building_id -> Array[unit_id]
```

`GameState` 是 LLM snapshot 的唯一权威读取源。`BattlefieldSnapshotBuilder` 查它；其它地方都不持有这份数据。

## 12. 行为树

09 拥有"消费 `CommandBus.order_issued` 的每单位/每 squad 行为树"实现。07 §11 已留出此对接点。

行为树编写**作为单独任务延后**——09 只锁契约，不写树：

- 每单位类别一个 BT 类（`worker_bt.gd`、`frontline_bt.gd` 等），加一个 `squad_bt.gd` 给小队长统领的组。
- BT 订阅 `CommandBus.order_issued`，按 `target_unit_ids` 含自身过滤。
- BT 通过 `EventBus` 风格信号回报：`order_completed`、`order_failed`、`order_progress`。
- BT 内部（selector / sequence / decorator）属实现选择——Godot 4.6 不自带 BT 框架，要么自己撸一个小的，要么引入社区插件。决策延后到实施任务。

## 13. 阵营 Roster 路线图（远期）

作为长期锚点记录；v1 忽略。

```
v1：共享镜像 roster（本文，§3.3 + §7.3）
   ↓
09+1：拆成 3 阵营
   ├─ 猫狗 (Cats & Dogs)
   ├─ 鹅鸭 (Geese & Ducks)
   └─ 野生动物 (Wild Animals)
```

09+1 时每个阵营会：
- 复用 §3.1 的七个类别（跨阵营保持稳定，降低 LLM 认知压力）
- 按 `unit_def.faction_id` 查表覆盖数值
- 引入 1–2 个阵营特色单位，呼应主题但不破矩阵
- 获得阵营特化 `captain_*` persona 变体（语气、口癖、特性）

## 14. 开放问题

- **副官能用的动词超出核心集**——brainstorm 提的 `retreat` / `harass` / `ambush` 等在 v1 *不是* `OrderTypeRegistry` 条目；09 §9 让它们走组合分解。playtest 若发现组合表达困难，再升为一类。→ 09+1 复审
- **英雄技能**——v1 英雄只有 600 HP / 25 DPS 没有特殊技能。技能（CD 主动、终极）属于 09+1。→ 09+1
- **阵营不对称的具体数值**——§3.3 / §7.3 的 per-faction 覆盖。→ 09+1
- **行为树框架选择**——自撸 vs 社区插件。→ 实施任务
- **地图编辑工具**——网格、地标、资源点如何在编辑器里摆放。→ 10（备战 UI）+ 未来地图编辑子文档
- **小队长强化的反 grief**——什么阻止玩家通过快速通关刷小队长 preferred_axis 数值，破坏 PvP 平衡？→ PvP 优先时由 09+1 解决

## 15. 验证（骨架）

09 实现"骨架完成"当且仅当：

1. `UnitDef` 与 `BuildingDef` Resources 解析 + `to_dict` / `from_dict` 往返一致。
2. `damage_matrix.tres` 加载成功，`multiplier()` 对 4×5 全部组合返回预期值。
3. `GameState` autoload 启动，暴露 §11 API，对空比赛返回合理值。
4. v1 七个 `.tres`（每类 1 个）单位文件无错加载。
5. v1 九个 `.tres` 建筑文件无错加载。
6. Headless 启动：`gather` order 经 `CommandBus.submit_orders` 抵达 `worker_basic` 行为树（行为树到位时）。
7. 一个简易集成：起点状态（50 mineral、6 worker）下 `supply_depot` 建造命令，21 秒后阵营 `supply_max` 为 18。
8. 小队长刷出时按 `MemoryStore.snapshot_captain_for(...)` 给正确轴上 `reinforcement_pct`。

09 **不要求**出厂行为树、胜利动画、音乐、美术——这些都是下游任务。09 只发数据层与契约。
