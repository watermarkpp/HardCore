extends Node


const ASYNC_DEADLINE_MSEC := 20000


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var catalog_file := FileAccess.open(
		"res://assets/data/runtime/monster_animation_catalog.json",
		FileAccess.READ,
	)
	var catalog: Variant = JSON.parse_string(catalog_file.get_as_text()) if catalog_file != null else null
	assert(catalog is Dictionary)
	var rows: Array = catalog.get("monsters", [])
	assert(rows.size() == 214)
	var verified_count := 0

	for row: Dictionary in rows:
		var monster_id := int(row.monster_id)
		MonsterVisual.reset_client_resource_cache()
		MonsterVisual.set_synchronous_loading_for_tests(false)
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(monster_id), player, false)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		var fallback_contact := enemy.ground_indicator_center()
		var fallback_radii := enemy.ground_indicator_radii()
		assert(enemy.visual.active_resources.is_empty(), "monsterId=%d did not start cold" % monster_id)
		assert(not enemy.is_targeted, "monsterId=%d cold redraw fixture must remain unselected" % monster_id)
		assert(fallback_contact.is_zero_approx(), "monsterId=%d fallback ground center drifted south of the canonical foot" % monster_id)
		assert(
			not enemy.should_draw_synthetic_ground_shadow(),
			"monsterId=%d authored cold profile exposed a procedural circular shadow" % monster_id,
		)

		var prefetch := MonsterVisual.begin_map_prefetch([monster_id])
		var deadline_msec := Time.get_ticks_msec() + ASYNC_DEADLINE_MSEC
		while not bool(prefetch.complete) and Time.get_ticks_msec() < deadline_msec:
			prefetch = MonsterVisual.poll_streaming()
			await get_tree().process_frame
		assert(bool(prefetch.complete) and int(prefetch.failed) == 0, "monsterId=%d cold profile failed" % monster_id)
		# Prefetch completion and actor activation are separate runtime events.
		# Keep polling the real actor residency path instead of assuming that one
		# synthetic _process call is enough on every atlas size and machine.
		var activation_deadline_msec := Time.get_ticks_msec() + ASYNC_DEADLINE_MSEC
		while (
			enemy.visual.active_resources.is_empty()
			and Time.get_ticks_msec() < activation_deadline_msec
		):
			enemy.visual._resource_residency_timer = 0.0
			enemy.visual._process(0.13)
			MonsterVisual.poll_streaming()
			await get_tree().process_frame
		assert(not enemy.visual.active_resources.is_empty(), "monsterId=%d cold art never activated" % monster_id)
		assert(enemy.visual.uses_final_art(), "monsterId=%d final texture is not visible" % monster_id)
		assert(not enemy.visual.ground_contact_profile.is_empty(), "monsterId=%d cold ground profile missing" % monster_id)
		assert(
			not enemy.should_draw_synthetic_ground_shadow(),
			"monsterId=%d final WIL profile retained a procedural circular shadow" % monster_id,
		)
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
		verified_count += 1

	MonsterVisual.reset_client_resource_cache()
	assert(verified_count == 214)
	print("MONSTER_GROUND_CONTACT_COLD_ACTIVATION_PASS 214 per-ID cold profiles activate and refresh reviewed center/ellipse")
	get_tree().quit(0)
