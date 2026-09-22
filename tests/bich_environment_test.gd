extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var background: WorldBackground = game.background
	assert(background.uses_bich_art(), "Bich presentation art is not active")
	assert(background.bich_ground_atlas_size() == Vector2i(512, 32), "Bich ground atlas dimensions changed")
	assert(background.bich_prop_atlas_size() == Vector2i(384, 128), "Bich prop atlas dimensions changed")
	assert(background.bich_collision_count() == 0, "Legacy Bich collision must not be mixed with editor runtime collision")
	assert(background.source_collision_shape_count() >= 4, "Editor obstacles and four-sided hard boundary were not built")

	var runtime := MapEditorRuntimeBridge.load_bich()
	var blocked_tiles: Array = runtime.get("collision", {}).get("blocked_tiles", [])
	assert(not blocked_tiles.is_empty(), "Editor runtime has no obstacle occupancy data")
	var blocked_parts := str(blocked_tiles[0]).split(",")
	var blocked_world := MapEditorRuntimeBridge.grid_cell_to_screen_position_px(runtime, [float(blocked_parts[0]), float(blocked_parts[1])])
	assert(background.is_environment_point_blocked(blocked_world), "Editor obstacle is absent from unified spatial query")
	var outside_world := MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(runtime, Vector2(-1.0, 0.0))
	assert(background.is_environment_point_blocked(outside_world), "Black area outside the map is not a hard boundary")

	var required_portals: Array = MapEditorRuntimeBridge.game_content().get("portals", []).map(func(portal: Dictionary) -> Vector2: return portal.screen_position_px)
	for portal_position: Vector2 in required_portals:
		assert(not background.is_environment_point_blocked(portal_position), "Portal is blocked: %s" % portal_position)

	var orc_tomb_f1_id := _runtime_map_id("bich_orc_tomb_f1")
	assert(MapEditorRuntimeBridge.has_runtime_map(orc_tomb_f1_id))
	# G0 (remote review 2026-09-16): the catalog memoizes per-map profiles.
	# The bich profile was built exactly once during this map session and a
	# repeat fetch is a cache hit (no rebuild). Editor-authored maps have no
	# catalog profile by design (their ground is authored chunks), so the
	# first-build counter is validated against the next configured catalog
	# map instead of the travel target.
	var builds_before_travel := EnvironmentCatalog.environment_profile_build_count()
	assert(builds_before_travel >= 1, "entering the bich map must have built its profile once")
	var bich_profile := EnvironmentCatalog.get_map_profile(4)
	assert(not bich_profile.is_empty(), "bich profile must exist")
	assert(
		EnvironmentCatalog.environment_profile_build_count() == builds_before_travel,
		"a repeat get_map_profile call must be a cache hit, not a rebuild"
	)
	# G0.1: the per-frame focus path must not rebuild (or even re-resolve)
	# the profile. Simulate 3600 focus updates on the live bich map - the
	# profile stays a shared cache hit and the resolved-lookup counter does
	# not move. This is the regression gate for the per-frame branch the
	# first G0 tests did not cover.
	var builds_before_focus_loop := EnvironmentCatalog.environment_profile_build_count()
	var focus_origin: Vector2 = game.player.global_position
	for focus_step in 3600:
		background.set_focus_position(
			focus_origin + Vector2(float(focus_step % 7) - 3.0, float(focus_step % 5) - 2.0)
		)
	assert(
		EnvironmentCatalog.environment_profile_build_count() == builds_before_focus_loop,
		"3600 per-frame focus updates must not resolve or rebuild any profile"
	)
	# G0.1: negative lookups are cached too - the first fetch of an unknown
	# map id resolves once, and a thousand repeats must not re-resolve.
	var builds_before_negative := EnvironmentCatalog.environment_profile_build_count()
	assert(
		EnvironmentCatalog.get_map_profile(999999).is_empty(),
		"an unknown map id must resolve to an empty profile"
	)
	assert(
		EnvironmentCatalog.environment_profile_build_count() == builds_before_negative + 1,
		"the first negative lookup must resolve exactly once"
	)
	for negative_repeat in 1000:
		assert(EnvironmentCatalog.get_map_profile(999999).is_empty())
	assert(
		EnvironmentCatalog.environment_profile_build_count() == builds_before_negative + 1,
		"repeated negative lookups must be cache hits, not re-resolutions"
	)
	game.travel_to_map(orc_tomb_f1_id)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.current_map_id == orc_tomb_f1_id, "formal orc tomb map change failed")
	assert(background.editor_runtime_ground_ready(), "formal orc tomb ground is not ready")
	assert(not background.uses_bich_art(), "Bich presentation remained active after map change")
	assert(background.bich_collision_count() == 0, "Bich legacy collision remained after map change")
	var next_catalog_map := -1
	for map_id: Variant in EnvironmentCatalog.configured_map_ids():
		if int(map_id) != 4:
			next_catalog_map = int(map_id)
			break
	assert(next_catalog_map > 0, "the catalog must configure at least one non-bich map")
	# G0.1 resolution contract, stated as invariants instead of absolute
	# counts: the travel legitimately resolves the new map's catalog ids
	# once (editor-map negative + presentation positive), ANY repeat fetch -
	# positive or negative - must be a cache hit with stable content.
	var first_fetch := EnvironmentCatalog.get_map_profile(next_catalog_map)
	var builds_after_first := EnvironmentCatalog.environment_profile_build_count()
	var second_fetch := EnvironmentCatalog.get_map_profile(next_catalog_map)
	assert(
		EnvironmentCatalog.environment_profile_build_count() == builds_after_first,
		"a repeat fetch of the same catalog map must stay a cache hit"
	)
	assert(second_fetch == first_fetch, "cached profile content must stay stable")
	# G0.1 per-frame gate on the NEW map (which has no catalog profile):
	# 3600 live focus updates must not resolve or rebuild anything - the
	# negative cache plus the early-return keep the frame path flat.
	var builds_before_new_map_loop := EnvironmentCatalog.environment_profile_build_count()
	var new_map_focus_origin: Vector2 = game.player.global_position
	for focus_step in 3600:
		background.set_focus_position(
			new_map_focus_origin
			+ Vector2(float(focus_step % 7) - 3.0, float(focus_step % 5) - 2.0)
		)
	assert(
		EnvironmentCatalog.environment_profile_build_count() == builds_before_new_map_loop,
		"3600 focus updates on the editor map must not resolve or rebuild any profile"
	)
	print(
		"BICH_ENVIRONMENT_PASS: editor occupancy, portals, hard boundary and map cleanup share one spatial contract (profile_builds=%d cache_size=%d)"
		% [
			EnvironmentCatalog.environment_profile_build_count(),
			EnvironmentCatalog.environment_profile_cache_size(),
		]
	)
	get_tree().quit(0)


func _runtime_map_id(map_key: String) -> int:
	for raw_map: Variant in GameData.get_available_maps(true):
		if (
			raw_map is Dictionary
			and str((raw_map as Dictionary).get("formalMapKey", "")) == map_key
		):
			return int((raw_map as Dictionary).get("mapId", -1))
	return -1
