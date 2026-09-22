extends Node

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SnapshotScript := preload("res://scripts/skills/skill_footprint_snapshot.gd")

var _descriptors: Array[Dictionary] = []
var _players: Array[PlayerCharacter] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var frozen_mover := _make_player(Vector2(4.0, 0.0))
	var frozen_dead := _make_player(Vector2(-4.0, 0.0))
	var frozen_cross_map := _make_player(Vector2(0.0, 8.0))
	frozen_cross_map.set_meta("runtime_map_id", 180)
	var square_corner := _make_player(Vector2(15.75, 15.75))
	var late_entrant := _make_player(Vector2(20.0, 0.0))
	var outside_square := _make_player(Vector2(16.25, 16.25))
	var safe := _make_player(Vector2(2.0, 2.0))

	var attacker := EnemyActor.new()
	attacker.global_position = Vector2.ZERO
	attacker.setup(GameData.get_monster_by_id(180), frozen_mover, true)
	attacker.configure_runtime_map_projection(
		180,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground"),
	)
	attacker.fixed_area_ground_spike_requested.connect(_capture_descriptor)
	attacker.set_meta("safe_zones", [{
		"shape": "circle",
		"center": safe.global_position,
		"center_ground_gu": _screen_to_ground(safe.global_position),
		"radius_gu": 0.25,
	}])
	add_child(attacker)
	attacker.set_physics_process(false)
	await get_tree().process_frame
	attacker.attack_min = 7
	attacker.attack_max = 7
	attacker._area_attack_warning = 0.0
	attacker._area_attack_cooldown = 0.0

	var mover_origin := frozen_mover.global_position
	var mover_hp := frozen_mover.current_hp
	var cross_map_hp := frozen_cross_map.current_hp
	var corner_hp := square_corner.current_hp
	var late_hp := late_entrant.current_hp
	var outside_hp := outside_square.current_hp
	var safe_hp := safe.current_hp

	# Cast start freezes four targets and emits four visuals immediately. The
	# corner target proves the original X/Y ±16 square rather than a circle.
	attacker._physics_process(0.01)
	assert(
		_descriptors.size() == 4,
		"expected four frozen descriptors, got %d records=%s"
		% [_descriptors.size(), str(attacker._area_attack_release_records)],
	)
	assert(attacker._area_attack_release_records.size() == 4)
	assert(frozen_mover.current_hp == mover_hp)
	assert(square_corner.current_hp == corner_hp)
	var snapshot: Dictionary = attacker._area_attack_footprint_snapshot
	assert(str(snapshot.get("shape_type", "")) == SnapshotScript.SHAPE_DIRECTED_RECTANGLE)
	assert(str(snapshot.get("range_shape", "")) == "chebyshev_axis_aligned_square")
	assert(is_equal_approx(float(snapshot.get("range_gu", 0.0)), 16.0))
	var release_id := str(snapshot.get("release_id", ""))
	assert(not release_id.is_empty())
	_assert_descriptor_ids(
		release_id,
		[
			frozen_mover.get_instance_id(),
			frozen_dead.get_instance_id(),
			frozen_cross_map.get_instance_id(),
			square_corner.get_instance_id(),
		],
	)
	var mover_descriptor := _descriptor_for(frozen_mover.get_instance_id())
	assert(
		(mover_descriptor.get("target_actor_origin_world_px", Vector2.INF) as Vector2)
		.is_equal_approx(mover_origin)
	)

	# Mutations during the 200 ms delay must not change the scheduled universe.
	# Leaving range still receives the bound hit; entering late never does.
	frozen_mover.global_position = _ground_to_screen(Vector2(30.0, 0.0))
	frozen_dead._dead = true
	frozen_cross_map.set_meta("runtime_map_id", 181)
	late_entrant.global_position = _ground_to_screen(Vector2(1.0, 0.0))
	attacker._physics_process(0.21)

	assert(frozen_mover.current_hp == mover_hp - 7)
	assert(square_corner.current_hp == corner_hp - 7)
	assert(frozen_dead.current_hp == frozen_dead.max_hp)
	assert(frozen_cross_map.current_hp == cross_map_hp)
	assert(late_entrant.current_hp == late_hp)
	assert(outside_square.current_hp == outside_hp)
	assert(safe.current_hp == safe_hp)
	assert(_descriptors.size() == 4, "settlement must not emit duplicate spikes")
	assert(attacker._area_attack_release_records.is_empty())

	# targetMode/scope are active policy, not decorative catalog fields.
	attacker._area_attack_cooldown = 0.0
	attacker.area_attack_rule["targetMode"] = "unsupported_mode"
	frozen_mover.global_position = _ground_to_screen(Vector2(1.0, 0.0))
	attacker._physics_process(0.01)
	assert(_descriptors.size() == 4)
	assert(attacker._area_attack_release_records.is_empty())
	assert(attacker._area_attack_warning <= 0.0)

	attacker.area_attack_rule["targetMode"] = "all_combat_targets"
	attacker.area_attack_rule["scope"] = "unsupported_scope"
	attacker._physics_process(0.01)
	assert(_descriptors.size() == 4)
	assert(attacker._area_attack_release_records.is_empty())
	assert(attacker._area_attack_warning <= 0.0)

	# A supported policy with zero valid targets must not create a visual,
	# schedule damage, or enter the warning/cooldown state.
	attacker.area_attack_rule["scope"] = "visible_actors"
	frozen_mover.global_position = _ground_to_screen(Vector2(30.0, 0.0))
	late_entrant.global_position = _ground_to_screen(Vector2(31.0, 0.0))
	square_corner.global_position = _ground_to_screen(Vector2(32.0, 0.0))
	attacker._physics_process(0.01)
	assert(_descriptors.size() == 4)
	assert(attacker._area_attack_release_records.is_empty())
	assert(attacker._area_attack_warning <= 0.0)

	attacker.queue_free()
	for player: PlayerCharacter in _players:
		if is_instance_valid(player):
			player.queue_free()
	await get_tree().process_frame
	print(
		"FIXED_AREA_RELEASE_BATCH_PASS "
		+ "frozen=4 spikes=4 scheduled=4 square_corner=1 "
		+ "leave_hits=1 late_entry_hits=0 death_cancel=1 cross_map_cancel=1 "
		+ "invalid_policy_fail_closed=1 zero_target_no_release=1"
	)
	get_tree().quit(0)


func _make_player(ground_gu: Vector2) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.global_position = _ground_to_screen(ground_gu)
	player.set_physics_process(false)
	add_child(player)
	player.max_hp = 1000
	player.current_hp = 1000
	player.current_mp = 0
	player.defense_min = 0
	player.defense_max = 0
	_players.append(player)
	return player


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(value)


func _capture_descriptor(descriptor: Dictionary) -> void:
	_descriptors.append(descriptor)


func _descriptor_for(target_instance_id: int) -> Dictionary:
	for descriptor: Dictionary in _descriptors:
		if int(descriptor.get("target_instance_id", 0)) == target_instance_id:
			return descriptor
	return {}


func _assert_descriptor_ids(release_id: String, expected_ids: Array[int]) -> void:
	var actual_ids: Array[int] = []
	for descriptor: Dictionary in _descriptors:
		assert(str(descriptor.get("release_id", "")) == release_id)
		var target_instance_id := int(descriptor.get("target_instance_id", 0))
		actual_ids.append(target_instance_id)
		assert(
			str(descriptor.get("release_target_id", ""))
			== "%s:target:%d" % [release_id, target_instance_id]
		)
	actual_ids.sort()
	var sorted_expected := expected_ids.duplicate()
	sorted_expected.sort()
	assert(actual_ids == sorted_expected)
