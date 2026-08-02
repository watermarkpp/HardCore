extends Node

const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	await _verify_all_warrior_modes_use_live_locked_geometry()
	await _verify_vanished_lock_never_allows_retarget()
	await _verify_wild_rush_preserves_original_selected_target()
	await _verify_target_centered_spatial_cast_policies()
	await _verify_continuous_line_releases_use_live_target_axis()
	_verify_locked_melee_facing_contract()
	print("COMBAT_RELEASE_GEOMETRY_PASS: live footpoints, locked melee facing, target-centred casts retain only live targets")
	get_tree().quit(0)


func _prepare_warrior() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("战士")
	PlayerState.level = 50
	PlayerState.learned_skills = {
		"基本剑术": 3,
		"攻杀剑术": 3,
		"刺杀剑术": 3,
		"半月弯刀": 3,
		"烈火剑法": 3,
	}
	PlayerState.recalculate_stats()


func _verify_all_warrior_modes_use_live_locked_geometry() -> void:
	_prepare_warrior()
	for mode: String in ["normal", "thrust", "half_moon", "fire"]:
		var player := PlayerCharacter.new()
		add_child(player)
		player.set_physics_process(false)
		player.attack_hit_windup = 0.04
		player.current_mp = 999
		player.thrusting_enabled = mode == "thrust"
		player.half_moon_enabled = mode == "half_moon"
		player.fire_sword_enabled = mode == "fire"
		player.global_position = Vector2(100.0, 100.0)
		var target := Node2D.new()
		add_child(target)
		target.global_position = Vector2(180.0, 100.0)
		var emission: Array = []
		player.attack_requested.connect(func(origin: Vector2, direction: Vector2, _damage: int) -> void:
			emission.append({
				"origin": origin,
				"direction": direction,
				"context": player.consume_attack_context(),
			})
		)
		assert(player.request_attack_toward(Vector2.RIGHT, true, target.get_instance_id()))
		# Both operands move after input acceptance and before the hit frame.
		player.global_position = Vector2(120.0, 130.0)
		target.global_position = Vector2(70.0, 210.0)
		await get_tree().create_timer(0.07).timeout
		assert(emission.size() == 1, "%s did not emit exactly once" % mode)
		var event: Dictionary = emission[0]
		var geometry: Dictionary = event.context.get("release_geometry", {})
		assert(event.origin == Vector2(120.0, 130.0), "%s retained stale actor origin" % mode)
		assert(event.direction.is_equal_approx(Vector2.RIGHT), "%s changed facing during windup" % mode)
		assert(str(event.context.get("mode", "normal")) == mode)
		assert(geometry.locked_target_instance_id == target.get_instance_id())
		assert(geometry.locked_target_valid_at_release)
		assert(geometry.direction_locked_for_action)
		assert(geometry.release_facing_policy_id == ReleaseGeometry.MELEE_RELEASE_FACING_POLICY_ID)
		assert(not geometry.allow_target_retarget)
		assert(ReleaseGeometry.candidate_allowed(geometry, target.get_instance_id()))
		var unrelated_target := Node2D.new()
		add_child(unrelated_target)
		assert(not ReleaseGeometry.candidate_allowed(
			geometry, unrelated_target.get_instance_id()
		), "%s may silently switch to another target" % mode)
		unrelated_target.free()
		player.free()
		target.free()


func _verify_vanished_lock_never_allows_retarget() -> void:
	_prepare_warrior()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.attack_hit_windup = 0.04
	var target := Node2D.new()
	add_child(target)
	var target_id := target.get_instance_id()
	var captured: Array[Dictionary] = []
	player.attack_requested.connect(func(_origin: Vector2, _direction: Vector2, _damage: int) -> void:
		captured.append(player.consume_attack_context())
	)
	assert(player.request_attack_toward(Vector2.RIGHT, true, target_id))
	target.free()
	await get_tree().create_timer(0.07).timeout
	assert(captured.size() == 1)
	var geometry: Dictionary = captured[0].get("release_geometry", {})
	assert(geometry.locked_target_instance_id == target_id)
	assert(not geometry.locked_target_valid_at_release)
	assert(not geometry.allow_target_retarget and not geometry.allow_directional_scan)
	player.free()


func _verify_wild_rush_preserves_original_selected_target() -> void:
	_prepare_warrior()
	PlayerState.learned_skills["warrior.wild_rush"] = 3
	assert(
		ReleaseGeometry.WILD_RUSH_RELEASE_TARGET_POLICY_ID
		== "gameplay.warrior.wild_rush.original_locked_target_release.v1"
	)
	assert(ReleaseGeometry.tracks_locked_target_for_skill(
		"warrior.wild_rush",
		"direction"
	))
	assert(ReleaseGeometry.tracks_locked_target_for_skill(
		"wizard.fire_wall",
		"target_area"
	))
	for line_skill_id: String in ["wizard.hellfire", "wizard.laser"]:
		assert(ReleaseGeometry.tracks_locked_target_for_skill(
			line_skill_id,
			"direction"
		), "%s lost the release-frame target axis" % line_skill_id)
	var rush := await _cast_and_capture("warrior.wild_rush", true)
	assert(rush.geometry.policy == ReleaseGeometry.POLICY_LOCKED_SINGLE_TARGET)
	assert(int(rush.geometry.locked_target_instance_id) > 0)
	assert(not rush.geometry.allow_target_retarget)
	assert(rush.direction.is_equal_approx(Vector2(rush.geometry.direction_world)))


func _verify_caster_single_target_and_spatial_cast_policies() -> void:
	PlayerState.reset_progress()
	PlayerState.select_profession("法师")
	PlayerState.level = 50
	PlayerState.learned_skills = {"火球术": 3, "火墙": 3, "雷电术": 3}
	PlayerState.recalculate_stats()
	assert(str(ProfessionRules.skill_combat_profile("火球术", 3).target_mode) == "single")
	assert(str(ProfessionRules.skill_combat_profile("雷电术", 3).target_mode) == "single")
	assert(str(ProfessionRules.skill_combat_profile("火墙", 3).target_mode) == "target_area")

	var projectile := await _cast_and_capture("火球术", true)
	assert(projectile.origin == Vector2(120.0, 130.0))
	assert(projectile.direction.is_equal_approx(Vector2(-50.0, 80.0).normalized()))
	assert(projectile.geometry.policy == ReleaseGeometry.POLICY_LOCKED_SINGLE_TARGET)
	assert(not projectile.geometry.allow_target_retarget)

	var area := await _cast_and_capture("火墙", false)
	assert(area.origin == Vector2(120.0, 130.0))
	assert(area.direction == Vector2.RIGHT)
	assert(area.geometry.policy == ReleaseGeometry.POLICY_INPUT_DIRECTION)
	assert(area.geometry.locked_target_instance_id == 0)


func _verify_target_centered_spatial_cast_policies() -> void:
	for stable_skill_id: String in [
		"wizard.fire_wall",
		"wizard.exploding_flame",
		"wizard.ice_storm",
	]:
		assert(ReleaseGeometry.tracks_locked_target_for_skill(
			stable_skill_id,
			"target_area"
		))
		assert(
			ReleaseGeometry.target_centered_spatial_policy_id(stable_skill_id)
			== ReleaseGeometry.TARGET_CENTERED_SPATIAL_RELEASE_POLICY_ID
		)

	# A valid target identity survives the windup, while its position is sampled
	# live at release. The old input direction must not become a ground fallback.
	var live := ReleaseGeometry.resolve(
		Vector2(120.0, 130.0),
		Vector2.RIGHT,
		77,
		Vector2(70.0, 210.0),
		true,
		true
	)
	assert(live.policy == ReleaseGeometry.POLICY_LOCKED_SINGLE_TARGET)
	assert(live.locked_target_instance_id == 77)
	assert(live.locked_target_valid_at_release)
	assert(live.refresh_locked_target_footpoint_at_release)
	assert(live.direction_world.is_equal_approx(Vector2(-50.0, 80.0).normalized()))
	assert(not live.allow_target_retarget and not live.allow_directional_scan)

	# Death/despawn/range invalidation keeps the original identity but formally
	# rejects it; the release may not retarget or fall back to a direction tile.
	var vanished := ReleaseGeometry.resolve(
		Vector2(120.0, 130.0),
		Vector2.RIGHT,
		77,
		Vector2.ZERO,
		false,
		true
	)
	assert(vanished.locked_target_instance_id == 77)
	assert(not vanished.locked_target_valid_at_release)
	assert(not vanished.allow_target_retarget and not vanished.allow_directional_scan)


func _verify_continuous_line_releases_use_live_target_axis() -> void:
	PlayerState.reset_progress()
	PlayerState.select_profession("法师")
	PlayerState.level = 50
	PlayerState.learned_skills = {"wizard.hellfire": 3, "wizard.laser": 3}
	PlayerState.recalculate_stats()
	for stable_skill_id: String in ["wizard.hellfire", "wizard.laser"]:
		var cast := await _cast_and_capture(stable_skill_id, true)
		assert(cast.origin == Vector2(120.0, 130.0))
		assert(cast.direction.is_equal_approx(
			Vector2(-50.0, 80.0).normalized()
		), "%s used an input-time/8-way axis instead of the live target" % stable_skill_id)
		assert(cast.geometry.policy == ReleaseGeometry.POLICY_LOCKED_SINGLE_TARGET)
		assert(cast.geometry.refresh_locked_target_footpoint_at_release)
		assert(not cast.geometry.allow_target_retarget)


func _verify_locked_melee_facing_contract() -> void:
	var geometry := ReleaseGeometry.resolve(
		Vector2(120.0, 130.0),
		Vector2.RIGHT,
		77,
		Vector2(70.0, 210.0),
		true,
		true,
		ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
	)
	assert(geometry.origin_world == Vector2(120.0, 130.0))
	assert(geometry.direction_world.is_equal_approx(Vector2.RIGHT))
	assert(geometry.locked_target_valid_at_release)
	assert(geometry.direction_locked_for_action)
	assert(
		geometry.direction_space_contract_id
		== "gameplay.professions.combat_direction_space.iso_64x32_tile_8dir.v1"
	)
	assert(geometry.direction_index == 6)
	assert(geometry.visual_direction_index == 6)
	assert(geometry.direction_canonical_tile_step == Vector2i(1, -1))
	assert(geometry.refresh_actor_footpoint_at_release)
	assert(geometry.refresh_locked_target_footpoint_at_release)
	assert(geometry.release_facing_policy_id == ReleaseGeometry.MELEE_RELEASE_FACING_POLICY_ID)
	assert(ReleaseGeometry.candidate_allowed(geometry, 77))
	assert(not ReleaseGeometry.candidate_allowed(geometry, 88))


func _cast_and_capture(skill_name: String, expects_tracking: bool) -> Dictionary:
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.current_mp = 999
	player.global_position = Vector2(100.0, 100.0)
	player.facing = Vector2.RIGHT
	var target := Node2D.new()
	add_child(target)
	target.global_position = Vector2(180.0, 100.0)
	var emission: Array[Dictionary] = []
	player.skill_requested.connect(func(_name: String, origin: Vector2, direction: Vector2, _damage: int) -> void:
		emission.append({
			"origin": origin,
			"direction": direction,
			"geometry": player.consume_skill_context().get("release_geometry", {}),
		})
	)
	assert(player.request_skill(skill_name, target.get_instance_id()))
	player.global_position = Vector2(120.0, 130.0)
	target.global_position = Vector2(70.0, 210.0)
	await get_tree().create_timer(0.72).timeout
	assert(emission.size() == 1, "%s did not release exactly once" % skill_name)
	assert(bool(emission[0].geometry.locked_target_valid_at_release) == expects_tracking)
	var result := emission[0].duplicate(true)
	player.free()
	target.free()
	return result
