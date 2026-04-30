# 备战界面与预案系统

日期：2026-04-28
项目：War Buddy（Godot 4.6.x）
状态：草案。Spec-only。**MVP 不实施本文。** 10 涵盖玩家在 *正式比赛之外* 接触到的一切——主菜单壳、预案编辑器、玩家命名区域工具、副官/小队长营地、设置面板。

> 本文为 [`10-warroom-and-preplans.md`](10-warroom-and-preplans.md) 的中文参考版。两份内容保持同步；如发生冲突，以英文版为权威。

母文档：06。
兄弟：07（消费本文产出的 `PrePlan` / `PlayerRegionSet` Resource）、08（本文编辑 08 写入的 `DeputyPersona` / `DeputyMemory` / `CaptainMemory`）、09（本文读取单位/建筑列表给编辑器下拉用）。
子：未来 10+1（时间线预案编辑器、更深营地可视化）。

## 1. 目的与范围

10 是玩家"非比赛"的全部表面。这里：

- 编辑和分享预案（07 §7）
- 在网格上绘制玩家命名区域（07 §3.3）
- 选副官 persona（08 §9）+ 调自主度 dial（08 §11.8）
- 查看小队长累积的记忆
- 配置控制策略（07 §8）
- 快速开局与 lobby 流程

10 范围外：

- 局内 HUD（独立 UX 文档；当前 MVP `hud_root.gd` 覆盖 MVP 切片）
- 语音 STT/TTS 表面（延后到独立子文档）
- 在线匹配、账号、变现（延后）
- 设计师地图编辑器（独立子文档）

10 是**结构与流程优先**，不是像素 mockup 优先。下面每屏描述都是布局意图 + 触及的数据；具体视觉设计后续 Figma。

## 2. 顶层信息架构

主菜单是**四标签壳**：

```
┌──────────────────────────────────────────────────────┐
│  War Buddy                                           │
│  ┌──────┬───────┬─────┬─────────┐                   │
│  │ 比赛 │ 备战  │ 营地│  设置   │                   │
│  └──────┴───────┴─────┴─────────┘                   │
│                                                      │
│  [tab 内容]                                          │
│                                                      │
└──────────────────────────────────────────────────────┘
```

| 标签 | 拥有者 | 主要用途 |
|---|---|---|
| **比赛** | 10 §3 | 快速开局；选地图与阵营；显示要带的副官；显示当前激活的预案 |
| **备战** | 10 §4 | 预案编辑器；玩家命名区域；分享码导入/导出 |
| **营地** | 10 §5 | 副官 persona 选择；自主度 dial；小队长名单 + 记忆查看；羁绊属性读出 |
| **设置** | 10 §6 | 控制策略；输入；音视频；语言 |

四标签拆分承重：把**短期行为**（比赛）与**长期资产**（备战/营地）与**系统配置**（设置）分离。新玩家可以只看比赛；老玩家在备战与营地上花时间。

## 3. 比赛标签

### 3.1 布局意图

```
┌────────────────────────────────────────────────────┐
│ 比赛                                                │
│  ┌────────────────────┐  ┌───────────────────────┐│
│  │ 地图预览            │  │ 阵营 & 副官          ││
│  │  [网格叠层]         │  │  阵营：shared (v1)   ││
│  │  [资源布局]         │  │  副官：veteran ▼      ││
│  │  自定义区域缩略图    │  │  自主度：●●●○○ 0.5   ││
│  └────────────────────┘  │  绑定：3/5 局         ││
│                          └───────────────────────┘│
│                                                    │
│  此地图激活的预案：                                 │
│   ☑ B 计划 — "alpha 防守 B4"                       │
│   ☑ 经济强化 — "+60s 建 supply"                    │
│   ☐ 速攻 — "2:00 前 scout 速推"                    │
│                                                    │
│  [ 开始比赛 ]                                       │
└────────────────────────────────────────────────────┘
```

### 3.2 显示数据

| 元素 | 数据源 |
|---|---|
| 地图预览 | `res://data/maps/<map_id>.tscn` 缩略图；网格 + 地标叠层来自 07 |
| 阵营 | v1：`&"shared"`；09+1 列出猫狗/鹅鸭/野生 |
| 副官下拉 | 来自 08 的 `DeputyPersona` 列表；当前*绑定*（10 §5.2）默认选中并锁定，除非 §5.2 swap 条件满足 |
| 自主度滑条 | 读写 `DeputyPersona.deputy_autonomy` ∈ [0, 1]（08 §9）。滑条 5 个 detent（0.1/0.3/0.5/0.7/0.9），底层连续 |
| 绑定计数 | "N/5 局"——persona 切换冷却（10 §5.2） |
| 激活预案 | `map_id` 匹配选中地图的 `PrePlan` 列表；勾选切换每个 plan 的 `enabled` 字段 |
| 开始比赛 | 引导到比赛场景；当前选项落位为局内配置 |

### 3.3 快速开局

标签顶部 "Quick Match" 按钮跳过此屏：复用上局选项立即开始。第二局后才出现，第一局玩家必须至少访问一次此屏，让"什么是副官"先曝光后才允许跳过。

## 4. 备战标签

最复杂的标签。两栏：左 **预案列表**，右 **编辑器**。

### 4.1 预案列表

```
┌─────────────────────┐
│ 备战                 │
│ 地图：forest_lake ▼  │
│  ┌───────────────┐  │
│  │ B 计划         │  │
│  │ 经济强化  ★    │  │
│  │ 速攻           │  │
│  │ + 新建        │  │
│  │ ↓ 导入分享码   │  │
│  └───────────────┘  │
└─────────────────────┘
```

按选中地图过滤。每行显示 plan `display_name` 与标识：
- ★ — 设为此地图默认（比赛标签自动加载）
- ⚠ — 验证失败（07 §8.5）
- 🔗 — 已生成分享码

按钮：
- **+ 新建** — 在当前地图下创建空白 `PrePlan`
- **↓ 导入分享码** — 打开分享码粘贴模态

### 4.2 表单式预案编辑器（v1）

Brainstorm 决议 Q2 = A：v1 出表单编辑器；时间线视图归 10+1。

```
┌───────────────────────────────────────────────────┐
│ 编辑：B 计划                              [保存]   │
│                                                   │
│ display_name:    [ B 计划                       ] │
│ trigger_phrases: [ b 计划, 计划 b, 执行 b       ] │
│                                                   │
│ Trigger:         [ on_match_start            ▼  ] │
│   conditions:                                     │
│     within_seconds_of_start: [_60_]               │
│     enemy_count_at_least:    [__3_]               │
│     cooldown_seconds:        [__0_]               │
│                                                   │
│ Orders:                                           │
│  ┌──────────────────────────────────────────┐    │
│  │ #1 verb=defend  target=B4  force=alpha×6 │    │
│  │     posture=stand_ground  duration=120s  │    │
│  │     priority=routine                     │    │
│  │     [编辑] [复制] [删除] [↑] [↓]           │    │
│  └──────────────────────────────────────────┘    │
│  [ + 添加 order ]                                  │
│                                                   │
│ [ 生成分享码 ]   [ 删除预案 ]                       │
└───────────────────────────────────────────────────┘
```

### 4.3 Order 编辑模态

新增/编辑一条 order 打开模态，所有字段都是下拉或输入：

| 字段 | 数据源 | UI |
|---|---|---|
| `type_id` | `OrderTypeRegistry.list_for_deputy(plan.deputy)` | 下拉 |
| `target_kind` | 07 §3.3 enum | 下拉 |
| `target_*` | 取决于 `target_kind` | 网格 picker / landmark 下拉 / region 下拉 / param 下拉 |
| `force.captain_id` | 小队长 persona 列表（08 §11.6） | 下拉，含"副官代选" |
| `force.count_min` / `count_max` | int | 数字输入 |
| `force.unit_types` | 09 单位类别 | 多选 |
| `posture` | aggressive / stand_ground / hold_fire | 单选 |
| `priority` | routine / high / emergency | 单选 |
| `duration_seconds` | int (-1 = 永久) | 数字 + "永久"切换 |

保存时跑验证（07 §8.5）：失败的预案不能保存；编辑器在失败字段处显示 inline 错误。

### 4.4 参数化占位（07 §8.4）

Order 模态里 `target_kind = param` 时 value 字段变成下拉，列出 4 个允许的占位：

```
< my_main_base >
< closest_enemy_base >
< hero_position >
< deputy_focus >
```

短 tooltip 解释每个含义。无自由文本——四个值就是全部词汇表。

### 4.5 玩家命名区域工具

从备战标签的次级开关进入（预案列表上方）："**编辑命名区域**"模式把编辑器面板换成网格涂格器。

```
┌───────────────────────────────────────────────────┐
│ Regions for: forest_lake                          │
│                                                   │
│   ┌───────────────────────────┐                   │
│   │   A1  A2  A3  ... A8      │                   │
│   │   B1  ▓▓  ▓▓  B4  ...     │  ▓ = 当前区域选中  │
│   │   C1  ▓▓  ▓▓  C4  ...     │   单元格           │
│   │   D1  D2  D3  ...         │                   │
│   │   ...                     │                   │
│   └───────────────────────────┘                   │
│                                                   │
│   Region name: [ alpha_corner          ]          │
│   Aliases:     [ corner, the corner    ]          │
│                                                   │
│   [保存]  [删除]  [+ 新建]                          │
└───────────────────────────────────────────────────┘
```

按 Q3 = B 决议：网格点击作为编辑原语。点击切换该格在当前区域的归属。无矩形拖拽、无笔刷——这些是 10+1 易用性追加，前提是测试发现纯点击太慢。

按 Q3a = (i)：无解锁门控。第 1 局即可用。

存储：`user://player_regions/<player_id>/<map_id>.tres`，按 07 §3.3。

### 4.6 分享码

两个交互：

**生成：** 已保存预案上"生成分享码"按钮产生不透明字母数字串（07 §8.5）。UI：

```
┌──────────────────────────────────┐
│ B 计划 — 分享码                   │
│                                  │
│   WB1·a8f2x9d3kp7m...            │
│                                  │
│   [ 复制 ]   [ 重新生成 ]          │
│                                  │
│   此码包含：                      │
│    • 预案结构                     │
│    • 引用的命名区域                │
│   不包含：                        │
│    • 你的副官记忆                  │
│    • 你的阵营解锁                  │
└──────────────────────────────────┘
```

**导入：** 把分享码粘进导入模态。系统校验 schema 版本前缀，解码，提交前先预览：

```
┌──────────────────────────────────┐
│ 导入："速攻"                      │
│                                  │
│ Schema 版本：1 ✓                  │
│ 地图：forest_lake ✓               │
│ 捆绑区域：                         │
│   • alpha_corner — 命名冲突        │
│     ◉ 重命名为 alpha_corner_2     │
│     ○ 覆盖我的                    │
│     ○ 跳过（预案需要它！）          │
│ Captain 引用：                    │
│   • captain:alpha — ok            │
│ Orders：3                         │
│                                  │
│   [ 导入 ]   [ 取消 ]              │
└──────────────────────────────────┘
```

冲突解决按 07 §8.5：命名冲突的区域加后缀；本地未知的 captain 引用仍允许导入但带警告（"此预案引用的 captain 你没玩过；副官将代选一个"）。

分享码编解码本身延后（07 §8.5）——10 的 UI 调单一 `ShareCodeService.encode(plan) -> String` / `decode(code) -> ImportPreview` API 并信任它。

### 4.7 验证表面

预案违反 07 §8.5 任一条即无效。编辑器在失败字段处显示 inline 错误 + 顶部 banner 汇总：

```
⚠ 此预案有 2 个问题：
  • Order #2 引用的地标 "old_north_mine" 在此地图已不存在。
  • Order #3 force.captain_id "delta" 不是已注册的 captain persona。
```

0 issues 前禁用保存。"另存为草稿"**不**提供——能跑不动的草稿比没预案更糟。

## 5. 营地标签

"长期资产"视图。大部分只读，两个具体编辑点（persona 切换、自主度 dial）。

### 5.1 布局意图

```
┌────────────────────────────────────────────────────┐
│ 营地                                                │
│                                                    │
│ ┌─ 副官 ──────────────────────────────────────┐   │
│ │ 老兵   [头像]                                │   │
│ │  Trust:        ████░ 0.8                    │   │
│ │  Frustration:  █░░░░ 0.1                    │   │
│ │  Bond:         █████ 1.0                    │   │
│ │  对局：        27 (W 18 / L 9)               │   │
│ │  最近：                                      │   │
│ │   "我跟你说守住的。" (败局，第 26 局)         │   │
│ │   "见过最干净的开局。" (胜，第 25 局)          │   │
│ │  自主度：●●●●○ 0.7                           │   │
│ │  [ 切换 persona ] (4/5 锁)                   │   │
│ └──────────────────────────────────────────────┘   │
│                                                    │
│ ┌─ Captains ──────────────────────────────────┐   │
│ │  alpha (combat)  出场：12  轴：hp           │   │
│ │  bravo (econ)    出场：8   轴：-             │   │
│ │  charlie (scout) 出场：4   轴：speed         │   │
│ │  + 退役 3                                    │   │
│ └──────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────┘
```

### 5.2 副官 persona 切换

Brainstorm 决议 Q4 = (b)：**persona 绑定连续 5 局后才能切换。**

UI 表面：
- 当前 persona 头像 + 名字 + 记忆摘要（只读；记忆整合在每局后由 08 §8 完成）
- "切换冷却：N/5 局"计数
- `[切换 persona]` 按钮——N < 5 时禁用并附 tooltip；N ≥ 5 启用并打开 persona 选择模态

Persona 选择模态：

```
┌──────────────────────────────────┐
│ 切换副官 persona                  │
│                                  │
│  ◉ 老兵   (当前 — 27 局)          │
│  ○ 激进  (12 局)                  │
│  ○ 学究  (3 局)                   │
│                                  │
│  每个 persona 各自维护记忆。      │
│  切换不会重置老兵。                │
│                                  │
│   [ 确认 ]   [ 取消 ]             │
└──────────────────────────────────┘
```

切换非破坏性——每个 `DeputyPersona` 各自有 `DeputyMemory` 文件（08 §8.1）。切换后锁定计数清 0。

测试旁路：debug 构建（`project.godot` 的 `debug=true`）绕过锁。v1 出厂锁开启；"我每局都想换"作为玩家请求的 setting 由 10+1 加。

### 5.3 自主度 dial

读写 `DeputyPersona.deputy_autonomy`（08 §9）。滑条三档标签按 08 §11.8：

```
Cautious  Balanced  Bold
  0.0       0.5      1.0
   ●─────────●─────────●
              ▲ current
```

短文案：

> "Bold 副官凭最佳猜测行动，仅在命令危险时澄清。Cautious 副官遇到任何歧义都先问。"

保存即生效，在下一局生效。

### 5.4 Captain 名册

只读表，列出有持久记忆的 captains（`MemoryStore.list_captains()`）。

列：

- **名字**（`captain_persona_id`）
- **角色**（combat / econ / scout）
- **出场**（`match_appearances`）
- **共胜**（`matches_won_alongside`）
- **死亡**
- **偏好轴**（— / hp / dps / sight / speed）
- **强化**（如 "+8% hp"）

点行 → captain 详情模态，显示 captain 的 anecdotes（最多 12 条）和"解释这个 captain"按钮——触发一次小 LLM 调用总结 captain 风格。

"退役" captain 是 persona 在最近 10 局未出现的；它们在 `MemoryStore` 里仍在但视觉上弱化；删除 captain 记忆是确认行为之后的故意破坏行为。

## 6. 设置标签

标准设置面板。分节：

| 节 | 设置 |
|---|---|
| **玩法** | 控制策略（FullControl / HeroOnly / AssistMode / ArchonControl，07 §8）；persona 切换锁（默认 5 局，可在此覆盖）；预案默认自动加载 |
| **输入** | 鼠标按键（11 §4.5 LMB 主）；摄像机键位（WASD/edge-scroll 切换，11 §5.3）；语音对讲键（占位延后） |
| **音频** | 主/SFX/音乐/副官语音音量；语音包（占位延后） |
| **视频** | 分辨率；窗口模式；UI 缩放；摄像机 pitch 覆盖（11 §5.2 默认 75°） |
| **语言** | English / 中文；仅影响显示字符串——内部 `StringName` ID 不变 |
| **开发者** | （仅 debug 构建）回放模式、mock LLM、日志详细度、`--archon-attach` 快捷键 |

设置写入 `user://settings.cfg` 经 `ConfigFile`。多数设置在启动 + tab 离开时读；控制策略在比赛开始时读（07 §8）。

## 7. Lobby 流程（v1：本地单人）

v1 出厂**无在线 lobby**。比赛标签 → 开始比赛 路径直接进单人比赛对脚本/MVP 风格敌方建筑（06 §5 延后——09 完整执行器落地前，敌方阵营保留为当前 MVP 敌方建筑）。

Lobby 表面为未来扩展（10+1 联网、12 回放）保留：

- **本地回放查看器**——打开存档的 `<match_id>.ndjson`（07 §9）对 stub world 回放。归 12。
- **联网 lobby**——加入远端比赛。延后到 12 联网子文档。
- **Archon attach**——v1 仅本地 F2 切换（08 §11.7）；完整联网 archon 延后。

代码从 v1 起预留三个 lobby 状态 `enum LobbyState { OFFLINE, IN_MATCH, REPLAY, NETWORK_LOBBY }`，即使只接通了 OFFLINE 与 IN_MATCH。

## 8. 记忆查看器（读取 08 的记忆文件）

营地标签读 `DeputyMemory` 与 `CaptainMemory`（08 §8 / §11.6），但**永不**在比赛中写。按 08 §8 唯一变更点是 `MemoryStore.consolidate_after_match(...)`。

10 营地 UI 因此是**比赛中只读、比赛间读写**的记忆编辑：

- **比赛间：** 删 anecdote、调 trait（仅 debug）、覆盖偏好轴（仅 debug）
- **比赛中：** 营地标签若被 alt-tab 看到仍可见，但所有写被"保存中"叠层挡住

captain 上的"删除记忆"按钮触发两步确认 + 先写 `user://deputies/<id>.tres.bak` 再删——软删除安全网。

## 9. 阵营未来钩子

09 §13 锁定 3 阵营路线（猫狗/鹅鸭/野生）。10 比赛标签的阵营下拉与营地标签的 persona 列表过滤器从今天起就为它准备：

```
阵营：[ shared (v1)        ▼ ]
       ──────────────────────
       · shared (v1)
       · 猫狗 (Cats & Dogs) — 锁定
       · 鹅鸭 (Geese & Ducks) — 锁定
       · 野生动物 (Wild) — 锁定
```

锁定项可见但灰显，附 tooltip 引向 09+1 的未来内容。把长期承诺烤进 UI，但不让 v1 工作量为它买单。

## 10. 资源与持久化映射

每个 UI 状态住在哪里：

| 表面 | 存储 |
|---|---|
| 预案（玩家） | `user://preplans/<player_id>/<map_id>/*.tres`（07 §7.2） |
| 预案（设计师） | `res://data/preplans/<map_id>/*.tres`（07 §7.2） |
| 玩家区域 | `user://player_regions/<player_id>/<map_id>.tres`（07 §3.3） |
| 副官记忆 | `user://deputies/<deputy_id>.tres`（08 §8） |
| Captain 记忆 | `user://captains/<captain_persona_id>.tres`（08 §11.6） |
| 设置 | `user://settings.cfg`（10 §6） |
| Persona 切换锁计数 | `user://settings.cfg` 内 |

10 UI **永不**新增持久化位置——以上每条路径都由兄弟规范（07 / 08 / 06 / 本节）拥有。UI 是读写者，不是新状态形态的作者。

## 11. 边界

- **10 ↔ 07：** 10 读 `OrderTypeRegistry`、写 `PrePlan` 与 `PlayerRegionSet`、调 `ShareCodeService.{encode,decode}`。10 不引入 07 其它内部。
- **10 ↔ 08：** 10 读 `DeputyMemory` / `CaptainMemory`（比赛间）。10 写 `DeputyPersona.deputy_autonomy`（v1 在 `DeputyPersona` 上的变更点）。10 调 `MemoryStore.list_captains()` / `MemoryStore.delete_captain(...)`（本文要求新增的方法）。
- **10 ↔ 09：** 10 读 `UnitDef.category` / `BuildingDef.category` 给编辑器下拉；读 `MapGrid` / `Landmark` 给区域工具。
- **10 ↔ 11：** 无直接依赖。11 治理局内手感；10 是局间。

## 12. 文件

### 新文件（本规范定义）

- `godot/scripts/ui/main_menu.gd` — 根标签壳
- `godot/scripts/ui/match_tab.gd`
- `godot/scripts/ui/warroom_tab.gd`
- `godot/scripts/ui/camp_tab.gd`
- `godot/scripts/ui/settings_tab.gd`
- `godot/scripts/ui/preplan_editor.gd`
- `godot/scripts/ui/order_edit_modal.gd`
- `godot/scripts/ui/region_painter.gd`
- `godot/scripts/ui/share_code_modal.gd`
- `godot/scripts/ui/persona_picker_modal.gd`
- `godot/scripts/ui/captain_detail_modal.gd`
- `godot/scripts/ui/share_code_service.gd` — 接口；编码器按 07 §8.5 延后
- `godot/scenes/main_menu.tscn` — 根菜单场景；10 落地后替换 `main.tscn` 为启动场景
- `godot/scenes/ui/*.tscn` — 每个模态/标签一个
- `godot/tests/test_main_menu.gd`
- `godot/tests/test_preplan_editor.gd`
- `godot/tests/test_region_painter.gd`
- `godot/tests/test_share_code_service.gd`

### 修改文件

- `godot/project.godot` — 把 `run/main_scene` 从 `main.tscn` 改为 `main_menu.tscn`（仅在 10 实施落地时；不在本文范围）
- `godot/scripts/bootstrap.gd` — 接受构造时的 lobby 状态，仅在"开始比赛"时分支进入比赛场景
- `docs/specs/05-godot-smoke-test-checklist.md` — 实施落地后追加主菜单启动章节

## 13. 验证（骨架）

10 实现"骨架完成"当且仅当：

1. `main_menu.tscn` 启动；四个标签无脚本错地渲染。
2. 比赛标签：打开后显示当前 `DeputyPersona` 与至少一张地图的下拉。
3. 备战标签：新建预案、用每个 `target_kind` 值编辑一条 order、保存——产生有效 `.tres` 文件在 `user://preplans/`。
4. 备战标签：无效预案显示 inline 错误并阻止保存。
5. 备战标签：`target_kind = param` 时四个参数化占位出现在 param 下拉。
6. 区域涂格器：点 5 个 grid cell、命名、保存——产生有效 `.tres` 在 `user://player_regions/`。
7. 分享码：在同玩家上生成、粘到导入、解决冲突——导入预案在列表中与原预案完全一致。
8. 营地标签：`match_count_since_persona_swap < 5` 时副官 persona 下拉锁定，5 时解锁。
9. 营地标签：自主度滑条变更持久化到 `DeputyPersona.deputy_autonomy` 并跨重启保留。
10. 设置标签：变更控制策略持久化到 `settings.cfg`，下次比赛启动被 `CommandBus` 读到。

10 出厂**不改局内**——它的工作完全在比赛循环之外。10 落地前玩家直接进比赛同当前 MVP 启动一致；零回归。

## 14. 开放问题

- **视觉 mockup**——Figma 文件延后。v1 实施前过设计师 review。
- **比赛标签上的比赛长度**——是否在地图预览旁显示 ~15 分钟目标？大概要，但非承重。
- **副官"删除记忆" UX**——目前 10 §8 允许 captain 记忆删除；副官记忆是否也允许？愿景 §2.3 暗示持久身份，删除副官记忆等于杀死它——10+1 处理。
- **预案"试运行"**——让玩家对冻结战场 snapshot 模拟预案以保存前验证。强大但重；延后到 10+1。
- **多语言副官语音包**——除显示字符串外，副官说语言。v1 出英文 + 中文 persona 作为独立 `.tres`；跨语言切换是延后特性。
- **教程流**——首次启动引导玩家走 比赛 → 备战 → 营地。10+1（教程子文档）规定。

## 15. 远期路线图

10+1 故意预留的丰富项，记录在此让 v1 别意外架构掉它们：

- 时间线模式预案编辑器（Q2 = B）
- 营地 3D 可视化（原 brainstorm Q1 = D——副官在战帐里）
- 联网 lobby + 匹配
- 与 12 集成的回放查看器
- 教程流
- Persona 删除 UX
- 预案试运行 sim
- 分享码社区评分（社区分享指数）
