extends Node

const APP_SOURCE := "res://scripts/map_editor/map_editor_app.gd"
const BUILD_SERVICE_SOURCE := (
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)
const BRIDGE_SOURCE := (
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := _read(APP_SOURCE)
	var build_service := _read(BUILD_SERVICE_SOURCE)
	var bridge := _read(BRIDGE_SOURCE)
	# MSE must expose the two-step flow and call the formal publish entry.
	for needle: String in [
		"构建 Runtime 候选",
		"发布为正式地图",
		"_on_build_candidate_pressed",
		"_on_publish_runtime_pressed",
		"build_candidate(",
		"publish_runtime_release(",
	]:
		assert(app.contains(needle), "map_editor_app.gd missing %s" % needle)
	# The old single-button Build-as-Publish path must be gone.
	for banned: String in [
		"_on_approve_and_build_runtime_pressed",
		"批准并构建 Runtime 快照",
	]:
		assert(
			not app.contains(banned),
			"map_editor_app.gd must not keep legacy approve+build button: %s" % banned
		)
	# Production service entry points exist.
	assert(build_service.contains("static func build_candidate("))
	assert(build_service.contains("static func publish_runtime_release("))
	# Production registry consumer runs the schema validator.
	assert(bridge.contains("validate_release_registry(parsed)"))
	print("MSE_PUBLISH_ENTRY_WIRED_PASS")
	get_tree().quit(0)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "missing source %s" % path)
	var text := file.get_as_text()
	file.close()
	return text
