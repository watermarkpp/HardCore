extends SceneTree

const OFFICIAL_VERSION_ID := "bich_orc_tomb_official_v1"
const MAP_IDS := [
	"bich_province",
	"orc_tomb_1",
	"orc_tomb_2",
	"orc_tomb_3",
]
const BICH_READY_MARKER := (
	"res://assets/data/runtime/map_editor/"
	+ "bich_province.manual_ready.json"
)


func _init() -> void:
	var documents := {}
	for map_id: String in MAP_IDS:
		var loaded := MapEditorLoadService.load_document(
			MapEditorSaveService.default_path(map_id)
		)
		if not bool(loaded.get("ok", false)):
			_fail("%s_load_failed:%s" % [map_id, loaded.get("errors", [])])
			return
		documents[map_id] = loaded.document

	var bich: Dictionary = documents["bich_province"]
	var floor_one: Dictionary = documents["orc_tomb_1"]
	var floor_two: Dictionary = documents["orc_tomb_2"]
	var floor_three: Dictionary = documents["orc_tomb_3"]
	var portal_result := _synchronize_bich_portals(bich, floor_one)
	if not bool(portal_result.get("ok", false)):
		_fail("bich_portals:%s" % portal_result.get("errors", []))
		return
	if not _validate_tomb_links(floor_one, floor_two, floor_three):
		return
	_refresh_wall_structure_metadata(floor_one)
	_refresh_wall_structure_metadata(floor_two)
	_refresh_wall_structure_metadata(floor_three)

	var built_runtimes := {}
	for map_id: String in MAP_IDS:
		var document: Dictionary = documents[map_id]
		var initialized := MapEditorGroundService.initialize(document)
		if not bool(initialized.get("ok", false)):
			_fail("%s_ground_init:%s" % [map_id, initialized.get("errors", [])])
			return
		var bake := MapEditorChunkBakeService.bake_dirty_chunks(document)
		if not bool(bake.get("ok", false)):
			_fail("%s_ground_bake:%s" % [map_id, bake.get("errors", [])])
			return
		var meta: Dictionary = document.get("editor_meta", {})
		if str(meta.get("official_version_id", "")) != OFFICIAL_VERSION_ID:
			meta["revision"] = int(meta.get("revision", 1)) + 1
		meta["official_version_id"] = OFFICIAL_VERSION_ID
		meta["official_source_authority"] = "user_saved_editor_document"
		meta["official_runtime_map_id"] = int(document.get("runtime_map_id", 0))
		document["editor_meta"] = meta
		var approval := MapEditorBuildRuntimeService.approve_for_runtime(document)
		if not bool(approval.get("ok", false)):
			_fail("%s_runtime_approval:%s" % [map_id, approval.get("errors", [])])
			return
		var saved := MapEditorSaveService.save_document(
			document,
			MapEditorSaveService.default_path(map_id)
		)
		if not bool(saved.get("ok", false)):
			_fail("%s_save:%s" % [map_id, saved.get("errors", [])])
			return
		var built := MapEditorBuildRuntimeService.build(document)
		if not bool(built.get("ok", false)):
			_fail("%s_runtime_build:%s" % [map_id, built.get("errors", [])])
			return
		built_runtimes[map_id] = built.runtime
		print(
			"OFFICIAL_MAP_RUNTIME_BUILT map=%s revision=%d instances=%d npcs=%d"
			% [
				map_id,
				int(document.editor_meta.revision),
				built.runtime.get("instances", []).size(),
				built.runtime.get("semantics", {}).get("npc_points", []).size(),
			]
		)

	var marker_result := _write_bich_ready_marker(
		bich,
		built_runtimes["bich_province"],
		portal_result.east_door
	)
	if not bool(marker_result.get("ok", false)):
		_fail("bich_ready_marker:%s" % marker_result.get("errors", []))
		return
	print(
		(
			"BICH_ORC_TOMB_OFFICIAL_PASS version=%s "
			+ "bich_exit=%s tomb_npcs=%d,%d links=3"
		)
		% [
			OFFICIAL_VERSION_ID,
			portal_result.east_door.tile,
			floor_two.layers.npc_points.size(),
			floor_three.layers.npc_points.size(),
		]
	)
	quit(0)


func _synchronize_bich_portals(
	bich: Dictionary,
	floor_one: Dictionary
) -> Dictionary:
	var doors: Array = bich.get("layers", {}).get("door_points", [])
	if doors.size() != 4:
		return {"ok": false, "errors": ["bich_requires_four_portals"]}
	for door: Dictionary in doors:
		var visual_id := str(door.get("linked_visual_instance_id", ""))
		if visual_id.is_empty():
			return {
				"ok": false,
				"errors": ["bich_portal_visual_missing:%s" % door.get("semantic_id", "")],
			}
		var synchronized := MapEditorPortalAnchorService.synchronize_linked_semantics(
			bich,
			visual_id
		)
		if not bool(synchronized.get("ok", false)):
			return synchronized
	doors = bich.layers.door_points
	var east_index := 0
	var east_score := -1_000_000
	for index in doors.size():
		var tile: Array = doors[index].get("tile", [0, 0])
		var score := int(tile[0]) - int(tile[1])
		if score > east_score:
			east_score = score
			east_index = index
	var entrances: Array = floor_one.get("layers", {}).get(
		"map_entrance_points",
		[]
	)
	if entrances.size() != 1:
		return {"ok": false, "errors": ["orc_tomb_1_requires_one_entrance"]}
	var entrance: Dictionary = entrances[0]
	var entrance_id := str(
		entrance.get("entrance_id", entrance.get("semantic_id", ""))
	)
	var east_door: Dictionary = doors[east_index]
	east_door["target_configured"] = true
	east_door["target_map_id"] = int(floor_one.get("runtime_map_id", 217))
	east_door["target_map_key"] = str(floor_one.get("map_id", "orc_tomb_1"))
	east_door["target_entrance_id"] = entrance_id
	east_door["target_tile"] = entrance.get("tile", [0, 0]).duplicate()
	east_door["display_name"] = "进入兽人古墓一层"
	east_door["official_connection_id"] = "bich_east_to_orc_tomb_1_v1"
	doors[east_index] = east_door
	bich.layers["door_points"] = doors
	return {
		"ok": true,
		"east_door": east_door,
		"east_index": east_index,
	}


func _validate_tomb_links(
	floor_one: Dictionary,
	floor_two: Dictionary,
	floor_three: Dictionary
) -> bool:
	var floors := [floor_one, floor_two, floor_three]
	for index in floors.size():
		var document: Dictionary = floors[index]
		if document.layers.map_entrance_points.size() != 1:
			_fail("%s_entrance_count" % document.map_id)
			return false
		var expected_exits := 1 if index < floors.size() - 1 else 0
		if document.layers.map_exit_points.size() != expected_exits:
			_fail("%s_exit_count" % document.map_id)
			return false
		if index >= floors.size() - 1:
			continue
		var target: Dictionary = floors[index + 1]
		var map_exit: Dictionary = document.layers.map_exit_points[0]
		var target_entrance: Dictionary = target.layers.map_entrance_points[0]
		if (
			str(map_exit.get("target_map_id", "")) != str(target.map_id)
			or str(map_exit.get("target_entrance_id", ""))
			!= str(target_entrance.get("entrance_id", ""))
		):
			_fail("%s_link_invalid" % document.map_id)
			return false
	return true


func _refresh_wall_structure_metadata(document: Dictionary) -> void:
	var design: Dictionary = document.get("design", {})
	var loops: Array = design.get("wall_loops", [])
	for index in loops.size():
		var loop: Dictionary = loops[index]
		var bounds_raw: Array = loop.get("bounds", [])
		if bounds_raw.size() != 4:
			continue
		var validation := MapEditorWallLoopService.validate_closed_rectangle(
			document,
			str(loop.get("wall_family_id", "")),
			Rect2i(
				int(bounds_raw[0]),
				int(bounds_raw[1]),
				int(bounds_raw[2]),
				int(bounds_raw[3])
			),
			str(loop.get("structure_id", ""))
		)
		loop["strict_closed_perimeter"] = bool(
			validation.get("ok", false)
		)
		loop["topology_status"] = (
			"closed"
			if bool(validation.get("ok", false))
			else "user_customized_opening"
		)
		loop["validation_contract_id"] = "wall_loop_perimeter_v1"
		loops[index] = loop
	design["wall_loops"] = loops
	document["design"] = design


func _write_bich_ready_marker(
	bich: Dictionary,
	runtime: Dictionary,
	east_door: Dictionary
) -> Dictionary:
	var configured := []
	for door: Dictionary in bich.layers.door_points:
		if not bool(door.get("target_configured", false)):
			continue
		configured.append({
			"door_id": str(door.get("semantic_id", "")),
			"tile": door.get("tile", [0, 0]).duplicate(),
			"linked_visual_instance_id": str(
				door.get("linked_visual_instance_id", "")
			),
			"portal_anchor_contract_id": str(
				door.get("portal_anchor_contract_id", "")
			),
			"portal_visual_origin_tile": (
				door.get("portal_visual_origin_tile", [0, 0]).duplicate()
			),
			"target_map_id": int(door.get("target_map_id", -1)),
			"target_map_key": str(door.get("target_map_key", "")),
			"target_entrance_id": str(door.get("target_entrance_id", "")),
			"target_tile": door.get("target_tile", [0, 0]).duplicate(),
		})
	var marker := {
		"schema_version": 1,
		"map_id": "bich_province",
		"runtime_map_id": int(bich.get("runtime_map_id", 4)),
		"source_workspace": "map_editor_workspace/bich_province",
		"status": "user_confirmed_official_80x80",
		"official_version_id": OFFICIAL_VERSION_ID,
		"runtime_build_sha256": str(runtime.get("build_sha256", "")),
		"content": {
			"design_size": bich.design.design_size.duplicate(),
			"instances": runtime.get("instances", []).size(),
			"monster_spawns": runtime.semantics.monster_spawn.size(),
			"npcs": runtime.semantics.npc_points.size(),
			"doors": runtime.semantics.door_points.size(),
			"doors_pending_target_configuration": (
				bich.layers.door_points.size() - configured.size()
			),
			"configured_connections": configured,
			"east_exit_tile": east_door.get("tile", [0, 0]).duplicate(),
		},
	}
	return MapEditorGroundService._write_json_atomic(BICH_READY_MARKER, marker)


func _fail(message: String) -> void:
	push_error("BICH_ORC_TOMB_OFFICIAL_FAILED %s" % message)
	quit(1)
