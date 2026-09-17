extends SceneTree
## One-off validation of MapEditorWallRenderCompiler against real maps:
## partition accounting closure, 1/N-layer coverage, paging bounds, digest
## stability, and one materialize smoke (shadow chunks + atlas pages).

const COMPILER := preload(
	"res://scripts/map_editor/map_editor_wall_render_compiler.gd"
)

var _image_cache := {}


func _init() -> void:
	var service := load(
		"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
	)
	var failed := false
	for map_key: String in ["mengzhong_dark_area", "chiyue_valley"]:
		var runtime_path := (
			"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
		)
		var raw := _read_json(runtime_path)
		if raw.is_empty():
			print("WCOMPILER missing runtime: ", map_key)
			failed = true
			continue
		var instances: Array = raw.get("instances", [])
		var commands: Array = service.sorted_draw_commands(instances)
		var plan: Dictionary = COMPILER.compile_plan(
			commands,
			Vector2i(
				int(raw.get("design_size", [64, 64])[0]),
				int(raw.get("design_size", [64, 64])[1])
			),
			func(path: String) -> Vector2i:
				var image: Image = _load_image(path)
				return Vector2i.ZERO if image == null else image.get_size()
		)
		var accounting: Dictionary = plan["accounting"]
		var sum: int = (
			int(accounting["atlas_commands"])
			+ int(accounting["shadow_chunk_commands"])
			+ int(accounting["legacy_commands"])
		)
		var closure := sum == int(accounting["total_commands"])
		var digest_again: String = COMPILER.commands_digest(commands)
		var digest_stable: bool = digest_again == plan["source_commands_sha256"]
		var pages_ok := true
		for page: Dictionary in plan["atlas_pages"]:
			if int(page["height"]) > COMPILER.PAGE_MAX_HEIGHT:
				pages_ok = false
		var demoted := 0
		for entry: Dictionary in plan["atlas_entries"]:
			if int(entry["page"]) < 0:
				demoted += 1
		print(
			"WCOMPILER %s total=%d atlas=%d chunk=%d legacy=%d closure=%s single_layer_covered=%s digest_stable=%s pages=%d pages_ok=%s oversized_entries=%d" % [
				map_key, accounting["total_commands"],
				accounting["atlas_commands"],
				accounting["shadow_chunk_commands"],
				accounting["legacy_commands"], str(closure),
				str(int(accounting["atlas_commands"]) > 0),
				str(digest_stable), plan["atlas_pages"].size(),
				str(pages_ok), demoted,
			]
		)
		if not closure or not digest_stable or not pages_ok:
			failed = true
		var materialized: Dictionary = COMPILER.materialize(
			plan, commands, _load_image
		)
		print(
			"WCOMPILER %s materialized chunks=%d pages=%d" % [
				map_key, materialized["shadow_chunks"].size(),
				materialized["atlas_pages"].size(),
			]
		)
	print("WCOMPILER_RESULT ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _load_image(path: String) -> Image:
	if _image_cache.has(path):
		return _image_cache[path]
	var image: Image = null
	var resource_path := path if path.begins_with("res://") else (
		"res://" + path.lstrip("/")
	)
	if ResourceLoader.exists(resource_path):
		var texture: Texture2D = load(resource_path)
		if texture != null:
			image = texture.get_image()
	if image != null and image.is_compressed():
		image.decompress()
	_image_cache[path] = image
	return image


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
