# 矿物箔膜/全息效果 Shader 设计方案

## 1. 可行性结论

你提供的 shader 是一个 **2D 透视卡片 + 箔膜/全息（foil/holo）混合** 效果。核心能力有三层：

1. **透视倾斜**：根据鼠标与精灵的相对位置，对 Sprite 做伪 3D 旋转。
2. **箔膜着色**：按 `foilcolor` 与像素颜色的相似度，把彩虹/金属渐变 `gradient` 混合到原图上。
3. **质感增强**：用 `noise` 制造金属颗粒/闪光，用 `normal_map` 制造 grooves/纹理起伏感。

### 1.1 能不能直接用到矿物上？

**能，但需要改造。**

- 当前 shader 的透视部分是为“整张卡片”设计的；我们的矿物是等角网格（isometric）中的小方块，直接套用透视会导致方块歪斜、穿帮、甚至 `cull_back` 把背面裁掉。
- 建议 **把透视倾斜和箔膜效果解耦**：保留箔膜着色逻辑，把透视参数默认设为 `max_tilt = 0`（不倾斜），或单独写一个不带 vertex 透视、只带箔膜着色的简化版 shader。
- 矿物本身已经有 `Block.base_material` 插槽，可以直接把 ShaderMaterial 挂到 `ore.sprite` 上，和现有 hit_flash、outline、TNT 闪烁逻辑兼容。

### 1.2 适用对象

不建议给所有矿物都上 foil 效果（会产生视觉疲劳且增加 draw call）。推荐只给 **高稀有度或高价值矿物** 使用：

| 矿物 | 稀有度 | 是否推荐 |
|------|--------|----------|
| 泥土 / 煤矿 / 铁矿 / 锌矿 | 普通 | 否，保持朴素 |
| 金矿 | 稀有 | 是，金属光泽 |
| 钻石矿 | 稀有 | 是，彩虹棱镜 |
| 水晶矿 | 稀有 | 是，冰晶全息 |
| 黑曜石 | 稀有 | 是，虹彩暗面 |
| 猫矿 | 传说 | 是，彩虹迷因箔 |

下面给出 **5 种不同效果** 的详细设计。

---

## 2. Shader 关键参数说明

| 参数 | 作用 | 设计时可调范围 |
|------|------|----------------|
| `foilcolor` + `threshold` + `fuzziness` | 决定原图哪些区域会呈现箔膜效果 | 白色+threshold=1 全图生效；特定颜色+低 threshold 只高亮边缘 |
| `gradient` | 箔膜颜色随角度/位置变化 | 彩虹、金橙、冰蓝、紫绿油彩等 |
| `noise` | 金属颗粒/闪光密度 | 细腻=金属质感；粗大=结晶质感 |
| `normal_map` |  grooves/纹理起伏 | 低强度=平滑；高强度=浮雕感 |
| `effect_alpha_mult` | 箔膜混合强度 | 0 ~ 1，越低越“若隐若现” |
| `direction` | 渐变方向 | 0.5 对角；0 竖直；1 水平 |
| `scroll` / `period` | 渐变滚动与重复周期 | 配合鼠标移动产生动态 shimmer |
| `max_tilt` | 透视倾斜幅度 | **建议矿物版设为 0** |
| `inset` / `fov` | 透视补偿 | 关闭倾斜后可固定为默认值 |

---

## 3. 五种矿物效果设计

### 3.1 金矿 — 金属金箔（Metallic Gold Sheen）

- **视觉目标**：像金币/金箔一样，在鼠标移动时泛起暖金色光泽。
- **参数建议**：
  - `foilcolor = Color.WHITE`，`threshold = 1.0`，`fuzziness = 0.1`：全图都参与箔膜。
  - `gradient`：金 → 橙 → 浅黄 的水平渐变。
  - `noise`：细密颗粒，模拟金属砂纸感。
  - `normal_map`：非常弱（`normal_strength = 0.05`），只做轻微浮雕。
  - `effect_alpha_mult = 0.5`
  - `direction = 0.0`（水平反光）
  - `scroll = 0.8`，`period = 1.2`
  - `max_tilt = 0`
- **所需新增贴图**：
  - `assets/masks/foil_gold_mask.png`：可选，只想让矿石表面金箔化，阴影部分保持原样。
  - `assets/gradients/gradient_gold.png`：金橙渐变。
  - `assets/noise/noise_fine.png`：通用细密 noise。

### 3.2 钻石矿 — 彩虹棱镜（Prismatic Crystal）

- **视觉目标**：钻石切面折射出彩虹色，鼠标移动时彩虹在切面上滑动。
- **参数建议**：
  - `foilcolor = Color.WHITE`，`threshold = 1.0`：全图生效。
  - `gradient`：完整彩虹条（红橙黄绿青蓝紫）。
  - `noise`：中等密度，带一点“闪光点”。
  - `normal_map`：切面条纹，让彩虹随鼠标方向在切面上转折。
  - `effect_alpha_mult = 0.65`
  - `direction = 0.5`（对角反光，模拟多切面）
  - `scroll = 1.5`，`period = 0.8`
  - `max_tilt = 0`
- **所需新增贴图**：
  - `assets/gradients/gradient_rainbow.png`：彩虹渐变。
  - `assets/normal/normal_crystal.png`：切面条纹。

### 3.3 水晶矿 — 冰晶全息（Icy Holographic）

- **视觉目标**：冷色调、半透明的冰晶感，反光偏青/白/淡紫。
- **参数建议**：
  - `foilcolor = Color.WHITE`，`threshold = 1.0`。
  - `gradient`：青 → 白 → 淡紫 的柔和渐变。
  - `noise`：稀疏雪花状/结晶状。
  - `normal_map`：冰裂纹理。
  - `effect_alpha_mult = 0.55`
  - `direction = 0.3`
  - `scroll = 0.6`，`period = 1.5`
  - `max_tilt = 0`
- **所需新增贴图**：
  - `assets/gradients/gradient_ice.png`
  - `assets/noise/noise_crystal.png`
  - `assets/normal/normal_ice.png`

### 3.4 黑曜石 — 暗面虹彩（Obsidian Iridescent）

- **视觉目标**：整体暗黑，但在边缘/高光处泛出紫绿油光（像黑曜石或油膜）。
- **参数建议**：
  - `foilcolor = Color(0.2, 0.2, 0.2)`（深灰），`threshold = 0.25`，`fuzziness = 0.2`：只让矿石较亮的边缘/高光参与。
  - `gradient`：紫 → 绿 → 暗红 的油彩渐变。
  - `noise`：稀疏大颗粒，制造暗色中的零星闪光。
  - `normal_map`：粗糙岩面。
  - `effect_alpha_mult = 0.35`（低强度，保持黑曜石的暗调）
  - `direction = 0.7`
  - `scroll = 0.4`，`period = 2.0`
  - `max_tilt = 0`
- **所需新增贴图**：
  - `assets/masks/foil_obsidian_mask.png`：只让边缘亮部生效。
  - `assets/gradients/gradient_oil.png`
  - `assets/normal/normal_rock.png`

### 3.5 猫矿 — 彩虹迷因箔（Rainbow Meme Foil）

- **视觉目标**：夸张的全息彩虹 + 强闪光，符合“传说级/玩梗”定位。
- **参数建议**：
  - `foilcolor = Color.WHITE`，`threshold = 1.0`。
  - `gradient`：高饱和彩虹 + 洋红/青跳色。
  - `noise`：高密度闪光颗粒。
  - `normal_map`：强浮雕，让颜色剧烈运动。
  - `effect_alpha_mult = 0.8`
  - `direction = 0.5`
  - `scroll = 2.0`，`period = 0.6`
  - `max_tilt = 0`
- **所需新增贴图**：
  - `assets/gradients/gradient_meme.png`：高饱和彩虹。
  - `assets/noise/noise_glitter.png`：亮片感 noise。

---

## 4. 工程接入方案

### 4.1 Shader 改造

建议先fork一份矿物专用 shader：`scripts/shaders/ore_foil.gdshader`，基于你提供的代码做以下修改：

1. **默认关闭透视**：
   - `uniform float max_tilt : hint_range(0, 2.0) = 0.0;`
   - 或者直接把 vertex 里的透视矩阵去掉，只保留箔膜逻辑。
2. **加入鼠标全局 uniform（可选优化）**：
   - 把 `mouse_position` 改成 `global uniform vec2 mouse_position;`，避免每帧给每个矿物 material 单独 set。
   - 保留 `sprite_position` 作为普通 uniform（每个矿物仍需知道自己位置）。
3. **UV 保持原图比例**：
   - 当 `max_tilt == 0` 时，让 `adjusted_uv = UV`，避免当前 shader 在无旋转时产生缩放/偏移。
4. **（可选）发光层**：
   - 加一个 `uniform float emission_strength`，把 foil 后的高亮区域再叠加一次自发光，用于钻石/猫矿的“闪耀”效果。

### 4.2 资源组织

```
assets/
  gradients/
    gradient_gold.png
    gradient_rainbow.png
    gradient_ice.png
    gradient_oil.png
    gradient_meme.png
  noise/
    noise_fine.png
    noise_crystal.png
    noise_glitter.png
  normal/
    normal_crystal.png
    normal_ice.png
    normal_rock.png
  masks/
    foil_gold_mask.png
    foil_obsidian_mask.png
```

### 4.3 代码接入

1. **给 `OreDef` 增加可选材质**：
   - 在 `scripts/game/block/ore_def.gd` 里加 `@export var foil_material: ShaderMaterial = null`。
   - 给 5 种矿物 `.tres` 分别挂上对应参数的材质实例。
2. **在 `Block`/`OreBlock` 里启用材质**：
   - 在 `setup_from_def` 或 `_ready` 中，如果 `def` 是 `OreDef` 且有 `foil_material`，则赋值给 `base_material` 并调用 `_refresh_sprite_material()`。
3. **更新 shader 参数**：
   - 在 `Block._process` 中检测：如果 `sprite.material` 是 ore_foil 材质，则每帧设置：
     - `material.set_shader_parameter("sprite_position", global_position)`
     - 若未使用 global uniform，则还需设置 `material.set_shader_parameter("mouse_position", get_global_mouse_position())`。
   - 为了性能，建议：
     - 在 `GameManager` 里统一把鼠标位置写进 global shader parameter。
     - 每个矿物只更新自己的 `sprite_position`，且只在屏幕内/可见时更新。

### 4.4 与现有特效的优先级

当前 `Block._refresh_sprite_material` 的优先级是：

1. 受击闪白 `_flash_material`
2. 外部 `base_material`（foil 材质放这里）
3. 悬停描边 `_outline_material`
4. 无材质

这意味着：
- 矿物被挖时仍会闪白（覆盖 foil）。
- 鼠标悬停时显示描边（覆盖 foil），移开后恢复 foil。
- TNT 的闪烁 shader 本身也走 `base_material`，所以 TNT 不会同时有 foil，符合设计。

---

## 5. 性能与风险

### 5.1 性能

- 每个使用 foil 的矿物都会多一份 `ShaderMaterial` 实例，且 shader 里采样 4 张额外贴图（mask/gradient/noise/normal）。
- 如果全屏大量矿物都开启 foil，draw call 和 GPU 采样压力会明显上升。
- **建议**：仅给稀有矿物开启；普通矿物保持原样。
- 鼠标位置若用普通 uniform 逐个设置，每帧遍历所有矿物会有 CPU 开销；推荐改用 `global_shader_parameter`。

### 5.2 视觉风险

- `foilcolor` 阈值调不好会让普通像素也泛出怪色，建议每种矿物单独调参并在实际场景中测试。
- 等角网格下如果保留透视倾斜，矿物在网格中会显得“立起来”，与地块不对齐；**务必默认关闭倾斜**。
- 当前 shader 无旋转时 UV 会缩放，需改造或调整 `inset`/`fov` 到原图 1:1。

### 5.3 兼容性

- 该 shader 是 `canvas_item` 类型，与 Godot 4.x 2D 渲染管线兼容。
- 导出到桌面/移动端均支持，但低端设备上额外 4 次贴图采样可能拖帧。

---

## 6. 推荐下一步

1. 先创建 `scripts/shaders/ore_foil.gdshader`（关闭透视、支持 global mouse uniform）。
2. 制作 5 张渐变图和 2~3 张通用 noise/normal 贴图。
3. 给 `OreDef` 加 `foil_material` 字段，为 5 种矿物配置材质实例。
4. 在 `Block` 中接入材质，并在 `GameManager` 中统一更新鼠标位置。
5. 在编辑器里跑起来，针对每种矿物微调 `effect_alpha_mult` / `threshold` / `direction`。

---

## 附录：快速参数速查表

| 效果 | foilcolor | threshold | effect_alpha_mult | direction | scroll | period | normal_strength |
|------|-----------|-----------|-------------------|-----------|--------|--------|-----------------|
| 金矿金属箔 | 白 #FFFFFF | 1.0 | 0.50 | 0.0 | 0.8 | 1.2 | 0.05 |
| 钻石彩虹棱镜 | 白 #FFFFFF | 1.0 | 0.65 | 0.5 | 1.5 | 0.8 | 0.10 |
| 水晶冰全息 | 白 #FFFFFF | 1.0 | 0.55 | 0.3 | 0.6 | 1.5 | 0.08 |
| 黑曜石虹彩 | 深灰 #333333 | 0.25 | 0.35 | 0.7 | 0.4 | 2.0 | 0.12 |
| 猫矿彩虹箔 | 白 #FFFFFF | 1.0 | 0.80 | 0.5 | 2.0 | 0.6 | 0.15 |

> 所有方案默认 `max_tilt = 0`，即不启用透视倾斜。
