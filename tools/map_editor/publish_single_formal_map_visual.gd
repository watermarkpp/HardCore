extends Node

const IDENTITY_PATH := "res://assets/data/map_design/map_identity_registry.json"
const PublisherScript := preload(
	"res://tools/map_editor/publish_formal_map_releases.gd"
)


func _ready() -> void:
	var map_key := _argument_value("--map=")
	if map_key.is_empty():
		_fail("missing --map=<formal_map_key>", 2)
		return
	var identity := _read_json(IDENTITY_PATH)
	var identity_entry := {}
	for raw_entry: Variant in identity.get("maps", []):
		if raw_entry is Dictionary and str(raw_entry.get("map_id", "")) == map_key:
			identity_entry = raw_entry
			break
	if identity_entry.is_empty():
		_fail("unknown formal map: %s" % map_key, 3)
		return
	var runtime_map_id := int(identity_entry.get("runtime_map_id", -1))
	if runtime_map_id <= 0:
		_fail("invalid runtime map id: %s" % map_key, 4)
		return
	var editor_path := (
		"res://map_editor_workspace/%s/%s.editor.json" % [map_key, map_key]
	)
	if not FileAccess.file_exists(editor_path):
		_fail("editor document missing: %s" % editor_path, 5)
		return

	# Reuse the exact production visual publisher without entering its full
	# 67-map runtime/registry transaction. This path writes only the requested
	# visual JSON and content-addressed ground PNGs.
	var publisher: Node = PublisherScript.new()
	var result: Dictionary = publisher._publish_formal_visual(
		map_key,
		runtime_map_id,
		editor_path
	)
	publisher.free()
	if not bool(result.get("ok", false)):
		_fail(
			"publish failed: %s" % str(result.get("errors", [])),
			6
		)
		return
	print(
		"PUBLISH_SINGLE_FORMAL_MAP_VISUAL_PASS map=%s runtime_map_id=%d chunks=%d"
		% [map_key, runtime_map_id, int(result.get("chunk_count", 0))]
	)
	get_tree().quit(0)


func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _fail(message: String, code: int) -> void:
	printerr("PUBLISH_SINGLE_FORMAL_MAP_VISUAL_FAIL %s" % message)
	get_tree().quit(code)
