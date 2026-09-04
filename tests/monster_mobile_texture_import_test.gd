extends Node


const MONSTER_ART_ROOT := "res://assets/art/monsters"
const BASELINE_ATLAS_COUNT := 580


func _ready() -> void:
	var import_paths: Array[String] = []
	_collect_import_paths(MONSTER_ART_ROOT, import_paths)
	assert(import_paths.size() >= BASELINE_ATLAS_COUNT, "monster atlas import coverage unexpectedly shrank: %d" % import_paths.size())
	for path: String in import_paths:
		var file := FileAccess.open(path, FileAccess.READ)
		assert(file != null, "cannot read monster texture import policy: %s" % path)
		var content := file.get_as_text()
		assert(content.contains("compress/mode=0"), "monster atlas is not lossless-compressed: %s" % path)
		assert(content.contains("path=\"res://.godot/imported/"), "monster atlas has no lossless payload: %s" % path)
		assert(content.contains("\"vram_texture\": false"), "monster atlas still requests fixed-block VRAM compression: %s" % path)
		assert(not content.contains("path.s3tc="), "monster atlas still has a desktop VRAM variant: %s" % path)
		assert(not content.contains("path.etc2="), "monster atlas still has an Android ETC2 variant: %s" % path)
		assert(not content.contains("\"imported_formats\":"), "monster atlas still declares VRAM formats: %s" % path)
		assert(content.contains("mipmaps/generate=false"), "pixel-art atlas unexpectedly enables mipmaps: %s" % path)
	print("MONSTER_LOSSLESS_TEXTURE_IMPORT_PASS %d atlases preserve source resolution without fixed-block padding" % import_paths.size())
	get_tree().quit(0)


func _collect_import_paths(directory_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	assert(directory != null, "cannot scan monster art directory: %s" % directory_path)
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child_path := directory_path.path_join(entry)
		if directory.current_is_dir():
			_collect_import_paths(child_path, output)
		elif entry.ends_with(".png.import"):
			output.append(child_path)
		entry = directory.get_next()
	directory.list_dir_end()
