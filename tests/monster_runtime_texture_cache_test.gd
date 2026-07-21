extends Node


const SAMPLE_MONSTER_ID := 31


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual._client_resource_profiles.clear()
	MonsterVisual._client_resource_profile_lru.clear()
	assert(MonsterVisual.CLIENT_RESOURCE_CACHE_CAPACITY == 16, "mobile texture cache capacity changed unexpectedly")
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

	print("MONSTER_RUNTIME_TEXTURE_CACHE_PASS same species shares and retains five action RIDs; unchanged frames do not resubmit")
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
