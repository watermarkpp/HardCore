extends Node

const Enemy := preload("res://scripts/enemy.gd")
const Summon := preload("res://scripts/summon_actor.gd")

var _game: Node
var _actor: EnemyActor
var _player: PlayerCharacter
var _failures: Array[String] = []
var _evidence: Dictionary = {"status": "NOT_RUN", "cases": {}}
var _valid_ground := Vector2.INF

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _ready() -> void:
	await get_tree().process_frame
	await _bootstrap()
	if _actor != null:
		_run_stale_target_contract()
	await _finish()

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
			var candidate: EnemyActor = raw as EnemyActor
			if candidate._source176_ordinary_melee() and not candidate.is_boss and candidate.passive_acquisition_extent_gu() > 0.0:
				_actor = candidate
				break
	if _actor == null:
		_failures.append("ordinary_actor_missing")
		return
	_actor.set_physics_process(false)
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

func _reset_actor() -> void:
	_actor._attack_action_active = false
	_actor._pending_attack_time = -1.0
	_actor._pending_attack_target = null
	_actor.target = null
	_actor._threat_table.clear()
	_actor._hc_damage_dirty = false
	_actor._clear_passive_wake()
	_actor.combat_enabled = true
	_actor.runtime_map_id = _game.current_map_id
	_actor.set_physics_process(false)
	_player._dead = false
	_player.current_hp = maxi(1, _player.current_hp)
	_player.global_position = _game._canonical_ground_gu_to_screen_px(_valid_ground)

func _make_summon() -> SummonActor:
	var summon: SummonActor = Summon.new()
	summon.setup(_player, "skeleton", 40, 3, "taoist.summon_skeleton", 35)
	summon.configure_runtime_map_projection(_game.current_map_id, Callable(_game, "_canonical_ground_gu_to_screen_px"), Callable(_game, "_canonical_screen_px_to_ground_gu"))
	summon.global_position = _game._canonical_ground_gu_to_screen_px(_valid_ground)
	_game.add_child(summon)
	summon.set_physics_process(false)
	return summon

func _run_stale_target_contract() -> void:
	_reset_actor()
	var stale: SummonActor = _make_summon()
	stale.current_hp = 0
	_actor.target = stale
	_check(is_instance_valid(_actor.target), "stale target remains a live Node reference before repair")
	_check(_actor.request_passive_player_wakeup(_player, _game.current_map_id, _game._zone_generation), "passive wake repairs an ineligible stale target")
	_check(_actor.target == _player, "stale target is replaced by the formally valid player")
	_evidence["stale_passive_target"] = {"repaired": _actor.target == _player}
	stale.free()

	var schema_parent: Node2D = Node2D.new()
	var schema_player: PlayerCharacter = PlayerCharacter.new()
	schema_parent.add_child(schema_player)
	_check(
		not _actor._passive_target_identity_valid(schema_player, _game.current_map_id, _game._zone_generation),
		"Player candidate with owner missing map/generation schema is rejected without coercion",
	)
	schema_parent.free()
	var orphan_owner := PlayerCharacter.new()
	var orphan_summon := Summon.new()
	orphan_summon.runtime_map_id = _game.current_map_id
	orphan_summon.owner_player = orphan_owner
	orphan_owner.free()
	_check(
		not _actor._passive_target_identity_valid(orphan_summon, _game.current_map_id, _game._zone_generation),
		"Summon whose owner was freed is rejected without dereferencing it",
	)
	orphan_summon.free()

	_reset_actor()
	var valid_summon: SummonActor = _make_summon()
	_actor.target = valid_summon
	_check(not _actor.request_passive_player_wakeup(_player, _game.current_map_id, _game._zone_generation), "valid Summon target is not replaced by a new Player wake")
	_check(_actor.target == valid_summon, "valid Summon target remains authoritative")
	valid_summon.free()

	_reset_actor()
	var old_map_target: SummonActor = _make_summon()
	old_map_target.runtime_map_id = _game.current_map_id + 1
	_actor.target = old_map_target
	_check(_actor.request_passive_player_wakeup(_player, _game.current_map_id, _game._zone_generation), "old-map target is retired before valid wake")
	_check(_actor.target == _player, "old-map target does not block valid Player activation")
	old_map_target.free()

	_reset_actor()
	var committed_stale: SummonActor = _make_summon()
	committed_stale.current_hp = 0
	_actor.target = committed_stale
	_actor._attack_action_active = true
	_check(not _actor.request_passive_player_wakeup(_player, _game.current_map_id, _game._zone_generation), "active committed attack blocks stale-target replacement")
	_check(_actor.target == committed_stale, "committed attack retains its original target")
	_actor._attack_action_active = false
	committed_stale.free()

	_reset_actor()
	var damage_stale: SummonActor = _make_summon()
	damage_stale.current_hp = 0
	_actor.target = damage_stale
	_actor.take_damage(1, _player, {"source_class": "direct", "damage_channel": "physical"}, {"release_id": "stale_damage_repair"})
	_check(_actor.target == _player, "positive damage repairs stale target to the legal attacker")
	_check(_actor._hc_damage_dirty, "stale-target damage still preserves immediate damage dirty state")
	damage_stale.free()

	_reset_actor()
	_actor.target = _player
	_check(not _actor.request_passive_player_wakeup(_player, _game.current_map_id, _game._zone_generation), "valid existing target is never redundantly replaced")
	_check(_actor.target == _player, "valid existing target remains authoritative")

func _finish() -> void:
	_evidence["status"] = "PASS" if _failures.is_empty() else "FAIL"
	_evidence["failures"] = _failures
	var out := FileAccess.open("res://outputs/test_logs/passive_wake_stale_target_repair_20261009.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(_evidence, "\t"))
	if is_instance_valid(_game):
		_game.queue_free()
		await get_tree().process_frame
	if _failures.is_empty():
		print("HC_PASSIVE_WAKE_STALE_TARGET_REPAIR_20261009_PASS")
	else:
		for failure: String in _failures:
			print("HC_TEST_FAIL ", failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
