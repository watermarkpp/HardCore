extends Node


class AudioProbe extends Node:
	var calls: Array[Dictionary] = []
	var prompt_status := "played"
	var prompt_request_count := 0

	func _ready() -> void:
		add_to_group(&"audio_runtime_service")

	func play_monster_event(
		monster_id: int,
		semantic_event: String,
		context: Dictionary = {},
	) -> Dictionary:
		calls.append({
			"monster_id": monster_id,
			"semantic_event": semantic_event,
			"context": context.duplicate(true),
		})
		return {"status": "played"}

	func play_monster_combat_prompt(
		monster_id: int,
		audio_owner_key: String,
		context: Dictionary = {},
	) -> Dictionary:
		prompt_request_count += 1
		calls.append({
			"monster_id": monster_id,
			"semantic_event": "combat_prompt",
			"audio_owner_key": audio_owner_key,
			"context": context.duplicate(true),
		})
		return {"status": prompt_status}

	func end_monster_combat_session(audio_owner_key: String, reason := "") -> Dictionary:
		calls.append({
			"semantic_event": "combat_session_end",
			"audio_owner_key": audio_owner_key,
			"reason": reason,
		})
		return {"status": "ended"}


func _ready() -> void:
	_run.call_deferred()


func _count(probe: AudioProbe, semantic_event: String) -> int:
	var result := 0
	for call: Dictionary in probe.calls:
		if str(call.get("semantic_event", "")) == semantic_event:
			result += 1
	return result


func _assert_rejected_entry_is_one_shot(
	probe: AudioProbe,
	rejection_status: String,
	case_name: String,
) -> void:
	probe.prompt_status = rejection_status
	var request_count_before := probe.prompt_request_count
	var actor := EnemyActor.new()
	actor.name = "RejectedEntry_%s" % case_name
	actor.monster_id = 21
	actor.monster_data = {"monster_id": 21}
	actor.max_hp = 100
	actor.current_hp = 100
	actor.global_position = Vector2(48.0, 48.0)
	add_child(actor)
	var target := Node2D.new()
	target.name = "RejectedEntryTarget_%s" % case_name
	target.global_position = Vector2(64.0, 48.0)
	add_child(target)
	await get_tree().process_frame
	actor.target = target
	await get_tree().process_frame
	assert(
		probe.prompt_request_count == request_count_before + 1,
		"%s entry must issue one service request" % case_name,
	)
	for _tick in range(120):
		actor._audio_try_enter_combat_session()
	assert(
		probe.prompt_request_count == request_count_before + 1,
		"%s rejection must not retry for 120 ticks" % case_name,
	)
	actor._audio_end_combat_session("explicit_disengage")
	actor.queue_free()
	target.queue_free()


func _run() -> void:
	EnemyActor.set_audio_service_cache_clock_for_test(1000)
	var lookup_before_missing := EnemyActor.audio_service_lookup_count_for_test()
	var enemy := EnemyActor.new()
	enemy.name = "MonsterAudioHookFixture"
	enemy.monster_id = 21
	enemy.monster_data = {"monster_id": 21}
	enemy.display_name = "测试怪物"
	enemy.max_hp = 100
	enemy.current_hp = 100
	enemy.global_position = Vector2(32.0, 32.0)
	add_child(enemy)
	await get_tree().process_frame
	var target := Node2D.new()
	target.name = "CombatTarget"
	add_child(target)
	await get_tree().process_frame
	enemy.target = target
	# Deterministic fixture window: the bare Node2D target's liveness competes
	# with boot-time async map registration inside the enemy's per-tick target
	# policy, and the manual cache-clock choreography below must not race a
	# physics-tick entry attempt. Freeze AI between the manual sections; the
	# existing set_physics_process(true) at the attack section re-enables it.
	enemy.set_physics_process(false)

	# The target edge is a real gameplay entry even when the service is absent.
	# Installing a service inside the one-second negative window must not cause a
	# retry: an audio rejection is not evidence that combat did not begin.
	assert(
		EnemyActor.audio_service_lookup_count_for_test() == lookup_before_missing + 1,
		"first missing service must perform one lookup",
	)
	var probe := AudioProbe.new()
	add_child(probe)
	await get_tree().process_frame
	enemy._audio_try_enter_combat_session()
	assert(probe.calls.is_empty(), "rejected entry must not retry within the same session")
	enemy._audio_end_combat_session("explicit_disengage")
	EnemyActor.set_audio_service_cache_clock_for_test(2000)
	# Physics must be processing for the audio listenability gate to accept the
	# manual one-shot combat entry below. The entry sequence itself stays
	# synchronous, so no physics tick can interleave and consume the edge.
	enemy.set_physics_process(true)
	enemy._audio_try_enter_combat_session()

	# Combat entry is one-shot and uses the runtime integer ID, not display text.
	enemy._audio_try_enter_combat_session()
	enemy._audio_try_enter_combat_session()
	enemy.set_physics_process(false)
	assert(_count(probe, "combat_prompt") == 1, "combat prompt must emit exactly once per session")
	assert(
		int(probe.calls[0].get("monster_id", -1)) == 21,
		"monster audio must pass the stable runtime monster ID",
	)
	assert(
		str(probe.calls[0].get("context", {}).get("source", "")) == "enemy_actor",
		"monster audio context must identify the actor hook",
	)

	# W3's optional property form is probed once per target instance. Repeated
	# semantic contexts must reuse that result instead of walking the property
	# list on every combat tick.
	var epoch_target := PlayerCharacter.new()
	enemy.primary_target = epoch_target
	var epoch_probe_before := enemy.audio_combat_epoch_property_probe_count_for_test()
	enemy._audio_context("attack_start")
	var epoch_probe_after := enemy.audio_combat_epoch_property_probe_count_for_test()
	for _context_call in range(120):
		enemy._audio_context("attack_frame")
	assert(epoch_probe_after == epoch_probe_before + 1, "epoch property probe must occur once")
	assert(
		enemy.audio_combat_epoch_property_probe_count_for_test() == epoch_probe_after,
		"epoch property probe must stay cached across 120 contexts",
	)
	epoch_target.free()
	enemy.primary_target = null
	var transient_end := probe.end_monster_combat_session("test-owner", "los_interrupted")
	assert(transient_end.get("status", "") == "ended", "probe lifecycle hook should accept session transition")
	assert(_count(probe, "combat_prompt") == 1, "LOS interruption must not reopen a combat prompt")

	# A cached service removed with an old GameRoot must not poison the next
	# world. The first semantic lookup after invalidation discovers the new one.
	probe.queue_free()
	# The cached-service contract compares tree membership, so the fixture must
	# wait for the actual exit instead of racing queue_free with one frame.
	await probe.tree_exited
	await get_tree().process_frame
	var replacement_probe := AudioProbe.new()
	add_child(replacement_probe)
	await get_tree().process_frame
	EnemyActor.set_audio_service_cache_clock_for_test(2001)
	assert(
		enemy._audio_service() == replacement_probe,
		"freed service cache must recover the replacement instance",
	)
	probe = replacement_probe
	var calls_before_audio_gate := probe.calls.size()
	enemy.global_position = Vector2(100000.0, 100000.0)
	enemy._audio_attack_started()
	assert(
		probe.calls.size() == calls_before_audio_gate,
		"off-screen monsters must not emit audio",
	)
	enemy.global_position = Vector2(32.0, 32.0)
	enemy.set_physics_process(false)
	enemy._audio_attack_started()
	assert(
		probe.calls.size() == calls_before_audio_gate,
		"inactive monsters must not emit audio",
	)
	enemy.set_physics_process(true)

	# Accepted attack actions produce start once; visual frame 3 is observed
	# separately and is not coupled to damage submission.
	enemy._play_attack_animation(1.0)
	assert(_count(probe, "attack_start") == 1, "attack_start missing")
	enemy.visual.current_state = "attack"
	enemy.visual.current_frame = 0
	enemy._audio_observe_visual_state()
	enemy.visual.current_frame = 2
	enemy._audio_observe_visual_state()
	enemy._audio_observe_visual_state()
	assert(_count(probe, "attack_frame") == 1, "attack frame 3 must be one-shot per action")

	# Monster hurt/death/ambient are outside the W4 production whitelist.
	enemy.current_hp = 100
	enemy.take_damage(0)
	assert(_count(probe, "hurt") == 0, "zero damage must not emit hurt")
	enemy.take_damage(5)
	assert(_count(probe, "hurt") == 0, "positive monster damage must stay silent in W4")
	enemy.visual.current_state = "walk"
	enemy.visual.current_frame = 0
	enemy._audio_observe_visual_state()
	enemy._audio_observe_visual_state()
	assert(_count(probe, "ambient") == 0, "walk/turn cadence must not emit continuous ambient")

	# A real target edge remains one-shot even when the service rejects the
	# prompt. Missing sample, muted SFX and exhausted budget each simulate a
	# rejected service result; 120 pursuit ticks must not add requests.
	await _assert_rejected_entry_is_one_shot(probe, "load_failed", "missing_sample")
	await _assert_rejected_entry_is_one_shot(probe, "sfx_disabled", "sfx_off")
	await _assert_rejected_entry_is_one_shot(probe, "monster_polyphony_limit", "budget")
	probe.prompt_status = "played"

	# The death boundary closes the session but does not synthesize a monster
	# death sound without a dedicated production source contract.
	enemy.current_hp = 0
	enemy._death_pending = false
	enemy._begin_death()
	enemy._begin_death()
	assert(_count(probe, "death") == 0, "monster death must stay silent in W4")

	# The retained presentation RNG is independent even though W4 no longer
	# consumes it for ambient cadence.
	enemy._rng.seed = 8128
	var gameplay_before := enemy._rng.randi_range(1, 100000)
	enemy._rng.seed = 8128
	enemy.set_audio_seed_for_test(7)
	enemy.set_physics_process(true)
	enemy._audio_previous_visual_state = ""
	enemy._audio_previous_visual_frame = -1
	enemy.visual.current_state = "walk"
	enemy.visual.current_frame = 0
	enemy._audio_observe_visual_state()
	var gameplay_after := enemy._rng.randi_range(1, 100000)
	assert(gameplay_before == gameplay_after, "ambient RNG must not consume gameplay RNG")

	# With no service, repeated actors/events share one bounded group scan per
	# negative-cache interval rather than scanning once per actor per frame.
	probe.queue_free()
	# The cached-service contract compares tree membership, so the fixture must
	# wait for the actual exit instead of racing queue_free with one frame.
	await probe.tree_exited
	await get_tree().process_frame
	var cache_observer := EnemyActor.new()
	cache_observer.monster_id = 21
	cache_observer.monster_data = {"monster_id": 21}
	cache_observer.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(cache_observer)
	await get_tree().process_frame
	EnemyActor.set_audio_service_cache_clock_for_test(3000)
	var lookup_before_burst := EnemyActor.audio_service_lookup_count_for_test()
	for _attempt in 32:
		assert(cache_observer._audio_service() == null)
	assert(
		EnemyActor.audio_service_lookup_count_for_test() == lookup_before_burst + 1,
		"missing service burst must perform exactly one shared group lookup",
	)
	var late_probe := AudioProbe.new()
	add_child(late_probe)
	await get_tree().process_frame
	EnemyActor.set_audio_service_cache_clock_for_test(3999)
	assert(cache_observer._audio_service() == null, "service must wait for negative-cache expiry")
	EnemyActor.set_audio_service_cache_clock_for_test(4000)
	assert(cache_observer._audio_service() == late_probe, "service must recover after bounded miss expiry")

	print("MONSTER_AUDIO_HOOK_PASS：ID精确/阶段门禁/独立RNG/服务生命周期恢复/缺失查询有界")
	get_tree().quit(0)
