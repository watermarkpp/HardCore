extends Node

## Consumer contract for the bounded formal spatial read lane.
##
## The formal binding API is consumed through the real Enemy entry.  The
## availability gate still uses has_method so stock source produces a clean
## RED instead of a parser-level missing-method error.  The fallback and index
## publication probes below are real Enemy/RuntimeCombatSpatialIndex paths.

const EnemyScript := preload("res://scripts/enemy.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const RootScript := preload("res://scripts/game_root.gd")
## This is the single Enemy-side synchronous read-segment entry.  It remains
## private to Enemy; the fixture uses has_method only so stock source produces
## a clean availability RED instead of a parser-level missing-method error.
const CONSUMER_ENTRY := &"_hc_formal_spatial_read_segment"

var _checks := 0
var _failures := 0


func _ready() -> void:
	_run_contract()
	print(
		"FORMAL_SPATIAL_READ_LANE_CONTRACT_%s checks=%d failures=%d"
		% ["PASS" if _failures == 0 else "FAIL", _checks, _failures]
	)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("FORMAL_SPATIAL_READ_LANE_PASS: " + label)
	else:
		_failures += 1
		push_error("FORMAL_SPATIAL_READ_LANE_FAIL: " + label)


func _override_projection(_value: Vector2) -> Vector2:
	return Vector2(999.0, -999.0)


func _run_contract() -> void:
	var index := SpatialIndexScript.new()
	var enemy := EnemyScript.new()
	if not enemy.has_method(CONSUMER_ENTRY):
		_checks += 1
		_failures += 1
		print("FORMAL_SPATIAL_READ_LANE_FAIL: Enemy exposes the formal spatial read segment consumer entry")
		print("FORMAL_SPATIAL_READ_LANE_AVAILABILITY_RED: missing %s" % CONSUMER_ENTRY)
		enemy.free()
		get_tree().quit(1)
		return
	var game := RootScript.new()
	game.current_map_id = 913203
	# Use the production provider object itself.  The GameRoot remains
	# unattached to the SceneTree, so this fixture cannot start world
	# construction as a side effect.
	var background := WorldBackground.new()
	# The owner lookup is part of the formal provider contract.  Attaching this
	# real provider to an unattached GameRoot instance supplies that identity
	# without entering the SceneTree or running either _ready path.
	game.add_child(background)
	enemy.configure_runtime_map_projection(
		913203,
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(game, "_canonical_screen_px_to_ground_gu"),
	)
	enemy.environment_blocker = background
	enemy.set_meta("zone_generation", 1)
	enemy.configure_spatial_index(index, 91)
	enemy.global_position = Vector2(4.0, 6.0)
	var initial_ground := game._canonical_screen_px_to_ground_gu(Vector2(4.0, 6.0))
	index.register(
		91,
		913203,
		initial_ground,
		1.0,
		1,
		enemy,
		Callable(enemy, "spatial_index_position"),
	)

	enemy.call("_hc_begin_formal_spatial_read_scope")
	var lane_value: Variant = enemy.call(CONSUMER_ENTRY, Vector2(4.0, 6.0))
	_check(
		lane_value is Vector2 and (lane_value as Vector2).is_finite(),
		"consumer entry returns the current formal read result",
	)
	_check(enemy._hc_spatial_read_binding != null, "known canonical provider binds in actual scope")
	var first_binding: Object = enemy._hc_spatial_read_binding
	var second_value: Variant = enemy.call(CONSUMER_ENTRY, Vector2(5.0, 7.0))
	_check(
		second_value is Vector2 and is_same(first_binding, enemy._hc_spatial_read_binding),
		"same scope reuses one immutable formal binding",
	)
	# The candidate lane only accepts a same-formal-world Enemy.  It is read
	# lazily inside the already-open scope; changing its actual screen position
	# must replace the fact, while a nonfinite position must never revive the
	# previous finite fact.
	var candidate := EnemyScript.new()
	candidate.setup(GameData.get_monster_by_id(24), null, false)
	candidate.set_physics_process(false)
	candidate.configure_runtime_map_projection(
		913203,
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(game, "_canonical_screen_px_to_ground_gu"),
	)
	candidate.environment_blocker = background
	candidate.set_meta("zone_generation", 1)
	var candidate_screen := Vector2(22.0, 31.0)
	candidate.global_position = candidate_screen
	var candidate_first_ground: Vector2 = enemy.call("_hc_current_candidate_position", candidate)
	_check(candidate_first_ground.is_finite(), "same-world candidate acquires a finite formal position")
	candidate.global_position = Vector2(48.0, 57.0)
	var candidate_second_ground: Vector2 = enemy.call("_hc_current_candidate_position", candidate)
	_check(
		candidate_second_ground.is_finite() and candidate_second_ground != candidate_first_ground,
		"candidate cache follows actual same-frame screen mutation",
	)
	candidate.global_position = Vector2(INF, 0.0)
	var candidate_nonfinite_ground: Vector2 = enemy.call("_hc_current_candidate_position", candidate)
	_check(
		not candidate_nonfinite_ground.is_finite() and candidate_nonfinite_ground != candidate_second_ground,
		"candidate nonfinite read does not reuse a prior finite fact",
	)
	candidate.global_position = Vector2(61.0, 73.0)
	candidate.set_meta("zone_generation", 2)
	background._environment_collision_revision += 1
	var candidate_revised_ground: Vector2 = enemy.call("_hc_current_candidate_position", candidate)
	_check(
		candidate_revised_ground.is_finite() and candidate_revised_ground != candidate_second_ground,
		"candidate generation and environment revision force a fresh formal read",
	)
	# Feed the real candidate list to each narrow consumer. The same actor is
	# first outside the envelope, then moved to the actual segment/destination;
	# these calls prove live-position reads participate in eligibility filters.
	var motion_origin := game._canonical_screen_px_to_ground_gu(enemy.global_position)
	var motion_endpoint := motion_origin + Vector2(1.0, 0.0)
	candidate.global_position = game._canonical_ground_gu_to_screen_px(motion_origin + Vector2(20.0, 20.0))
	var complete_candidates: Array = [candidate]
	var motion_clear_outside: bool = enemy.call("_hc_motion_candidates", motion_origin, motion_endpoint, complete_candidates)
	var destination_clear_outside: bool = enemy.call(
		"_hc_flank_destination_candidates_clear",
		motion_endpoint,
		complete_candidates,
	)
	_check(motion_clear_outside and destination_clear_outside, "candidate list preserves outside-envelope eligibility")
	candidate.global_position = game._canonical_ground_gu_to_screen_px(motion_origin + Vector2(0.5, 0.0))
	var motion_clear_inside: bool = enemy.call("_hc_motion_candidates", motion_origin, motion_endpoint, complete_candidates)
	var destination_clear_inside: bool = enemy.call(
		"_hc_flank_destination_candidates_clear",
		motion_origin + Vector2(0.5, 0.0),
		complete_candidates,
	)
	_check(not motion_clear_inside, "candidate current position participates in motion collision")
	_check(not destination_clear_inside, "candidate current position participates in destination eligibility")
	candidate.global_position = Vector2(INF, 0.0)
	var frontline_nonfinite: int = enemy.call(
		"_hc_frontline_candidates",
		motion_origin,
		motion_endpoint,
		enemy,
		complete_candidates,
	)
	_check(
		frontline_nonfinite == candidate.get_instance_id(),
		"nonfinite candidate follows the production fail-closed frontline policy",
	)
	enemy.call("_hc_end_formal_spatial_read_scope")
	candidate.free()

	# The sanctioned writer publishes the same-frame actor position before a
	# later query can observe it.
	enemy.set_combat_position(Vector2(9.0, 11.0), &"contract_same_frame_move")
	var moved_ground := game._canonical_screen_px_to_ground_gu(Vector2(9.0, 11.0))
	_check(
		index._entries[91].absolute_ground_gu == moved_ground,
		"same-frame position setter publishes the spatial index",
	)

	# RuntimeCombatSpatialIndex must never overwrite a valid entry with a
	# nonfinite projection; this is a pre-existing formal contract reused here.
	index.update_actor(91, Vector2(INF, 0.0))
	_check(
		index._entries[91].absolute_ground_gu == moved_ground,
		"nonfinite position retains the last valid index entry",
	)

	# Generation/environment changes invalidate the Enemy's projection proof;
	# the existing writer must still publish the current position through the
	# live formal path rather than treating the old entry as current.
	enemy.set_meta("zone_generation", 2)
	enemy.set_combat_position(Vector2(12.0, 15.0), &"contract_generation_move")
	var generation_ground := game._canonical_screen_px_to_ground_gu(Vector2(12.0, 15.0))
	_check(
		index._entries[91].absolute_ground_gu == generation_ground,
		"generation change forces current-position index publication",
	)

	# A non-canonical override is an identity assertion failure and must use the
	# actual old Callable path rather than the formal binding.
	enemy.configure_runtime_map_projection(
		913203,
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(self, "_override_projection"),
	)
	enemy.call("_hc_begin_formal_spatial_read_scope")
	var overridden: Variant = enemy.call(CONSUMER_ENTRY, Vector2(4.0, 6.0))
	_check(
		enemy._hc_spatial_read_binding == null and overridden == Vector2(999.0, -999.0),
		"override provider rejects formal binding and falls back to old Callable",
	)
	enemy.call("_hc_end_formal_spatial_read_scope")

	game.current_map_id = 913203
	enemy.configure_runtime_map_projection(
		913203,
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(game, "_canonical_screen_px_to_ground_gu"),
	)
	enemy.call("_hc_begin_formal_spatial_read_scope")
	enemy.call(CONSUMER_ENTRY, Vector2(8.0, 9.0))
	_check(enemy._hc_spatial_read_binding != null, "canonical binding reacquires after override scope")
	var old_writer_screen := Vector2(8.0, 9.0)
	enemy.call("_screen_position_px_to_ground_position_gu", old_writer_screen)
	_check(enemy._hc_spatial_read_points.has(old_writer_screen), "writer scope records the old formal read point")
	enemy.set_combat_position(Vector2(13.0, 16.0), &"contract_reentry_move")
	var writer_ground := game._canonical_screen_px_to_ground_gu(Vector2(13.0, 16.0))
	_check(not enemy._hc_spatial_read_points.has(old_writer_screen), "position writer clears the old formal read point before publish")
	_check(index._entries[91].absolute_ground_gu == writer_ground, "position writer publishes the new authoritative index ground")
	enemy.call("_hc_end_formal_spatial_read_scope")

	# Candidate current-position facts must follow the live screen position,
	# while a nonfinite provider result must leave the last valid index entry.
	var live_position := {"screen": Vector2(22.0, 31.0)}
	var candidate_ground: Vector2 = game._canonical_screen_px_to_ground_gu(live_position["screen"])
	var index_candidate := Node2D.new()
	index.register(
		92,
		913203,
		candidate_ground,
		1.0,
		2,
		index_candidate,
		func() -> Vector2: return game._canonical_screen_px_to_ground_gu(live_position["screen"]),
	)
	var initial_candidates: Array = index.query_aabb_candidates(
		913203,
		Rect2(candidate_ground - Vector2.ONE, Vector2.ONE * 2.0),
	)
	_check(initial_candidates.any(func(row: Dictionary) -> bool: return row.get("node") == index_candidate), "candidate initial domain query")
	live_position["screen"] = Vector2(48.0, 57.0)
	var moved_candidate_ground: Vector2 = game._canonical_screen_px_to_ground_gu(live_position["screen"])
	var moved_candidates: Array = index.query_aabb_candidates(
		913203,
		Rect2(moved_candidate_ground - Vector2.ONE, Vector2.ONE * 2.0),
	)
	_check(moved_candidates.any(func(row: Dictionary) -> bool: return row.get("node") == index_candidate), "candidate query consumes current live position")
	var candidate_last_valid: Vector2 = index._entries[92].absolute_ground_gu
	live_position["screen"] = Vector2(INF, 0.0)
	index.query_aabb_candidates(913203, Rect2(candidate_last_valid - Vector2.ONE, Vector2.ONE * 2.0))
	_check(index._entries[92].absolute_ground_gu == candidate_last_valid, "candidate nonfinite live read retains index entry")
	index.unregister(92)
	index.register(92, 913204, candidate_last_valid, 1.0, 2, index_candidate, func() -> Vector2: return candidate_last_valid)
	var old_map_candidates: Array = index.query_aabb_candidates(
		913203,
		Rect2(candidate_last_valid - Vector2.ONE, Vector2.ONE * 2.0),
	)
	_check(
		not old_map_candidates.any(func(row: Dictionary) -> bool: return row.get("node") == index_candidate),
		"candidate map domain change is visible same frame",
	)
	index_candidate.free()

	# Target life/access facts use actual typed Player/Enemy actors in a minimal
	# fixture tree. Their processes are disabled; no GameRoot is attached, so
	# only the production actor predicates and direct calls execute.
	var player := PlayerCharacter.new()
	player.set_physics_process(false)
	player.max_hp = 1000
	player.current_hp = 1000
	player.set_meta("runtime_map_id", 913203)
	add_child(player)
	var combat_enemy := EnemyScript.new()
	combat_enemy.setup(GameData.get_monster_by_id(24), player, false)
	combat_enemy.set_physics_process(false)
	combat_enemy.configure_runtime_map_projection(
		913203,
		Callable(game, "_canonical_ground_gu_to_screen_px"),
		Callable(game, "_canonical_screen_px_to_ground_gu"),
	)
	combat_enemy.environment_blocker = background
	combat_enemy.set_meta("zone_generation", 1)
	combat_enemy.set_meta("safe_zone_context", {"valid": true, "zones": [], "revision": 1})
	add_child(combat_enemy)
	combat_enemy.configure_spatial_index(index, 93)
	var combat_enemy_ground := game._canonical_screen_px_to_ground_gu(Vector2(9.0, 11.0))
	combat_enemy.global_position = Vector2(9.0, 11.0)
	index.register(93, 913203, combat_enemy_ground, 1.0, 1, combat_enemy)
	player.global_position = game._canonical_ground_gu_to_screen_px(combat_enemy_ground + Vector2(20.0, 0.0))
	combat_enemy.call("_hc_begin_formal_spatial_read_scope")
	_check(combat_enemy._target_candidate_is_live(player), "typed Player target live predicate accepts current map")
	_check(combat_enemy._hc_target_usable(player), "typed Player target passes actual usable and safe-context gates")
	_check(combat_enemy._hc_access(player, 0.0, true) == "OUT_OF_RANGE", "typed Player target establishes far-range access baseline")
	player.current_hp = 0
	_check(not combat_enemy._target_candidate_is_live(player), "Player HP zero closes live predicate")
	_check(not combat_enemy._hc_target_usable(player), "Player HP zero closes usable predicate")
	_check(combat_enemy._hc_access(player) == "INVALID_TARGET", "Player HP zero reaches invalid-target access gate")
	player.current_hp = player.max_hp
	player.set_meta("runtime_map_id", 913204)
	_check(not combat_enemy._target_candidate_is_live(player), "Player map mismatch closes live predicate")
	_check(combat_enemy._hc_access(player) == "INVALID_TARGET", "Player map mismatch reaches invalid-target access gate")
	player.set_meta("runtime_map_id", 913203)
	_check(combat_enemy._target_candidate_is_live(player), "Player map restoration is observed immediately")
	_check(player.begin_combat_transition("formal_read_lane"), "Player transition owner enters actual transition")
	_check(not combat_enemy._target_candidate_is_live(player), "Player transition closes live predicate")
	_check(combat_enemy._hc_access(player) == "INVALID_TARGET", "Player transition reaches invalid-target access gate")
	_check(player.finish_combat_transition("formal_read_lane"), "Player transition owner closes actual transition")
	combat_enemy.call("_hc_end_formal_spatial_read_scope")

	var enemy_target := EnemyScript.new()
	enemy_target.setup(GameData.get_monster_by_id(24), null, false)
	enemy_target.set_physics_process(false)
	enemy_target.runtime_map_id = 913203
	enemy_target.set_meta("runtime_map_id", 913203)
	add_child(enemy_target)
	_check(combat_enemy._target_candidate_is_live(enemy_target), "typed Enemy target live predicate accepts current map")
	enemy_target.current_hp = 0
	_check(not combat_enemy._target_candidate_is_live(enemy_target), "typed Enemy HP zero closes live predicate")
	enemy_target.current_hp = enemy_target.max_hp
	enemy_target.set_meta("runtime_map_id", 913204)
	_check(not combat_enemy._target_candidate_is_live(enemy_target), "typed Enemy map mismatch closes live predicate")
	enemy_target.queue_free()
	_check(not combat_enemy._target_candidate_is_live(enemy_target), "typed Enemy deletion closes live predicate")
	combat_enemy.queue_free()
	player.queue_free()
	index.unregister(93)

	index.unregister(91)
	enemy.free()
	game.free()
