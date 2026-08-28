extends Node

## Contract test for the reviewed small_prop occlusion Authority.
##
## This test intentionally uses exact asset IDs and the formal release
## registry.  It does not infer occlusion from `asset_type`, geometry, or a
## name/suffix convention, so a future small_prop cannot silently opt in.

const VisualGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)

const CATALOG_PATH := (
	"res://assets/data/assets/map_small_decoration_asset_catalog.json"
)
const REGISTRY_PATH := (
	"res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
)
const WORKSPACE_ROOT := "res://map_editor_workspace"
const SMALL_PREFIX := "mse.small_decor."
const EXPECTED_SMALL_ASSET_COUNT := 48
const EXPECTED_WORKSPACE_DOCUMENT_COUNT := 20
const EXPECTED_WORKSPACE_INSTANCE_COUNT := 196

const EXPECTED_FORMAL_SMALL_COUNTS := {
	"cangyue_bone_cave_f1": 15,
	"cangyue_bone_cave_f2": 15,
	"cangyue_bone_cave_f3": 15,
	"cangyue_bone_cave_f4": 15,
	"cangyue_bone_cave_f5": 10,
	"world_bich_province": 7,
	"world_cangyue_island": 1,
	"world_fengmo_valley": 7,
	"world_mengzhong_province": 6,
	"world_white_day_gate": 7,
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MapAssetCatalogService.invalidate_cache()
	MapEditorRuntimeBridge.invalidate_release_registry()

	var catalog := _read_json(CATALOG_PATH)
	assert(not catalog.is_empty(), "small decoration catalog missing/invalid")
	_assert_catalog_authority(catalog)
	_assert_no_type_fallback()

	var registry := _read_json(REGISTRY_PATH)
	assert(not registry.is_empty(), "formal release registry missing/invalid")
	assert(
		MapEditorRuntimeBridge.validate_release_registry(registry).is_empty(),
		"formal release registry schema invalid"
	)

	var formal_runtime_count := 0
	var formal_instance_count := 0
	var formal_actor_command_count := 0
	var formal_geometry_pair_count := 0
	var formal_keys := {}
	var formal_well_checked := false
	for raw_entry: Variant in registry.get("maps", []):
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var map_key := str(entry.get("map_key", ""))
		var runtime_path := str(entry.get("runtime_path", ""))
		if not EXPECTED_FORMAL_SMALL_COUNTS.has(map_key):
			continue
		assert(
			runtime_path == "res://assets/data/runtime/map_editor/%s.runtime.json" % map_key,
			"formal runtime path drifted: %s" % map_key
		)
		var loaded := MapEditorRuntimeMapService.load_runtime(runtime_path)
		assert(loaded.ok, "%s runtime failed formal loader: %s" % [map_key, loaded.errors])
		var runtime: Dictionary = loaded.runtime
		var expected_count := int(EXPECTED_FORMAL_SMALL_COUNTS[map_key])
		var runtime_small := _small_instances(runtime.get("instances", []))
		assert(
			runtime_small.size() == expected_count,
			"%s runtime small_prop count %d/%d" % [map_key, runtime_small.size(), expected_count]
		)
		for instance: Dictionary in runtime_small:
			assert(
				bool(instance.get("occlusion", false)),
				"%s runtime instance is not an occluder: %s" % [map_key, instance.get("instance_id", "")]
			)
		var approved_hash := str(entry.get("approved_build_sha256", ""))
		assert(approved_hash == str(runtime.get("build_sha256", "")),
			"%s registry/runtime build hash mismatch" % map_key)
		assert(MapEditorRuntimeBridge.is_formal_playable(int(entry.get("runtime_map_id", -1))),
			"%s cannot load through formal registry" % map_key)

		var editor_path := "%s/%s/%s.editor.json" % [WORKSPACE_ROOT, map_key, map_key]
		var editor := _read_json(editor_path)
		assert(not editor.is_empty(), "%s editor source missing/invalid" % map_key)
		var editor_small := _small_instances(MapEditorInstanceService.all_instances(editor))
		assert(editor_small.size() == expected_count,
			"%s editor small_prop count %d/%d" % [map_key, editor_small.size(), expected_count])
		for instance: Dictionary in editor_small:
			assert(bool(instance.get("occlusion", false)),
				"%s editor instance is not an occluder: %s" % [map_key, instance.get("instance_id", "")])

		var editor_by_id := _by_instance_id(editor_small)
		var runtime_by_id := _by_instance_id(runtime_small)
		assert(editor_by_id.keys().size() == runtime_by_id.keys().size(),
			"%s source/runtime small_prop identity count mismatch" % map_key)
		for instance_id: String in editor_by_id:
			assert(runtime_by_id.has(instance_id),
				"%s runtime missing small_prop %s" % [map_key, instance_id])
			var editor_instance: Dictionary = editor_by_id[instance_id]
			var runtime_instance: Dictionary = runtime_by_id[instance_id]
			assert(_geometry_projection(editor_instance) == _geometry_projection(runtime_instance),
				"%s geometry changed across source/runtime for %s" % [map_key, instance_id])
		var stripped := _strip_small_occlusion(editor)
		assert(
			VisualGeometry.editor_layout_sha256(editor)
				== VisualGeometry.editor_layout_sha256(stripped),
			"%s layout semantic hash changed when occlusion was stripped" % map_key
		)
		var stripped_small := _small_instances(
			MapEditorInstanceService.all_instances(stripped)
		)
		assert(stripped_small.size() == editor_small.size(),
			"%s stripped small_prop count changed" % map_key)
		for stripped_instance: Dictionary in stripped_small:
			var stripped_id := str(stripped_instance.get("instance_id", ""))
			assert(_geometry_projection(editor_by_id[stripped_id])
				== _geometry_projection(stripped_instance),
				"%s critical geometry changed when occlusion was stripped: %s"
				% [map_key, stripped_id])
		formal_geometry_pair_count += editor_small.size()

		var commands := VisualGeometry.sorted_draw_commands(runtime.get("instances", []))
		var commands_by_id := {}
		for command: Dictionary in commands:
			var command_instance: Dictionary = command.get("instance", {})
			var command_id := str(command_instance.get("instance_id", ""))
			if not runtime_by_id.has(command_id):
				continue
			commands_by_id[command_id] = int(commands_by_id.get(command_id, 0)) + 1
			assert(
				str(command.get("render_domain", ""))
					== VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT,
				"%s small_prop command is not actor_y_sort: %s" % [map_key, command_id]
			)
			assert(
				str(command.get("occlusion_contract_id", ""))
					== VisualGeometry.OCCLUSION_SORT_CONTRACT_ID,
				"%s small_prop command lacks occlusion contract: %s" % [map_key, command_id]
			)
			formal_actor_command_count += 1
		for instance_id: String in runtime_by_id:
			assert(int(commands_by_id.get(instance_id, 0)) == 1,
				"%s small_prop command multiplicity is not 1: %s" % [map_key, instance_id])
			var asset := MapAssetCatalogService.find_asset(str(runtime_by_id[instance_id].get("asset_id", "")))
			assert(not asset.is_empty(), "%s asset missing: %s" % [map_key, instance_id])
			assert(VisualGeometry.instance_is_occluder(runtime_by_id[instance_id], asset),
				"%s small_prop did not resolve as an occluder: %s" % [map_key, instance_id])

		if map_key == "world_bich_province":
			_assert_bich_well(runtime, editor, commands)
			formal_well_checked = true
		formal_runtime_count += 1
		formal_instance_count += runtime_small.size()
		formal_keys[map_key] = true

	var workspace_document_count := 0
	var workspace_instance_count := 0
	for path: String in _collect_editor_paths(WORKSPACE_ROOT):
		var document := _read_json(path)
		var small := _small_instances(MapEditorInstanceService.all_instances(document))
		if small.is_empty():
			continue
		workspace_document_count += 1
		workspace_instance_count += small.size()
		for instance: Dictionary in small:
			assert(bool(instance.get("occlusion", false)),
				"workspace instance is not an occluder: %s:%s" % [path, instance.get("instance_id", "")])
	assert(workspace_document_count == EXPECTED_WORKSPACE_DOCUMENT_COUNT,
		"workspace small_prop document count %d/%d" % [workspace_document_count, EXPECTED_WORKSPACE_DOCUMENT_COUNT])
	assert(workspace_instance_count == EXPECTED_WORKSPACE_INSTANCE_COUNT,
		"workspace small_prop instance count %d/%d" % [workspace_instance_count, EXPECTED_WORKSPACE_INSTANCE_COUNT])
	assert(formal_keys.size() == EXPECTED_FORMAL_SMALL_COUNTS.size(),
		"formal small_prop map count drifted: %s" % str(formal_keys.keys()))
	for expected_key: String in EXPECTED_FORMAL_SMALL_COUNTS:
		assert(formal_keys.has(expected_key),
			"formal small_prop map missing: %s" % expected_key)
	assert(formal_runtime_count == EXPECTED_FORMAL_SMALL_COUNTS.size())
	assert(formal_instance_count == 98)
	assert(formal_actor_command_count == 98)
	assert(formal_geometry_pair_count == 98,
		"formal geometry pair count %d/98" % formal_geometry_pair_count)
	assert(formal_well_checked, "Bich well exact regression was not checked")

	print(
		"MSE_SMALL_PROP_OCCLUSION_AUTHORITY_PASS "
		+ "catalog=%d workspace_documents=%d workspace_instances=%d "
		+ "formal_runtime_maps=%d formal_runtime_instances=%d "
		+ "actor_y_sort_commands=%d geometry_pairs=%d bich_well=true"
		% [
			EXPECTED_SMALL_ASSET_COUNT,
			workspace_document_count,
			workspace_instance_count,
			formal_runtime_count,
			formal_instance_count,
			formal_actor_command_count,
			formal_geometry_pair_count,
		]
	)
	get_tree().quit(0)


func _assert_catalog_authority(catalog: Dictionary) -> void:
	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == EXPECTED_SMALL_ASSET_COUNT,
		"small_prop catalog count %d/%d" % [assets.size(), EXPECTED_SMALL_ASSET_COUNT])
	var seen := {}
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(asset_id.begins_with(SMALL_PREFIX), "unexpected catalog asset: %s" % asset_id)
		assert(not seen.has(asset_id), "duplicate catalog asset: %s" % asset_id)
		seen[asset_id] = true
		assert(str(asset.get("asset_type", "")) == "small_prop",
			"catalog asset type drifted: %s" % asset_id)
		assert(bool(asset.get("occlusion", false)),
			"catalog occlusion Authority is not true: %s" % asset_id)
	for index in EXPECTED_SMALL_ASSET_COUNT:
		assert(seen.has("%s%03d" % [SMALL_PREFIX, index + 1]),
			"catalog ID missing: %s%03d" % [SMALL_PREFIX, index + 1])
	for index in EXPECTED_SMALL_ASSET_COUNT:
		var resolved := MapAssetCatalogService.find_asset("%s%03d" % [SMALL_PREFIX, index + 1])
		assert(bool(resolved.get("occlusion", false)), "effective catalog lost occlusion")


func _assert_no_type_fallback() -> void:
	var synthetic_instance := {"instance_id": "future_small_prop", "asset_id": "future.small_prop"}
	var synthetic_asset := {"asset_type": "small_prop", "image": "future.png"}
	assert(not VisualGeometry.instance_is_occluder(synthetic_instance, synthetic_asset),
		"unknown small_prop was implicitly promoted by type")
	var explicit_instance := {"instance_id": "future_small_prop", "asset_id": "future.small_prop", "occlusion": true}
	assert(VisualGeometry.instance_is_occluder(explicit_instance, synthetic_asset),
		"explicit future small_prop Authority was not honored")


func _assert_bich_well(runtime: Dictionary, editor: Dictionary, commands: Array) -> void:
	var editor_well := _instance_by_id(
		_small_instances(MapEditorInstanceService.all_instances(editor)), "inst_000087"
	)
	var runtime_well := _instance_by_id(
		_small_instances(runtime.get("instances", [])), "inst_000087"
	)
	assert(str(editor_well.get("asset_id", "")) == "mse.small_decor.002")
	assert(str(runtime_well.get("asset_id", "")) == "mse.small_decor.002")
	assert(editor_well.get("tile", []) == [34.0, 37.0])
	assert(runtime_well.get("tile", []) == [34.0, 37.0])
	assert(editor_well.get("placement_anchor_px", []) == [171.0, 422.0])
	assert(runtime_well.get("placement_anchor_px", []) == [171.0, 422.0])
	var asset := MapAssetCatalogService.find_asset("mse.small_decor.002")
	var expected_foot := VisualGeometry.instance_foot_tile(runtime_well, asset)
	var expected_baseline := VisualGeometry.instance_sort_baseline_tile(runtime_well, asset)
	assert(expected_foot.is_equal_approx(Vector2(35.0, 38.0)))
	assert(expected_baseline.is_equal_approx(expected_foot),
		"Bich well baseline no longer follows authored visual foot")
	var well_command: Dictionary = {}
	for command: Dictionary in commands:
		if str(command.get("instance", {}).get("instance_id", "")) == "inst_000087":
			well_command = command
			break
	assert(not well_command.is_empty(), "Bich well draw command missing")
	assert(Vector2(well_command.get("sort_baseline_tile", Vector2.ZERO)).is_equal_approx(expected_baseline),
		"Bich well draw baseline diverged from authored foot")
	assert(str(well_command.get("render_domain", "")) == VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT)


func _strip_small_occlusion(document: Dictionary) -> Dictionary:
	var stripped := document.duplicate(true)
	for instance: Dictionary in MapEditorInstanceService.all_instances(stripped):
		if str(instance.get("asset_id", "")).begins_with(SMALL_PREFIX):
			instance.erase("occlusion")
	return stripped


func _geometry_projection(instance: Dictionary) -> Dictionary:
	var result := {}
	for field: String in [
		"instance_id", "asset_id", "layer", "tile", "tile_anchor",
		"footprint_tiles", "visual_footprint_tiles",
		"occupancy_footprint_tiles", "base_footprint_tiles", "offset_px",
		"anchor_px", "placement_anchor_px", "scale", "rotation_deg",
		"flip_x", "flip_y", "material_layer_order",
		"adaptive_corner_sort_tile_offset", "placement_rule",
		"collision_policy", "collision_footprint_tiles", "collision_cells",
		"navigation_policy", "map_collision_override",
	]:
		if instance.has(field):
			result[field] = instance[field]
	return result


func _small_instances(instances: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not instances is Array:
		return result
	for raw: Variant in instances:
		if raw is Dictionary and str(raw.get("asset_id", "")).begins_with(SMALL_PREFIX):
			result.append(raw)
	return result


func _by_instance_id(instances: Array[Dictionary]) -> Dictionary:
	var result := {}
	for instance: Dictionary in instances:
		result[str(instance.get("instance_id", ""))] = instance
	return result


func _instance_by_id(instances: Array[Dictionary], instance_id: String) -> Dictionary:
	for instance: Dictionary in instances:
		if str(instance.get("instance_id", "")) == instance_id:
			return instance
	return {}


func _collect_editor_paths(root: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root)
	if directory == null:
		return result
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name in [".", ".."]:
			continue
		var child := root.path_join(name)
		if directory.current_is_dir():
			result.append_array(_collect_editor_paths(child))
		elif name.ends_with(".editor.json"):
			result.append(child)
	directory.list_dir_end()
	result.sort()
	return result


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
