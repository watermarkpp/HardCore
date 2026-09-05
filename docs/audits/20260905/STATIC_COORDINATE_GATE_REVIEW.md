# Critical 静态坐标门禁与火墙夹具只读审查

审查基线：`eb9993b1c4e5a63125f54f7f29e394e985c4bace`。本审查未修改生产或坐标/Snapshot 合同，也未运行 Godot；经主控授权后，仅对已确认失效的独立测试夹具准备最小修复。

## 结论 1：`origin_world` 是静态子串误报

`tests/combat_unit_runtime_static_audit_test.gd:29` 把 `origin_world` 放入全局禁止 token，并在第 86 行用 `source.contains(token)` 检查。该检查会把合法、显式带单位的 `origin_world_px` 也判为违规。

`scripts/enemy.gd` 的九处命中全部以 `_world_px` 结尾：

- 2742、2976、3056、3124：远程/目标魔法 release record 的显式 PX 原点；同一记录同时保留 `source_ground_gu`、`target_ground_gu` 和 `target_world_px`。
- 4047、4170-4171、4188-4189：固定区域攻击冻结的 `target_actor_origin_world_px`/`actor_origin_world_px` 元数据，用于区分 actor 原点与获批 ground footpoint。

消费者也明确按 PX 使用：`scripts/monster_ranged_projectile_effect.gd:80-95` 读取 `origin_world_px`，校验有限值后赋给 `global_position`；第 133-137 行在两个 PX 端点间插值。`tests/monster_physical_projectile_visual_source_test.gd:83-89` 直接用 PX 坐标验证该描述符；`tests/fixed_area_ground_spike_effect_test.gd:159-171` 分别断言 `target_world_px`、`target_actor_origin_world_px` 与 `target_ground_gu` 的语义。

历史证据：静态 token 来自提交 `01643b68c`；`origin_world_px` 后续由 `fbf7645bc`/`f964851ec` 引入。已验收基线 `c97a08b4` 同时包含相同门禁和 enemy 中九处合法后缀，因此当前失败不是 `eb9993b1` 的生产回归。

最小建议：仅修改静态门禁，让 `origin_world`、`direction_world`、`geometry_world` 检查拒绝无单位或非正式后缀，但允许精确 `_px` 后缀。不要从门禁删除语义；可用正则 `origin_world(?!_px(?:[^A-Za-z0-9_]|$))`（另外两个 token 同构），并加自检：裸 `origin_world` 必须命中，`origin_world_px` 与 `target_actor_origin_world_px` 必须放行，`origin_world_px_extra` 必须命中。

## 结论 2：火墙失败是失效的无 ID Enemy 夹具

`tests/fire_wall_single_controller_test.gd:134-138` 仍用旧的自由字段字典构造 Enemy，没有 `monster_id`。`EnemyActor.setup` 自 `f776afdab` 起只接受 canonical exact ID：`scripts/enemy.gd:413-425` 对缺失/未知 ID 设置 `monster_id=-1` 与 `canonical_rejected`；`_ready` 第 1594-1597 行随后 `queue_free()`。

这与失败计数完全一致：controller 第 222-230 行 broadphase 仍能取到手工注册的一个候选，所以 `candidate_count=1`；第 236-243 行先检查 `enemy.is_queued_for_deletion()`/`can_receive_damage()`，通过后才增加 `controller_exact_test_count`。失效夹具因此得到 `controller_exact_test_count=0` 和 damage 0，尚未进入坐标/Snapshot 精确相交。

`git diff c97a08b4..eb9993b1` 对 `scripts/enemy.gd`、`scripts/fire_wall_field_controller.gd`、`scripts/runtime_combat_spatial_index.gd` 和该测试均为空，排除本轮生产回归。现有统一夹具 `tests/helpers/fire_wall_controller_test_fixtures.gd:94-109` 已示范正确方式：用 `GameData.get_monster_by_id(19)` 构造，再按测试需要覆盖 HP/半径并注册。

最小建议：只修 `fire_wall_single_controller_test.gd::_make_enemy`，以一个明确的正式 ID（建议复用现有火墙夹具的 ID 19）调用 `enemy.setup(GameData.get_monster_by_id(19), game.player, false)`；保留 broadphase、exact-test、visual-cell-zero-query 和 damage-tick 全部断言。为防夹具再次静默失效，在 `add_child` 后、注册前增加 `assert(enemy.monster_id == 19 and enemy.can_receive_damage() and not enemy.is_queued_for_deletion())`。不要改 controller 的资格过滤、坐标转换或 Snapshot 逻辑。

## 结论 3：灵魂火符 timing 也是无 ID Enemy 夹具失效

`tests/skills/taoist_soul_fire_launch_timing_test.gd:75-84` 同样以没有 `monster_id` 的旧自由字段字典调用 `EnemyActor.setup`。第 87 行 `add_child(enemy)` 触发上述 canonical 拒绝和 `queue_free()`；第 45 行又显式等待一帧，因此第 52 行执行 `target.get_instance_id()` 时，目标已被释放。这不是切图或自动战斗回收：释放条件在 Enemy 自身 `_ready` 的首个 fail-closed 分支即可完整解释错误。

该夹具由 `75153da14`（2026-08-10）引入，早于 `f776afdab`（2026-08-15）的 exact-ID Enemy 合同。`git diff c97a08b4..eb9993b1` 对该测试和 `scripts/enemy.gd` 为空，故同样不是本轮生产回归。相邻通过的 `taoist_summon_projectile_origin_anchor_test` 与 `taoist_summon_projectile_stealth_buff_visual_test` 验证的是召唤投射物/召唤体路径，不复用这个无 ID Enemy timing 夹具，不能证明第 52 行目标仍存活，也不与本诊断冲突。

最小建议：只改 `_make_enemy`，复用正式普通怪 ID 19：先断言 `GameData.get_monster_by_id(19)` 非空，再用该 canonical 记录调用 `setup`；如 timing 测试需要高血量，可在 setup 后显式覆盖 `max_hp/current_hp`。在 `add_child` 后增加 `assert(is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.can_receive_damage())`，然后保留第 52-62 行的 600/1200/1500 ms、单次信号和单投射物全部断言。不要修改 Player/SkillProjectile/GameRoot 生命周期或放宽 Enemy exact-ID 合同。

## 结论 4：两项雷电术失败复用同一无 ID 夹具根因

`tests/canonical_skill_production_entry_test.gd:196-210` 和 `tests/canonical_snapshot_propagation_test.gd:12-26` 原先都用无 `monster_id` 的自由字段字典创建 Enemy。两者在 `add_child` 时进入 `EnemyActor._ready` 的 canonical 拒绝分支；随后雷电术拿到的是已排队释放的目标，因此前者先在第 36 行观察到 MP 没有提交，后者先在第 53 行观察到 `accepted=false`。这两个失败都发生在技能数值、扣蓝唯一性或 Snapshot 传播之前，不构成这些生产合同的反证。

最小修复与火墙/timing 相同：改用正式普通怪 ID 19，显式覆盖测试所需高 HP，并在返回目标前断言 exact-ID、非 Boss、未排队释放且可承伤。原有 MP、伤害、视觉、技能资格、四格火墙与 Snapshot identity/coordinate-space 断言全部保留。

另发现 `tests/canonical_snapshot_identity_production_test.gd` 的失败文本同为 `lightning must be accepted`，但它已经使用 canonical ID 18，不属于无 ID 根因。该测试在 `reset_progress()` 后没有像另外两项那样设置 `PlayerState.profession="法师"`、等级和 `learned_skills`；当前 reset 明确恢复战士且清空已学技能。经主控授权，已仅补齐这些法师技能前置，未放宽技能正式入口。

## 结论 5：`class_combat_test` 暴露既存正式刷新策略冲突

该场景 stderr 的首个 ERROR 是：`monster_id=56 slot=outskirts:910001:spawn:5:0 reason=elite_policy_mismatch`，之后测试仍打印 `CLASS_COMBAT_PASS`；退出时另有 ObjectDB/resource 泄漏告警。第一个错误不是测试目标缺 ID：`class_combat_test.gd:18` 进入真实“比奇郊外”，`game_root.gd:3537-3558` 的正式 spawn plan 把 ID 56 与其余普通怪一律标记为 `BEGINNER_OUTDOOR`。但 canonical 分类权威从 `f776afdab` 起就把 ID 56 定义为 `elite`，`monster_respawn_policy.gd:85-88` 按合同只接受 `ELITE`，因此第六个 authored slot 必然被 fail-closed 拒绝。

冲突由 `edbe9628c` 同一次 MFC-4 提交引入：它给整个旧 outskirts 列表统一补了 beginner policy，却同时启用了 elite mismatch 门禁；当前 `c97a08b4` 与 `eb9993b1` 都已包含这个既存矛盾。测试随后选择前五个成功刷出的普通怪继续完成职业战斗断言，所以 PASS marker 与 ERROR 可同时出现。

这不是适合通过测试吞错或改成任意目标来隐藏的问题。最小生产修复需要 integration/怪物权威裁决该 authored ID 56 槽：若保留精英身份，则该槽应提交 `ELITE` 策略；若该位置不应刷精英，则必须由地图/怪物权威改为正确 exact ID。未经该裁决，本审查不修改生产或 `class_combat_test`。测试自身还应在成功路径 `queue_free(game)` 并等待帧以关闭退出泄漏，但这不能替代正式刷新冲突修复。

## 结论 6：三项 Snapshot 生产测试缺少稳定 slot 的测试上下文

`warrior_snapshot_v2_production_test.gd:38-42`、`enemy_snapshot_v2_production_test.gd:20-22` 和 `production_snapshot_no_legacy_test.gd:32-34` 都直接调用五参生产 `_spawn_enemy` 的前三参。在当前真实地图 `910001` 下，省略的 `spawn_context` 默认 `respawn_enabled=true`，而 `game_root.gd:3767-3777` 明确拒绝没有稳定 `spawn_slot_id/spawn_group_id` 的正式可复活刷新，返回 `null`。这完整解释三项共同的 `unstable formal slot`，以及后两项紧接着对 nil 设置 `attack_range_gu` 的错误。

这三项测试只需要一个短生命周期的快照攻击目标，不验证死亡后复活或持久 slot。因此最小夹具改法不是伪造正式 slot，而是沿用仓库既有先例（如 `implemented_map_runtime_projection_test.gd:118-124`、`vertical_slice_loop_test.gd:66-72`），补齐第四参 `-1.0` 和第五参 `{"respawn_enabled": false}`，并立即断言返回值非空。三项没有共享 helper；经主控确认相关场景已经失败结束后，已分别修改其调用点。生产稳定-slot 门禁保持不变。

## 结论 7：三项 safe-logout 失败由共享测试 userdata 与未校验创建结果共同触发

`safe_logout_character_select_guard_test`、`safe_logout_exit_guard_test` 和 `safe_logout_existing_state_preservation_test` 都直接使用默认 `user://characters` 与固定角色名，并且没有检查 `create_character()` 返回值。当前主树 runner 的实际目录为 `.godot/runtime_appdata/Godot/app_userdata/HardCore/characters`；只读统计发现其中已有：

- `Q0B守卫测试` 91 个主 JSON；
- `Q0B退出测试` 91 个主 JSON；
- `Q0B保留测试` 91 个主 JSON；
- `Q0B1落点测试` 82 个主 JSON。

这些记录最早来自 2026-08-06、最新来自 2026-08-13，早于当前 `eb9993b1`，且本次失败运行（14:20-14:22）没有生成新的 character JSON。`PlayerState._character_name_exists` 自 `4fc4af406` 起即会扫描主 profile 文件，故固定名创建必然返回“角色名已存在”。测试忽略这个失败后保持空 `active_profile_id`；`save_safe_logout` 第 5017-5018 行随即返回 false，所谓 prior record 从未建立：preservation 测试直接在“prior record must be saved”断言失败，另两项因忽略首次保存结果而在稍后的固定位置断言失败。

因此这是确定的测试隔离债务，不是 B02/B03/B04 的存档事务回归，也不能用删除当前 userdata 作为正式修复。最小可靠方案是让三项测试各自建立唯一 `user://safe_logout_<case>/<ticks>_<pid>` 根，并同时重定向 `profile_directory`、`profile_index_path`、`shared_warehouse_path`、`shared_warehouse_transaction_log_path`；保存/恢复这些全局路径和相关初始化状态，断言 `create_character()` 成功，再保留原失败回滚断言。可复用 `profile_business_validation_recovery_test.gd:405-418,535-563` 的四路径隔离模式。用户允许未来设备安装阶段清手机存档并重建三职业角色，与本地 runner 污染诊断无关，本审查没有执行设备或 userdata 删除。

## 结论 8：missing-arrival 失败是旧 map ID 夹具，不是 userdata 或 Home 合同回归

`map_transition_missing_arrival_test.gd:32` 仍调用 `_pipeline_arrival_position(4)`。但 `game_root.gd:3` 的正式 `BICH_RUNTIME_MAP_ID` 自 `1244300cf` 起为 `910001`，`_pipeline_arrival_position` 仅对该正式 ID 调 `_resolve_bich_home()`；传入旧 ID 4 会走普通 route-arrival 分支并返回 `valid=true`，所以第 33 行按当前代码必然失败，尚未触达 `_test_force_home_failure`。`c97a08b4..eb9993b1` 对该测试和相关 arrival/Home 函数没有本轮差异。

已授权的最小修复使用 `GameData.service_home_runtime_map_id(false)` 替换三处旧 `4`，并保留 invalid arrival、pipeline FAILED、同步 travel 不切图/不移动的全部断言。该测试也已采用四路径存档隔离，校验角色创建和首次落盘成功；本次第 33 行失败的直接根因仅是旧 map ID。

后续授权已将该覆盖边界收紧：测试现在从 `GameData.get_available_maps(false)` 中按最小 map ID 选取一个 `MapEditorRuntimeBridge.is_formal_playable()` 的非 Home 地图，通过 `_begin_map_transition` 和真实 staged world pipeline 进入该地图，完整等待 coordinator READY，并断言 current map/data/runtime authority 均一致。然后才注入 Home 解析失败，且在同步调用前显式断言 source ID 不等于 service Home ID，因此 `_travel_to_map_immediate` 不能再靠同图早退获得假 PASS。

根据当前生产静态路径，这个强 oracle 会真实进入 `_load_zone`；该函数现在先写 `current_map_id=Home`，再报告 Home 解析失败，没有回滚，而 `_travel_to_map_immediate` 随后会返回 true。因此此测试在生产增加最小前置 arrival 校验之前预期保持红色；这是要求发现的安全回归，不是测试夹具再失效。

## 结论 9：FireWall dead-target parity 的 reference 与生命周期恢复都已过期

`tests/fire_wall_hit_parity_test.gd:101-102` 先对 `dead_target` 执行致命 `take_damage`；`EnemyActor.take_damage` 在生命归零后进入 `_mark_death_pending`，立即从 combat spatial index 注销、设置 `_death_pending`，并延迟进入 `_dying`。生产 controller 在 `scripts/fire_wall_field_controller.gd:235-243` 还会先检查 `can_receive_damage()`，所以死亡对象不应进入 exact test 或伤害回调。

当前 `tests/helpers/fire_wall_legacy_reference_tick.gd:32-34` 只过滤无效/排队删除对象，没有 `can_receive_damage()`，因此仍会对死亡对象做精确相交和 callback。紧接着的 `_restore_hp()`（`fire_wall_hit_parity_test.gd:168-171`）只把 `current_hp` 改回 10000，没有清理 `_death_pending/_dying`、恢复 groups/collision 或重新注册 spatial index；这不是合法复活，也不能将同一 Enemy 作为 manager 阶段的存活对照。

已授权的 oracle 修正同时处理两点：

1. reference 的候选资格已与生产对齐：在精确相交前排除 `not enemy.can_receive_damage()`，并对 dead-target 显式断言 reference/manager 均为零 exact-test、零 callback、零 damage。
2. 已删除 HP 赋值伪造复活；reference/manager 阶段现在从同一 spec 各自新建独立 canonical Enemy、controller 和 spatial-index 世界。两个世界的 Godot instance ID 天然不同，因此顺序 oracle 改用两边一致的 fixture spatial serial（`i + 1`）比较，不会把对象地址当成业务身份。

其余 living-target 场景继续比对命中 ID 顺序和每 tick 一次伤害；不应为追求与过期 reference 相等而移除生产 `can_receive_damage()` 门禁，也不应直接写 `_dying/_death_pending`。
