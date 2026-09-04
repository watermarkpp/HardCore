extends Node

## Exact single-target formal release: editor source -> candidate -> validate ->
## visual rehash -> runtime promotion -> release-registry commit.
##
## This tool accepts one allow-listed formal map per invocation.  A repair
## cannot accidentally reset or republish the complete 67-map registry.

const FORMAL_TARGET_COUNTS := {
	"world_bich_province": Vector2i(82, 0),
	"world_cangyue_island": Vector2i(37, 0),
	"world_wooma_forest": Vector2i(50, 4),
	"bich_orc_tomb_f1": Vector2i(40, 0),
}
const IDENTITY_PATH := "res://assets/data/map_design/map_identity_registry.json"
const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const PublisherScript := preload(
	"res://tools/map_editor/publish_formal_map_releases.gd"
)
const SpawnIdentityService := preload(
	"res://scripts/map_editor/map_editor_spawn_identity_service.gd"
)


func _ready() -> void:
	var map_key := _argument_value("--map=")
	if not FORMAL_TARGET_COUNTS.has(map_key):
		_fail("exact formal target required: --map=<allow-listed map>", 2)
		return
	var editor_path := (
		"res://map_editor_workspace/%s/%s.editor.json" % [map_key, map_key]
	)
	var identity := _read_json(IDENTITY_PATH)
	var identity_maps: Variant = identity.get("maps", [])
	if not identity_maps is Array:
		_fail("formal identity registry invalid", 3)
		return
	var runtime_map_id := -1
	for raw_identity: Variant in identity_maps:
		if raw_identity is Dictionary and str(raw_identity.get("map_id", "")) == map_key:
			runtime_map_id = int(raw_identity.get("runtime_map_id", -1))
			break
	if runtime_map_id <= 0:
		_fail("formal runtime id missing", 4)
		return
	var raw_document := _read_json(editor_path)
	if raw_document.is_empty():
		_fail("editor source missing", 5)
		return
	var source_layers: Dictionary = raw_document.get("layers", {})
	var expected_counts: Vector2i = FORMAL_TARGET_COUNTS[map_key]
	if (
		(source_layers.get("monster_spawn", []) as Array).size() != expected_counts.x
		or (source_layers.get("boss_spawn", []) as Array).size() != expected_counts.y
	):
		_fail("target placement count changed", 6)
		return
	var source_identity_errors := SpawnIdentityService.validate_document(
		raw_document,
		true
	)
	if not source_identity_errors.is_empty():
		_fail("source identity invalid:%s" % str(source_identity_errors), 7)
		return

	var publisher: Node = PublisherScript.new()
	var prepared: Dictionary = publisher.prepare_formal_document(
		map_key,
		runtime_map_id,
		raw_document,
		identity_maps as Array
	)
	if not bool(prepared.get("ok", false)):
		publisher.free()
		_fail("prepare failed:%s" % str(prepared.get("errors", [])), 8)
		return
	var document: Dictionary = prepared.get("document", {})
	var approval := BuildService.approve_for_runtime(document)
	if not bool(approval.get("ok", false)):
		publisher.free()
		_fail("approval failed:%s" % str(approval.get("errors", [])), 9)
		return
	var candidate := BuildService.build_candidate(document)
	if not bool(candidate.get("ok", false)):
		publisher.free()
		_fail("candidate build failed:%s" % str(candidate.get("errors", [])), 10)
		return
	var visual: Dictionary = publisher._publish_formal_visual(
		map_key,
		runtime_map_id,
		editor_path
	)
	if not bool(visual.get("ok", false)):
		publisher.free()
		_fail("visual rehash failed:%s" % str(visual.get("errors", [])), 11)
		return
	var published := BuildService.publish_runtime_release(
		str(candidate.get("candidate_path", "")),
		runtime_map_id,
		candidate.get("document_binding", {}),
		REGISTRY_PATH,
		map_key
	)
	publisher.free()
	if not bool(published.get("success", false)):
		_fail("runtime publish failed:%s" % str(published), 12)
		return
	var runtime_path := BuildService.default_runtime_path(map_key)
	var runtime_file := FileAccess.open(runtime_path, FileAccess.READ)
	var runtime: Dictionary = JSON.parse_string(runtime_file.get_as_text()) if runtime_file != null else {}
	var runtime_errors := SpawnIdentityService.validate_runtime(runtime, true)
	if not runtime_errors.is_empty():
		_fail("published runtime identity invalid:%s" % str(runtime_errors), 13)
		return
	var runtime_layers: Dictionary = runtime.get("semantics", {})
	print(
		"PUBLISH_SINGLE_FORMAL_MAP_RELEASE_PASS map=%s runtime_map_id=%d monster_spawn=%d boss_spawn=%d build_sha256=%s approval_revision=%d"
		% [
			map_key,
			runtime_map_id,
			(runtime_layers.get("monster_spawn", []) as Array).size(),
			(runtime_layers.get("boss_spawn", []) as Array).size(),
			str(published.get("approved_build_sha256", "")),
			int(published.get("approval_revision", 0)),
		]
	)
	get_tree().quit(0)


func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _fail(message: String, code: int) -> void:
	printerr("PUBLISH_SINGLE_FORMAL_MAP_RELEASE_FAIL %s" % message)
	get_tree().quit(code)
