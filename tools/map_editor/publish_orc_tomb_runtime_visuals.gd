extends SceneTree

const VISUAL_CONTRACT_ID := "orc_tomb_editor_runtime_visual_v1"
const MAPS := [
	{"map_id": "orc_tomb_1", "runtime_map_id": 217},
	{"map_id": "orc_tomb_2", "runtime_map_id": 218},
	{"map_id": "orc_tomb_3", "runtime_map_id": 221},
]


func _init() -> void:
	var total_chunks := 0
	for config: Dictionary in MAPS:
		var result := _publish(config)
		if not bool(result.get("ok", false)):
			push_error(
				"ORC_TOMB_VISUAL_PUBLISH_FAILED %s:%s"
				% [config.map_id, result.get("errors", [])]
			)
			quit(1)
			return
		total_chunks += int(result.chunk_count)
		print(
			"ORC_TOMB_VISUAL_PUBLISHED map=%s runtime=%d chunks=%d"
			% [config.map_id, int(config.runtime_map_id), int(result.chunk_count)]
		)
	print(
		"ORC_TOMB_VISUALS_PASS contract=%s maps=3 chunks=%d"
		% [VISUAL_CONTRACT_ID, total_chunks]
	)
	quit(0)


func _publish(config: Dictionary) -> Dictionary:
	var map_id := str(config.map_id)
	var workspace_root := "res://map_editor_workspace/%s" % map_id
	var editor_path := "%s/%s.editor.json" % [workspace_root, map_id]
	var manifest_path := workspace_root + "/ground/ground_manifest.json"
	var ground_manifest := _read_json(manifest_path)
	if ground_manifest.is_empty():
		return {"ok": false, "errors": ["ground_manifest_missing"]}
	var output_root := (
		"res://assets/art/maps/orc_tomb/editor_runtime_chunks/%s" % map_id
	)
	var mkdir := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(output_root)
	)
	if mkdir != OK:
		return {"ok": false, "errors": ["output_mkdir_failed:%d" % mkdir]}
	var published_chunks: Array = []
	for chunk: Dictionary in ground_manifest.get("chunks", []):
		var preview_path := str(chunk.get("preview_png", ""))
		if preview_path.is_empty():
			continue
		var rect: Array = chunk.get("rect_px", [])
		if rect.size() != 4:
			return {"ok": false, "errors": ["invalid_chunk_rect"]}
		var source_path := workspace_root + "/" + preview_path
		if not FileAccess.file_exists(source_path):
			return {"ok": false, "errors": ["chunk_source_missing:%s" % source_path]}
		var destination_path := output_root + "/" + preview_path.get_file()
		var copy := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(source_path),
			ProjectSettings.globalize_path(destination_path)
		)
		if copy != OK:
			return {"ok": false, "errors": ["chunk_copy_failed:%d" % copy]}
		var sha := FileAccess.get_sha256(destination_path)
		if sha.is_empty() or sha != FileAccess.get_sha256(source_path):
			return {"ok": false, "errors": ["chunk_hash_mismatch"]}
		published_chunks.append({
			"chunk_id": str(chunk.get("chunk_id", "")),
			"rect_px": rect.duplicate(),
			"image": destination_path.trim_prefix("res://"),
			"sha256": sha,
		})
	var pixel_size: Array = ground_manifest.get("ground_pixel_size", [])
	if pixel_size.size() != 2 or published_chunks.is_empty():
		return {"ok": false, "errors": ["publishable_ground_missing"]}
	var visual := {
		"schema_version": 1,
		"visual_contract_id": VISUAL_CONTRACT_ID,
		"map_id": map_id,
		"runtime_map_id": int(config.runtime_map_id),
		"source_editor_document_sha256": FileAccess.get_sha256(editor_path),
		"source_ground_manifest_sha256": FileAccess.get_sha256(manifest_path),
		"design_size": ground_manifest.get("design_size", []).duplicate(),
		"ground_pixel_size": pixel_size.duplicate(),
		"ground_pixel_center": [
			float(pixel_size[0]) * 0.5,
			float(pixel_size[1]) * 0.5,
		],
		"base_color": "#16120e",
		"guard_band_px": 512.0,
		"render_mode": "batched_canvas_draw",
		"coverage": {
			"source_chunk_count": ground_manifest.get("chunks", []).size(),
			"required_chunk_count": published_chunks.size(),
			"packaged_chunk_count": published_chunks.size(),
			"complete": true,
		},
		"chunks": published_chunks,
	}
	var write := MapEditorGroundService._write_json_atomic(
		"res://assets/data/runtime/map_editor/%s.visual.json" % map_id,
		visual
	)
	if not bool(write.get("ok", false)):
		return write
	return {"ok": true, "chunk_count": published_chunks.size()}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
