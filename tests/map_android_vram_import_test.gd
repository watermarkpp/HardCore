extends Node


const VISUAL_MANIFESTS := [
	"res://assets/data/runtime/map_editor/bich_province.visual.json",
	"res://assets/data/runtime/map_editor/wooma_forest.visual.json",
]


func _ready() -> void:
	var import_paths: Array[String] = []
	for manifest_path: String in VISUAL_MANIFESTS:
		var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
		assert(manifest_file != null, "缺少地图视觉清单：%s" % manifest_path)
		var manifest: Variant = JSON.parse_string(manifest_file.get_as_text())
		manifest_file.close()
		assert(manifest is Dictionary, "地图视觉清单不是有效 JSON：%s" % manifest_path)
		assert(str(manifest.get("render_mode", "")) == "batched_canvas_draw")
		for chunk: Dictionary in manifest.get("chunks", []):
			import_paths.append("res://%s.import" % str(chunk.get("image", "")))

	assert(import_paths.size() == 21, "预期检查 21 个移动端地图块导入规则，实际 %d" % import_paths.size())
	for import_path: String in import_paths:
		var import_file := FileAccess.open(import_path, FileAccess.READ)
		assert(import_file != null, "地图块缺少持久导入规则：%s" % import_path)
		var settings := import_file.get_as_text()
		import_file.close()
		assert("compress/mode=2" in settings, "地图块未使用 VRAM Compressed：%s" % import_path)
		assert("mipmaps/generate=false" in settings, "地图块不应生成 mipmap：%s" % import_path)
		assert("\"vram_texture\": true" in settings, "地图块未生成 VRAM 纹理：%s" % import_path)
		assert(".etc2.ctex" in settings, "地图块未生成 Android ETC2 变体：%s" % import_path)

	print("MAP_ANDROID_VRAM_IMPORT_PASS chunks=%d compression=VRAM_ETC2 mipmaps=false" % import_paths.size())
	get_tree().quit(0)
