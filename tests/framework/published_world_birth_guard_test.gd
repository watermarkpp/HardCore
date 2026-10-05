extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/published_birth_probe_root.gd")
const Identity := preload("res://scripts/monster_identity.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var game := Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false)
	game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	var bound: Dictionary = game.feature_world_capacity_bound()
	check(bool(bound.get("sealed", false)) and bool(bound.get("proved", false)), "READY has a complete sealed published base plan")
	var position: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5))
	var serial: int = game._runtime_spawn_serial
	var count: int = game._active_enemy_cache.size()
	var timers: int = game._respawn_wakeups.size()
	var illegal: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(19), position, false, -1.0,
		{"respawn_enabled": false, "spawn_slot_id": "test:unpublished:19"})
	check(illegal == null, "new READY base slot has no qualification")
	check(game._runtime_spawn_serial == serial and game._active_enemy_cache.size() == count,
		"rejection precedes serial, allocation and registration")
	check(game._respawn_wakeups.size() == timers and game.feature_world_capacity_bound() == bound,
		"rejection preserves timers and the frozen proof")
	game._respawn_later(GameData.get_monster_by_id(19), position, false, 10.0, game._zone_generation,
		{"respawn_enabled": false, "spawn_slot_id": "test:unpublished:timer"})
	check(game._respawn_wakeups.size() == timers, "unpublished delayed birth rejects before creating or registering a real Timer")
	var known: EnemyActor = game._active_enemy_cache.values()[0]
	var known_position: Vector2 = known.get_meta("spawn_position")
	var known_seconds: float = known.get_meta("respawn_seconds")
	var known_context: Dictionary = known.get_meta("spawn_context").duplicate(true)
	game._respawn_later({"monster_id": known.monster_id}, known_position + Vector2(1, 0), known.is_boss,
		known_seconds, game._zone_generation, known_context)
	check(game._respawn_wakeups.size() == timers, "changed delayed base descriptor rejects before Timer ownership")
	game._respawn_later({"monster_id": known.monster_id}, known_position, known.is_boss,
		known_seconds, game._zone_generation - 1, known_context)
	check(game._respawn_wakeups.size() == timers, "retired-generation delayed request cannot register a new wakeup")
	if illegal != null: illegal.queue_free(); await get_tree().process_frame
	serial = game._runtime_spawn_serial
	var anonymous: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(19), position, false, -1.0, {"respawn_enabled": false})
	check(anonymous == null and game._runtime_spawn_serial == serial, "anonymous runtime slot cannot manufacture a birth")
	if anonymous != null: anonymous.queue_free(); await get_tree().process_frame
	serial = game._runtime_spawn_serial
	var fake_child: EnemyActor = game._hc_m30_materialize(GameData.get_monster_by_id(127), position,
		{"respawn_enabled": false, "summoner_spawn_slot": "test:unpublished:owner", "m30_source_instance_id": game.player.get_instance_id(), "m30_source_life": 1})
	check(fake_child == null and game._runtime_spawn_serial == serial, "summon labels without original queue issuance cannot grant a birth")
	if fake_child != null: fake_child.queue_free(); await get_tree().process_frame
	var coordinator: WorldBootstrapCoordinator = game._world_bootstrap_coordinator
	var planned: int = coordinator.planned_actors
	var failed: int = coordinator.failed_actors
	var duplicates: int = coordinator.duplicate_actors
	var queued: int = coordinator._actor_spawn_queue.size()
	var source_index: int = game._staged_actor_source_index
	check(not game._submit_staged_actor_descriptor("enemy", {"monster_id": 19}, "test:late:root"), "Root rejects new READY descriptor")
	check(not coordinator.submit_actor_descriptor({"actor_id": "test:late:coordinator", "actor_type": "enemy", "payload": {"monster_id": 19}}), "queue owner rejects new READY descriptor")
	check(game._staged_actor_source_index == source_index and coordinator.planned_actors == planned
		and coordinator.failed_actors == failed and coordinator.duplicate_actors == duplicates
		and coordinator._actor_spawn_queue.size() == queued, "descriptor rejection precedes every owned counter and queue change")
	game.queue_free(); await get_tree().process_frame
	_finish()

func _finish() -> void:
	var ok := proof.write_receipt("published_world_birth_guard_test", proof.records.size(), failures.size())
	print("PUBLISHED_WORLD_BIRTH_GUARD_%s checks=%d failures=%s" % ["PASS" if ok and failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if ok and failures.is_empty() else 1)
