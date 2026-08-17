# Beam Visual Type Design

## Goal
`goal-skill-visual-projection-layer-v1.5-beam-design`

## Scope
本设计文档仅定义 VisualType `beam` 的展示层模型与接口，不包含任何代码实现变更。

## 0) Background
当前项目已完成 `sky_strike` 的表现层模板化：
- 几何与视觉尺寸解耦
- `visual_type` 驱动 `VisualEffect` 创建
- `skill_visual_profiles.json` 进入 `schema_version` 化管理

在此基础上，下一步先完成 `beam` 的标准化设计，再进入迁移与实现。

## 1) Beam 的定义

Beam 不是“普通静态序列帧动画”，而是一类“方向性连续视觉元”

Beam 由五项状态驱动：

- `origin`
- `direction`
- `length`
- `width`
- `duration`
- `termination_rule`

### 典型示意（Laser 作为当前案例）

```text
caster_position -> direction -> declared_length -> terrain/impact cutoff -> actual_length -> continuous visual playback
```

### 关键边界

- Beam 的长度与方向不是纯视觉参数；长度来自 Gameplay 计算结果
- Beam 的持续性通常与视觉生命周期与状态机相关
- Beam 的宽度是视觉参数，可通过 profile 驱动

## 2) Beam Profile Schema（仅设计）

新增 `skill_visual_profiles.json` 中的 `visual_profile` 建议结构：

```json
{
  "visual_type": "beam",
  "geometry_binding": {
    "length": "snapshot_axis",
    "direction": "snapshot_axis",
    "width": "profile"
  },
  "animation": {
    "scale_mode": "axis_scaled",
    "texture_scale": {
      "width": 1.0,
      "height": 1.0
    }
  },
  "anchor": {
    "type": "caster_forward",
    "offset": [0, 0]
  },
  "lifecycle": {
    "mode": "continuous",
    "warning": 0.0,
    "impact": 0.0,
    "duration": 0.5
  },
  "geometry_binding_metadata": {
    "declared_length": "snapshot.declared_effect_length_gu",
    "actual_length": "snapshot.resolved_effect_length_gu",
    "collision_cutoff_contract": "skills.caster.line_collision_cutoff.v1"
  },
  "ground_projection": {
    "enabled": true
  },
  "visual_binding": {
    "width": "visual_profile.animation.width_scale",
    "color": "#7ec7ff",
    "animation_speed": 1.0
  }
}
```

### Schema 设计说明

- `visual_type`：统一入口，决定 `CasterSkillVisualFactory` 路由。
- `geometry_binding.length`：推荐值 `snapshot_axis`。
- `geometry_binding.direction`：推荐值 `snapshot_axis`。
- `geometry_binding.width`：推荐值 `profile`。
- `animation.scale_mode`：统一为 `axis_scaled`。
- `anchor.type`：`caster_forward`，表示起点对齐施法者方向。
- `lifecycle.mode`：`continuous` 表示持续显示到 `actual_length` 生命周期结束。

## 3) Beam 与 Visual/Gameplay 职责划分

### Gameplay 层提供（真值来源）
- `origin`
- `direction`
- `declared_length`
- `actual_length`
- `stops_on_terrain`
- `declared_vs_actual_length` 的判定依据
- `termination_rule`（例如 terrain cut off）

### Visual 层提供（表现来源）
- `texture`
- `width`
- `glow`
- `animation_speed`
- `color`
- `particle`
- `visual_profile.geometry_binding`

### 禁止项

- `visual length` 不得决定伤害范围
- `visual scale` 不得反向决定碰撞或 `SkillFootprintSnapshot`

### 绑定约束（必须）

- Gameplay 产出的 `declared_length` 与 `actual_length` 都必须被记录/保留
- Visual 展示应优先使用 `actual_length`（可带上 `declared_length` 仅用于 UI/调试）

## 4) Beam 未来数据流（目标）

```text
skill_visual_profiles.json
        ↓
visual_type: beam
        ↓
CasterSkillVisualFactory
        ↓
CasterSkillBeamVisualEffect
        ↓
CasterSkillVisualProfile + SkillFootprintSnapshot
        ↓
AnimationPlayer（axis_scaled/持续播放）
```

```text
Gameplay (caster/layer)
  ├─ 声明长度 declared_length
  ├─ 生成 snapshot（actual_length + geometry_axis）
  ├─ 记录 stops_on_terrain 截断结果
  ↓
Visual Input
  ├─ length: actual_length
  ├─ direction: snapshot.axis
  ├─ width: profile.width
  ├─ lifecycle: continuous
  └─ renderer: axis_scaled beam sprite/particle
```

## 5) Laser 当前数据流（现状）

```text
wizard_skill_runtime
  → effect_length_gu/effect_width_gu/stops_on_terrain/line_geometry_contract
        ↓
game_root
  → _canonical_continuous_line_strip_ground_gu
  → direction_ground_gu/declared/effect_length
  → terrain cutoff（stops_on_terrain）
  → resolved/declared length 写入 snapshot metadata
        ↓
caster_spell_geometry
  → continuous_line_strip_ground_gu / visual_context_from_plan
  → desired_sprite_axis_extent_px 与 desired_sprite_cross_axis_extent_px
        ↓
CasterSkillRuntime.create_visual
  → CasterSkillVisualEffect（非 beam 类型）
        ↓
CasterSkillVisualEffect + AnimationPlayer
  → axis/cross 缩放显示
        ↓
CasterSkillVisualEffect 特化逻辑
  → 单实例组 `_single_active_laser_visual_group`
```

现状特征：
- 长度、方向、截断主要来自 gameplay/snapshot
- 显示端仍为基于 `desired_sprite_*` 的通用 line 渲染路径
- 处理逻辑与 sky_strike/hellfire 共享/混用，尚未独立成 beam type

## 6) 设计时可迁移字段（建议）

### 可迁移到 Beam Profile/Effect 的候选
- `geometry_binding.length = snapshot_axis`
- `geometry_binding.direction = snapshot_axis`
- `geometry_binding.width = profile`
- `animation.scale_mode = axis_scaled`
- `anchor.type = caster_forward`
- `visual_profile.lifecycle.mode = continuous`
- `ground_projection.enabled`

### 当前字段到 Beam 字段的映射建议

- `desired_sprite_axis_extent_px` 是否可替换为 `geometry_binding.length`：
  - 建议：**可以部分替换**。`desired_sprite_axis_extent_px` 的来源若已经是合法 snapshot 轴向长度（且非临时回退值），则映射到 `snapshot_axis` 更清晰。

- `desired_sprite_cross_axis_extent_px` 是否可替换为 `visual_profile.width`：
  - 建议：**可以替换**。宽度应从 profile 表示，避免 gameplay 长度策略污染 visual width。

## 7) 设计时不可迁移字段（不应替换）

- `geometry_binding.direction` 不能直接等价 `caster look`（必须来自 snapshot/geometry 轴）
- Laser 的单实例管理组策略（`_single_active_laser_visual_group`）
- `stops_on_terrain` 的业务判断与截断规则（仍属于 gameplay/snapshot 层）
- `declared/actual_length` 计算与验证流程

## 8) Laser 迁移问题答复

1. `desired_sprite_axis_extent_px` 是否可替换为 `geometry_binding.length`？
   - **是，但需边界保护。** 条件是 snapshot 已稳定提供“实际可见轴向长度”；若几何尚未合法，需 fallback 或视为 `schema` 报错。\
2. `desired_sprite_cross_axis_extent_px` 是否可替换为 `visual_profile.width`？
   - **是。** Beam 视觉宽度应 profile 驱动，独立于 gameplay 长度。
3. `_single_active_laser_visual_group` 如何迁移？
   - **保留语义，后置在 BeamVisualEffect 内部实现。** 先保留规则在迁移过渡层，避免多实例光束并发导致行为回归。
4. Hellfire 是否共享 Beam？
   - **不能共享。** Hellfire 当前是 area/strip 概念，属于非 Beam 的 `area`/`line strip + trail` 行为，不进入 Beam type。

## 9) 风险列表

- Beam 视觉与地形截断语义耦合不足
- 声明长度与实际长度断点不一致导致视觉锚点漂移
- 单实例管理迁移不彻底导致旧 laser 的叠加/覆盖行为变化
- 16向量/方向量化策略与快照轴不一致导致抖动
- 旧版 profile fallback 与新 `geometry_binding` 的兼容窗口不完整

## 10) 预计修改文件（设计阶段）

### 仅设计产出
- `docs/skill_visual_beam_design.md`

### 迁移实现阶段（不在本目标内）
- `assets/data/skill_visual_profiles.json`
- `scripts/caster_skill_visual_factory.gd`
- `scripts/caster_skill_runtime.gd`
- `scripts/caster_skill_animation_player.gd`
- `scripts/caster_spell_geometry.gd`
- 新增 `scripts/caster_skill_beam_visual_effect.gd`
- `scripts/skills/runtimes/wizard_skill_runtime.gd`（仅如需 profile/metadata 对齐）

## 11) 验收清单（本设计产出）

1. Beam Schema 设计提交
2. Laser 当前数据流识别完备
3. Beam 目标数据流明确
4. 可迁移字段清单
5. 不可迁移字段清单
6. 风险清单
7. 预计修改文件列表

## 12) 结论

本阶段结论：

- 不对 Laser 做任何代码改造。
- 将 Beam 作为独立 VisualType 先完成 schema 与职责边界。
- 保留 Gameplay 对长度裁剪（stops_on_terrain）的真值权威。
- Beam 的“length axis + width profile + continuous lifecycle”从一开始就与 sky_strike 解耦。
