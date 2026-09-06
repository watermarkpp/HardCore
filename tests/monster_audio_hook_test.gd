extends Node


class AudioProbe extends Node:
	var calls: Array[Dictionary] = []

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


func _ready() -> void:
	_run.call_deferred()


func _count(probe: AudioProbe, semantic_event: String) -> int:
	var result := 0
	for call: Dictionary in probe.calls:
		if str(call.get("semantic_event", "")) == semantic_event:
			result += 1
	return result


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

	# A first miss is shared and recoverable. Installing a service inside the
	# one-second negative window must not cause another group scan; expiry must
	# discover it naturally without any production reset call.
	enemy._audio_try_emit_appear()
	assert(
		EnemyActor.audio_service_lookup_count_for_test() == lookup_before_missing + 1,
		"first missing service must perform one lookup",
	)
	var probe := AudioProbe.new()
	add_child(probe)
	await get_tree().process_frame
	enemy._audio_try_emit_appear()
	assert(probe.calls.is_empty(), "negative-cache window must stay fail-closed")
	EnemyActor.set_audio_service_cache_clock_for_test(2000)
	enemy._audio_try_emit_appear()

	# Spawn audio is one-shot and uses the runtime integer ID, not display text.
	enemy._audio_try_emit_appear()
	enemy._audio_try_emit_appear()
	assert(_count(probe, "appear") == 1, "appear must emit exactly once")
	assert(
		int(probe.calls[0].get("monster_id", -1)) == 21,
		"monster audio must pass the stable runtime monster ID",
	)
	assert(
		str(probe.calls[0].get("context", {}).get("source", "")) == "enemy_actor",
		"monster audio context must identify the actor hook",
	)

	# A cached service removed with an old GameRoot must not poison the next
	# world. The first semantic lookup after invalidation discovers the new one.
	probe.queue_free()
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

	# Zero damage never enters hit presentation; positive damage does.
	enemy.current_hp = 100
	enemy.take_damage(0)
	assert(_count(probe, "hurt") == 0, "zero damage must not emit hurt")
	enemy.take_damage(5)
	assert(_count(probe, "hurt") == 1, "positive damage entering hit must emit hurt")

	# The death boundary emits exactly once, including when the actor is already
	# leaving active physics for corpse presentation.
	enemy.current_hp = 0
	enemy._death_pending = false
	enemy._begin_death()
	enemy._begin_death()
	assert(_count(probe, "death") == 1, "death must emit once at the death transition")

	# An independent audio RNG must not advance gameplay randomness.  Search a
	# deterministic seed only to reach the 1/8 ambient branch in this fixture.
	var ambient_seen := false
	for seed_value in range(1, 128):
		enemy._dying = false
		enemy._death_pending = false
		enemy.current_hp = 100
		enemy.set_physics_process(true)
		enemy.set_audio_seed_for_test(seed_value)
		enemy._audio_previous_visual_state = ""
		enemy._audio_previous_visual_frame = -1
		enemy.visual.current_state = "walk"
		enemy.visual.current_frame = 0
		var before := _count(probe, "ambient")
		enemy._audio_observe_visual_state()
		if _count(probe, "ambient") > before:
			ambient_seen = true
			break
	assert(ambient_seen, "ambient 1/8 branch must be reachable")

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
