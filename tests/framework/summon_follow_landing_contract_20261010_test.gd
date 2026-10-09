extends Node

const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

var _game: Node
var _player: PlayerCharacter
var _summon: SummonActor
var _ignored_summons: Array[SummonActor] = []
var _occupying_summons: Array[SummonActor] = []
var _proof := Proof.new()
var _failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = ProfessionRules.profession_display_name("taoist")
	PlayerState.level = 40
	PlayerState.learned_skills = {
		ProfessionRules.skill_display_name("taoist.summon_skeleton"): 3,
	}
	PlayerState.recalculate_stats()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	await Fixture.wait_for_formal_world(self, _game, "summon_follow_landing")
	_player = _game.player
	_game.set_process(false)
	_game.set_physics_process(false)
	_player.set_physics_process(false)
	for raw: Node in get_tree().get_nodes_in_group("enemies"):
		if raw is EnemyActor:
			(raw as EnemyActor).set_physics_process(false)
	var formal_profile: Dictionary = _game._resolve_projection_profile_for_map(
		_game.current_map_id
	)
	if not check(bool(formal_profile.get("success", false)), "formal runtime projection profile is valid"):
		await _cleanup_and_finish(1)
		return
	var formal_source_size: Vector2i = formal_profile.get("source_size", Vector2i.ZERO)
	if not check(
		formal_source_size.x > 0 and formal_source_size.y > 0,
		"formal runtime projection profile has a source domain",
	):
		await _cleanup_and_finish(1)
		return

	_summon = SummonActor.new()
	_summon.setup(_player, "骷髅", 40, 3, "taoist.summon_skeleton", 40)
	_summon.set_meta("taoist_main_pet", true)
	_summon.set_meta("taoist_main_pet_contract", PlayerState.TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID)
	_summon.configure_runtime_map_projection(
		_game.current_map_id,
		Callable(_game, "_canonical_ground_gu_to_screen_px"),
		Callable(_game, "_canonical_screen_px_to_ground_gu"),
	)
	_summon.configure_spatial_index(_game._combat_spatial_index)
	_game.add_child(_summon)
	_summon.set_physics_process(false)
	# Registry membership is map-scoped; live emitter signal ownership is not.
	var emitter_id := _summon.get_instance_id()
	_game._register_passive_wake_emitter(_summon)
	_game._passive_wake_emitters.erase(emitter_id)
	_game._on_passive_wake_emitter_changed(emitter_id)
	_game._register_passive_wake_emitter(_summon)
	check(
		_count_game_signal_hooks(_summon, &"passive_wakeup_changed") == 1,
		"live emitter re-admission keeps one movement wake hook",
	)
	check(
		_count_game_signal_hooks(_summon, &"summon_state_changed") == 1,
		"live emitter re-admission keeps one summon-state wake hook",
	)
	check(
		_count_game_signal_hooks(_summon, &"tree_exiting") == 1,
		"live emitter re-admission keeps one retirement hook",
	)
	var retiring_summon := SummonActor.new()
	retiring_summon.setup(_player, "骷髅", 40, 3, "taoist.summon_skeleton", 40)
	_game.add_child(retiring_summon)
	retiring_summon.set_physics_process(false)
	_game._register_passive_wake_emitter(retiring_summon)
	var retiring_id := retiring_summon.get_instance_id()
	_game._passive_wake_emitters.erase(retiring_id)
	retiring_summon.passive_wakeup_changed.emit()
	retiring_summon.queue_free()
	_game._on_passive_wake_emitter_changed(retiring_id)
	check(
		not _game._passive_wake_emitters.has(retiring_id),
		"queued old-map emitter cannot re-enter the registry",
	)
	await get_tree().process_frame
	check(
		not _game._passive_wake_emitters.has(retiring_id),
		"deferred wake callback cannot resurrect a retired emitter",
	)
	_ignored_summons.append(_summon)
	var open_plan: Dictionary = _game._canonical_summon_spawn_plan(
		"taoist.summon_skeleton", _summon, _summon.pet_slot_index, _ignored_summons
	)
	if not check(bool(open_plan.get("valid", false)), "formal map has an open canonical summon landing"):
		await _cleanup_and_finish(1)
		return
	var clear_ground: Vector2 = open_plan.get("position_ground_gu", Vector2.ZERO)
	var clear_screen: Vector2 = _game._canonical_ground_gu_to_screen_px(clear_ground)
	_game._set_player_world_position(clear_screen)
	_summon.global_position = Vector2(5000.0, 5000.0)

	var open_before := _summon.global_position
	_summon._physics_process(1.0 / 60.0)
	check(not _summon.owner_teleport_pending, "open canonical landing commits without pending")
	check(_summon.global_position != open_before, "open owner teleport uses a legal canonical landing")
	check(
		_game._canonical_summon_position_is_valid(
			_game._canonical_screen_px_to_ground_gu(_summon.global_position),
			_summon.combat_radius_gu,
			_summon,
			_ignored_summons,
		),
		"open owner teleport result must pass the formal landing validator",
	)

	var original_map_id: int = _summon.runtime_map_id
	_summon.runtime_map_id = original_map_id + 1
	var stale_map_plan: Dictionary = _game._canonical_summon_follow_landing_plan(_summon)
	check(not bool(stale_map_plan.get("valid", false)), "map mismatch rejects follow landing")
	check(not bool(stale_map_plan.get("defer_allowed", true)), "map mismatch cannot register deferred arrival")
	_summon.runtime_map_id = original_map_id
	var other_player := PlayerCharacter.new()
	_game.add_child(other_player)
	var original_owner: PlayerCharacter = _summon.owner_player
	_summon.owner_player = other_player
	var stale_owner_plan: Dictionary = _game._canonical_summon_follow_landing_plan(_summon)
	check(not bool(stale_owner_plan.get("valid", false)), "owner mismatch rejects follow landing")
	check(not bool(stale_owner_plan.get("defer_allowed", true)), "owner mismatch cannot defer arrival")
	_summon.owner_player = original_owner
	other_player.queue_free()
	_game._map_transition_in_progress = true
	var transition_plan: Dictionary = _game._canonical_summon_follow_landing_plan(_summon)
	check(not bool(transition_plan.get("valid", false)), "map transition rejects follow landing")
	check(not bool(transition_plan.get("defer_allowed", true)), "map transition cannot defer arrival")
	_game._map_transition_in_progress = false
	check(not bool(_game._register_pending_main_pet_arrival(_summon)), "non-pending summon cannot register arrival")

	var wall_owner := _find_clear_owner_with_blocked_formation_anchor()
	check(wall_owner.is_finite(), "formal map has a clear owner with a blocked formation anchor")
	if not wall_owner.is_finite():
		await _cleanup_and_finish(1)
		return
	_game._set_player_world_position(wall_owner)
	_summon.global_position = Vector2(5000.0, 5000.0)
	_summon.owner_teleport_pending = false
	var blocked_before := _summon.global_position
	_summon._physics_process(1.0 / 60.0)
	check(not _summon.owner_teleport_pending, "blocked anchor with alternate legal landing recovers immediately")
	check(_summon.global_position != blocked_before, "alternate legal landing is committed")
	check(
		_game._canonical_summon_position_is_valid(
			_game._canonical_screen_px_to_ground_gu(_summon.global_position),
			_summon.combat_radius_gu,
			_summon,
			_ignored_summons,
		),
		"alternate blocked-anchor landing passes the formal validator",
	)

	_game._set_player_world_position(clear_screen)
	_summon.global_position = Vector2(5000.0, 5000.0)
	_summon.owner_teleport_pending = false
	var occupied_center: Vector2 = _game._canonical_screen_px_to_ground_gu(clear_screen)
	_fill_teleport_radius_with_real_summons(occupied_center)
	var no_landing_before := _summon.global_position
	_summon._physics_process(1.0 / 60.0)
	check(_summon.owner_teleport_pending, "fully occupied radius-8 landing defers")
	check(_summon.global_position == no_landing_before, "no-landing case preserves actual position")
	for blocker: SummonActor in _occupying_summons:
		blocker.queue_free()
	_occupying_summons.clear()
	await get_tree().process_frame

	check(_game.has_method("_register_pending_main_pet_arrival"), "GameRoot exposes pending-pet recovery seam")
	if not _game.has_method("_register_pending_main_pet_arrival"):
		await _cleanup_and_finish(1)
		return
	_game.call("_register_pending_main_pet_arrival", _summon)
	_game.call("_register_pending_main_pet_arrival", _summon)
	check(_game._pending_main_pet_arrivals.count(_summon) == 1, "pending registration is idempotent")
	_game.set_physics_process(true)
	await get_tree().physics_frame
	check(_summon.owner_teleport_pending, "same owner tile does not consume pending retry")
	var recovery_plan: Dictionary = _game._canonical_summon_spawn_plan(
		"taoist.summon_skeleton", _summon, _summon.pet_slot_index, _ignored_summons
	)
	check(bool(recovery_plan.get("valid", false)), "fixture recovery location is formally clear")
	var recovery_screen := _find_different_clear_owner_screen(clear_ground)
	check(recovery_screen.is_finite(), "recovery owner position uses a different formal ground tile")
	if not recovery_screen.is_finite():
		await _cleanup_and_finish(1)
		return
	_game._set_player_world_position(recovery_screen)
	await get_tree().physics_frame
	for _frame: int in range(30):
		if not _summon.owner_teleport_pending:
			break
		await get_tree().physics_frame
	check(not _summon.owner_teleport_pending, "pending summon landing recovers through GameRoot retry")
	check(
		_game._canonical_summon_position_is_valid(
			_game._canonical_screen_px_to_ground_gu(_summon.global_position),
			_summon.combat_radius_gu,
			_summon,
			_ignored_summons,
		),
		"recovered summon landing must pass the formal validator",
	)
	await _cleanup_and_finish(0 if _failures.is_empty() else 1)


func _find_clear_owner_with_blocked_formation_anchor() -> Vector2:
	var background: Node = _game.background
	var formal_profile: Dictionary = _game._resolve_projection_profile_for_map(
		_game.current_map_id
	)
	var source_size: Vector2i = formal_profile.get("source_size", Vector2i.ZERO)
	if not bool(formal_profile.get("success", false)) or source_size == Vector2i.ZERO:
		return Vector2.INF
	var radius_px: float = WorldSpatialRulesScript.actor_screen_radius_px_from_combat_radius_gu(
		_summon.combat_radius_gu
	)
	for y: int in range(0, source_size.y):
		for x: int in range(0, source_size.x):
			var screen: Vector2 = _game._canonical_ground_gu_to_screen_px(
				Vector2(float(x), float(y))
			)
			if background.is_environment_actor_blocked(screen, radius_px):
				continue
			_player.global_position = screen
			var anchor: Vector2 = _summon._owner_formation_anchor_screen_px()
			if background.is_environment_actor_blocked(anchor, radius_px):
				return screen
	return Vector2.INF


func _find_different_clear_owner_screen(previous_ground: Vector2) -> Vector2:
	var background: Node = _game.background
	var radius_px: float = WorldSpatialRulesScript.actor_screen_radius_px_from_combat_radius_gu(
		_summon.combat_radius_gu
	)
	var previous_tile := Vector2i(floori(previous_ground.x), floori(previous_ground.y))
	for delta_y: int in range(-12, 13):
		for delta_x: int in range(-12, 13):
			if delta_x == 0 and delta_y == 0:
				continue
			var candidate_ground := previous_ground + Vector2(float(delta_x), float(delta_y))
			var candidate_tile := Vector2i(floori(candidate_ground.x), floori(candidate_ground.y))
			if candidate_tile == previous_tile:
				continue
			var candidate_screen: Vector2 = _game._canonical_ground_gu_to_screen_px(candidate_ground)
			if background.is_environment_actor_blocked(candidate_screen, radius_px):
				continue
			_player.global_position = candidate_screen
			var candidate_plan: Dictionary = _game._canonical_summon_spawn_plan(
				"taoist.summon_skeleton", _summon, _summon.pet_slot_index, _ignored_summons
			)
			if not bool(candidate_plan.get("valid", false)):
				continue
			return candidate_screen
	return Vector2.INF


func _count_game_signal_hooks(emitter: Node, signal_name: StringName) -> int:
	var count := 0
	for connection: Dictionary in emitter.get_signal_connection_list(signal_name):
		var callback: Callable = connection.get("callable", Callable())
		if callback.get_object() == _game:
			count += 1
	return count


func check(passed: bool, label: String) -> bool:
	_proof.record(passed, label)
	if not passed:
		_failures.append(label)
	return passed


func _cleanup_and_finish(exit_code: int) -> void:
	_game.set_physics_process(false)
	for blocker: SummonActor in _occupying_summons:
		if is_instance_valid(blocker):
			blocker.queue_free()
	_occupying_summons.clear()
	if is_instance_valid(_summon):
		_summon.queue_free()
	if is_instance_valid(_game):
		_game.queue_free()
	await get_tree().process_frame
	_finish.call_deferred(exit_code)


func _finish(exit_code: int) -> void:
	var receipt_ok: bool = _proof.write_receipt(
		"summon_follow_landing_contract_20261010_test",
		_proof.records.size(),
		_failures.size(),
	)
	var final_pass: bool = exit_code == 0 and receipt_ok
	print("SUMMON_FOLLOW_LANDING_RECEIPT ", JSON.stringify({"failures": _failures, "receipt_ok": receipt_ok, "status": "PASS" if final_pass else "FAIL"}))
	print("SUMMON_FOLLOW_LANDING_CONTRACT_PASS" if final_pass else "SUMMON_FOLLOW_LANDING_CONTRACT_FAIL")
	get_tree().quit(0 if final_pass else 1)


func _fill_teleport_radius_with_real_summons(center_ground: Vector2) -> void:
	for y: int in range(-8, 9):
		for x: int in range(-8, 9):
			var blocker := SummonActor.new()
			blocker.setup(_player, "骷髅", 40, 3, "taoist.summon_skeleton", 40)
			blocker.configure_runtime_map_projection(
				_game.current_map_id,
				Callable(_game, "_canonical_ground_gu_to_screen_px"),
				Callable(_game, "_canonical_screen_px_to_ground_gu"),
			)
			_game.add_child(blocker)
			blocker.set_physics_process(false)
			blocker.global_position = _game._canonical_ground_gu_to_screen_px(
				center_ground + Vector2(float(x), float(y))
			)
			_occupying_summons.append(blocker)
