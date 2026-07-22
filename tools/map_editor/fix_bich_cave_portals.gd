extends SceneTree

const SOURCE_PATH := (
	"res://map_editor_workspace/bich_province/"
	+ "bich_province.editor.json"
)
const READY_MARKER_PATH := (
	"res://assets/data/runtime/map_editor/"
	+ "bich_province.manual_ready.json"
)
const POLICY_ID := "bich_cave_mouth_explicit_v1"
const VERSION_ID := "bich_cave_portals_v1"
const PORTAL_OFFSETS := {
	# Offsets are relative to the instance's top-left footprint tile.
	# 53/54: footprint centre (4,3) plus one tile toward the cave mouth.
	"inst_000001": Vector2i(5, 3),
	"inst_000002": Vector2i(5, 3),
	# 56: its opening is two tiles to the right of the footprint centre.
	"inst_000004": Vector2i(6, 3),
	"inst_000016": Vector2i(6, 3),
}


func _init() -> void:
	var loaded := MapEditorLoadService.load_document(SOURCE_PATH)
	if not bool(loaded.get("ok", false)):
		_fail("load_failed:%s" % loaded.get("errors", []))
		return
	var document: Dictionary = loaded.document
	for instance_id: String in PORTAL_OFFSETS:
		var configured := _configure_cave_instance(
			document,
			instance_id,
			PORTAL_OFFSETS[instance_id]
		)
		if not bool(configured.get("ok", false)):
			_fail("%s:%s" % [instance_id, configured.get("errors", [])])
			return

	var cleared_count := _clear_cave_footprint_collisions(document)
	var walkability := MapEditorCollisionService.build_walkability(document)
	for instance_id: String in PORTAL_OFFSETS:
		var located := MapEditorInstanceService._locate(document, instance_id)
		var instance: Dictionary = located.instance
		var tile: Array = instance.get("tile", [0, 0])
		var footprint: Array = instance.get("footprint_tiles", [1, 1])
		for y in int(footprint[1]):
			for x in int(footprint[0]):
				var key := "%d,%d" % [
					int(tile[0]) + x,
					int(tile[1]) + y,
				]
				if walkability.blocked_tiles.has(key):
					_fail("cave_collision_remains:%s:%s" % [instance_id, key])
					return

	var meta: Dictionary = document.get("editor_meta", {})
	if str(meta.get("bich_cave_portal_version_id", "")) != VERSION_ID:
		meta["revision"] = int(meta.get("revision", 1)) + 1
	meta["bich_cave_portal_version_id"] = VERSION_ID
	meta["bich_cave_portal_policy_id"] = POLICY_ID
	document["editor_meta"] = meta
	var approved := MapEditorBuildRuntimeService.approve_for_runtime(document)
	if not bool(approved.get("ok", false)):
		_fail("approval_failed:%s" % approved.get("errors", []))
		return
	var saved := MapEditorSaveService.save_document(document, SOURCE_PATH)
	if not bool(saved.get("ok", false)):
		_fail("save_failed:%s" % saved.get("errors", []))
		return
	var built := MapEditorBuildRuntimeService.build(document)
	if not bool(built.get("ok", false)):
		_fail("runtime_failed:%s" % built.get("errors", []))
		return
	var marker := _update_ready_marker(document, built.runtime)
	if not bool(marker.get("ok", false)):
		_fail("marker_failed:%s" % marker.get("errors", []))
		return
	var east_door := _door_for_visual(document, "inst_000002")
	print(
		(
			"BICH_CAVE_PORTALS_FIXED policy=%s east=%s "
			+ "collision_erases_added=%d revision=%d"
		)
		% [
			POLICY_ID,
			east_door.get("tile", []),
			cleared_count,
			int(document.editor_meta.revision),
		]
	)
	quit(0)


func _configure_cave_instance(
	document: Dictionary,
	instance_id: String,
	offset: Vector2i
) -> Dictionary:
	var located := MapEditorInstanceService._locate(document, instance_id)
	if not bool(located.get("ok", false)):
		return located
	var instance: Dictionary = located.instance
	instance["portal_trigger_offset_tiles"] = [offset.x, offset.y]
	instance["portal_trigger_policy_id"] = POLICY_ID
	instance["collision_policy"] = "none"
	instance["collision_profile_id"] = "none_visual"
	instance["collision_footprint_tiles"] = [0, 0]
	instance["collision_cells"] = []
	instance["navigation_policy"] = "ignore"
	instance["map_collision_override"] = "disabled"
	instance["collision_authority"] = "map_instance"
	instance["gameplay_role"] = "none"
	instance["scene_intent"] = "map_portal_visual"
	MapEditorInstanceService._located_replace(document, located, instance)
	var synchronized := MapEditorPortalAnchorService.synchronize_linked_semantics(
		document,
		instance_id
	)
	if not bool(synchronized.get("ok", false)):
		return synchronized
	var door := _door_for_visual(document, instance_id)
	door["portal_trigger_policy_id"] = POLICY_ID
	return {"ok": true, "tile": synchronized.get("tile", Vector2i.ZERO)}


func _clear_cave_footprint_collisions(document: Dictionary) -> int:
	var before := MapEditorCollisionService.build_walkability(document)
	var erased: Array = document.layers.get("collision_erase", [])
	var existing := {}
	for entry: Dictionary in erased:
		var tile: Array = entry.get("tile", [])
		if tile.size() == 2:
			existing["%d,%d" % [int(tile[0]), int(tile[1])]] = true
	var added := 0
	for instance_id: String in PORTAL_OFFSETS:
		var located := MapEditorInstanceService._locate(document, instance_id)
		var instance: Dictionary = located.instance
		var origin: Array = instance.get("tile", [0, 0])
		var footprint: Array = instance.get("footprint_tiles", [1, 1])
		for y in int(footprint[1]):
			for x in int(footprint[0]):
				var tile := Vector2i(int(origin[0]) + x, int(origin[1]) + y)
				var key := "%d,%d" % [tile.x, tile.y]
				if (
					not before.blocked_tiles.has(key)
					or existing.has(key)
				):
					continue
				erased.append({
					"tile": [tile.x, tile.y],
					"source": "bich_cave_no_collision",
					"linked_visual_instance_id": instance_id,
					"policy_id": POLICY_ID,
					"content_layer": "personal_expansion",
				})
				existing[key] = true
				added += 1
	document.layers["collision_erase"] = erased
	return added


func _door_for_visual(
	document: Dictionary,
	instance_id: String
) -> Dictionary:
	for door: Dictionary in document.layers.get("door_points", []):
		if str(door.get("linked_visual_instance_id", "")) == instance_id:
			return door
	return {}


func _update_ready_marker(
	document: Dictionary,
	runtime: Dictionary
) -> Dictionary:
	var file := FileAccess.open(READY_MARKER_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": ["ready_marker_missing"]}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"ok": false, "errors": ["ready_marker_invalid"]}
	var marker: Dictionary = parsed
	var east_door := _door_for_visual(document, "inst_000002")
	marker["runtime_build_sha256"] = str(runtime.get("build_sha256", ""))
	marker["bich_cave_portal_version_id"] = VERSION_ID
	marker.content["east_exit_tile"] = east_door.get("tile", []).duplicate()
	for connection: Dictionary in marker.content.get(
		"configured_connections",
		[]
	):
		if str(connection.get("door_id", "")) != "door_000002":
			continue
		connection["tile"] = east_door.get("tile", []).duplicate()
		connection["portal_trigger_policy_id"] = POLICY_ID
	return MapEditorGroundService._write_json_atomic(
		READY_MARKER_PATH,
		marker
	)


func _fail(message: String) -> void:
	push_error("BICH_CAVE_PORTALS_FAILED %s" % message)
	quit(1)
