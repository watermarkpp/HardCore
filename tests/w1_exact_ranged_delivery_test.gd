extends Node2D

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const TerrainPolicy := preload("res://scripts/monster_terrain_navigation_policy.gd")
const SnapshotScript := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const ProjectileEffectScript := preload(
	"res://scripts/monster_ranged_projectile_effect.gd"
)
const TargetMagicEffectScript := preload(
	"res://scripts/monster_target_magic_effect.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

const PHYSICAL_IDS := [50, 42, 145, 186, 62, 174]
const SPECIAL_NONCOMBAT_IDS := [226, 227, 228, 229, 230, 231, 232, 233, 234]

const PHYSICAL_CASES := {
	50: {
		"service_name": "TDualAxeMonster",
		"service_race": 87,
		"range_gu": 7.0,
	},
	42: {
		"service_name": "TArcherMonster",
		"service_race": 104,
		"range_gu": 7.0,
	},
	145: {
		"service_name": "TArcherMonster",
		"service_race": 104,
		"range_gu": 7.0,
	},
	186: {
		"service_name": "TArcherMonster",
		"service_race": 104,
		"range_gu": 7.0,
	},
	62: {
		"service_name": "TThornDarkMonster",
		"service_race": 93,
		"range_gu": 7.0,
	},
	174: {
		"service_name": "TThornDarkMonster",
		"service_race": 93,
		"range_gu": 7.0,
	},
}

const TARGET_MAGIC_CASE := {
	"service_name": "TElectronicScolpionMon",
	"service_race": 200,
	"range_gu": 2.0,
}

const SPECIAL_NONCOMBAT_CASES := {
	226: {
		"canonical_name": "宝箱",
		"class_binding_status": "CANDIDATE",
		"server_race": 107,
		"pascal_class": "TCentipedeKingMonster",
	},
	227: {
		"canonical_name": "宝箱1",
		"class_binding_status": "CANDIDATE",
		"server_race": 107,
		"pascal_class": "TCentipedeKingMonster",
	},
	228: {
		"canonical_name": "宝箱2",
		"class_binding_status": "DATA_HOLD",
	},
	229: {
		"canonical_name": "宝箱3",
		"class_binding_status": "DATA_HOLD",
	},
	230: {
		"canonical_name": "宝箱4",
		"class_binding_status": "DATA_HOLD",
	},
	231: {
		"canonical_name": "宝箱5",
		"class_binding_status": "DATA_HOLD",
	},
	232: {
		"canonical_name": "宝箱6",
		"class_binding_status": "DATA_HOLD",
	},
	233: {
		"canonical_name": "宝箱7",
		"class_binding_status": "DATA_HOLD",
	},
	234: {
		"canonical_name": "宝箱8",
		"class_binding_status": "CANDIDATE",
		"server_race": 107,
		"pascal_class": "TCentipedeKingMonster",
	},
}

var _projectile_descriptors: Array[Dictionary] = []
var _target_magic_descriptors: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()

	_run_special_classification_hold()
	await _run_special_noncombat_actor_matrix()
	await _run_physical_matrix()
	await _run_target_magic_case()

	print(
		"W1_EXACT_RANGED_DELIVERY_PASS "
		+ "physical=50,42,145,186,62,174 range=7 "
		+ "target_magic=224 range=2 melee_fallback=1 "
		+ "special_noncombat=226,227,228,229,230,231,232,233,234 "
		+ "same_world=1 moving_target=1 epoch_cancel=1 "
		+ "world_body=1 target_magic_world_body=1"
	)
	get_tree().quit(0)


func _run_special_classification_hold() -> void:
	# These exact IDs are runtime-allowed special entities.  226/227/234 have a
	# candidate service-class binding; 228-233 deliberately remain DATA_HOLD.
	# Record both layers without inheriting an attack from the candidate class.
	for monster_id: int in SPECIAL_NONCOMBAT_IDS:
		var expected: Dictionary = SPECIAL_NONCOMBAT_CASES.get(monster_id, {})
		var data := GameData.get_monster_by_id(monster_id)
		assert(int(data.get("monster_id", -1)) == monster_id)
		assert(str(data.get("canonical_name", "")) == str(expected.get("canonical_name", "")))
		assert(str(data.get("classification", "")) == "special")
		var combat_value: Variant = data.get("combat", {})
		assert(combat_value is Dictionary)
		var stats_value: Variant = (combat_value as Dictionary).get("stats", {})
		assert(stats_value is Dictionary)
		var stats := stats_value as Dictionary
		assert(
			int(stats.get("attack_min", -1)) == 0
			and int(stats.get("attack_max", -1)) == 0,
			"ID%d canonical attack stats must remain 0/0 while behavior is held"
			% monster_id,
		)

		var authority := EnemyActor._movement_authority_record_for_id(monster_id)
		assert(not authority.is_empty(), "ID%d runtime authority missing" % monster_id)
		var movement: Dictionary = authority.get("movement", {})
		assert(bool(movement.get("stationary", false)))
		assert(is_zero_approx(float(movement.get("base_move_speed_gu_per_sec", -1.0))))
		var movement_override_value: Variant = movement.get("movement_authority_override", null)
		assert(movement_override_value is Dictionary)
		var movement_override := movement_override_value as Dictionary
		assert(str(movement_override.get("authority", "")) == "HUMAN_FROZEN")
		assert(str(movement_override.get("kind", "")) == "stationary_entity")
		assert(
			str(movement_override.get("reason", ""))
			== "treasure chest is a fixed non-combat entity"
		)

		var targeting: Dictionary = authority.get("targeting", {})
		var expected_binding := str(expected.get("class_binding_status", ""))
		assert(str(targeting.get("class_binding_status", "")) == expected_binding)
		if expected_binding == "CANDIDATE":
			assert(int(targeting.get("server_race", -1)) == int(expected.get("server_race", -1)))
			assert(str(targeting.get("pascal_class", "")) == str(expected.get("pascal_class", "")))
			assert(str(targeting.get("class_binding_authority", "")) == "B_CANDIDATE")
			assert(not str(targeting.get("class_binding_source", "")).is_empty())
		else:
			assert(targeting.get("server_race", null) == null)
			assert(targeting.get("pascal_class", null) == null)
			assert(str(targeting.get("class_binding_authority", "")) == "UNKNOWN")
			assert(targeting.get("class_binding_source", null) == null)
			var missing_evidence: Dictionary = targeting.get("class_binding_missing_evidence", {})
			assert(
				str(missing_evidence.get("reason", ""))
				== "no exact Monster.DB source row; reused base-row Race cannot authorize target acquisition"
			)
		var bound_class_name := str(targeting.get("pascal_class", "UNRESOLVED"))
		var class_race := str(targeting.get("server_race", "UNRESOLVED"))
		print(
			(
				"W1_SPECIAL_NONCOMBAT_HOLD id=%d binding=%s class=%s/%s "
				+ "attack_behavior=DISABLED_BY_CONTRACT movement=HUMAN_FROZEN"
			)
			% [monster_id, expected_binding, bound_class_name, class_race]
		)


func _run_special_noncombat_actor_matrix() -> void:
	# This is a negative combat test, not an area-delivery test.  The production
	# exact-ID combatEnabled=false gate must stop autonomous attack, release,
	# and attack audio while leaving damage reception/drop identity intact.
	for monster_id: int in SPECIAL_NONCOMBAT_IDS:
		await _exercise_special_noncombat_actor(monster_id)


func _exercise_special_noncombat_actor(monster_id: int) -> void:
	var player := _make_player(Vector2(1.0, 0.0))
	var actor := _make_attacker(monster_id, player)
	await get_tree().process_frame

	assert(actor.monster_id == monster_id, "special exact monster_id mismatch")
	assert(actor.stationary, "ID%d chest actor must remain stationary" % monster_id)
	assert(
		is_zero_approx(actor.move_speed_gu_per_sec),
		"ID%d chest actor movement must remain frozen" % monster_id,
	)
	assert(
		not str(actor.monster_data.get("drop_profile_id", "")).is_empty(),
		"ID%d chest actor must retain drop identity" % monster_id,
	)

	_projectile_descriptors.clear()
	_target_magic_descriptors.clear()
	actor._attack_timer = 0.0
	actor.target = player
	var player_hp_before := player.current_hp
	actor._physics_process(0.01)
	actor._physics_process(2.0)
	assert(
		player.current_hp == player_hp_before,
		"ID%d noncombat actor must not autonomously damage player" % monster_id,
	)
	assert(_projectile_descriptors.is_empty())
	assert(_target_magic_descriptors.is_empty())
	assert(actor._pending_attack_time < 0.0)
	assert(actor._pending_attack_release_record.is_empty())
	assert(
		actor._audio_attack_sequence == 0,
		"ID%d noncombat actor must not emit attack audio" % monster_id,
	)

	var actor_hp_before := actor.current_hp
	actor.take_damage(7, player)
	assert(
		actor.current_hp == actor_hp_before - 7,
		"ID%d noncombat actor must remain damageable" % monster_id,
	)
	assert(actor.can_receive_damage())

	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _run_physical_matrix() -> void:
	for monster_id: int in PHYSICAL_IDS:
		await _exercise_physical_case(
			monster_id,
			PHYSICAL_CASES.get(monster_id, {}),
		)


func _exercise_physical_case(monster_id: int, expected: Dictionary) -> void:
	var player := _make_player(Vector2(4.0, 0.0))
	var attacker := _make_attacker(monster_id, player)
	await get_tree().process_frame

	_assert_actor_identity_and_delivery(
		attacker,
		monster_id,
		expected,
		"physical_projectile",
	)
	assert(
		is_equal_approx(attacker.attack_range_gu, float(expected.get("range_gu", -1.0))),
		"ID%d physical range must be %s GU, got %s"
		% [monster_id, str(expected.get("range_gu", -1.0)), str(attacker.attack_range_gu)],
	)

	_projectile_descriptors.clear()
	attacker.attack_min = 7
	attacker.attack_max = 7
	attacker._attack_timer = 0.0
	attacker.target = player
	var hp_before := player.current_hp
	attacker._physics_process(0.01)
	assert(
		_projectile_descriptors.size() == 1,
		"ID%d must emit one exact physical projectile" % monster_id,
	)
	assert(
		player.current_hp == hp_before,
		"ID%d projectile must not deal instant damage" % monster_id,
	)
	assert(
		attacker._pending_attack_release_record.get("kind", "") == "physical_projectile",
		"ID%d must freeze a physical_projectile release" % monster_id,
	)
	var descriptor: Dictionary = _projectile_descriptors[0]
	_assert_projectile_descriptor(descriptor, monster_id, player)
	var expected_duration := 0.6 + 4.0 * 0.05
	assert(
		is_equal_approx(float(descriptor.get("duration_seconds", 0.0)), expected_duration),
		"ID%d projectile delay must be %s seconds, got %s"
		% [monster_id, str(expected_duration), str(descriptor.get("duration_seconds", 0.0))],
	)
	attacker._physics_process(0.79)
	assert(
		player.current_hp == hp_before,
		"ID%d projectile settled before frozen delay" % monster_id,
	)
	attacker._physics_process(0.02)
	assert(
		player.current_hp == hp_before - 7,
		"ID%d physical projectile did not resolve" % monster_id,
	)

	# A live target may move within the same WORLD while the projectile is in
	# flight.  The frozen target instance remains a valid hit; this is separate
	# from the WORLD/epoch cancellation cases below.
	player.current_hp = hp_before
	player.global_position = _ground_to_screen(Vector2(4.0, 0.0))
	_projectile_descriptors.clear()
	attacker._attack_timer = 0.0
	attacker.target = player
	attacker._physics_process(0.01)
	assert(_projectile_descriptors.size() == 1)
	player.global_position = _ground_to_screen(Vector2(3.0, 1.0))
	attacker._physics_process(0.79)
	assert(player.current_hp == hp_before)
	attacker._physics_process(0.02)
	assert(
		player.current_hp == hp_before - 7,
		"ID%d moving same-WORLD target did not resolve" % monster_id,
	)

	player.current_hp = hp_before
	player.set_meta("runtime_map_id", 1)
	_projectile_descriptors.clear()
	attacker._attack_timer = 0.0
	attacker.target = player
	attacker._physics_process(0.01)
	assert(
		_projectile_descriptors.size() == 1,
		"ID%d WORLD probe must launch before map change" % monster_id,
	)
	player.set_meta("runtime_map_id", 2)
	attacker._physics_process(0.81)
	assert(
		player.current_hp == hp_before,
		"ID%d projectile crossed runtime WORLD boundary" % monster_id,
	)
	player.set_meta("runtime_map_id", 1)

	player.current_hp = hp_before
	_projectile_descriptors.clear()
	attacker._attack_timer = 0.0
	attacker._physics_process(0.01)
	assert(
		_projectile_descriptors.size() == 1,
		"ID%d epoch probe must launch before transition" % monster_id,
	)
	var token := "w1-id%d-epoch" % monster_id
	assert(player.begin_combat_transition(token))
	assert(player.finish_combat_transition(token))
	attacker._physics_process(0.81)
	assert(
		player.current_hp == hp_before,
		"ID%d physical release crossed combat_epoch" % monster_id,
	)

	if monster_id == 50:
		await _assert_physical_world_wall(attacker, player, hp_before)

	attacker.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _assert_physical_world_wall(
	attacker: EnemyActor,
	player: PlayerCharacter,
	hp_before: int,
) -> void:
	# A real WORLD-layer body must veto both sides of the delayed projectile
	# transaction. The test's environment provider deliberately reports no
	# block, so these assertions exercise the physics-server ray, not a fake
	# point lookup or a runtime_map_id mismatch.
	player.set_meta("runtime_map_id", 1)
	player.global_position = _ground_to_screen(Vector2(4.0, 0.0))
	player.current_hp = hp_before
	attacker.target = player
	attacker._attack_timer = 0.0
	_projectile_descriptors.clear()
	var launch_wall := _make_world_wall(Vector2.ZERO, Vector2(4.0, 0.0))
	await get_tree().physics_frame
	attacker._physics_process(0.01)
	assert(
		_projectile_descriptors.is_empty(),
		"ID50 WORLD wall must block physical launch",
	)
	assert(
		attacker._pending_attack_release_record.is_empty(),
		"ID50 launch-blocked path must not retain pending damage",
	)
	attacker._physics_process(0.81)
	assert(
		player.current_hp == hp_before,
		"ID50 launch-blocked WORLD path must deal no damage",
	)
	launch_wall.queue_free()
	await get_tree().physics_frame

	# Launch through an open corridor, then insert the same kind of WORLD body
	# before release. This catches implementations that only gate the launch.
	player.current_hp = hp_before
	_projectile_descriptors.clear()
	attacker._attack_timer = 0.0
	attacker._physics_process(0.01)
	assert(
		_projectile_descriptors.size() == 1,
		"ID50 open WORLD corridor must launch the projectile",
	)
	assert(
		attacker._pending_attack_release_record.get("kind", "")
		== "physical_projectile",
		"ID50 open corridor must retain physical release state",
	)
	var release_wall := _make_world_wall(Vector2.ZERO, Vector2(4.0, 0.0))
	await get_tree().physics_frame
	attacker._physics_process(0.81)
	assert(
		player.current_hp == hp_before,
		"ID50 WORLD wall inserted before release must deal no damage",
	)
	assert(
		attacker._pending_attack_release_record.is_empty(),
		"ID50 release-blocked path must clear pending damage",
	)
	release_wall.queue_free()
	await get_tree().physics_frame


func _assert_target_magic_world_wall(
	attacker: EnemyActor,
	player: PlayerCharacter,
	hp_before: int,
) -> void:
	# Target magic uses the same WORLD contract at launch and at delayed
	# settlement.  Keep the map id fixed so this isolates real collision.
	player.set_meta("runtime_map_id", 1)
	player.global_position = _ground_to_screen(Vector2(2.0, 0.0))
	player.current_hp = hp_before
	attacker.target = player
	attacker._attack_timer = 0.0
	_target_magic_descriptors.clear()
	var launch_wall := _make_world_wall(Vector2.ZERO, Vector2(2.0, 0.0))
	await get_tree().physics_frame
	attacker._physics_process(0.01)
	assert(
		_target_magic_descriptors.is_empty(),
		"ID224 WORLD wall must block target-magic launch",
	)
	assert(attacker._pending_attack_release_record.is_empty())
	attacker._physics_process(0.21)
	assert(player.current_hp == hp_before)
	launch_wall.queue_free()
	await get_tree().physics_frame

	# An open cast is valid; inserting a real WORLD body before the 200 ms
	# release must cancel damage and clear the pending transaction.
	player.current_hp = hp_before
	_target_magic_descriptors.clear()
	attacker._attack_timer = 0.0
	attacker._physics_process(0.01)
	assert(_target_magic_descriptors.size() == 1)
	assert(attacker._pending_attack_release_record.get("kind", "") == "target_magic")
	var release_wall := _make_world_wall(Vector2.ZERO, Vector2(2.0, 0.0))
	await get_tree().physics_frame
	attacker._physics_process(0.21)
	assert(player.current_hp == hp_before)
	assert(attacker._pending_attack_release_record.is_empty())
	release_wall.queue_free()
	await get_tree().physics_frame


func _run_target_magic_case() -> void:
	var player := _make_player(Vector2(2.0, 0.0))
	var attacker := _make_attacker(224, player)
	await get_tree().process_frame

	_assert_actor_identity_and_delivery(
		attacker,
		224,
		TARGET_MAGIC_CASE,
		"target_magic",
	)
	assert(
		is_equal_approx(attacker.attack_range_gu, 2.0),
		"ID224 target magic range must be 2 GU",
	)
	assert(
		is_equal_approx(
			float(attacker.attack_delivery_rule.get("range_gu", -1.0)),
			2.0,
		),
		"ID224 target magic gate must carry formal 2 GU",
	)

	_target_magic_descriptors.clear()
	attacker.attack_min = 50
	attacker.attack_max = 50
	attacker._attack_timer = 0.0
	attacker.target = player
	var hp_before := player.current_hp
	attacker._physics_process(0.01)
	assert(
		_target_magic_descriptors.size() == 1,
		"ID224 axis-boundary cast must emit target magic",
	)
	assert(
		player.current_hp == hp_before,
		"ID224 target magic must retain its delayed damage",
	)
	assert(
		attacker._pending_attack_release_record.get("kind", "") == "target_magic",
		"ID224 must freeze a target_magic release",
	)
	var descriptor: Dictionary = _target_magic_descriptors[0]
	assert(
		int(descriptor.get("source_monster_id", -1)) == 224,
		"ID224 target magic must preserve exact source monster_id",
	)
	assert(
		int(descriptor.get("target_instance_id", 0)) == player.get_instance_id(),
		"ID224 target magic must bind the exact target instance",
	)
	assert(
		str(descriptor.get("effect_id", "")) == TargetMagicEffectScript.EFFECT_ID,
		"ID224 target magic effect id mismatch",
	)
	assert(str(descriptor.get("damage_channel", "")) == "magic_defense")
	assert(str(descriptor.get("damage_owner", "")) == "enemy.target_magic_release")
	assert(
		is_equal_approx(float(descriptor.get("duration_seconds", 0.0)), 0.2),
		"ID224 target magic delay must be 0.2 seconds",
	)
	var snapshot: Dictionary = descriptor.get("footprint_snapshot", {})
	assert(str(snapshot.get("shape_type", "")) == SnapshotScript.SHAPE_CIRCLE)
	assert(str(snapshot.get("projection_relationship_id", "")) == "ground_exact")
	attacker._physics_process(0.19)
	assert(player.current_hp == hp_before)
	attacker._physics_process(0.02)
	assert(
		player.current_hp < hp_before,
		"ID224 target magic did not resolve through magic defense",
	)
	assert(bool(attacker.last_magic_attack_resolution.get("success", false)))
	assert(bool(attacker.last_magic_attack_resolution.get("magic_defense_checked", false)))
	assert(bool(attacker.last_magic_attack_resolution.get("physical_defense_bypassed", false)))
	assert(str(attacker.last_magic_attack_resolution.get("damage_channel", "")) == "magic_defense")

	# Target identity remains valid when the live player moves inside the same
	# WORLD during the 200 ms flight.  WORLD obstruction is tested separately.
	player.current_hp = hp_before
	player.global_position = _ground_to_screen(Vector2(2.0, 0.0))
	_target_magic_descriptors.clear()
	attacker._attack_timer = 0.0
	attacker.target = player
	attacker._physics_process(0.01)
	assert(_target_magic_descriptors.size() == 1)
	player.global_position = _ground_to_screen(Vector2(1.0, 1.0))
	attacker._physics_process(0.19)
	assert(player.current_hp == hp_before)
	attacker._physics_process(0.02)
	assert(
		player.current_hp < hp_before,
		"ID224 moving same-WORLD target did not resolve",
	)

	attacker.current_hp = attacker.max_hp
	assert(not attacker._target_magic_condition_met(Vector2(1.0, 0.0)))
	assert(attacker._target_magic_condition_met(Vector2(2.0, 0.0)))
	attacker.current_hp = maxi(1, int(attacker.max_hp / 2.0) - 1)
	assert(attacker._target_magic_condition_met(Vector2(1.0, 0.0)))
	assert(not attacker._target_magic_condition_met(Vector2(2.01, 2.01)))
	attacker.current_hp = attacker.max_hp
	await _assert_target_magic_world_wall(attacker, player, hp_before)

	player.current_hp = hp_before
	player.set_meta("runtime_map_id", 1)
	player.global_position = _ground_to_screen(Vector2(2.0, 0.0))
	_target_magic_descriptors.clear()
	attacker._attack_timer = 0.0
	attacker.target = player
	attacker._physics_process(0.01)
	assert(_target_magic_descriptors.size() == 1)
	player.set_meta("runtime_map_id", 2)
	attacker._physics_process(0.21)
	assert(player.current_hp == hp_before)
	player.set_meta("runtime_map_id", 1)

	player.current_hp = hp_before
	_target_magic_descriptors.clear()
	attacker._attack_timer = 0.0
	attacker._physics_process(0.01)
	assert(_target_magic_descriptors.size() == 1)
	var transition_token := "w1-id224-epoch"
	assert(player.begin_combat_transition(transition_token))
	assert(player.finish_combat_transition(transition_token))
	attacker._physics_process(0.21)
	assert(player.current_hp == hp_before)

	player.current_hp = hp_before
	player.global_position = _ground_to_screen(Vector2(1.0, 0.0))
	player.set_meta("runtime_map_id", 1)
	_target_magic_descriptors.clear()
	attacker._attack_timer = 0.0
	attacker.target = player
	attacker.current_hp = attacker.max_hp
	attacker._physics_process(0.01)
	assert(
		_target_magic_descriptors.is_empty(),
		"ID224 adjacent attack must not masquerade as target magic",
	)
	if attacker._pending_attack_time >= 0.0:
		var pending := attacker._pending_attack_time
		attacker._physics_process(maxf(0.01, pending + 0.01))
	assert(
		player.current_hp < hp_before,
		"ID224 inherited adjacent ordinary attack did not resolve",
	)
	assert(bool(attacker.last_physical_hit_resolution.get("success", false)))

	attacker.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _assert_actor_identity_and_delivery(
	attacker: EnemyActor,
	monster_id: int,
	expected: Dictionary,
	expected_kind: String,
) -> void:
	assert(attacker.monster_id == monster_id, "EnemyActor exact monster_id mismatch")
	var data := GameData.get_monster_by_id(monster_id)
	assert(int(data.get("monster_id", -1)) == monster_id)
	var profile := MonsterIdentity.behavior_profile(data)
	var service_class: Dictionary = profile.get("serviceClass", {})
	assert(
		str(service_class.get("name", "")) == str(expected.get("service_name", "")),
		"ID%d service class mismatch: expected %s got %s"
		% [
			monster_id,
			str(expected.get("service_name", "")),
			str(service_class.get("name", "")),
		],
	)
	assert(
		int(service_class.get("race", -1)) == int(expected.get("service_race", -1)),
		"ID%d service race mismatch" % monster_id,
	)
	assert(str(service_class.get("confidence", "")) == "A")
	var delivery: Dictionary = profile.get("attackDelivery", {})
	assert(
		str(delivery.get("kind", "")) == expected_kind,
		"ID%d delivery kind mismatch: expected %s got %s"
		% [monster_id, expected_kind, str(delivery.get("kind", ""))],
	)
	assert(str(delivery.get("confidence", "")) == "A")
	if expected_kind == "physical_projectile":
		assert(str(delivery.get("effectId", "")) == ProjectileEffectScript.EFFECT_ID)
		assert(str(delivery.get("obstaclePolicy", "")) == "environment_can_fly_line")
	elif expected_kind == "target_magic":
		assert(str(delivery.get("effectId", "")) == TargetMagicEffectScript.EFFECT_ID)
		assert(str(delivery.get("damageChannel", "")) == "magic_defense")
		assert(str(delivery.get("rangeShape", "")) == "chebyshev_square")


func _assert_projectile_descriptor(
	descriptor: Dictionary,
	monster_id: int,
	player: PlayerCharacter,
) -> void:
	assert(int(descriptor.get("source_monster_id", -1)) == monster_id)
	assert(
		int(descriptor.get("target_instance_id", 0)) == player.get_instance_id()
	)
	assert(str(descriptor.get("effect_id", "")) == ProjectileEffectScript.EFFECT_ID)
	assert(str(descriptor.get("damage_owner", "")) == "enemy.physical_projectile_release")
	var snapshot: Dictionary = descriptor.get("footprint_snapshot", {})
	assert(str(snapshot.get("shape_type", "")) == SnapshotScript.SHAPE_SWEPT_CAPSULE_PATH)
	assert(str(snapshot.get("projection_relationship_id", "")) == "projectile_sweep")


func _make_world_wall(
	from_ground_gu: Vector2,
	to_ground_gu: Vector2,
) -> StaticBody2D:
	var from_world_px := _ground_to_screen(from_ground_gu)
	var to_world_px := _ground_to_screen(to_ground_gu)
	var path_world_px := to_world_px - from_world_px
	var wall := StaticBody2D.new()
	wall.name = "W1WorldWall"
	wall.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	wall.collision_mask = 0
	wall.global_position = from_world_px.lerp(to_world_px, 0.5)
	wall.rotation = path_world_px.angle()
	var collider := CollisionShape2D.new()
	collider.name = "W1WorldWallShape"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12.0, path_world_px.length() + 32.0)
	collider.shape = shape
	wall.add_child(collider)
	add_child(wall)
	return wall


func _make_player(ground_gu: Vector2) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.global_position = _ground_to_screen(ground_gu)
	player.set_meta("runtime_map_id", 1)
	player.set_meta("safe_zones", [])
	player.set_physics_process(false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.max_hp = 1000
	player.current_hp = 1000
	player.defense_min = 0
	player.defense_max = 0
	return player


func _make_attacker(monster_id: int, player: PlayerCharacter) -> EnemyActor:
	var attacker := EnemyActor.new()
	attacker.global_position = Vector2.ZERO
	attacker.setup(GameData.get_monster_by_id(monster_id), player, false)
	attacker.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	attacker.configure_terrain_navigation_context(_empty_terrain_context())
	attacker.environment_blocker = self
	attacker.set_meta("safe_zones", [])
	attacker.set_physics_process(false)
	attacker.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(attacker)
	attacker.ranged_projectile_requested.connect(_capture_projectile_descriptor)
	attacker.target_magic_requested.connect(_capture_target_magic_descriptor)
	attacker.target = player
	attacker._retarget_timer = 999.0
	return attacker


func _capture_projectile_descriptor(descriptor: Dictionary) -> void:
	_projectile_descriptors.append(descriptor)


func _capture_target_magic_descriptor(descriptor: Dictionary) -> void:
	_target_magic_descriptors.append(descriptor)


func is_environment_point_blocked(world_px: Vector2) -> bool:
	# The provider remains present so EnemyActor exercises the normal map-query
	# contract. It intentionally reports open ground; WORLD-layer StaticBody2D
	# fixtures above are the only blocker in this test.
	return false


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(value)


func _empty_terrain_context() -> Dictionary:
	return TerrainPolicy.build_context(
		1,
		{
			"build_sha256": "1".repeat(64),
			"source": {"runtime_map_id": 1},
			"design": {"design_size": [32, 32]},
			"collision": {"blocked_tiles": []},
		},
		TerrainPolicy.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
	)
