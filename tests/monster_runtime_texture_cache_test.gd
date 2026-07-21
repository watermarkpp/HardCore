extends Node


const SAMPLE_MONSTER_ID := 31


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual._client_resource_profiles.clear()
	MonsterVisual._client_resource_profile_lru.clear()
	MonsterVisual._client_texture_load_request_count = 0
	assert(MonsterVisual.CLIENT_RESOURCE_CACHE_CAPACITY == 32, "mobile texture cache must cover the largest single-region profile set")
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(2000, 0)

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
	first.queue_free()
	second.queue_free()
	await get_tree().process_frame
	var returned := await _spawn_sample(player)
	assert(MonsterVisual.cached_client_profile_count() == 1, "returning to an area rebuilt an already-seen species profile")
	for action_name: String in retained_rids:
		assert((returned.visual.active_resources[action_name] as Texture2D).get_rid() == retained_rids[action_name], "returning to an area recreated %s texture" % action_name)
	returned.queue_free()
	await get_tree().process_frame

	# Bich's common runtime set contains 22 distinct visual profiles. A player can
	# leave it for a neighboring area and encounter ten more profiles before
	# returning; the full Bich set must still be resident and issue no new loads.
	MonsterVisual._client_resource_profiles.clear()
	MonsterVisual._client_resource_profile_lru.clear()
	MonsterVisual._client_texture_load_request_count = 0
	var bich_profiles: Dictionary = GameData.bich_common_art.get("runtimeMappings", {})
	var bich_keys: Array = bich_profiles.keys()
	bich_keys.sort()
	assert(bich_keys.size() == 22, "Bich common visual working set changed: %d" % bich_keys.size())
	var loader := MonsterVisual.new()
	for key: Variant in bich_keys:
		assert(not loader._client_resources(bich_profiles[key]).is_empty(), "failed to load Bich profile: %s" % key)
	assert(MonsterVisual.cached_client_profile_count() == 22, "Bich working set was not retained in full")
	assert(MonsterVisual.client_texture_load_request_count() == 110, "Bich first visit must request exactly 22 x 5 action textures")

	var seed_profile: Dictionary = bich_profiles[bich_keys[0]]
	for index in range(10):
		assert(not loader._client_resources(_synthetic_neighbor_profile(seed_profile, index)).is_empty())
	assert(MonsterVisual.cached_client_profile_count() == 32, "Bich plus neighboring profiles did not fill the bounded cache")
	var requests_before_return := MonsterVisual.client_texture_load_request_count()
	for key: Variant in bich_keys:
		assert(not loader._client_resources(bich_profiles[key]).is_empty())
	assert(MonsterVisual.client_texture_load_request_count() == requests_before_return, "returning to Bich re-requested an evicted action texture")
	assert(MonsterVisual.cached_client_profile_count() == 32, "return visit changed bounded cache size")

	assert(not loader._client_resources(_synthetic_neighbor_profile(seed_profile, 10)).is_empty())
	assert(MonsterVisual.cached_client_profile_count() == MonsterVisual.CLIENT_RESOURCE_CACHE_CAPACITY, "LRU cache grew beyond its mobile bound")
	loader.free()
	MonsterVisual._client_resource_profiles.clear()
	MonsterVisual._client_resource_profile_lru.clear()

	print("MONSTER_RUNTIME_TEXTURE_CACHE_PASS 22-profile Bich round trip adds zero loads; 32-profile LRU remains bounded")
	get_tree().quit(0)


func _spawn_sample(player: PlayerCharacter) -> EnemyActor:
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
	assert(enemy.visual.uses_final_art(), "cache fixture did not resolve final client art")
	return enemy


func _synthetic_neighbor_profile(seed_profile: Dictionary, index: int) -> Dictionary:
	var profile := seed_profile.duplicate(true)
	profile["directionPolicy"] = "neighbor_profile_%d" % index
	return profile
