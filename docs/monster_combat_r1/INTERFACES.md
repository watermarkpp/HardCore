# HC-MONSTER-COMBAT-R1 + HC-BODY-2TIER-1P5-V1 接口清单（INTERFACES）

## 新增 GDScript 静态接口

### `scripts/actor_body_policy.gd`（新文件，preload 别名 `ActorBodyPolicyScript`）

| 签名 | 说明 |
|---|---|
| `static func tier_screen_radius_px(tier: StringName) -> float` | 档位屏幕半径 px；未知档位返回 -1.0（调用方 fail-closed） |
| `static func player_screen_radius_px() -> float` | 冻结玩家半径 18.0 px |
| `static func summon_tier(summon_id: String) -> String` | "skeleton"→"small"、"divine_beast"→"large"、未知→"" |
| `static func validate_body_profile(profile: Variant) -> Dictionary` | 严格校验（contract/policy id、档位枚举、有限正半径、0.50625 GU 上界、iso 换算一致、assignment_rule 非空）；失败返回 `{}`，调用方必须 fail-closed |
| `static func footsole_shape_px(screen_radius_px: float) -> ConvexPolygonShape2D` | 统一 16 点等距脚底形状入口（转发 WorldSpatialRules 模板） |

常量：`BODY_POLICY_CONTRACT_ID`、`MAX_BODY_GROUND_RADIUS_GU=0.50625`、`TIER_SMALL`/`TIER_LARGE`。约束：**无每帧逻辑**（静态缓存仅初始化期访问）。

### `scripts/monster_identity.gd`（既有，新增访问器）

| 签名 | 说明 |
|---|---|
| `static func body_profile(id: int) -> Dictionary` | 经正式 catalog entry 的 `combat.body_profile`；无名称/后缀回退；缺 Profile 返回 `{}` |

### `scripts/monster_movement_cadence.gd`（既有，新增）

| 签名/字段 | 说明 |
|---|---|
| `var direct_magic_walk_floor_ms := -1` | applied>0 时 floor = walk_tick_ms + walk_interval_ms |
| `static…/instance func direct_magic_delay_blocks_next_step(now_ms: int) -> bool` | configured 且未违规且 floor>=0 且 now_ms<=floor |
| `reset()` / `_reset_state()` | 清 floor |

### `scripts/monster_visual.gd`（既有，新增）

| 签名 | 说明 |
|---|---|
| `func begin_attack_presentation(duration: float) -> bool` | 运行时攻击表现仲裁入口；death 冻结返回 false；受击中合并；仅真正开播返回 true |
| `func _merge_pending_struck_feedback() -> int` | 保留最新 STRUCK 到槽 0，同步 `_pending_struck_count` |
| `var _attack_action_serial := 0` | 攻击开播序号 |

### `scripts/enemy.gd`（既有，新增字段/入口）

| 签名 | 说明 |
|---|---|
| `var combat_body_profile: Dictionary` | setup 时经 `MonsterIdentityScript.body_profile(requested_id)` 捕获 |
| `func _begin_autonomous_step_without_cadence(..., now_ms_override := -1)` | 节拍外自治步；门禁时钟源显式 |
| `func _current_attack_interval() -> float` | 空 boss_rule 直接返回 `_attack_interval` |

### `tools/apply_actor_body_policy_v1.py`（新，构建工具）

`python tools/apply_actor_body_policy_v1.py`：对检入 `canonical_monster_catalog.json` 盖印 body_profile（双集合、拒绝重复盖印、越界失败）并产出 `docs/monster_combat_r1/body_tier_table.json`。属有界注入步骤；生成器修复漂移后仍以生成器为唯一烘焙路径。

## 数据文件接口

| 文件 | 角色 |
|---|---|
| `assets/data/actor_body_policy_v1.json` | 身体策略权威源（policy_id `actor_body_policy_v1`，contract `hardcore.actor.body_policy.v1`） |
| `assets/data/runtime/canonical_monster_catalog.json` | 烘焙产物（`combat.body_profile` × 156） |
| `docs/monster_combat_r1/body_tier_table.json` | 逐 ID 档位表交付物（含 assignment_rule 与 policy_sha256） |

## 变更的消费者契约要点（integration 注意）

1. 身体半径在 `_ready` 初始化期一次性解析，先于出生占用检查与索引注册——任何新消费者不得在 ready 前读取 `collision_radius_px/combat_radius_gu` 作为权威。
2. `combat.body_profile` 是唯一身体半径来源；禁止运行时读贴图尺寸或以 `is_boss` 变大。
3. 1.5 GU 近战门禁保持中心到中心语义；接触站位需求 = `ra + rt + 0.4375`，不得在 1.5 之上做半径补偿。
4. 新增诊断计数器名（对账/审计用）：`monster_damage_rejected_nonpositive`、`monster_direct_magic_walk_delay_blocked_steps`、`monster_presentation_struck_merged`、`monster_body_policy_fallback`。
