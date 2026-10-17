extends RefCounted

## MAIN ONLY: resolve original published source/readiness/resource qualification.
## No Node, Resource, Image, Callable, compiled Index or Graph crosses this boundary.
const Graph := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const Catalog := preload("res://scripts/environment_catalog.gd")

static func capture(background: Node, requested_map_ids: Array[int]) -> Dictionary:
	if not is_instance_valid(background) or not background.has_method("environment_profile") or not background.has_method("_active_map_id"):
		return {"ok": false, "errors": ["original_background_required"]}
	var ids: Array[int] = requested_map_ids.duplicate()
	var active_id: int = background._active_map_id()
	if not ids.has(active_id):
		ids.append(active_id)
	var values := {
		"contract_id": "world.environment.publication.v1",
		"map_load_order": ids,
		"runtime_maps": {}, "profiles": {}, "themes": {},
		"region_content": {}, "resource_exists": {}, "masks": {},
		"gothic_collision_entries": background.get("_gothic_camp_built").get("collisions", []),
		"generation_context": {"coordinator_present": background.get("bootstrap_coordinator") != null,
			"generation_token": background._generation_token(), "generation_current_at_publication": background._generation_is_current()},
		"background": {
			"zone_name": background.get("zone_name"), "zone_data": background.get("zone_data"),
			"bich_collision_shapes": background.get("_bich_collision_shapes"),
			"tomb_collision_shapes": background.get("_tomb_collision_shapes"),
			"source_collision_shape_count": background.get("_source_collision_shape_count"),
			"collision_revision": background.environment_collision_revision(),
			"source_mask_path": background.get("_source_mask_path"),
			"source_mask_present": background.get("_source_mask_image") != null,
			"source_clear_segments": background.get("_source_clear_segments"),
			"source_clear_cell_cache": background.get("_source_clear_cell_cache"),
			"gothic_camp_layout": background.get("_gothic_camp_layout"),
			"editor_runtime_size": background.get("_editor_runtime_size"),
			"editor_runtime_collision_invalid": background.get("_editor_runtime_collision_invalid"),
			"staged_generation": background.get("_staged_generation"),
		},
	}
	for id: int in ids:
		var runtime := Bridge.load_map(id) if Bridge.has_runtime_map(id) else {}
		values.runtime_maps[id] = {
			"formal_playable": Bridge.is_formal_playable(id),
			"has_runtime_map": Bridge.has_runtime_map(id),
			"runtime_path": Bridge.runtime_path(id), "runtime": runtime,
			"runtime_game_content": Bridge.game_content_for_map(id),
			"world_has_map": WorldContent != null and WorldContent.has_map(id),
			"world_content": WorldContent.map_content(id) if WorldContent != null and WorldContent.has_map(id) else {},
		}
		var presentation_id: int = background._presentation_map_id(id)
		var profile: Dictionary = Catalog.get_map_profile(presentation_id)
		values.profiles[presentation_id] = profile
		var theme_id := str(profile.get("theme", ""))
		values.themes[theme_id] = Catalog.get_theme(theme_id)
		values.region_content[id] = RegionContent.get_map_content(id)
		var mask_path := str(profile.get("collision_mask_path", ""))
		if not mask_path.is_empty():
			var exists := ResourceLoader.exists(mask_path)
			values.resource_exists[mask_path] = exists
			var texture: Texture2D = background._prefetched_texture(mask_path, "BUILD_COLLISION") if exists else null
			var image: Image = texture.get_image() if texture != null else null
			values.masks[mask_path] = _capture_mask(image, profile.get("source_size", Vector2i.ZERO))
		# Source's original prepare_map_build installs the requested GameData
		# record before awaiting Main's resource/build publication. A detached
		# boot Background still has empty zone_data at this point, so its own
		# presentation lookup cannot resolve the requested record's legacy ID.
		# Publish that exact original lookup too; never grant a runtime map,
		# build a mask, or substitute a profile for an unpublished ID on S.
		var requested_map: Dictionary = GameData.get_map_by_id(id)
		if not requested_map.is_empty():
			if requested_map.get("mapId") != id:
				return {"ok": false, "errors": ["requested_map_record_identity_mismatch:" + str(id)]}
			var requested_presentation_id := id
			var legacy_id := int(requested_map.get("legacyRuntimeMapId", -1))
			if legacy_id > 0:
				requested_presentation_id = legacy_id
			if not values.profiles.has(requested_presentation_id):
				var requested_profile: Dictionary = Catalog.get_map_profile(requested_presentation_id)
				values.profiles[requested_presentation_id] = requested_profile
				var requested_theme := str(requested_profile.get("theme", ""))
				values.themes[requested_theme] = Catalog.get_theme(requested_theme)
				var requested_mask := str(requested_profile.get("collision_mask_path", ""))
				if not requested_mask.is_empty():
					values.resource_exists[requested_mask] = ResourceLoader.exists(requested_mask)
	var active_image: Image = background.get("_source_mask_image")
	if active_image != null:
		var active_path := str(values.background.source_mask_path)
		values.resource_exists[active_path] = ResourceLoader.exists(active_path)
		values.masks[active_path] = _capture_mask(active_image, active_image.get_size())
	var result := Graph.copy_and_seal(values)
	return {"ok": result.ok, "errors": result.errors, "publication": result.value if result.ok else {}}

static func _capture_mask(image: Image, expected_size: Vector2i) -> Dictionary:
	if image == null or image.get_size() != expected_size:
		return {"qualified": false, "size": Vector2i.ZERO, "red": PackedFloat32Array()}
	var size := image.get_size()
	var red := PackedFloat32Array()
	red.resize(size.x * size.y)
	for y: int in range(size.y):
		for x: int in range(size.x):
			red[y * size.x + x] = image.get_pixel(x, y).r
	return {"qualified": true, "size": size, "red": red}
