extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const FIXED_AREA_IDS := [180, 195]
const STATIONARY_SPECIAL_IDS := [30, 124, 126, 180, 182, 195]
var _last_summon: Dictionary = {}


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _configure_enemy_map(enemy: EnemyActor) -> void:
	enemy.configure_runtime_map_projection(
		1,
		Callable(self, "_test_ground_to_screen")
	)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterIdentityScript.reset_caches_for_test()

	for stationary_id: int in STATIONARY_SPECIAL_IDS:
		var stationary_profile := MonsterIdentityScript.behavior_profile({
			"monsterId": stationary_id,
			"name": "故意冲突的旧名称",
		})
		assert(bool(stationary_profile.get("movement", {}).get("stationary", false)), "monsterId=%d 特殊固定单位分类缺失" % stationary_id)
		assert(not str(stationary_profile.get("specialClassification", "")).is_empty(), "monsterId=%d 特殊行为类型缺失" % stationary_id)

	for monster_id: int in FIXED_AREA_IDS:
		var profile := MonsterIdentityScript.behavior_profile({
			"monsterId": monster_id,
			"name": "故意冲突的旧名称",
		})
		assert(profile.get("specialClassification", "") == "fixed_body_full_area_attacker", "monsterId=%d 特殊分类错误" % monster_id)
		assert(bool(profile.get("movement", {}).get("stationary", false)), "monsterId=%d 未声明固定单位" % monster_id)
		assert(int(profile.get("serviceClass", {}).get("race", -1)) == 115, "monsterId=%d 未绑定原服Race=115" % monster_id)
		assert(profile.get("serviceClass", {}).get("name", "") == "TBigHeartMonster", "monsterId=%d 未绑定原服特殊类" % monster_id)
		assert(int(profile.get("areaAttack", {}).get("rangeTiles", 0)) == 16, "monsterId=%d 未使用原服16格可见范围" % monster_id)

		var player := PlayerCharacter.new()
		player.global_position = Vector2(480, 0)
		add_child(player)
		player.set_physics_process(false)
		# Keep this mechanics test away from death/revival equipment paths.
		player.max_hp = 1000
		player.current_hp = 1000
		player.current_mp = 0
		var hp_before := player.current_hp

		var data: Dictionary = GameData.get_monster_by_id(monster_id).duplicate(true)
		data["name"] = "运行时改名固定怪"
		var enemy := EnemyActor.new()
		enemy.global_position = Vector2.ZERO
		enemy.setup(data, player, true)
		_configure_enemy_map(enemy)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame

		var position_before := enemy.global_position
		assert(enemy.stationary and is_zero_approx(enemy.move_speed_gu_per_sec), "monsterId=%d 运行时仍可移动" % monster_id)
		assert(enemy.area_attack_rule.get("targetMode", "") == "all_combat_targets", "monsterId=%d 未启用全屏多目标攻击" % monster_id)
		enemy._physics_process(0.01)
		enemy._physics_process(0.21)
		assert(
			SkillFootprintSnapshotScript.has_legacy_base_contract(
				enemy._last_attack_footprint_snapshot
			),
			"monsterId=%d fixed area attack did not publish an immutable GU footprint" % monster_id,
		)
		assert(
			str(enemy._last_attack_footprint_snapshot.shape_type)
			== SkillFootprintSnapshotScript.SHAPE_CIRCLE,
			"monsterId=%d fixed area attack is not resolved by its projected circle" % monster_id,
		)
		assert(
			str(enemy._last_attack_footprint_snapshot.projection_relationship_id)
			== EnemyActor.PROJECTION_RELATIONSHIP_GROUND_EXACT,
			"monsterId=%d fixed area attack does not declare ground_exact" % monster_id,
		)
		assert(enemy.global_position == position_before and enemy.velocity == Vector2.ZERO, "monsterId=%d 攻击时发生位移" % monster_id)
		assert(player.current_hp < hp_before, "monsterId=%d 没有命中普通近战范围外的屏内目标" % monster_id)

		enemy.queue_free()
		player.queue_free()
		await get_tree().process_frame

	var summoner_player := PlayerCharacter.new()
	summoner_player.global_position = Vector2(120, 0)
	add_child(summoner_player)
	summoner_player.set_physics_process(false)
	for summoner_id: int in [126, 182]:
		var summoner_data: Dictionary = GameData.get_monster_by_id(summoner_id).duplicate(true)
		summoner_data["name"] = "运行时改名固定召唤怪"
		var summoner := EnemyActor.new()
		summoner.setup(summoner_data, summoner_player, false)
		_configure_enemy_map(summoner)
		add_child(summoner)
		summoner.set_physics_process(false)
		summoner.summon_requested.connect(_capture_summon)
		await get_tree().process_frame
		_last_summon.clear()
		summoner._physics_process(0.01)
		summoner._physics_process(0.51)
		assert(is_zero_approx(summoner.move_speed_gu_per_sec), "monsterId=%d 固定召唤怪发生移动" % summoner_id)
		assert(int(_last_summon.get("sourceId", -1)) == summoner_id, "monsterId=%d 未通过通用召唤信号输出机制" % summoner_id)
		assert(not _last_summon.get("monsterIds", []).is_empty(), "monsterId=%d 召唤规则没有稳定子怪ID" % summoner_id)
		summoner.queue_free()
		await get_tree().process_frame
	summoner_player.queue_free()
	await get_tree().process_frame

	# Regression: an immobilized normal monster can temporarily lose its target
	# after a scripted relocation.  It must stay pinned instead of entering the
	# return-to-spawn path before the control-state check.
	var control_player := PlayerCharacter.new()
	control_player.global_position = Vector2(2400, 0)
	add_child(control_player)
	control_player.set_physics_process(false)
	var controlled := EnemyActor.new()
	controlled.global_position = Vector2(640, -64)
	controlled.setup(GameData.get_monster_by_id(21), control_player, false)
	_configure_enemy_map(controlled)
	add_child(controlled)
	controlled.set_physics_process(false)
	await get_tree().process_frame
	controlled.global_position = Vector2(640, -64)
	controlled.set_meta("spawn_position", Vector2(-1200, 320))
	controlled.target = null
	controlled.apply_control(30.0)
	var controlled_origin := controlled.global_position
	for _frame in range(32):
		controlled._physics_process(1.0 / 60.0)
	assert(controlled.global_position.distance_to(controlled_origin) < 0.001, "受控怪物丢失目标后被返巢逻辑带动")
	controlled.queue_free()
	control_player.queue_free()
	await get_tree().process_frame

	print("FIXED_AREA_MONSTER_PASS：固定攻击怪、固定召唤怪与无目标受控怪物均保持不可推动")
	get_tree().quit(0)


func _capture_summon(enemy: EnemyActor, monster_ids: Array, count: int, max_active: int) -> void:
	_last_summon = {
		"sourceId": enemy.monster_id,
		"monsterIds": monster_ids.duplicate(),
		"count": count,
		"maxActive": max_active,
	}
