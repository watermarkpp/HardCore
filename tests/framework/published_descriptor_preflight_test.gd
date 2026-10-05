extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/published_birth_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var proof := Proof.new()
var failures: Array[String] = []
var cold_records: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _queue_state(game: Node) -> Dictionary:
	var coordinator: WorldBootstrapCoordinator = game._world_bootstrap_coordinator
	return {"planned": coordinator.planned_actors, "failed": coordinator.failed_actors,
		"duplicates": coordinator.duplicate_actors, "queued": coordinator._actor_spawn_queue.size(),
		"ids": coordinator._planned_actor_ids.duplicate(true), "source_index": game._staged_actor_source_index,
		"bound": game.feature_world_capacity_bound()}

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	var game := Root.new(); add_child(game)
	var initial_deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < initial_deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual initial mapped world reaches READY within original framework20seconds")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	await Fixture.wait_for_formal_world(self, game, "descriptor_preflight")
	var generation: int = game._zone_generation
	var started: bool = game._begin_map_transition(func():
		game._load_zone(game.current_zone, true, game.current_map_data)
		var coordinator: WorldBootstrapCoordinator = game._world_bootstrap_coordinator
		var position: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5))
		var payload := {"monster_id": 19.5, "position": position, "is_boss": false,
			"respawn_seconds": -1.0, "spawn_context": {"respawn_enabled": false, "spawn_slot_id": "test:preflight:fraction"}}
		var before := _queue_state(game)
		var accepted: bool = game._submit_staged_actor_descriptor("enemy", payload, "test:preflight:fraction")
		cold_records.append({"ok": not accepted and _queue_state(game) == before,
			"label": "fractional raw ID rejects before Bound/source-index/queue/counters"})
		payload = {"monster_id": 19, "position": position, "is_boss": false, "respawn_seconds": -1.0,
			"spawn_context": {"respawn_enabled": false, "spawn_slot_id": "test:preflight:uncompiled"}}
		before = _queue_state(game)
		accepted = coordinator.submit_actor_descriptor({"actor_id": "test:preflight:uncompiled", "actor_type": "enemy", "payload": payload})
		cold_records.append({"ok": not accepted and _queue_state(game) == before,
			"label": "direct open-collection descriptor cannot bypass compiled base closure"})
		payload.spawn_context.spawn_slot_id = "test:preflight:accepted"
		accepted = game._submit_staged_actor_descriptor("enemy", payload, "test:preflight:shared-id")
		cold_records.append({"ok": accepted, "label": "one valid cold descriptor joins original complete plan"})
		before = _queue_state(game)
		accepted = coordinator.submit_actor_descriptor({"actor_id": "test:preflight:duplicate-slot", "actor_type": "enemy", "payload": payload})
		cold_records.append({"ok": not accepted and _queue_state(game) == before,
			"label": "exact compiled slot cannot join original queue twice under different actor IDs"})
		before = _queue_state(game)
		var duplicate := payload.duplicate(true)
		duplicate.spawn_context.spawn_slot_id = "test:preflight:rejected"
		accepted = game._submit_staged_actor_descriptor("enemy", duplicate, "test:preflight:shared-id")
		cold_records.append({"ok": not accepted and _queue_state(game) == before,
			"label": "distinct slot with duplicate actor ID rejects before compiled allowance and counters"})
		before = _queue_state(game)
		accepted = coordinator.submit_actor_descriptor({"actor_id": "", "actor_type": "enemy", "payload": payload})
		cold_records.append({"ok": not accepted and _queue_state(game) == before,
			"label": "missing actor ID rejects before all queue counters"})
	, game.current_map_id)
	check(started, "original transition owner accepts actual republication")
	var deadline := Time.get_ticks_msec() + 5000
	while game._map_transition_in_progress and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled() and game._zone_generation > generation, "actual full plan reaches READY after rejected foreign descriptors")
	for record: Dictionary in cold_records: check(bool(record.ok), str(record.label))
	check(cold_records.size() == 6, "all cold admission counterexamples execute inside actual collection")
	var bound: Dictionary = game.feature_world_capacity_bound()
	var serial: int = game._runtime_spawn_serial
	var late: EnemyActor = game._spawn_enemy({"monster_id": 19}, game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5)), false, -1.0,
		{"respawn_enabled": false, "spawn_slot_id": "test:preflight:rejected"})
	check(late == null and game._runtime_spawn_serial == serial and game.feature_world_capacity_bound() == bound,
		"rejected cold descriptor never grants a later READY birth")
	game.queue_free(); await get_tree().process_frame; _finish()

func _finish() -> void:
	var ok := proof.write_receipt("published_descriptor_preflight_test", proof.records.size(), failures.size())
	print("PUBLISHED_DESCRIPTOR_PREFLIGHT_%s checks=%d failures=%s" % ["PASS" if ok and failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if ok and failures.is_empty() else 1)
