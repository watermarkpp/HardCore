extends Node

const Policy := preload("res://scripts/map_editor/map_editor_connection_policy_service.gd")
const Collision := preload("res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd")
const Background := preload("res://scripts/world_background.gd")
const Spatial := preload("res://scripts/world_spatial_rules.gd")

var failures: Array[String] = []
var rows: Array = []

func _ready() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _read(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _run() -> void:
	var identity := _read("res://assets/data/map_design/map_identity_registry.json")
	var entries: Array = identity.get("maps", [])
	_expect(entries.size() == 67, "formal identity coverage must remain 67")
	var endpoint_count := 0
	var one_way_fixture := {}
	for entry: Dictionary in entries:
		var key := str(entry.map_id)
		var map_id := int(entry.runtime_map_id)
		var source := _read("res://map_editor_workspace/%s/%s.editor.json" % [key, key])
		var source_errors := Policy.validate_document(source)
		_expect(source_errors.is_empty(), "%s authoring policy: %s" % [key, source_errors])
		for endpoint: Dictionary in source.get("layers", {}).get("map_exit_points", []):
			if one_way_fixture.is_empty() and bool(endpoint.get("one_way", false)) and str(endpoint.get("portal_role", "")) == "one_way_endpoint":
				one_way_fixture = endpoint.duplicate(true)
		var runtime := MapEditorRuntimeBridge.load_map(map_id)
		_expect(not runtime.is_empty(), "%s must load through the formal consumer" % key)
		if runtime.is_empty():
			continue
		var compiled := Collision.compile_runtime_collision(runtime, map_id)
		_expect(bool(compiled.get("ok", false)), "%s collision compile: %s" % [key, compiled.get("errors", [])])
		if not bool(compiled.get("ok", false)):
			continue
		var background := Background.new()
		background._editor_runtime_collision_snapshot = compiled.snapshot
		background._editor_runtime_size = compiled.snapshot.design_size
		for endpoint: Dictionary in runtime.get("semantics", {}).get("map_exit_points", []):
			endpoint_count += 1
			var ground := MapEditorRuntimeBridge.cell_to_ground_position_gu(endpoint.tile)
			var screen := MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px(runtime, ground)
			# The production WorldBackground footprint query uses the same
			# compiled polygons and 18px player ellipse as movement/teleport.
			var blocked := Spatial.environment_blocks_actor_screen_px(background, screen, ArtSpec.PLAYER_COLLISION_RADIUS_PX)
			_expect(not blocked, "%s::%s player footprint blocked" % [key, endpoint.semantic_id])
			rows.append({"map_key": key, "runtime_map_id": map_id, "portal_id": endpoint.semantic_id,
				"tile": endpoint.tile, "player_radius_px": ArtSpec.PLAYER_COLLISION_RADIUS_PX,
				"blocked": blocked, "authoring_errors": source_errors})
		background.free()
	_expect(endpoint_count == 132, "all 132 source/arrival footprints must be checked")
	_expect(not one_way_fixture.is_empty(), "real one-way positive control missing")
	if not one_way_fixture.is_empty():
		var positive := {"layers": {"map_exit_points": [one_way_fixture]}}
		_expect(Policy.validate_document(positive).is_empty(), "real positive one-way fixture must validate")
		for fault: Dictionary in [{"one_way": false}, {"portal_role": "bidirectional_endpoint"}, {"explicit_one_way_reason": " \t "}]:
			var broken := positive.duplicate(true)
			(broken.layers.map_exit_points[0] as Dictionary).merge(fault, true)
			_expect(not Policy.validate_document(broken).is_empty(), "one-way malformed field accepted: %s" % fault)
	var report := {"maps": entries.size(), "endpoints": endpoint_count, "rows": rows, "failures": failures,
		"scope": "Real formal loader, authoring policy and production 18px footprint queries; not 132 physical walks or device acceptance."}
	FileAccess.open("res://outputs/test_logs/portal_all_map_authoring_footprint.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	for failure: String in failures:
		printerr("PORTAL_ALL_MAP_AUTHORING_FOOTPRINT_FAIL ", failure)
	print("PORTAL_ALL_MAP_AUTHORING_FOOTPRINT_%s maps=%d endpoints=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", entries.size(), endpoint_count, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
