# 天赋系统设计 V4：可重复升级节点 + Foil Shader 视觉

> 目标：把原本"一长串线性单级节点"改成"每个节点可反复点击、最高升到 5 级"的紧凑天赋树；并按节点类别挂上 shadertest 里那套 Balatro 风格 foil shader，让不同分支有鲜明的视觉识别。

---

## 1. 核心改动

### 1.1 节点可升 5 级

- 绝大多数普通天赋节点统一 `max_rank = 5`。
- 特殊节点保持 1 级：重置·升华、升华天赋、永久槽等。
- 点击已购买但未满级的节点 = 继续升级，而不是无效。
- 旧版线性链（如 `pickaxe_dmg_1/2/3`、`coin_bonus_1~6`、`prod_coal_01~10`）全部合并成单个可升级节点。

### 1.2 等级效果公式

| 公式类型 | 写法 | 示例 |
|---|---|---|
| 线性叠加 | `+X*level` | 基础伤害 +2/级 → 满级 +10 |
| 百分比叠加 | `+X%*level` | 全局金币 +15%/级 → 满级 +75% |
| 指数翻倍 | `×2^level` | 矿产价值 L2~5 每级 ×2，累计 ×16 |
| 解锁型 | `unlock at level 1` | L1 解锁，L2~5 强化效果 |
| 协同型 | `+X% per placed tile` | 每放置 1 个目标地块，额外 +Y% |

### 1.3 成本曲线

```text
第 n 级成本 = base_cost × cost_mult^(n-1)
```

- 稿子/金币类 `cost_mult = 5`：快速进入中盘价格。
- 地块/矿产类 `cost_mult = 10`：体现解锁 + 指数翻倍的成长感。

---

## 2. 天赋分类与节点设计

### 2.1 稿子类（Ice Blue Foil）

挂在 `scripts/shaders/balatro_foil_ice.gdshader`，冰蓝色调。

> 布局：稿子节点统一放在重置节点**上方**（row < 0, col = 0）。

| ID | 名称 | 每级效果 | 基础成本 | cost_mult | 坐标 (col,row) | 前置 |
|---|---|---|---|---|---|---|
| `pickaxe_root` | 稿子精通 | 解锁稿子升级链（1 级） | 100 | - | (0, -1) | 开局可见 |
| `pickaxe_dmg` | 稿子·锋利 | 基础伤害 +2 | 500 | 5 | (0, -2) | pickaxe_root |
| `pickaxe_crit` | 稿子·精准 | 暴击几率 +3% | 1,000 | 5 | (0, -3) | pickaxe_root |
| `pickaxe_crit_dmg` | 稿子·重击 | 暴击伤害 +20% | 2,500 | 5 | (0, -4) | pickaxe_crit |
| `pickaxe_range` | 稿子·延伸 | 攻击范围 +2 像素/级 | 5,000 | 5 | (0, -5) | pickaxe_dmg |
| `pickaxe_extra` | 稿子·连击 | 额外攻击几率 +10% | 10,000 | 5 | (0, -6) | pickaxe_range |

### 2.2 金币类（Gold Foil）

挂在 `scripts/shaders/balatro_foil_gold.gdshader`，金黄色调。

> 布局：金币节点统一放在重置节点**左方**（col < 0）。

| ID | 名称 | 每级效果 | 基础成本 | cost_mult | 坐标 (col,row) | 前置 |
|---|---|---|---|---|---|---|
| `coin_bonus` | 金币收益 | 全局金币获取 +15% | 100 | 5 | (-1, 0) | 开局可见 |
| `dirt_synergy` | 土质丰饶 | 每放置 1 个 dirt 地块，全局产值 +1% | 1,000 | 5 | (-2, 0) | coin_bonus |
| `stone_synergy` | 石脉煤矿 | 每放置 1 个 stone 地块，coal 产值 +2% | 2,500 | 5 | (-2, 1) | coin_bonus |
| `grass_synergy` | 草地点金 | 每放置 1 个 grass 地块，gold 产值 +2% | 25,000 | 5 | (-3, 0) | dirt_synergy |
| `water_synergy` | 水域沉宝 | 每放置 1 个 water 地块，全局沉没返还 +0.5% | 50,000 | 5 | (-3, 1) | stone_synergy |
| `ore_value_global` | 落矿收益 | 矿石结算价值 +10% | 100,000 | 5 | (-4, 0) | coin_bonus |

### 2.3 地块类（Void Purple Foil）

挂在 `scripts/shaders/balatro_foil_void.gdshader`，虚空紫色调。

> 说明：这里的"土块/石块"指 `defs/tiles/` 里的地块。L1 解锁该地块的放置权；L2~5 把该地块的核心效果翻倍一次（×2/级）。
> 布局：地块节点统一放在重置节点**下方**（row > 0），避免和右侧矿产重叠。

| ID | 名称 | 每级效果 | 基础成本 | cost_mult | 坐标 (col,row) | 前置 |
|---|---|---|---|---|---|---|
| `tile_dirt` | 土地开拓 | L1 解锁 dirt；L2~5 dirt 相关协同效果 ×2 | 0 | 10 | (0, 1) | 开局可见 |
| `tile_grass` | 草地培育 | L1 解锁 grass；L2~5 grass 伤害倍率 ×2 | 100 | 10 | (-1, 2) | tile_dirt |
| `tile_stone` | 石质改良 | L1 解锁 stone；L2~5 stone 价值倍率 ×2 | 500 | 10 | (1, 2) | tile_dirt |
| `tile_water` | 水域开拓 | L1 解锁 water；L2~5 water 沉没返还 ×2 | 2,500 | 10 | (1, 3) | tile_stone |
| `tile_fire` | 熔岩引流 | L1 解锁 fire；L2~5 fire 每秒伤害 ×2 | 12,500 | 10 | (-1, 3) | tile_grass |
| `tile_conveyor` | 传送带 | L1 解锁 push；L2~5 push 周期减半（最多到 0.3s） | 50,000 | 10 | (0, 4) | tile_fire |

### 2.4 矿产类（Rainbow Holo Foil）

挂在 `scripts/shaders/balatro_foil_rainbow.gdshader`，彩虹全息色调。

> 说明：这里的"矿产"指 `defs/ores/` 里的矿石。L1 解锁该矿进入自然落矿池；L2~5 每级让该矿结算价值 ×2。
> 布局：矿产节点统一放在重置节点**右方**（col > 0, row = 0），和下方地块、上方稿子、左方金币互不重叠。

| ID | 名称 | 每级效果 | 基础成本 | cost_mult | 坐标 (col,row) | 前置 |
|---|---|---|---|---|---|---|
| `ore_dirt` | 泥土开采 | L1 解锁 dirt 矿；L2~5 dirt 价值 ×2 | 0 | 10 | (1, 0) | 开局可见 |
| `ore_coal` | 煤矿开采 | L1 解锁 coal；L2~5 coal 价值 ×2 | 50 | 10 | (2, 0) | ore_dirt |
| `ore_iron` | 铁矿开采 | L1 解锁 iron；L2~5 iron 价值 ×2 | 250 | 10 | (3, 0) | ore_coal |
| `ore_zinc` | 锌矿开采 | L1 解锁 zinc；L2~5 zinc 价值 ×2 | 2,500 | 10 | (4, 0) | ore_iron |
| `ore_gold` | 金矿开采 | L1 解锁 gold；L2~5 gold 价值 ×2 | 25,000 | 10 | (5, 0) | ore_zinc |
| `ore_crystal` | 水晶开采 | L1 解锁 crystal；L2~5 crystal 价值 ×2 | 250,000 | 10 | (6, 0) | ore_gold |

### 2.5 特殊矿类（Crimson Foil）

挂在 `scripts/shaders/balatro_foil_crimson.gdshader`，暗红/猩红色调，与矿物分支的彩虹全息区分。

> 说明：这里的“特殊矿”指自然落矿时附加的 3 种变体——彩虹矿（全局价值翻倍 60 秒）、富矿（5 倍价值 / 3 倍血）、脆矿（一击即碎）。基础出现几率为 0，购买对应天赋后解锁并提升概率。三者按累计阈值判定：先 roll 彩虹 → 再 roll 富矿 → 最后 roll 脆矿。
> 布局：特殊矿节点挂在矿物链下方，从 `ore_coal` 向右延伸，避免与地块分支重叠。

| ID | 名称 | 每级效果 | 基础成本 | cost_mult | 坐标 (col,row) | 前置 |
|---|---|---|---|---|---|---|
| `special_value_buff` | 彩虹矿脉 | 彩虹矿出现几率 +2% | 5,000 | 5 | (2, 1) | ore_coal |
| `special_high_value` | 富矿矿脉 | 富矿出现几率 +4% | 10,000 | 5 | (3, 1) | special_value_buff |
| `special_fragile` | 脆矿矿脉 | 脆矿出现几率 +7% | 25,000 | 5 | (4, 1) | special_high_value |

> 满级概率：彩虹 10%、富矿累计 30%、脆矿累计 65%。数值设计偏激进，让玩家在中盘能频繁遇到特殊矿。

### 2.6 升华/特殊节点

保持 1 级，视觉沿用现有方案。

| ID | 名称 | 效果 | 视觉 |
|---|---|---|---|
| `talent_reset` | 重置·升华 | 重置本轮普通天赋，结算升华点 | `reset_orb.gdshader` 球缸 |
| `meta_legacy` | 矿业传承 | 启用升华点与声望 | 升华树中心 |
| ... | 其他升华天赋 | 见 `ascension_talent_design.md` | 默认或按类别着色 |

---

## 3. 视觉与 Shader 映射

### 3.1 等级 → Shader 外观

所有普通天赋节点统一使用 `scripts/shaders/card.gdshader`（Balatro 风格 3D foil），并根据当前 **rank（0~5）** 切换外观。外观直接复用 `scenes/vfx/shadertest.tscn` 里的 5 档设计：

| 节点等级 | 外观 | gradient | normal_map | threshold | effect_alpha_mult | 说明 |
|---|---|---|---|---|---|---|
| rank 0 / 未购买 | 无 foil 效果 | - | - | - | - | 锁定/可买状态保持原图标 |
| rank 1 | 银白光泽 | 默认 | 默认 | 1.0 | 0.5 | 刚购买时的基础光泽 |
| rank 2 | 青色-蓝色微光 | 青-蓝-青渐变 | `normal_circles.jpg` | 1.0 | 0.15 | 开始显色 |
| rank 3 | 绿色微光 | 绿-深绿-绿渐变 | `7813-normal.jpg` | 1.0 | 0.15 | 中段成长 |
| rank 4 | 黑白微光 | 黑-白-黑渐变 | `groovy normal.png` | 1.0 | 0.15 | 高阶 |
| rank 5 | 彩虹全息 | `gradient_rainbow.png` | `12551-normal.jpg` | 1.0 | 0.15 | 满级大师外观 |

公共 sampler：`foil_mask` = `assets/masks/foil_mask.png`，`noise` = `assets/noise/noise_fine.png`，`foilcolor` = 白色。

> 已购买节点（rank ≥ 1）统一显示为 `PURCHASED` 状态（scale 1.0、alpha 1.0），和满级节点一样大、一样不透明；rank 标签区分具体等级。

重置节点仍使用 `scripts/shaders/reset_orb.gdshader` 球缸；升华天赋可沿用默认或单独设计。

> **当前代码状态**：foil shader 效果已临时禁用，`TalentNode` 只显示原图标 + 悬停描边 + 右下角 `Lv.x` 标签。下表保留作为后续重新开启时的参数参考。

### 3.2 TalentNode 需要支持的改动

1. **统一使用 `card.gdshader`，直接挂在 `Icon` 上**：
   - 图标已提前烘焙成独立 `ImageTexture`，避免 AtlasTexture 的 UV 问题。
   - `enable_tilt = false` 取消透视倾斜，但保留鼠标距离带来的微光流动。
   - 由于图标颜色偏浅，统一使用 `foilcolor = 白色`、`threshold = 1.0`，确保整张贴图都有光泽。
   - 根据 `current_rank` 设置 `gradient`、`normal_map`、`normal_strength`、`effect_alpha_mult`。
2. **悬停描边独立层**：
   - 悬停描边用独立的 `OutlineSprite` 子节点，大小与 `Icon` 对齐，挂 `outline.gdshader`。
   - 描边材质开启 `only_outline = true`，只画外框、中心透明，避免悬停时盖住 `Icon` 的 foil 效果。
3. **每帧更新 shader 参数**：
   - `mouse_position` = 全局鼠标位置
   - `sprite_position` = 节点全局位置
4. **等级显示**：
   - 节点右下角加 `Label` 显示 `Lv.x`。
   - rank 变化时同步刷新 shader 外观。

---

## 4. CSV 结构调整

### 4.1 新增/修改列

| 列名 | 说明 |
|---|---|
| `max_rank` | 从 `1` 改成 `5`（特殊节点保持 1） |
| `value` | 支持带 `level` 占位符的公式，如 `"+2*level"`、`"×2^level"`、`"+0.1*level"` |
| `cost_mult` | 每级成本乘数（默认 5） |
| `group` | 决定 shader 类别：稿子 / 金币收益 / 地块 / 矿物 / 特殊矿 |

### 4.2 删除旧节点

旧版线性链全部删除，合并为单节点：

- `pickaxe_dmg_1/2/3` → `pickaxe_dmg`
- `pickaxe_crit_1/2` → `pickaxe_crit`
- `coin_bonus_1~6` → `coin_bonus`
- `unlock_coal` + `prod_coal_01~10` → `ore_coal`
- `unlock_iron` + `prod_iron_01~10` → `ore_iron`
- ...

### 4.3 示例 CSV 行（普通天赋）

```csv
"id","name","description","currency","cost","cost_display","cost_mantissa","cost_exponent","col","row","prerequisite_ids","prerequisite_ranks","ascension_prerequisite_id","unlock_condition","effect_type","target_ids","operation","value","max_rank","cost_mult","secondary_effect","group","branch","level","stage","requires_big_number"
"pickaxe_dmg","稿子·锋利","[color=#67E9F8][b]稿子基础伤害[/b][/color] [color=#86EFAC][b]+2×等级[/b][/color]。","金币","500","500","5","2","0","-2","pickaxe_root","1","","","PICKAXE_DAMAGE_FLAT","pickaxe","ADD","2*level","5","5","","稿子","pickaxe","1","本轮核心","false"
"coin_bonus","金币收益","[color=#67E9F8][b]全局金币获取[/b][/color] [color=#86EFAC][b]+15%×等级[/b][/color]。","金币","100","100","1","2","-1","0","","","","开局可见","GLOBAL_COIN_MULT","all","ADD","0.15*level","5","5","","金币收益","coin","1","本轮核心","false"
"ore_coal","煤矿开采","[color=#67E9F8][b]煤矿[/b][/color][color=#67E9F8][b]解锁[/b][/color]；L2~5 每级价值 [color=#86EFAC][b]×2[/b][/color]。","金币","50","50","5","1","2","0","ore_dirt","1","","","UNLOCK_ORE_VALUE_MULT","coal","MULTIPLY","2^(level-1)","5","10","","矿物","coal","Unlock","本轮核心","false"
"tile_stone","石质改良","[color=#67E9F8][b]石头地块[/b][/color][color=#67E9F8][b]解锁[/b][/color]；L2~5 价值倍率 [color=#86EFAC][b]×2[/b][/color]。","金币","500","500","5","2","1","1","tile_dirt","1","","","UNLOCK_TILE_BEHAVIOR","stone","MULTIPLY","2^(level-1)","5","10","","地块","stone","1","本轮核心","false"
```

> 注：`ore_coal` 这种"L1 解锁 + L2~5 翻倍"的节点，effect_type 需要新的复合类型 `UNLOCK_ORE_VALUE_MULT`，或在 `TalentSystem` 中拆成"解锁"和"价值倍率"两个效果统一处理。

---

## 5. 数值设计原则

1. **指数可见**：矿产/地块类 L5 累计 ×16，让玩家明显感到"这一支变强了十倍"。
2. **线性稳定**：稿子/金币类每级稳定 +X，避免前期过度膨胀。
3. **协同上限**："每放置 1 个地块 +Y%" 类效果需要设置软上限或衰减，防止后期无限堆叠。
4. **前置节奏**：所有节点的前置条件统一为"前置节点已购买过即可"（rank ≥ 1），降低解锁门槛，让玩家可以自由选择先 deepening 还是先 broadening 天赋树。

---

## 6. 实现要点

### 6.1 数据层

- `TalentDef`：
  - 保留 `max_rank: int`。
  - 新增 `cost_mult: int = 5`（从 CSV 读取）。
  - `value` 字符串支持公式解析，或在 `TalentSystem` 中按 `current_rank` 计算。
- `GameState`：
  - 购买记录从 `Dictionary[StringName, bool]` 改成 `Dictionary[StringName, int]`（记录当前等级）。
  - 提供 `get_talent_rank(id: StringName) -> int`。
  - `record_talent_purchase(id)` 时如果已存在则 rank += 1，直到 max_rank。

### 6.2 逻辑层

- `TalentSystem`：
  - 解析 `value` 中的 `level` 占位符，根据当前 rank 计算实际数值。
  - 新增 effect_type 处理：
    - `PICKAXE_AOE`：累加到稿子挖矿范围半径（像素），`GameManager` 实时同步到鼠标空心圆。
    - `UNLOCK_ORE_VALUE_MULT`：rank >= 1 时解锁，rank >= 2 时应用 `(rank-1)` 次 ×2。
    - `UNLOCK_TILE_BEHAVIOR`：rank >= 1 时解锁地块，rank >= 2 时强化效果。
    - `SYNERGY_PER_TILE`：根据已放置目标地块数量动态计算加成。
    - `SPECIAL_VALUE_BUFF_CHANCE` / `SPECIAL_HIGH_VALUE_CHANCE` / `SPECIAL_FRAGILE_CHANCE`：分别累加三种特殊矿的累计出现阈值。
- `TalentGrid._click(node)`：
  - 如果节点已满级，无操作。
  - 如果买得起，购买并 rank += 1；购买特效按当前 rank 调整强度（满级更炫）。

### 6.3 表现层

- `TalentNode.setup(def)`：
  - 根据 `def.group` 选择 shader，创建 `ShaderMaterial` 并赋给 `icon_sprite`。
  - 等级 Label 初始隐藏，购买后更新。
- `TalentNode._process(delta)`：
  - 如果自身有 foil shader material，每帧更新 `mouse_position` 和 `sprite_position`。
- `TalentNode.set_state()`：
  - 已满级时 modulate 增加微光或金色描边。

### 6.4 Shader 兼容性

- `outline.gdshader` 与 foil shader 不能同时挂在同一个 `icon_sprite.material` 上。
- 方案：
  - foil shader 挂 `icon_sprite.material`。
  - 悬停描边改用一个独立的 `Sprite2D` 子节点（`OutlineSprite`），尺寸比 icon 大一圈，常态透明，悬停时显示并挂 outline shader。
  - 或把 outline 画在 `TalentGrid` 的叠加层，通过世界坐标绘制矩形描边。

---

## 7. 后续可扩展

1. **L5 满级特效**：节点达到 5 级后，shader 的 `effect_alpha_mult` 自动提高，产生"大师级"光泽。
2. **跨类别协同**：例如"稿子·连击 Lv.5 + 金矿开采 Lv.5" 解锁隐藏节点"炼金手"。
3. **升华对应**：升华天赋也可以改成 5 级，跨轮永久成长。
4. **动态价格**：根据本轮已购买等级总数，全局微调后续成本，防止单轮买满所有节点。
