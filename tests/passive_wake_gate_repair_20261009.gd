extends Node

const Enemy := preload("res://scripts/enemy.gd")
const Summon := preload("res://scripts/summon_actor.gd")

var _game: Node
var _actor: EnemyActor
var _player: PlayerCharacter
var _summon: SummonActor
var _failures: Array[String] = []
var _evidence: Dictionary = {"status": "NOT_RUN", "cases": {}}
var _valid_ground := Vector2.INF
var _blocked_ground := Vector2.INF

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _ready() -> void:
	await get_tree().process_frame
	await _bootstrap()
	if _game != null and _actor != null:
		await _run_gate_contract()
	_finish()

func _bootstrap() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	for _frame: int in 1200:
		await get_tree().process_frame
		if not _game._world_bootstrap_in_progress and not _game._map_transition_in_progress:
			break
	if not is_instance_valid(_game.player) or not _game.gameplay_input_is_enabled():
		_failures.append("formal_bootstrap_incomplete")
		return
	_player = _game.player as PlayerCharacter
	_game.set_process(false)
	_game.set_physics_process(false)
	_player.set_physics_process(false)
	for raw: Variant in _game._active_enemy_cache.values():
		if raw is EnemyActor:
			var candidate := raw as EnemyActor
			if candidate._source176_ordinary_melee() and not candidate.is_boss and candidate.passive_acquisition_extent_gu() > 0.0:
				_actor = candidate
				break
	if _actor == null:
		_failures.append("ordinary_actor_missing")
		return
	_actor.set_physics_process(false)
	_actor.target = null
	_actor._threat_table.clear()
	_actor._hc_damage_dirty = false
	_actor._clear_passive_wake()
	var anchor: Vector2 = _game._canonical_screen_px_to_ground_gu(_actor.global_position)
	for radius: float in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			var point: Vector2 = anchor + axis * radius
			_player.global_position = _game._canonical_ground_gu_to_screen_px(point)
			if not _actor._point_inside_safe_zone(_player.global_position) and _actor._initial_acquisition_static_los_clear(_player):
				_valid_ground = point
				break
		if _valid_ground.is_finite():
			break
	if not _valid_ground.is_finite():
		_failures.append("valid_clear_probe_missing")
		return
	_player.global_position = _game._canonical_ground_gu_to_screen_px(_valid_ground)
	for radius: float in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
		for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized()]:
			var point: Vector2 = anchor + axis * radius
			_player.global_position = _game._canonical_ground_gu_to_screen_px(point)
			if _actor._initial_acquisition_contains_ground_delta_gu(_actor._ground_delta_gu_between_screen_positions(_actor.global_position, _player.global_position)) and not _actor._initial_acquisition_static_los_clear(_player):
				_blocked_ground = point
				break
		if _blocked_ground.is_finite():
			break
	_player.global_position = _game._canonical_ground_gu_to_screen_px(_valid_ground)
func _reset_actor() -> void:
	_actor.target = null
	_actor._threat_table.clear()
	_actor._hc_damage_dirty = false
	_actor._clear_passive_wake()
	_actor.combat_enabled = true
	_actor.runtime_map_id = _game.current_map_id
	_actor._enter_background_deep_sleep(true)
	_actor.set_physics_process(false)
	_player._dead = false
	_player.current_hp = maxi(1, _player.current_hp)
	_player.global_position = _game._canonical_ground_gu_to_screen_px(_valid_ground)

func _request(expected_map: int = -1, expected_generation: int = -1) -> bool:
	var map_id: int = _game.current_map_id if expected_map < 0 else expected_map
	var generation: int = _game._zone_generation if expected_generation < 0 else expected_generation
	return _actor.request_passive_player_wakeup(_player, map_id, generation)

func _run_gate_contract() -> void:
	_reset_actor()
	_check(_request(), "valid player wake is accepted")
	_check(_actor.target == _player, "valid player target is assigned synchronously")
	_check(not _actor._background_deep_sleeping and _actor.is_physics_processing(), "valid target wake leaves deep sleep and restores physics processing")
	_evidence["valid_player"] = {"accepted": true, "target": _actor.target == _player}

	_reset_actor()
	_check(not _request(_game.current_map_id + 1), "map mismatch is rejected")
	_check(_actor.target == null and not _actor.is_physics_processing(), "map mismatch leaves actor unchanged")
	_reset_actor()
	_check(not _request(_game._zone_generation + 1), "generation mismatch is rejected")
	_check(_actor.target == null and not _actor.is_physics_processing(), "generation mismatch leaves actor unchanged")

	_reset_actor()
	_player._dead = true
	_player.current_hp = 0
	_check(not _request(), "dead player is rejected")
	_check(_actor.target == null and not _actor.is_physics_processing(), "dead player leaves actor unchanged")
	_reset_actor()
	_actor.combat_enabled = false
	_check(not _request(), "combat-disabled actor rejects wake")
	_check(_actor.target == null and not _actor.is_physics_processing(), "combat-disabled actor leaves target and physics unchanged")

	_reset_actor()
	_player.global_position = _game._canonical_ground_gu_to_screen_px(_valid_ground + Vector2(100.0, 100.0))
	_check(not _request(), "out-of-range player is rejected")
	_check(_actor.target == null and not _actor.is_physics_processing(), "out-of-range rejection leaves actor unchanged")

	if _blocked_ground.is_finite():
		_reset_actor()
		_player.global_position = _game._canonical_ground_gu_to_screen_px(_blocked_ground)
		_check(not _request(), "straight-line wall LOS is rejected")
		_check(_actor.target == null and not _actor.is_physics_processing(), "wall rejection leaves actor unchanged")
	else:
		_failures.append("wall_los_probe_missing")

	# Formal safe-zone records are compiled geometry, not Rect2 metadata.
	# Exercise the Bich home directly rather than gating this case on an old
	# metadata probe that cannot find any compiled safe zone.
	if _game.current_map_id == GameData.service_home_runtime_map_id(false):
		_reset_actor()
		var saved_actor_position: Vector2 = _actor.global_position
		var saved_player_position: Vector2 = _player.global_position
		var home: Dictionary = _game._resolve_bich_home()
		var home_position: Vector2 = home.get("position_px", Vector2.INF) as Vector2
		if bool(home.get("valid", false)) and home_position.is_finite():
			_actor.global_position = home_position
			_player.global_position = home_position
			_check(_actor._point_inside_safe_zone(_player.global_position), "formal Bich home is recognized as safe")
			_check(not _request(), "formal Bich home candidate is rejected")
			_check(_actor.target == null and not _actor.is_physics_processing(), "safe-zone rejection leaves actor unchanged")
		else:
			_failures.append("formal_bich_home_probe_missing")
		_actor.global_position = saved_actor_position
		_player.global_position = saved_player_position
	else:
		_failures.append("formal_bich_home_map_missing")

	_reset_actor()
	_player.global_position = _game._canonical_ground_gu_to_screen_px(_valid_ground)
	var neighbor: EnemyActor = null
	var neighbor_original_position := Vector2.INF
	for raw_neighbor: Variant in _game._active_enemy_cache.values():
		if raw_neighbor is EnemyActor and raw_neighbor != _actor:
			neighbor = raw_neighbor as EnemyActor
			neighbor_original_position = neighbor.global_position
			break
	if neighbor != null:
		neighbor.set_physics_process(false)
		neighbor.global_position = _game._canonical_ground_gu_to_screen_px(
			(_game._canonical_screen_px_to_ground_gu(_actor.global_position) + _valid_ground) * 0.5
		)
		_check(_request(), "same-map Enemy neighbor does not block static LOS")
		_check(_actor.target == _player, "same-map Enemy neighbor leaves valid target assignment intact")
		neighbor.global_position = neighbor_original_position
	else:
		_failures.append("neighbor_enemy_probe_missing")

	_reset_actor()
	_player.global_position = _game._canonical_ground_gu_to_screen_px(_valid_ground)
	var damage_summon := _make_visible_summon()
	_actor.target = _player
	var hp_before := _actor.current_hp
	_actor.take_damage(1, damage_summon, {"source_class": "direct", "damage_channel": "physical"}, {"release_id": "existing_target_preserved"})
	_check(_actor.current_hp == hp_before - 1 and _actor.target == _player, "positive damage preserves an existing target")
	damage_summon.free()

	_reset_actor()
	var zero_hp := _actor.current_hp
	_actor.take_damage(0, _player, {"source_class": "direct", "damage_channel": "physical"}, {"release_id": "zero_damage_no_wake"})
	_check(_actor.current_hp == zero_hp and _actor.target == null, "zero damage does not acquire a target")

	_reset_actor()
	_actor.runtime_map_id = _game.current_map_id + 1
	_actor.take_damage(1, _player, {"source_class": "direct", "damage_channel": "physical"}, {"release_id": "cross_map_no_wake"})
	_check(_actor.target == null, "cross-map attacker does not acquire a target")

	_test_summon_visibility()

func _test_summon_visibility() -> void:
	_reset_actor()
	_summon = _make_visible_summon()
	_summon.global_position = _game._canonical_ground_gu_to_screen_px(_valid_ground)
	_game._apply_friendly_stealth_to_actor(_summon, 60.0, "buff.taoist.mass_invisibility")
	_check(_summon.is_stealthed(), "summon stealth setup is active")
	_check(not _actor.request_passive_target_wakeup(_summon, _game.current_map_id, _game._zone_generation), "hidden summon is rejected")
	_check(_actor.target == null and not _actor.is_physics_processing(), "hidden summon rejection leaves actor unchanged")
	_summon._update_support_buff_timers(61.0)
	_check(not _summon.is_stealthed(), "summon visibility expiry follows existing policy")
	_check(_actor.request_passive_target_wakeup(_summon, _game.current_map_id, _game._zone_generation), "visible summon is accepted")
	_check(_actor.target == _summon, "visible summon is assigned synchronously")
	_summon.free()

func _make_visible_summon() -> SummonActor:
	var summon := SummonActor.new()
	summon.setup(_player, "skeleton", 40, 3, "taoist.summon_skeleton", 35)
	summon.configure_runtime_map_projection(_game.current_map_id, Callable(_game, "_canonical_ground_gu_to_screen_px"), Callable(_game, "_canonical_screen_px_to_ground_gu"))
	summon.global_position = _game._canonical_ground_gu_to_screen_px(_valid_ground)
	_game.add_child(summon)
	summon.set_physics_process(false)
	_game._register_passive_wake_emitter(summon)
	return summon

func _finish() -> void:
	_evidence["status"] = "PASS" if _failures.is_empty() else "FAIL"
	_evidence["failures"] = _failures
	var out := FileAccess.open("res://outputs/test_logs/passive_wake_gate_repair_20261009.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(_evidence, "\t"))
	if _failures.is_empty():
		print("HC_PASSIVE_WAKE_GATE_REPAIR_20261009_PASS")
	else:
		for failure: String in _failures:
			print("HC_TEST_FAIL ", failure)
	if is_instance_valid(_game):
		_game.queue_free()
		await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)
