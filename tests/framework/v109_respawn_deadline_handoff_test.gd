extends Node

const Root := preload("res://scripts/game_root.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var game := Root.new()
	add_child(game)
	var ready_deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < ready_deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "formal Root reaches READY")
	if not game.gameplay_input_is_enabled():
		_finish(game)
		return
	game.set_process(false)
	var actor: EnemyActor = null
	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if candidate is EnemyActor and bool(candidate.get_meta("respawn_enabled", false)):
			actor = candidate as EnemyActor
			break
	check(actor != null, "actual published world has a respawn-enabled base actor")
	if actor == null:
		_finish(game)
		return
	var context: Dictionary = (actor.get_meta("spawn_context", {}) as Dictionary).duplicate(true)
	var monster := GameData.get_monster_by_id(int(actor.monster_data.get("monster_id", -1)))
	var spawn: Vector2 = actor.get_meta("spawn_position", actor.global_position)
	var configured := float(actor.get_meta("respawn_seconds", -1.0))
	var death := {
		"monster_id": int(monster.get("monster_id", -1)),
		"canonical_monster": monster,
		"spawn_context": context,
		"spawn_position": spawn,
		"origin_generation": game._zone_generation,
		"configured_respawn": configured,
		"respawn_enabled": true,
		"was_boss": bool(actor.get_meta("spawn_is_boss", false)),
	}
	# This exercises the actual preparation-to-scheduling owner handoff with
	# a real published descriptor. It does not claim a natural death/drop load.
	var preparation: Dictionary = game._prepare_queued_enemy_respawn(death, false)
	check(bool(preparation.get("valid", false)), "formal preparation accepts the published slot")
	if not bool(preparation.get("valid", false)):
		_finish(game)
		return
	death["respawn_preparation"] = preparation
	var base_seconds := float(preparation.wait_seconds)
	var due := float(preparation.world_entry.respawn_at_unix)
	check(base_seconds >= 300.0, "canonical respawn policy duration is preserved")
	var admitted: Dictionary = game._feature_target_bound.admit_base(
		int(monster.monster_id), spawn, base_seconds, preparation.spawn_context)
	check(bool(admitted.get("accepted", false)), "published birth authority accepts unchanged base policy")
	await get_tree().create_timer(0.35).timeout
	var before := game._respawn_wakeups.size()
	game._schedule_queued_enemy_respawn(death)
	check(game._respawn_wakeups.size() == before + 1, "handoff acquires one real SceneTreeTimer owner")
	var wakeup: SceneTreeTimer = null
	for raw: Variant in game._respawn_wakeups.values():
		wakeup = raw as SceneTreeTimer
	if wakeup != null:
		var remaining := maxf(0.0, due - Time.get_unix_time_from_system())
		check(wakeup.time_left < base_seconds - 0.20, "queue elapsed time is subtracted rather than restarted")
		check(absf(wakeup.time_left - remaining) < 0.10, "actual timer matches captured absolute deadline")
	check(float(preparation.spawn_context.respawn_base_seconds) == base_seconds,
		"canonical base duration remains the admission value")
	game._schedule_queued_enemy_respawn(death)
	check(game._respawn_wakeups.size() == before + 1, "repeat scheduling cannot duplicate the owner")
	game._cancel_respawn_wakeups()
	check(game._respawn_wakeups.is_empty(), "world retirement revokes timer ownership")
	print("V109_RESPAWN_DEADLINE_TRACE base=", base_seconds, " due=", due,
		" remaining=", wakeup.time_left if wakeup != null else -1.0)
	_finish(game)

func _finish(game: Node) -> void:
	game.queue_free()
	var valid := proof.write_receipt("v109_respawn_deadline_handoff_test", proof.records.size(), failures.size())
	print("V109_RESPAWN_DEADLINE_", "PASS" if valid and failures.is_empty() else "FAIL",
		" checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if valid and failures.is_empty() else 1)
