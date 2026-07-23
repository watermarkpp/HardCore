extends Node


const SAMPLE_IDS := [24, 46, 127, 168, 76, 180, 195]
const BOSS_IDS := [76, 180, 195]
const ASYNC_DEADLINE_MSEC := 20000


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)

	for monster_id: int in SAMPLE_IDS:
		MonsterVisual.reset_client_resource_cache()
		MonsterVisual.set_synchronous_loading_for_tests(false)
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(monster_id), player, monster_id in BOSS_IDS)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		enemy.set_targeted(true)
		var fallback_contact := enemy.ground_indicator_center()
		var fallback_radii := enemy.ground_indicator_radii()
		assert(not enemy.visual.uses_final_art(), "monsterId=%d did not start cold" % monster_id)

		var prefetch := MonsterVisual.begin_map_prefetch([monster_id])
		var deadline_msec := Time.get_ticks_msec() + ASYNC_DEADLINE_MSEC
		while not bool(prefetch.complete) and Time.get_ticks_msec() < deadline_msec:
			prefetch = MonsterVisual.poll_streaming()
			await get_tree().process_frame
		assert(bool(prefetch.complete) and int(prefetch.failed) == 0, "monsterId=%d cold profile failed" % monster_id)
		enemy.visual._resource_residency_timer = 0.0
		enemy.visual._process(0.13)
		assert(enemy.visual.uses_final_art(), "monsterId=%d cold art never activated" % monster_id)
		assert(not enemy.visual.ground_contact_profile.is_empty(), "monsterId=%d cold ground profile missing" % monster_id)
		var final_contact := enemy.ground_indicator_center()
		var final_radii := enemy.ground_indicator_radii()
		assert(final_contact.is_equal_approx(enemy.visual.position + enemy.visual.ground_contact_offset()))
		assert(
			not final_contact.is_equal_approx(fallback_contact)
			or not final_radii.is_equal_approx(fallback_radii),
			"monsterId=%d retained both fallback center and fallback ellipse" % monster_id,
		)

		enemy.queue_free()
		await get_tree().process_frame
		MonsterVisual.release_map_pins()

	MonsterVisual.reset_client_resource_cache()
	print("MONSTER_GROUND_CONTACT_COLD_ACTIVATION_PASS grounded/slender/flying/hover/boss refresh calibrated center and ellipse after async activation")
	get_tree().quit(0)
