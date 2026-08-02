extends Node


const SAMPLE_MONSTER_ID := 31


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual.reset_client_resource_cache()
	assert(MonsterVisual.CLIENT_RESOURCE_CACHE_CAPACITY == 12, "mobile texture cache count guard changed")
	assert(MonsterVisual.CLIENT_RESOURCE_CACHE_BUDGET_BYTES == 64 * 1024 * 1024, "mobile texture cache byte guard changed")
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO

	var first := await _spawn_sample(player)
	var second := await _spawn_sample(player)
	assert(MonsterVisual.cached_client_profile_count() == 1, "same-species actors rebuilt the five-action resource profile")
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var first_texture: Texture2D = first.visual.active_resources[action_name]
		var second_texture: Texture2D = second.visual.active_resources[action_name]
		assert(first_texture.get_rid() == second_texture.get_rid(), "same-species %s texture RID is not shared" % action_name)

	var idle_updates := first.visual.render_state_update_count()
	first.visual._process(0.0)
	first.visual._process(0.0)
	assert(first.visual.render_state_update_count() == idle_updates, "unchanged idle frame resubmitted sprite state")
	first.visual.play_attack(0.5)
	first.visual._process(0.05)
	var attack_updates := first.visual.render_state_update_count()
	first.visual._process(0.0)
	assert(first.visual.render_state_update_count() == attack_updates, "unchanged attack frame resubmitted sprite state")

	var retained_rids := {}
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		retained_rids[action_name] = (first.visual.active_resources[action_name] as Texture2D).get_rid()
	var fixture_resources: Dictionary = first.visual.active_resources
	first.queue_free()
	second.queue_free()
	await get_tree().process_frame
	var returned := await _spawn_sample(player)
	assert(MonsterVisual.cached_client_profile_count() == 1, "returning to an area rebuilt an already-seen species profile")
	for action_name: String in retained_rids:
		assert((returned.visual.active_resources[action_name] as Texture2D).get_rid() == retained_rids[action_name], "returning to an area recreated %s texture" % action_name)
	returned.queue_free()
	await get_tree().process_frame

	# Stress the byte/count eviction policy without decoding another 21 enormous
	# profile sets. Reusing the fixture textures is sufficient here because the
	# cache accounts conservative ETC2 residency from atlas dimensions.
	MonsterVisual.reset_client_resource_cache()
	var loader := MonsterVisual.new()
	var fixture_bytes := loader._estimated_client_profile_bytes(fixture_resources)
	assert(fixture_bytes > 0, "fixture did not produce a measurable ETC2 residency estimate")
	for index in range(40):
		loader._retain_client_resource_profile("synthetic_pressure_%02d" % index, fixture_resources)
	assert(MonsterVisual.cached_client_profile_count() <= MonsterVisual.CLIENT_RESOURCE_CACHE_CAPACITY, "pressure cache exceeded profile cap")
	assert(MonsterVisual.cached_client_profile_estimated_bytes() <= MonsterVisual.CLIENT_RESOURCE_CACHE_BUDGET_BYTES, "pressure cache exceeded 64 MiB: %d" % MonsterVisual.cached_client_profile_estimated_bytes())
	assert(MonsterVisual.cached_client_profile_count() < 40, "pressure cache did not evict old profiles")

	# Actor residency is independent of the bounded cross-zone cache: far actors
	# release their own five atlas references and reacquire before entering view.
	player.global_position = Vector2(50000, 50000)
	var streamed := await _spawn_sample(player)
	assert(streamed.visual.active_resources.is_empty(), "far spawned actor eagerly retained five atlases")
	player.global_position = streamed.global_position
	streamed.visual._resource_residency_timer = 0.0
	streamed.visual._process(0.13)
	assert(not streamed.visual.active_resources.is_empty(), "near actor did not activate visual resources")
	player.global_position = Vector2(50000, 50000)
	streamed.visual._resource_residency_timer = 0.0
	streamed.visual._process(0.13)
	assert(streamed.visual.active_resources.is_empty(), "far actor retained its atlas resources")
	streamed.queue_free()

	# Runtime path: map loading requests/pins stable monsterIds on the threaded
	# loader. Approaching the already-prefetched crowd must perform zero sync loads.
	MonsterVisual.reset_client_resource_cache()
	MonsterVisual.set_synchronous_loading_for_tests(false)
	assert(loader._try_pin_map_profile("priority_a", 48 * 1024 * 1024), "first priority profile did not fit hard pin budget")
	assert(not loader._try_pin_map_profile("priority_b", 20 * 1024 * 1024), "map pins exceeded the 64 MiB hard budget")
	assert(int(MonsterVisual.map_prefetch_status().pinned_bytes) == 48 * 1024 * 1024, "rejected pin changed budget accounting")
	MonsterVisual.release_map_pins()
	var prefetch := MonsterVisual.begin_map_prefetch([31, 31, 76, 18])
	assert(int(prefetch.requested) == 3, "map prefetch did not deduplicate stable monsterIds: %s" % prefetch)
	assert(MonsterVisual.threaded_texture_request_count() <= MonsterVisual.MAX_CONCURRENT_PROFILE_LOADS * 5, "map prefetch launched the entire map at once")
	player.global_position = Vector2.ZERO
	var prefetched_actor := EnemyActor.new()
	prefetched_actor.setup({
		"monsterId": SAMPLE_MONSTER_ID, "name": "async_fallback_sample",
		"hp": 100, "attackMin": 1, "attackMax": 2,
	}, player, false)
	add_child(prefetched_actor)
	prefetched_actor.set_physics_process(false)
	assert(not prefetched_actor.visual.uses_final_art(), "proximity actor bypassed async fallback before prefetch completed")
	assert(prefetched_actor.visual.has_authored_client_art(), "stable monsterId lost its authored-client-art contract")
	assert(not prefetched_actor.visual.should_draw_procedural_fallback(), "authored monster exposed the green procedural circle while atlases were pending")
	assert(not prefetched_actor.should_draw_synthetic_ground_shadow(), "authored monster exposed the legacy circular shadow while atlases were pending")
	var deadline_msec := Time.get_ticks_msec() + 15000
	var poll_count := 0
	while not bool(prefetch.complete) and Time.get_ticks_msec() < deadline_msec:
		prefetch = MonsterVisual.poll_streaming()
		poll_count += 1
		if poll_count % 60 == 0:
			print("MONSTER_STREAMING_PENDING %s" % prefetch)
		await get_tree().process_frame
	assert(bool(prefetch.complete) and int(prefetch.failed) == 0, "threaded map prefetch exceeded 15s; pending path/status: %s" % prefetch)
	assert(int(prefetch.ready) + int(prefetch.streamed) == 3, "prefetch completion accounting lost a profile: %s" % prefetch)
	assert(int(prefetch.pinned_bytes) <= MonsterVisual.CLIENT_RESOURCE_CACHE_BUDGET_BYTES, "map pins exceeded the 64 MiB hard budget: %s" % prefetch)
	assert(MonsterVisual.cached_client_profile_estimated_bytes() <= MonsterVisual.CLIENT_RESOURCE_CACHE_BUDGET_BYTES, "async cache exceeded the 64 MiB hard budget")
	assert(MonsterVisual.threaded_texture_request_count() == 15, "bounded queue did not eventually request 3 x 5 atlases")
	assert(MonsterVisual.client_texture_load_request_count() == 0, "map prefetch used synchronous texture loading")
	prefetched_actor.visual._resource_residency_timer = 0.0
	prefetched_actor.visual._process(0.13)
	assert(prefetched_actor.visual.uses_final_art(), "fallback MonsterVisual did not automatically retry after async completion")
	assert(not prefetched_actor.should_draw_synthetic_ground_shadow(), "final WIL monster retained the legacy circular shadow")
	assert(MonsterVisual.client_texture_load_request_count() == 0, "approaching a prefetched monster blocked on synchronous loading")
	prefetched_actor.queue_free()
	MonsterVisual.release_map_pins()
	loader.free()
	MonsterVisual.reset_client_resource_cache()

	print("MONSTER_RUNTIME_TEXTURE_CACHE_PASS lazy residency; async stable-ID map pin; runtime sync loads=0")
	get_tree().quit(0)


func _spawn_sample(player: PlayerCharacter, expect_final_art := true) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"monsterId": SAMPLE_MONSTER_ID,
		"name": "runtime_texture_cache_sample",
		"hp": 100,
		"attackMin": 1,
		"attackMax": 2,
	}, player, false)
	add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().process_frame
	if expect_final_art and enemy.global_position.distance_to(player.global_position) <= MonsterVisual.VISUAL_ACTIVATION_DISTANCE_PX:
		assert(enemy.visual.uses_final_art(), "cache fixture did not resolve final client art")
	return enemy


func _synthetic_neighbor_profile(seed_profile: Dictionary, index: int) -> Dictionary:
	var profile := seed_profile.duplicate(true)
	profile["directionPolicy"] = "neighbor_profile_%d" % index
	return profile
