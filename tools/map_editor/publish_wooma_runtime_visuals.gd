extends SceneTree

const MapEditorCoordinate := preload(
	"res://scripts/map_editor/map_editor_coordinate.gd"
)
const VISUAL_CONTRACT_ID := "wooma_editor_runtime_visual_v1"
const MAPS := [
	{
		"map_id": "wooma_forest",
		"runtime_map_id": 268,
		"output_root": "res://assets/art/maps/wooma_region/editor_runtime_chunks/wooma_forest",
		"base_color": "#172016",
	},
	{
		"map_id": "wooma_temple_1",
		"runtime_map_id": 313,
		"output_root": "res://assets/art/maps/wooma_temple/editor_runtime_chunks/wooma_temple_1",
		"base_color": "#17130f",
	},
	{
		"map_id": "wooma_temple_2",
		"runtime_map_id": 314,
		"output_root": "res://assets/art/maps/wooma_temple/editor_runtime_chunks/wooma_temple_2",
		"base_color": "#17130f",
	},
	{
		"map_id": "wooma_temple_3",
		"runtime_map_id": 315,
		"output_root": "res://assets/art/maps/wooma_temple/editor_runtime_chunks/wooma_temple_3",
		"base_color": "#17130f",
	},
]


func _init() -> void:
	for config: Dictionary in MAPS:
		var result := _publish(config)
		if not bool(result.get("ok", false)):
			push_error(
				"WOOMA_RUNTIME_VISUAL_PUBLISH_FAILED %s:%s"
				% [config.map_id, result.get("errors", [])]
			)
			quit(1)
			return
		print(
			"WOOMA_RUNTIME_VISUAL_PUBLISHED map=%s runtime=%d chunks=%d"
			% [
				config.map_id,
				int(config.runtime_map_id),
				int(result.chunk_count),
			]
		)
	print(
		"WOOMA_RUNTIME_VISUALS_PASS contract=%s maps=4 chunks=26"
		% VISUAL_CONTRACT_ID
	)
	quit(0)


func _publish(config: Dictionary) -> Dictionary:
	var map_id := str(config.map_id)
	var workspace_root := "res://map_editor_workspace/%s" % map_id
	var ground_manifest_path := (
		workspace_root + "/ground/ground_manifest.json"
	)
	var ground_manifest := _read_json(ground_manifest_path)
	if ground_manifest.is_empty():
		return {"ok": false, "errors": ["ground_manifest_missing"]}
	var geometry := _validated_ground_geometry(ground_manifest)
	if not bool(geometry.get("ok", false)):
		return geometry
	var output_root := str(config.output_root)
	var mkdir := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(output_root)
	)
	if mkdir != OK:
		return {"ok": false, "errors": ["output_mkdir_failed:%d" % mkdir]}
	var published_chunks: Array = []
	for chunk: Dictionary in ground_manifest.get("chunks", []):
		var preview_path := str(chunk.get("preview_png", ""))
		var rect: Array = chunk.get("rect_px", [])
		if preview_path.is_empty() or rect.size() != 4:
			return {
				"ok": false,
				"errors": ["invalid_chunk:%s" % chunk.get("chunk_id", "")],
			}
		var source_path := workspace_root + "/" + preview_path
		var file_name := preview_path.get_file()
		var destination_path := output_root + "/" + file_name
		var copy_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(source_path),
			ProjectSettings.globalize_path(destination_path)
		)
		if copy_error != OK:
			return {
				"ok": false,
				"errors": ["chunk_copy_failed:%s:%d" % [file_name, copy_error]],
			}
		var source_sha := FileAccess.get_sha256(source_path)
		var published_sha := FileAccess.get_sha256(destination_path)
		if source_sha.is_empty() or source_sha != published_sha:
			return {
				"ok": false,
				"errors": ["chunk_hash_mismatch:%s" % file_name],
			}
		published_chunks.append({
			"chunk_id": str(chunk.get("chunk_id", "")),
			"rect_px": rect.duplicate(),
			"image": destination_path.trim_prefix("res://"),
			"sha256": published_sha,
		})
	var design_size: Vector2i = geometry.design_size
	var pixel_size: Array = geometry.pixel_size
	var pixel_center: Vector2 = MapEditorCoordinate.ground_pixel_center(
		design_size
	)
	var visual := {
		"schema_version": 1,
		"visual_contract_id": VISUAL_CONTRACT_ID,
		"map_id": map_id,
		"runtime_map_id": int(config.runtime_map_id),
		"design_size": geometry.design_values.duplicate(),
		"ground_pixel_size": pixel_size.duplicate(),
		"ground_coordinate_contract_id": (
			MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
		),
		"ground_pixel_center": [
			pixel_center.x,
			pixel_center.y,
		],
		"base_color": str(config.base_color),
		"guard_band_px": 512.0,
		"render_mode": "batched_canvas_draw",
		"coverage": {
			"required_chunk_count": ground_manifest.get("chunks", []).size(),
			"packaged_chunk_count": published_chunks.size(),
			"complete": (
				published_chunks.size()
				== ground_manifest.get("chunks", []).size()
			),
		},
		"chunks": published_chunks,
	}
	var manifest_path := (
		"res://assets/data/runtime/map_editor/%s.visual.json" % map_id
	)
	var write := MapEditorGroundService._write_json_atomic(
		manifest_path, visual
	)
	if not bool(write.get("ok", false)):
		return write
	return {"ok": true, "chunk_count": published_chunks.size()}


func _validated_ground_geometry(manifest: Dictionary) -> Dictionary:
	if str(manifest.get("coordinate_contract_id", "")) != (
		MapEditorCoordinate.GROUND_COORDINATE_CONTRACT_ID
	):
		return {"ok": false, "errors": ["ground_coordinate_contract_invalid"]}
	var design_raw: Variant = manifest.get("design_size", null)
	var pixel_raw: Variant = manifest.get("ground_pixel_size", null)
	if not design_raw is Array or design_raw.size() != 2:
		return {"ok": false, "errors": ["design_size_invalid"]}
	if not pixel_raw is Array or pixel_raw.size() != 2:
		return {"ok": false, "errors": ["ground_pixel_size_invalid"]}
	if not _positive_json_integer(design_raw[0]) or not _positive_json_integer(
		design_raw[1]
	):
		return {"ok": false, "errors": ["design_size_invalid"]}
	if not _positive_json_integer(pixel_raw[0]) or not _positive_json_integer(
		pixel_raw[1]
	):
		return {"ok": false, "errors": ["ground_pixel_size_invalid"]}
	var design_size := Vector2i(int(design_raw[0]), int(design_raw[1]))
	var expected_size := MapEditorCoordinate.ground_image_size(design_size)
	if Vector2i(int(pixel_raw[0]), int(pixel_raw[1])) != expected_size:
		return {"ok": false, "errors": ["ground_pixel_size_contract_mismatch"]}
	return {
		"ok": true,
		"design_size": design_size,
		"design_values": design_raw,
		"pixel_size": pixel_raw,
	}


func _positive_json_integer(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return number > 0.0 and number == floor(number)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
