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


func _count(probe: AudioProbe, monster_id: int, semantic_event: String) -> int:
	var result := 0
	for call: Dictionary in probe.calls:
		if (
			int(call.get("monster_id", -1)) == monster_id
			and str(call.get("semantic_event", "")) == semantic_event
		):
			result += 1
	return result


func _run() -> void:
	SummonActor.set_audio_service_cache_clock_for_test(1000)
	var lookup_before_missing := SummonActor.audio_service_lookup_count_for_test()
	var owner := PlayerCharacter.new()
	owner.global_position = Vector2(32.0, 32.0)
	owner.current_hp = 100
	add_child(owner)
	await get_tree().process_frame

	var skeleton := SummonActor.new()
	skeleton.setup(owner, "骷髅", 30, 3, "taoist.summon_skeleton", 40)
	skeleton.global_position = Vector2(64.0, 64.0)
	add_child(skeleton)
	await get_tree().process_frame

	# A miss is globally bounded and must recover when a service appears after
	# the negative-cache interval, without any production reset dependency.
	skeleton._audio_try_emit_appear()
	assert(
		SummonActor.audio_service_lookup_count_for_test() == lookup_before_missing + 1,
		"first missing service must perform one lookup",
	)
	var probe := AudioProbe.new()
	add_child(probe)
	await get_tree().process_frame
	skeleton._audio_try_emit_appear()
	assert(probe.calls.is_empty(), "negative-cache window must stay fail-closed")
	SummonActor.set_audio_service_cache_clock_for_test(2000)
	skeleton._audio_try_emit_appear()
	skeleton._audio_try_emit_appear()
	assert(_count(probe, 145, "appear") == 1, "skeleton appear must emit once")
	assert(
		str(probe.calls[0].get("context", {}).get("source", ""))
		== "summon_actor",
		"summon audio context must identify the actor hook",
	)

	# Replacing the old GameRoot/service must invalidate the shared positive
	# cache and discover the new in-tree service immediately.
	probe.queue_free()
	await get_tree().process_frame
	var replacement_probe := AudioProbe.new()
	add_child(replacement_probe)
	await get_tree().process_frame
	SummonActor.set_audio_service_cache_clock_for_test(2001)
	assert(
		skeleton._audio_service() == replacement_probe,
		"freed service cache must recover the replacement instance",
	)
	probe = replacement_probe
	var calls_before_gate := probe.calls.size()
	skeleton.global_position = Vector2(100000.0, 100000.0)
	skeleton._audio_attack_started()
	assert(
		probe.calls.size() == calls_before_gate,
		"off-screen summons must not emit attack audio",
	)
	skeleton.global_position = Vector2(64.0, 64.0)
	skeleton._audio_attack_started()
	assert(_count(probe, 145, "attack_start") == 1, "attack_start missing")
	skeleton._audio_attack_frame()
	skeleton._audio_attack_frame()
	assert(_count(probe, 145, "attack_frame") == 1, "attack_frame must be one-shot")

	var hp_before := skeleton.current_hp
	skeleton._apply_resolved_damage(5)
	assert(skeleton.current_hp == hp_before - 5)
	assert(_count(probe, 145, "hurt") == 1, "positive summon damage must emit hurt")
	skeleton._apply_resolved_damage(skeleton.current_hp)
	skeleton._audio_death_once()
	assert(_count(probe, 145, "death") == 1, "summon death must emit once")

	var divine := SummonActor.new()
	divine.setup(owner, "神兽", 30, 3, "taoist.summon_divine_beast", 40)
	divine.global_position = Vector2(96.0, 64.0)
	add_child(divine)
	await get_tree().process_frame
	divine._audio_try_emit_appear()
	assert(_count(probe, 146, "appear") == 1, "divine beast must use monster ID 146")
	divine._audio_attack_started()
	divine._audio_attack_frame()
	assert(_count(probe, 146, "attack_start") == 1)
	assert(_count(probe, 146, "attack_frame") == 1)

	# Repeated events while no service exists share one scan for the whole actor
	# class during the one-second miss window.
	probe.queue_free()
	await get_tree().process_frame
	SummonActor.set_audio_service_cache_clock_for_test(3000)
	var lookup_before_burst := SummonActor.audio_service_lookup_count_for_test()
	for _attempt in 32:
		assert(skeleton._audio_service() == null)
	assert(
		SummonActor.audio_service_lookup_count_for_test() == lookup_before_burst + 1,
		"missing service burst must perform exactly one shared group lookup",
	)
	var late_probe := AudioProbe.new()
	add_child(late_probe)
	await get_tree().process_frame
	SummonActor.set_audio_service_cache_clock_for_test(3999)
	assert(skeleton._audio_service() == null, "service must wait for negative-cache expiry")
	SummonActor.set_audio_service_cache_clock_for_test(4000)
	assert(skeleton._audio_service() == late_probe, "service must recover after bounded miss expiry")

	skeleton.queue_free()
	divine.queue_free()
	owner.queue_free()
	await get_tree().process_frame
	print(
		"SUMMON_AUDIO_HOOK_PASS: exact 145/146 IDs, accepted attack phases, "
		+ "positive hurt, one-shot death, off-screen gate, service lifecycle recovery, "
		+ "and bounded missing-service lookup"
	)
	get_tree().quit(0)
