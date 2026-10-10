extends Node

const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const OpenTerrainFixture := preload(
	"res://tests/helpers/monster_open_terrain_test_fixture.gd"
)


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var rules: Dictionary = GameData.boss_service_rules
	var activation_order: Array = rules.get("mapActivationOrder", [])
	assert(activation_order.map(func(value: Variant) -> int: return int(value)) == [76, 124, 160], "Boss施工顺序没有按地图实际启用顺序固化")
	assert(BossMechanics.profile(124).get("serviceClass", "") == "TCentipedeKingMonster", "Boss技能注册表未按monsterId查询")
	assert(BossMechanics.profile("触龙神").get("serviceClass", "") == "TCentipedeKingMonster", "Boss技能注册表旧名称兼容失效")

	var player := PlayerCharacter.new()
	player.max_hp = 1000
	player.current_hp = 1000
	player.max_mp = 0
	player.current_mp = 0
	player.defense_min = 0
	player.defense_max = 0
	var open_field_center_px := _test_ground_to_screen(
		OpenTerrainFixture.CENTER_GROUND_GU
	)
	player.global_position = open_field_center_px + Vector2(400, 0)
	add_child(player)
	player.set_physics_process(false)
	# _ready() applies the persisted profile, so pin the combat fixture after it.
	player.max_hp = 1000
	player.current_hp = 1000
	player.max_mp = 0
	player.current_mp = 0
	player.defense_min = 0
	player.defense_max = 0
	player.damage_reduction = 0.0
	# This fixture asserts a successful hit, not an evasion sample. Incoming
	# magic reads compiled stats (not the actor's physical defence fields).
	# Pin its real preconditions before either release or HP sampling.
	PlayerState.computed_stats["anti_magic_points"] = 0
	PlayerState.computed_stats["magic_defense_min"] = 0
	PlayerState.computed_stats["magic_defense_max"] = 0

	var wooma := _boss(76, "本地化沃玛首领", player)
	await get_tree().process_frame
	assert(wooma.visual.uses_final_art() and int(wooma.boss_rule.get("monsterId", -1)) == 76, "沃玛教主未按monsterId读取动画/规则")
	assert(is_equal_approx(wooma._boss_base_attack_interval, 1.5), "沃玛教主基础攻击间隔必须来自21CQ canonical 1500ms")
	var relocation_result := {"radius": 0}
	wooma.relocation_requested.connect(func(_enemy: EnemyActor, radius_gu: float) -> void:
		relocation_result.radius = radius_gu
	)
	wooma.take_damage(int(ceil(float(wooma.max_hp) / 7.0)) + 1)
	assert(wooma._boss_rage_time > 7.9 and wooma._attack_interval == 0.5, "沃玛教主七段临时狂暴未触发")
	assert(wooma.request_surrounded_relocation(5) and is_equal_approx(float(relocation_result.radius), 4.0), "沃玛教主受困传送接口未发出稳定请求")

	var dragon := _boss(124, "本地化触龙首领", player)
	await get_tree().process_frame
	assert(not dragon.visual.active_resources.is_empty() and dragon.visual.sprite.texture != null, "触龙神monsterId客户端动画未加载")
	assert(dragon._burrowed, "触龙神没有按规则以潜伏状态出生")
	assert(not dragon.visual.visible, "触龙神潜伏时仍显示地表动画")
	player.global_position = dragon.global_position + Vector2(100, 0)
	var hp_before := player.current_hp
	dragon._physics_process(0.01)
	assert(not dragon._burrowed and dragon.visual.visible and dragon.current_hp == dragon.max_hp, "触龙神近身钻出/满血机制失效")
	assert(not dragon._boss_skill_enabled, "触龙神不应保留无来源的独立警示圈技能")
	assert(
		SkillFootprintSnapshotScript.has_legacy_base_contract(
			dragon._area_magic_footprint_snapshot
		),
		"触龙神没有冻结释放时的GU方形范围",
	)
	assert(
		str(dragon._area_magic_footprint_snapshot.get("range_shape", ""))
		== "chebyshev_axis_aligned_square_exclusive",
		"触龙神范围不是原版严格切比雪夫方形",
	)
	var warned_release_id := str(dragon._area_magic_footprint_snapshot.release_id)
	assert(
		dragon.boss_warning_polygon_px(dragon.boss_rule.get("specialSkill", {})).is_empty(),
		"触龙神仍生成了没有客户端来源的警示圈",
	)
	assert(player.current_hp < hp_before, "触龙神范围攻击必须在释放帧结算主目标伤害")
	var hp_after_activation := player.current_hp
	player.global_position = _test_ground_to_screen(OpenTerrainFixture.CENTER_GROUND_GU + Vector2(8.0, 8.0))
	dragon._update_area_magic_delivery(0.61)
	assert(player.current_hp == hp_after_activation, "触龙神警告结束不得因目标移动重复或撤销伤害")
	assert(
		str(dragon._last_attack_footprint_snapshot.get("range_shape", ""))
		== "chebyshev_axis_aligned_square_exclusive",
		"触龙神结算没有消费冻结的方形范围",
	)
	assert(
		str(dragon._last_attack_footprint_snapshot.release_id) == warned_release_id,
		"触龙神释放与警告清理必须保留同一release_id",
	)
	assert(
		str(dragon._last_attack_footprint_snapshot.projection_relationship_id)
		== EnemyActor.PROJECTION_RELATIONSHIP_GROUND_EXACT,
		"触龙神方形范围没有声明ground_exact",
	)
	assert(str(dragon.last_magic_attack_resolution.get("delivery_kind", "")) == "area_magic")
	assert(not bool(dragon.last_magic_attack_resolution.get("magic_evaded", true)), "成功命中夹具不能发生魔法闪避")
	assert(int(dragon.last_magic_attack_resolution.get("applied_damage", 0)) == hp_before - player.current_hp, "真实范围投递与HP变化必须一致")

	player.global_position = open_field_center_px + Vector2(400, 0)
	var zuma := _boss(160, "本地化祖玛首领", player)
	await get_tree().process_frame
	assert(zuma.visual.uses_final_art() and zuma.dormant, "祖玛教主未以石化动画状态出生")
	assert(is_equal_approx(zuma._boss_base_attack_interval, 1.0), "祖玛教主基础攻击间隔必须来自21CQ canonical 1000ms")
	player.global_position = zuma.global_position + Vector2(60, 0)
	zuma._physics_process(0.01)
	assert(not zuma.dormant, "祖玛教主两格范围苏醒失效")
	var summon_result := {"count": 0, "max_active": 0, "ids": []}
	zuma.summon_requested.connect(func(_enemy: EnemyActor, ids: Array, count: int, max_active: int) -> void:
		summon_result.count = count
		summon_result.max_active = max_active
		summon_result.ids = ids
	)
	# Real wall-clock physics scenario: repeated damage arrives during 8.2 s of
	# live actor frames. Each hit wakes target maintenance, but the Boss search
	# anchor must remain untouched until the authored with-target boundary.
	zuma.take_damage(1)
	assert(int(summon_result.count) == 0, "祖玛教主受击回调不得立即释放阶段召唤")
	zuma.set_physics_process(true)
	zuma._rng.seed = 160
	var first_search_anchor := zuma._boss_search_clock_anchor_s
	for _tick in range(82):
		zuma.take_damage(25)
		await get_tree().create_timer(0.1).timeout
		if zuma._combat_action_time_s - first_search_anchor < 8.0:
			assert(int(summon_result.count) == 0, "positive hit or target maintenance released summon before 8-second boundary")
			assert(zuma._boss_search_clock_anchor_s == first_search_anchor, "positive damage changed stage search anchor")
	assert(int(summon_result.count) >= 4 and int(summon_result.count) <= 7, "真实8秒physics受击期间祖玛阶段召唤未按搜索边界释放")
	zuma.set_physics_process(false)
	# R3 W6: the stage bounds follow the canonical healthStageSummon authority
	# (minCount 4 / maxCount 7, stages 5).
	assert(int(summon_result.count) >= 4 and int(summon_result.count) <= 7, "祖玛教主血量阶段召唤数量错误")
	var summon_ids: Array = summon_result.ids
	# R3 W6: follow the decompiled authority (ObjMon.pas
	# TScultureKingMonster.CallSlave, canonical boss_rule healthStageSummon,
	# confidence A): maxActive 15 over the stable KIND SET [156, 153, 150,
	# 128]. CallSlave draws one kind per child, so the emitted list is a draw
	# from that set, not a fixed permutation. The old hardcoded 30 /
	# [153, 156, 150, 159] predated that authority.
	assert(
		int(summon_result.max_active) == 15
		and summon_ids.size() == int(summon_result.count)
		and summon_ids.size() > 0
		and summon_ids.all(func(value: Variant) -> bool: return [156, 153, 150, 128].has(int(value))),
		"祖玛教主召唤上限或稳定monsterId集合错误",
	)
	# No-target searches use the authored one-second boundary independently of
	# the fast target-maintenance wake path.
	var first_release_count := int(summon_result.count)
	summon_result.count = 0
	zuma.queue_free()
	await get_tree().process_frame
	player.global_position = Vector2(100000.0, 100000.0)
	zuma = _boss(160, "祖玛无目标时钟夹具", player)
	await get_tree().process_frame
	zuma.dormant = false
	zuma.target = null
	zuma.primary_target = null
	zuma._hc_forget(player)
	zuma.summon_requested.connect(func(_enemy: EnemyActor, ids: Array, count: int, max_active: int) -> void:
		summon_result.count = count
		summon_result.max_active = max_active
		summon_result.ids = ids
	)
	zuma._boss_health_stage = 5
	zuma.current_hp = 1
	for _tick in range(9):
		zuma._physics_process(0.1)
	assert(int(summon_result.count) == 0, "祖玛教主无目标时不得在1秒搜索边界前阶段召唤")
	# The boundary is due at 1 s; an already committed attack may defer the
	# release until its action slot is free, but cannot reset the due boundary.
	for _tick in range(11):
		zuma._physics_process(0.1)
	assert(int(summon_result.count) >= 4 and int(summon_result.count) <= 7, "祖玛教主无目标1秒搜索边界未释放4-7只")
	assert(first_release_count >= 4 and first_release_count <= 7, "祖玛首次阶段召唤数量未保留")
	# A depleted cursor is restored only at a legal search boundary after full
	# healing; healing itself must not emit a summon.
	summon_result.count = 0
	zuma._boss_health_stage = 0
	zuma.current_hp = zuma.max_hp
	zuma._boss_search_clock_anchor_s = zuma._combat_action_time_s - 1.0
	zuma._retarget(0.0)
	assert(zuma._boss_health_stage == 5 and int(summon_result.count) == 0, "祖玛满血搜索未恢复阶段5或错误召唤")
	# Control, dormant and death-pending actors keep a due search boundary but
	# cannot consume it until the action gate is legal again.
	for blocked_kind in [&"control", &"dormant", &"death"]:
		summon_result.count = 0
		zuma._boss_health_stage = 5
		zuma.current_hp = 1
		zuma._boss_search_clock_anchor_s = zuma._combat_action_time_s - 1.0
		if blocked_kind == &"control":
			zuma.control_time = 1.0
		elif blocked_kind == &"dormant":
			zuma.dormant = true
		else:
			zuma._death_pending = true
		zuma._retarget(0.0)
		assert(int(summon_result.count) == 0, "祖玛%s状态不得消费到期召唤搜索" % str(blocked_kind))
		zuma.control_time = 0.0
		zuma.dormant = false
		zuma._death_pending = false
		zuma._retarget(0.0)
		assert(int(summon_result.count) >= 4 and int(summon_result.count) <= 7, "祖玛%s解除后未消费保留的召唤搜索" % str(blocked_kind))

	wooma.queue_free()
	dragon.queue_free()
	zuma.queue_free()
	player.queue_free()
	print("CLASSIC_BOSS_ORDER_PASS：沃玛76、触龙124、祖玛160动画与数据驱动机制按地图顺序生效")
	get_tree().quit(0)


func _boss(monster_id: int, renamed: String, player: PlayerCharacter) -> EnemyActor:
	var data := GameData.get_monster_by_id(monster_id).duplicate(true)
	data["name"] = renamed
	var boss := EnemyActor.new()
	boss.setup(data, player, true)
	boss.configure_runtime_map_projection(
		1,
		Callable(self, "_test_ground_to_screen")
	, GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu)
	boss.configure_terrain_navigation_context(OpenTerrainFixture.build(1))
	boss.global_position = _test_ground_to_screen(
		OpenTerrainFixture.CENTER_GROUND_GU
	)
	add_child(boss)
	boss.set_physics_process(false)
	return boss
