extends Node


const IDENTITY_PATH := "res://assets/data/map_design/map_identity_registry.json"
const RELEASE_REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const VISUAL_CONTRACT_ID := "mse.map.runtime.visual.v1"
const FORMAL_GROUND_CHUNK_ROOT := "assets/data/runtime/map_editor/formal_ground_chunks/sha256/"
const EXPECTED_FORMAL_MAPS := 67
const EXPECTED_AUTHORED_CHUNKS := 445
const EXPECTED_UNIQUE_CHUNKS := 208


func _ready() -> void:
	var identity := _read_json(IDENTITY_PATH)
	var registry := _read_json(RELEASE_REGISTRY_PATH)
	assert(str(identity.get("contract_id", "")) == "hardcore.formal_map_identity.v1")
	assert(str(registry.get("registry_contract_id", "")) == "mse.map.runtime.release.v1")
	var identity_by_id := {}
	for entry: Dictionary in identity.get("maps", []):
		identity_by_id[int(entry.get("runtime_map_id", -1))] = str(entry.get("map_id", ""))
	var import_paths := {}
	var map_count := 0
	var authored_chunk_refs := 0
	for entry: Dictionary in registry.get("maps", []):
		var runtime_map_id := int(entry.get("runtime_map_id", -1))
		var map_key := str(entry.get("map_key", ""))
		assert(identity_by_id.get(runtime_map_id, "") == map_key, "release registry identity mismatch %d" % runtime_map_id)
		var manifest_path := "res://assets/data/runtime/map_editor/%s.visual.json" % map_key
		var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
		assert(manifest_file != null, "缺少地图视觉清单：%s" % manifest_path)
		var manifest: Variant = JSON.parse_string(manifest_file.get_as_text())
		manifest_file.close()
		assert(manifest is Dictionary, "地图视觉清单不是有效 JSON：%s" % manifest_path)
		assert(str(manifest.get("render_mode", "")) == "batched_canvas_draw")
		assert(str(manifest.get("visual_contract_id", "")) == VISUAL_CONTRACT_ID)
		assert(int(manifest.get("runtime_map_id", -1)) == runtime_map_id)
		assert(str(manifest.get("map_id", "")) == map_key)
		assert(bool(manifest.get("coverage", {}).get("complete", false)))
		for chunk: Dictionary in manifest.get("chunks", []):
			var image_path := str(chunk.get("image", ""))
			assert(image_path.begins_with(FORMAL_GROUND_CHUNK_ROOT), "正式视觉引用了非正式 chunk：%s" % image_path)
			assert(not image_path.contains("map_editor_workspace"), "正式视觉引用了 workspace：%s" % image_path)
			assert(FileAccess.file_exists("res://" + image_path), "正式视觉 chunk 缺失：%s" % image_path)
			import_paths[image_path] = true
			authored_chunk_refs += 1
		map_count += 1

	assert(map_count == EXPECTED_FORMAL_MAPS, "预期检查 67 个正式视觉地图，实际 %d" % map_count)
	assert(authored_chunk_refs == EXPECTED_AUTHORED_CHUNKS, "预期检查 445 个 authored chunk 引用，实际 %d" % authored_chunk_refs)
	assert(import_paths.size() == EXPECTED_UNIQUE_CHUNKS, "预期 SHA-256 去重后 208 个正式地图块，实际 %d" % import_paths.size())
	for image_path: String in import_paths:
		var import_path := "res://%s.import" % image_path
		var import_file := FileAccess.open(import_path, FileAccess.READ)
		assert(import_file != null, "地图块缺少持久导入规则：%s" % import_path)
		var settings := import_file.get_as_text()
		import_file.close()
		assert("compress/mode=2" in settings, "地图块未使用 VRAM Compressed：%s" % import_path)
		assert("mipmaps/generate=false" in settings, "地图块不应生成 mipmap：%s" % import_path)
		assert("\"vram_texture\": true" in settings, "地图块未生成 VRAM 纹理：%s" % import_path)
		assert(".etc2.ctex" in settings, "地图块未生成 Android ETC2 变体：%s" % import_path)

	print("MAP_ANDROID_VRAM_IMPORT_PASS maps=%d refs=%d unique_chunks=%d compression=VRAM_ETC2 mipmaps=false" % [map_count, authored_chunk_refs, import_paths.size()])
	get_tree().quit(0)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
