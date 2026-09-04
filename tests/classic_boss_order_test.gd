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

	var wooma := _boss(76, "本地化沃玛首领", player)
	await get_tree().process_frame
	assert(wooma.visual.uses_final_art() and int(wooma.boss_rule.get("monsterId", -1)) == 76, "沃玛教主未按monsterId读取动画/规则")
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
	dragon._physics_process(0.01)
	assert(not dragon._burrowed and dragon.visual.visible and dragon.current_hp == dragon.max_hp, "触龙神近身钻出/满血机制失效")
	var hp_before := player.current_hp
	assert(not dragon._boss_skill_enabled, "触龙神不应保留无来源的独立警示圈技能")
	dragon._attack_timer = 0.0
	dragon._update_area_magic_delivery(0.01)
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
	dragon._update_area_magic_delivery(0.61)
	assert(
		str(dragon._last_attack_footprint_snapshot.get("range_shape", ""))
		== "chebyshev_axis_aligned_square_exclusive",
		"触龙神结算没有消费冻结的方形范围",
	)
	assert(
		str(dragon._last_attack_footprint_snapshot.release_id) == warned_release_id,
		"触龙神释放与600ms延迟伤害没有保留同一release_id",
	)
	assert(
		str(dragon._last_attack_footprint_snapshot.projection_relationship_id)
		== EnemyActor.PROJECTION_RELATIONSHIP_GROUND_EXACT,
		"触龙神方形范围没有声明ground_exact",
	)
	assert(player.current_hp < hp_before, "触龙神范围攻击没有结算主目标伤害")
	assert(str(dragon.last_magic_attack_resolution.get("delivery_kind", "")) == "area_magic")

	player.global_position = open_field_center_px + Vector2(400, 0)
	var zuma := _boss(160, "本地化祖玛首领", player)
	await get_tree().process_frame
	assert(zuma.visual.uses_final_art() and zuma.dormant, "祖玛教主未以石化动画状态出生")
	player.global_position = zuma.global_position + Vector2(60, 0)
	zuma._physics_process(0.01)
	assert(not zuma.dormant, "祖玛教主两格范围苏醒失效")
	var summon_result := {"count": 0, "max_active": 0, "ids": []}
	zuma.summon_requested.connect(func(_enemy: EnemyActor, ids: Array, count: int, max_active: int) -> void:
		summon_result.count = count
		summon_result.max_active = max_active
		summon_result.ids = ids
	)
	zuma._rng.seed = 160
	zuma.take_damage(int(ceil(float(zuma.max_hp) / 5.0)) + 1)
	assert(int(summon_result.count) >= 6 and int(summon_result.count) <= 11, "祖玛教主血量阶段召唤数量错误")
	var summon_ids: Array = summon_result.ids
	assert(int(summon_result.max_active) == 30 and summon_ids.map(func(value: Variant) -> int: return int(value)) == [153, 156, 150, 159], "祖玛教主召唤上限或稳定monsterId集合错误")

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
