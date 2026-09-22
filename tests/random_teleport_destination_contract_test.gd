extends Node

const Rules := preload("res://scripts/world_spatial_rules.gd")
const ORIGIN_GROUND := Vector2(38.5, 13.5)
## Formal Bich right wall starts at x=79 here. The actor fits at this
## sampled cell center, but the old round-to-grid path lands in the wall.
const EDGE_GROUND := Vector2(78.5, 30.5)
const EDGE_ORIGIN_GROUND := Vector2(70.5, 30.5)
const BLOCKED_GROUND := Vector2(79.0, 31.0)
const SCREEN_ZERO_GROUND := Vector2(39.5, 39.5)
const SCREEN_ZERO_ORIGIN_GROUND := Vector2(47.5, 39.5)
## Restore the skill's pre-36bfb5f8 range; the random scroll stays full-map.
const SKILL_MIN_DISTANCE_GU := 3.0
const SKILL_MAX_DISTANCE_GU := 16.25
const SAMPLE_SEED := 20260922
const SAMPLE_COUNT := 64

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {"瞬息移动": 3}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var deadline_ms := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline_ms:
		if game.gameplay_input_is_enabled() and game._target_spatial_query_ready():
			break
		await get_tree().process_frame
	if not _check(
		int(game.current_map_id) == 910001
		and game.gameplay_input_is_enabled()
		and game._target_spatial_query_ready(),
		"fixture must use the fully ready formal Bich world"
	):
		await _finish(game)
		return
	game.set_process(false)
	game.player.set_physics_process(false)
	var edge_screen: Vector2 = game._canonical_ground_gu_to_screen_px(EDGE_GROUND)
	var old_tile: Vector2i = game._canonical_screen_px_to_grid_cell(edge_screen)
	var old_screen: Vector2 = game._canonical_grid_cell_to_screen_px(old_tile)
	_check(not _blocked(game, edge_screen), "formal edge cell center must fit the player footprint")
	_check(old_tile == Vector2i(79, 31), "fixture must expose the original half-cell rounding")
	_check(_blocked(game, old_screen), "old tile roundtrip must hit the authored right wall")
	print("RANDOM_TELEPORT_COUNTEREXAMPLE center_gu=%s old_tile=%s old_blocked=%s" % [
		str(EDGE_GROUND), str(old_tile), str(_blocked(game, old_screen)),
	])

	_check_successful_destination(game, EDGE_GROUND, EDGE_ORIGIN_GROUND, "edge cell center")
	var zero_screen: Vector2 = game._canonical_ground_gu_to_screen_px(SCREEN_ZERO_GROUND)
	_check(zero_screen == Vector2.ZERO, "formal map center must exercise screen ZERO")
	_check(not _blocked(game, zero_screen), "screen ZERO is a legal authored landing")
	_check_successful_destination(game, SCREEN_ZERO_GROUND, SCREEN_ZERO_ORIGIN_GROUND, "legal screen ZERO")
	_check_blocked_destination(game)
	_check_out_of_range_destination(game)
	_check_local_skill_sampler(game)
	_check_full_map_scroll_sampler(game)
	await _finish(game)


func _check_successful_destination(game: Node, ground: Vector2, origin_ground: Vector2, label: String) -> void:
	_reset_caster(game, origin_ground)
	_check(is_equal_approx(origin_ground.distance_to(ground), 8.0), "%s fixture must be within the skill's local range" % label)
	var expected_screen: Vector2 = game._canonical_ground_gu_to_screen_px(ground)
	var arrivals_before := _arrival_visuals(game).size()
	var result := _cast_at_ground(game, ground)
	_check(bool(result.get("effect_success", false)), "%s must report the applied teleport" % label)
	_check(game.player.global_position.is_equal_approx(expected_screen), "%s must retain the exact checked destination" % label)
	var plan: Dictionary = result.get("canonical_plan", {})
	var snapshot: Dictionary = plan.get("canonical_snapshot", {})
	var snapshot_center: Vector2 = snapshot.get("target_center_ground_gu", Vector2.INF)
	_check(snapshot_center.is_equal_approx(ground), "%s snapshot must retain the exact destination" % label)
	var action := _teleport_action(plan)
	var action_ground: Vector2 = action.get("destination_ground_gu", Vector2.INF)
	_check(action_ground.is_equal_approx(ground), "%s action must carry the exact GU destination" % label)
	_check(bool(result.get("plan_immutable", {}).get("valid", false)), "%s must leave the canonical plan immutable" % label)
	var arrivals := _arrival_visuals(game)
	if _check(arrivals.size() == arrivals_before + 1, "%s must create one arrival visual" % label):
		var arrival: CasterSkillVisualEffect = arrivals.back()
		_check(arrival.global_position.is_equal_approx(expected_screen), "%s arrival must share the actual landing" % label)
		var arrival_snapshot: Dictionary = arrival.get("_skill_footprint_snapshot")
		_check(
			str(arrival_snapshot.get("snapshot_id", "")) == str(snapshot.get("snapshot_id", ""))
			and not str(snapshot.get("snapshot_id", "")).is_empty(),
			"%s arrival must consume the release snapshot: actual=%s expected=%s validation=%s" % [
				label, str(arrival_snapshot.get("snapshot_id", "")), str(snapshot.get("snapshot_id", "")),
				str(SkillFootprintSnapshot.validate_for_consumer(snapshot,
					arrival.get("_snapshot_validation_context"), SkillFootprintSnapshot.VALIDATION_STRICT_V2))]
		)


func _check_blocked_destination(game: Node) -> void:
	_reset_caster(game, EDGE_ORIGIN_GROUND)
	var origin: Vector2 = game.player.global_position
	var blocked_screen: Vector2 = game._canonical_ground_gu_to_screen_px(BLOCKED_GROUND)
	_check(_blocked(game, blocked_screen), "negative control must use a real authored wall")
	_check(EDGE_ORIGIN_GROUND.distance_to(BLOCKED_GROUND) < SKILL_MAX_DISTANCE_GU, "wall negative control must be within skill range")
	var arrivals_before := _arrival_visuals(game).size()
	## The caller's advisory destination_valid=true cannot overrule collision.
	var result := _cast_at_ground(game, BLOCKED_GROUND)
	_check(game.player.global_position == origin, "blocked destination must preserve the player's position")
	_check(not bool(result.get("effect_success", true)), "blocked destination must not claim effect_success")
	_check(_arrival_visuals(game).size() == arrivals_before, "blocked destination must not create an arrival visual")


func _check_out_of_range_destination(game: Node) -> void:
	_reset_caster(game, EDGE_ORIGIN_GROUND)
	var origin: Vector2 = game.player.global_position
	var far_screen: Vector2 = game._canonical_ground_gu_to_screen_px(ORIGIN_GROUND)
	_check(not _blocked(game, far_screen), "out-of-range negative control must be collision-legal")
	_check(EDGE_ORIGIN_GROUND.distance_to(ORIGIN_GROUND) > SKILL_MAX_DISTANCE_GU, "negative control must exceed the skill's maximum range")
	var arrivals_before := _arrival_visuals(game).size()
	var result := _cast_at_ground(game, ORIGIN_GROUND)
	_check(game.player.global_position == origin, "out-of-range destination must preserve the player's position")
	_check(not bool(result.get("effect_success", true)), "out-of-range destination must not claim effect_success")
	_check(_arrival_visuals(game).size() == arrivals_before, "out-of-range destination must not create an arrival visual")


func _check_local_skill_sampler(game: Node) -> void:
	if not _check(game.has_method("_find_valid_skill_teleport_position"), "skill needs its own local-range production sampler"):
		return
	_reset_caster(game)
	var origin: Vector2 = game.player.global_position
	for sample_index: int in range(SAMPLE_COUNT):
		game._rng.seed = SAMPLE_SEED + sample_index
		var candidate: Vector2 = game._find_valid_skill_teleport_position(origin)
		var candidate_ground: Vector2 = game._canonical_screen_px_to_ground_gu(candidate)
		var distance_gu := candidate_ground.distance_to(ORIGIN_GROUND)
		_check(candidate != origin, "local seed %d must find a legal landing" % sample_index)
		_check(
			distance_gu >= SKILL_MIN_DISTANCE_GU - 0.00001
			and distance_gu <= SKILL_MAX_DISTANCE_GU + 0.00001,
			"local seed %d must remain in the 3..16.25 GU annulus, got %.6f" % [sample_index, distance_gu]
		)
		_check(not _blocked(game, candidate), "local seed %d must preserve actual collision clearance" % sample_index)
	game._rng.seed = SAMPLE_SEED
	# The real entry rolls the caster stat before choosing the destination,
	# then prepares the common caster factory's spiritual-power input.
	game._canonical_primary_stat_roll("wizard")
	var sampled: Vector2 = game._find_valid_skill_teleport_position(origin)
	game._canonical_primary_stat_roll("taoist")
	var sampled_rng_state: int = game._rng.state
	if not _check(sampled != origin, "seeded skill sampler must find a legal destination"):
		return
	game._rng.seed = SAMPLE_SEED
	var result: Dictionary = game._execute_canonical_skill(
		"wizard.teleport", origin, Vector2.RIGHT, 0, {"force_success": true}
	)
	_check(bool(result.get("effect_success", false)), "seeded skill teleport must apply")
	_check(game.player.global_position.is_equal_approx(sampled), "skill must apply its local sampler's exact checked point")
	_check(int(game._rng.state) == sampled_rng_state, "skill must consume its local sampling RNG sequence once")


func _check_full_map_scroll_sampler(game: Node) -> void:
	_reset_caster(game)
	var origin: Vector2 = game.player.global_position
	var far_seed := -1
	var sampled := origin
	var sampled_rng_state := 0
	for sample_index: int in range(SAMPLE_COUNT):
		var seed_value := SAMPLE_SEED + sample_index
		game._rng.seed = seed_value
		var candidate: Vector2 = game._find_valid_random_teleport_position(origin)
		var candidate_ground: Vector2 = game._canonical_screen_px_to_ground_gu(candidate)
		if candidate_ground.distance_to(ORIGIN_GROUND) > SKILL_MAX_DISTANCE_GU:
			far_seed = seed_value
			sampled = candidate
			sampled_rng_state = game._rng.state
			break
	if not _check(far_seed >= 0, "full-map scroll sampling must reach beyond the skill's 16.25 GU range"):
		return
	var sampled_ground: Vector2 = game._canonical_screen_px_to_ground_gu(sampled)
	_check(sampled_ground - sampled_ground.floor() == Vector2(0.5, 0.5), "scroll landing distribution must stay on cell centers")
	_check(not _blocked(game, sampled), "full-map scroll target must retain actual collision clearance")
	game._rng.seed = far_seed
	var scroll := GameData.get_item_record("随机传送卷")
	if _check(str(scroll.get("useEffect", "")) == "random_teleport", "scroll fixture must resolve the formal item"):
		game._on_scroll_used(str(scroll.get("name", "")))
		_check(game.player.global_position.is_equal_approx(sampled), "scroll must apply its full-map sampler's exact checked point")
		_check(int(game._rng.state) == sampled_rng_state, "scroll must preserve the sampling RNG sequence")


func _cast_at_ground(game: Node, ground: Vector2) -> Dictionary:
	var destination_screen: Vector2 = game._canonical_ground_gu_to_screen_px(ground)
	return game._execute_canonical_skill(
		"wizard.teleport", game.player.global_position, Vector2.RIGHT, 0,
		{
			"force_success": true,
			"destination_valid": true,
			"destination_ground_gu": ground,
			## Retained to prove the lossy legacy field cannot override exact GU.
			"destination_tile": game._canonical_screen_px_to_grid_cell(destination_screen),
		}
	)


func _reset_caster(game: Node, origin_ground := ORIGIN_GROUND) -> void:
	var origin_screen: Vector2 = game._canonical_ground_gu_to_screen_px(origin_ground)
	_check(not _blocked(game, origin_screen), "caster fixture origin must be legal on the formal map")
	game._set_player_world_position(origin_screen)
	game.player.current_mp = 100


func _blocked(game: Node, point: Vector2) -> bool:
	return Rules.environment_blocks_actor_screen_px(game.background, point, ArtSpec.PLAYER_COLLISION_RADIUS_PX)


func _arrival_visuals(game: Node) -> Array[CasterSkillVisualEffect]:
	var result: Array[CasterSkillVisualEffect] = []
	for child: Node in game.get_children():
		if child is CasterSkillVisualEffect and child.skill_id == "wizard.teleport" and child.phase_id == "arrival":
			result.append(child)
	return result


func _teleport_action(plan: Dictionary) -> Dictionary:
	for action: Dictionary in plan.get("gameplay_actions", []):
		if str(action.get("type", "")) == "server_random_teleport":
			return action
	return {}


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failures.append(message)
	return condition


func _finish(game: Node) -> void:
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _failures.is_empty():
		for message: String in _failures:
			push_error("RANDOM_TELEPORT_DESTINATION_CONTRACT_FAIL: %s" % message)
		get_tree().quit(1)
		return
	print("RANDOM_TELEPORT_DESTINATION_CONTRACT_PASS: exact landing, snapshot, arrival, local skill range and full-map scroll")
	get_tree().quit(0)
