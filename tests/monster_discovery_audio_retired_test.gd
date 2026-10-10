extends Node

const Service := preload("res://scripts/audio_runtime_service.gd")
const Identity := preload("res://scripts/monster_identity.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var service := Service.new()
	add_child(service)
	await get_tree().process_frame
	service.set_sfx_enabled(true)
	service.stop_all_audio("retired_discovery_setup")
	service.reset_metrics_for_test(true)
	var before: Dictionary = service.metrics_snapshot()
	for owner in range(30):
		for tick in range(120):
			var result: Dictionary = service.play_monster_combat_prompt(21, "retired-%d" % owner)
			assert(result.get("reason", "") == "combat_prompt_disabled", "Removed discovery/combat-state sound must stay disabled")
	assert(service.monster_combat_session_snapshot().is_empty(), "Retired prompt must not retain actor sessions")
	assert(service._owner_release_seen.is_empty(), "Retired prompt must not retain release keys")
	assert(service._rng_by_event.is_empty(), "Retired prompt must not choose samples")
	assert(service.metrics_snapshot().get("stream_lookup_attempts", 0) == before.get("stream_lookup_attempts", 0), "Retired prompt must not fetch streams")
	assert(service.metrics_snapshot().get("played", 0) == 0, "Retired prompt must not start voices")
	var expected_paths := {}
	for binding: Dictionary in service._bindings.values():
		for path in binding.get("runtime_paths", []):
			expected_paths[path] = true
	for event: Dictionary in service._events.values():
		if str(event.get("owner_kind", "")) == "monster" and str(event.get("semantic_event", "")) not in Service.MONSTER_ATTACK_SEMANTICS:
			continue
		for path in event.get("runtime_paths", []):
			expected_paths[path] = true
	assert(service._stream_cache.size() == expected_paths.size(), "Prewarm must contain only production-reachable sounds")
	for path in expected_paths:
		assert(service._stream_cache.has(path), "Every allowed sound must remain prewarmed")
	var target := Node2D.new()
	add_child(target)
	var actor := EnemyActor.new()
	actor.monster_id = 21
	actor.monster_data = {"monster_id": 21}
	actor.combat_body_profile = Identity.body_profile(21)
	actor.max_hp = 100
	actor.current_hp = 100
	add_child(actor)
	assert(actor._audio_rng == null, "Retired ambient RNG must not allocate or seed on spawn")
	actor.set_physics_process(false)
	var requests_before := int(service.metrics_snapshot().get("requests", 0))
	actor.target = target
	for tick in range(120):
		actor._audio_try_enter_combat_session()
	assert(int(service.metrics_snapshot().get("requests", 0)) == requests_before, "Discovery hook must not submit any audio request")
	assert(not actor._audio_combat_session_active, "Discovery must not open a retired audio session")
	var summon := SummonActor.new()
	for tick in range(120):
		summon._audio_try_emit_appear()
	assert(summon._audio_appear_emitted, "Already disabled summon appear hook must be sealed without retry")
	summon.free()
	var attack: Dictionary = service.play_monster_event(21, "attack_start", {"audio_owner_key": "live-attack", "release_id": "attack:1"})
	assert(attack.get("status", "") == "played", "Removing discovery sound must preserve actual attack sound")
	assert(service.metrics_snapshot().get("stream_cache_misses", 0) == 0, "Allowed attack must use prewarmed stream")
	print("MONSTER_DISCOVERY_AUDIO_RETIRED_PASS: 30 owners x 120 calls, no prompt voices/resources/sessions; production attack preserved")
	service.stop_all_audio("test_exit")
	get_tree().quit(0)
