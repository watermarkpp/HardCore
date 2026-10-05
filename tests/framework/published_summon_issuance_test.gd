extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/summon_claim_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	var game := Root.new(); add_child(game)
	var initial_deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < initial_deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "actual initial mapped world reaches READY within original framework20seconds")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	await Fixture.wait_for_formal_world(self, game, "summon_issuance")
	var descriptors: Array[Dictionary] = []
	for index in range(3):
		var id: int = [126, 182, 160][index]
		descriptors.append({"id": id, "ground": Vector2(40.5 + index * 4.0, 13.5), "context": {
			"respawn_enabled": false, "spawn_slot_id": "test:issued:%d" % id}})
	var published: Array[EnemyActor] = await Fixture.publish_targets(self, game, descriptors, "summon_issuance")
	check(published.size() == 3 and published[0] != null, "one actual complete plan publishes canonical sources126/182/160")
	if published.size() != 3 or published[0] == null: game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	game.player.max_hp = 999999; game.player.current_hp = game.player.max_hp
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Vector2(38.5, 13.5)))
	var source: EnemyActor = published[0]
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	source.dormant = false; source.target = game.player
	game.enable_claim_probe()
	var bound: Dictionary = game.feature_world_capacity_bound()
	await _release(source)
	var queue: HCM30SummonQueue = game._hc_m30_get_summon_queue()
	await _drain(queue)
	check(queue._active("test:issued:126") == 1, "real original126 producer materializes its canonical127 child")
	check(game.claim_observations.size() == 1, "one original job ordinal reaches sole factory")
	for observation: Dictionary in game.claim_observations: _check_claim(observation)
	var old_child: EnemyActor
	if queue._active("test:issued:126") > 0: old_child = (queue._children["test:issued:126"].values()[0] as WeakRef).get_ref()
	game.claim_probe_mode = "death_and_cancel"
	await _release(source); await _drain(queue)
	check(game.claim_observations.size() == 2, "next original release gets exactly one new ordinal")
	if game.claim_observations.size() == 2:
		var observation: Dictionary = game.claim_observations[-1]
		_check_claim(observation)
		check(bool(observation.get("source_fatal", false)) and bool(observation.get("inflight_reserved", false)), "real source death and cancellation preserve the already-admitted in-flight slot")
	check(queue._active("test:issued:126") == 2 and queue._reserved.is_empty(), "accepted birth survives source-death callback and transfers reservation once")
	var position: Vector2 = source.get_meta("spawn_position")
	var context: Dictionary = source.get_meta("spawn_context").duplicate(true)
	var seconds: float = source.get_meta("respawn_seconds")
	source.queue_free(); await get_tree().process_frame
	var replacement: EnemyActor = game._spawn_enemy({"monster_id": 126}, position, false, seconds, context)
	check(replacement != null, "new source life uses original published base descriptor")
	game.claim_probe_mode = "normal"
	if replacement != null:
		replacement.set_physics_process(false); replacement.dormant = false; replacement.target = game.player
		for index in range(5): await _release(replacement); await _drain(queue)
	check(queue._active("test:issued:126") == 5 and queue._reserved.is_empty(), "new life shares five slots with surviving previous-life children")
	check(is_instance_valid(old_child) and old_child.current_hp > 0, "previous-life accepted child remains alive")
	check(game.feature_world_capacity_bound() == bound, "jobs, replacement and old-life children never grow frozen birth allowance")
	var additional: Array[EnemyActor] = [published[1], published[2]]
	for actor: EnemyActor in additional:
		actor.set_physics_process(false); actor.dormant = false; actor.target = game.player
	for index in range(20):
		await get_tree().physics_frame
		for actor: EnemyActor in additional:
			if actor.is_boss:
				actor._boss_health_stage = 5; actor.current_hp = 1
				actor._apply_health_stage_mechanics()
			else:
				actor._summon_cooldown = 0
				actor._update_behavior_summon(0); actor._update_behavior_summon(0.5)
	await _drain(queue)
	for actor: EnemyActor in additional:
		var slot := "test:issued:%d" % actor.monster_id
		var cap := 15 if actor.is_boss else 5
		check(queue._active(slot) == cap, "original20 decision frames preserve real source%d cap%d" % [actor.monster_id, cap])
		for child_ref: WeakRef in queue._children.get(slot, {}).values():
			var child: EnemyActor = child_ref.get_ref()
			var ids: Array = [156, 153, 150, 128] if actor.is_boss else [183]
			check(child.monster_id in ids and child.direct_spell_stats_valid and child.current_hp > 0, "newborn%d retains canonical identity and actual combat HP" % child.monster_id)
		check(int(queue._reserved.get(slot, 0)) == 0, "source%d completed births retire all reservations" % actor.monster_id)
	check(int(queue.snapshot().max_materializations_in_tick) <= 1 and int(queue.snapshot().max_probes_in_tick) <= 8, "original bounded landing and materialization quanta remain intact")
	print("PUBLISHED_SUMMON_TRACE ", JSON.stringify({"observations": game.claim_observations, "queue": queue.snapshot()}))
	game.queue_free(); await get_tree().process_frame; _finish()

func _release(source: EnemyActor) -> void:
	await get_tree().physics_frame
	source._summon_cooldown = 0
	source._update_behavior_summon(0)
	source._update_behavior_summon(0.5)

func _drain(queue: HCM30SummonQueue) -> void:
	for index in range(360):
		if queue._jobs.is_empty(): return
		await get_tree().physics_frame
	check(false, "original queue drains within original360 physics-frame bound")

func _check_claim(observation: Dictionary) -> void:
	check(bool(observation.get("copied_rejected", false)) and bool(observation.get("copy_unchanged", false)), "copied job cannot issue or change factory serial")
	check(bool(observation.get("reentrant_rejected", false)) and bool(observation.get("reentrant_unchanged", false)), "add_child reentry cannot reuse consumed ordinal")
	check(bool(observation.get("replay_rejected", false)) and bool(observation.get("replay_unchanged", false)), "returned original job cannot replay its ordinal")
	check(bool(observation.get("child_valid", false)) and bool(observation.get("job_not_in_actor", false)), "accepted child is real and actor metadata retains no original job capability")

func _finish() -> void:
	var ok := proof.write_receipt("published_summon_issuance_test", proof.records.size(), failures.size())
	print("PUBLISHED_SUMMON_ISSUANCE_%s checks=%d failures=%s" % ["PASS" if ok and failures.is_empty() else "FAIL", proof.records.size(), str(failures)])
	get_tree().quit(0 if ok and failures.is_empty() else 1)
