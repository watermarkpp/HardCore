extends Node

const AudioServiceScript := preload("res://scripts/audio_runtime_service.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")


func _ready() -> void:
	_run.call_deferred()


func _make_enemy(monster_id: int, index: int) -> EnemyActor:
	var enemy := EnemyScript.new()
	enemy.name = "AudioFrontierEnemy_%d" % index
	enemy.monster_id = monster_id
	enemy.monster_data = {"monster_id": monster_id}
	enemy.combat_body_profile = MonsterIdentityScript.body_profile(monster_id)
	enemy.max_hp = 100
	enemy.current_hp = 100
	enemy.global_position = Vector2(32.0 + float(index), 32.0)
	add_child(enemy)
	await get_tree().process_frame
	enemy.set_physics_process(false)
	return enemy


func _check(proof: Variant, condition: bool, label: String) -> void:
	proof.record(condition, label)
	if not condition:
		push_error(label)


func _run() -> void:
	var service := AudioServiceScript.new()
	add_child(service)
	await get_tree().process_frame
	service.set_clock_for_test(1000)
	service.reset_metrics_for_test(true)
	var proof := Proof.new()
	var live_enemy := await _make_enemy(21, 0)
	_check(proof, live_enemy._audio_service() == service, "real EnemyActor resolves shared audio service")
	var live_context: Dictionary = live_enemy._audio_context("attack_start")
	live_context["release_id"] = "attack:1"
	var first := service.play_monster_event(21, "attack_start", live_context)
	_check(proof, first.get("status", "") == "played", "real EnemyActor attack context must play")
	service.stop_all_events("frontier_step")
	var duplicate := service.play_monster_event(21, "attack_start", live_context)
	_check(proof, duplicate.get("status", "") == "duplicate_owner_release", "same live EnemyActor release must reject")
	service.stop_all_events("frontier_step")
	live_context["release_id"] = "attack:2"
	service.set_clock_for_test(2001)
	var second := service.play_monster_event(21, "attack_start", live_context)
	_check(proof, second.get("status", "") == "played", "new live EnemyActor release must play")
	live_context["release_id"] = "attack:1"
	service.stop_all_events("frontier_step")
	var replay_old := service.play_monster_event(21, "attack_start", live_context)
	_check(proof, replay_old.get("status", "") == "duplicate_owner_release", "old live EnemyActor receipt must reject")
	service.stop_all_events("frontier_step")
	var alias_context := live_context.duplicate(true)
	alias_context["audio_owner_key"] = "monster:21:alias"
	var alias_result := service.play_monster_event(21, "attack_start", alias_context)
	_check(proof, alias_result.get("status", "") == "stale_monster_owner", "owner alias must reject")
	var wrong_life_context := live_context.duplicate(true)
	wrong_life_context["source_life"] = int(wrong_life_context.get("source_life", 0)) + 1
	var wrong_life_result := service.play_monster_event(21, "attack_start", wrong_life_context)
	_check(proof, wrong_life_result.get("status", "") == "stale_monster_owner", "wrong owner life must reject")
	service.stop_all_events("frontier_step")

	var retired_context := live_context.duplicate(true)
	live_enemy.queue_free()
	await live_enemy.tree_exited
	var retired_result := service.play_monster_event(21, "attack_start", retired_context)
	_check(proof, retired_result.get("status", "") == "stale_monster_owner", "retired EnemyActor context must reject")
	var after_retire: Dictionary = service.state_snapshot()
	_check(proof, int(after_retire.get("monster_audio_live_owner_count", -1)) == 0, "retired EnemyActor must release live owner state")

	for owner_index in range(1, 21):
		var owner_enemy := await _make_enemy(21, owner_index)
		var owner_context: Dictionary = owner_enemy._audio_context("attack_start")
		owner_context["release_id"] = "attack:1"
		service.set_clock_for_test(3000 + owner_index * 1001)
		var owner_result := service.play_monster_event(21, "attack_start", owner_context)
		_check(proof, owner_result.get("status", "") == "played", "owner %d first release must play" % owner_index)
		service.stop_all_events("frontier_step")
		owner_enemy.queue_free()
		await owner_enemy.tree_exited
	var retired_many: Dictionary = service.state_snapshot()
	_check(proof, int(retired_many.get("monster_audio_live_owner_count", -1)) == 0, "retired owners must not accumulate")

	# Synthetic/editor callers without enemy identity remain on the compatibility
	# exact-key path; they are not silently reclassified as production owners.
	service.set_clock_for_test(25000)
	var uuid_first := service.play_monster_event(
		21,
		"attack_start",
		{"audio_owner_key": "synthetic-owner", "release_id": "uuid:one"},
	)
	_check(proof, uuid_first.get("status", "") == "played", "synthetic compatibility event must play")
	service.stop_all_events("frontier_step")
	var uuid_duplicate := service.play_monster_event(
		21,
		"attack_start",
		{"audio_owner_key": "synthetic-owner", "release_id": "uuid:one"},
	)
	_check(proof, uuid_duplicate.get("status", "") == "duplicate_owner_release", "synthetic exact-key replay must reject")
	service.stop_all_events("frontier_step")

	var frame_enemy := await _make_enemy(24, 100)
	var frame_context: Dictionary = frame_enemy._audio_context("attack_frame")
	frame_context["release_id"] = "attack:1"
	service.set_clock_for_test(26000)
	var frame_first := service.play_monster_event(24, "attack_frame", frame_context)
	_check(proof, frame_first.get("status", "") == "played", "same release frame event is independently admissible")
	service.stop_all_events("frontier_step")
	var frame_duplicate := service.play_monster_event(24, "attack_frame", frame_context)
	_check(proof, frame_duplicate.get("status", "") == "duplicate_owner_release", "same frame event must be rejected")
	frame_enemy.queue_free()
	await frame_enemy.tree_exited

	var serial_enemy := await _make_enemy(21, 101)
	var serial_context: Dictionary = serial_enemy._audio_context("attack_start")
	for serial in range(1, 501):
		service.stop_all_events("frontier_step")
		serial_context["release_id"] = "attack:%d" % serial
		service.set_clock_for_test(27000 + serial * 1001)
		var result := service.play_monster_event(21, "attack_start", serial_context)
		_check(proof, result.get("status", "") == "played", "new serial %d must play at authored cadence" % serial)
	var snapshot: Dictionary = service.state_snapshot()
	_check(proof, int(snapshot.get("monster_attack_release_frontier_count", -1)) == 1, "one frontier per live owner/event is required")
	_check(proof, int(snapshot.get("owner_release_exact_count", -1)) == 1, "only non-monotonic synthetic UUIDs use the exact-key ledger")
	serial_enemy.queue_free()
	await serial_enemy.tree_exited
	var after_many: Dictionary = service.state_snapshot()
	_check(proof, int(after_many.get("monster_audio_live_owner_count", -1)) == 0, "retired serial owner must release live owner state")
	_check(proof, int(after_many.get("monster_attack_release_frontier_count", -1)) == 0, "retired serial owner must release its frontier")

	service.stop_all_audio("frontier_exit")
	var cleared: Dictionary = service.state_snapshot()
	_check(proof, int(cleared.get("monster_attack_release_frontier_count", -1)) == 0, "world stop clears attack frontiers")
	_check(proof, frame_first.get("status", "") == "played", "independent attack frame frontier")
	_check(proof, frame_duplicate.get("status", "") == "duplicate_owner_release", "duplicate attack frame rejects")
	_check(proof, int(snapshot.get("monster_attack_release_frontier_count", -1)) == 1, "one frontier per live owner/event")
	_check(proof, int(snapshot.get("owner_release_exact_count", -1)) == 1, "only synthetic UUID uses exact ledger")
	_check(proof, int(after_many.get("monster_attack_release_frontier_count", -1)) == 0, "retired serial owner releases frontier")
	_check(proof, int(cleared.get("monster_attack_release_frontier_count", -1)) == 0, "world stop clears attack frontiers")
	var failures := 0
	for record: Dictionary in proof.records:
		if not bool(record.get("passed", false)):
			failures += 1
	var receipt_ok: bool = proof.write_receipt(
		"audio_release_frontier_contract_20261010_test",
		proof.records.size(),
		failures,
	)
	if not receipt_ok:
		push_error("frontier receipt must be written")
	print("AUDIO_RELEASE_FRONTIER_CONTRACT_%s" % ("PASS" if receipt_ok and failures == 0 else "FAIL"))
	get_tree().quit(0 if receipt_ok and failures == 0 else 1)
