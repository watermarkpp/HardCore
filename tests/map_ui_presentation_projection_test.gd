extends Node

const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	Bridge.invalidate_release_registry()
	var released_ids := Bridge.released_map_ids()
	assert(released_ids.size() == 67, "UI projection must cover all 67 released maps")
	assert(Bridge.debug_runtime_cache_size() == 0, "registry read must not parse runtime maps")
	for map_id: int in released_ids:
		var cache_before_lookup := Bridge.debug_runtime_cache_size()
		var lightweight := Bridge.map_ui_content_for_map(map_id)
		assert(not lightweight.is_empty(), "missing lightweight UI projection: %d" % map_id)
		assert(Bridge.debug_runtime_cache_size() == cache_before_lookup, "lightweight UI lookup parsed a runtime map: %d" % map_id)
		var full := Bridge.game_content_for_map(map_id)
		assert(not full.is_empty(), "released runtime failed to load: %d" % map_id)
		assert(_record_names(lightweight.get("spawns", [])) == _record_names(full.get("spawns", [])), "monster summary drift: %d" % map_id)
		assert(_record_names(lightweight.get("bosses", [])) == _record_names(full.get("bosses", [])), "boss summary drift: %d" % map_id)
		assert(_npc_kinds(lightweight.get("npcs", [])) == _npc_kinds(full.get("npcs", [])), "NPC summary drift: %d" % map_id)
		assert(_portal_summaries(lightweight.get("portals", [])) == _portal_summaries(full.get("portals", [])), "portal summary drift: %d" % map_id)
		assert((not lightweight.get("safe_areas", []).is_empty()) == (not full.get("safe_areas", []).is_empty()), "safe-area summary drift: %d" % map_id)
	Bridge.invalidate_release_registry()
	var panel := MapPanel.new()
	add_child(panel)
	await get_tree().process_frame
	var counters := panel.debug_operation_counters()
	assert(Bridge.debug_runtime_cache_size() == 0, "MapPanel cold construction parsed full runtime maps")
	assert(int(counters.get("presentation_catalog_hits", 0)) == released_ids.size(), "MapPanel did not use every UI projection")
	assert(int(counters.get("presentation_catalog_misses", 0)) == 0, "MapPanel projection fallback occurred")
	assert(int(counters.get("runtime_content_resolves", 0)) == 0, "MapPanel cold construction resolved full runtime content")
	print("MAP_UI_PRESENTATION_PROJECTION_PASS maps=%d runtime_cache=0" % released_ids.size())
	get_tree().quit(0)


func _record_names(raw_records: Variant) -> Array[String]:
	var names: Array[String] = []
	for raw_record: Variant in raw_records:
		if not raw_record is Dictionary:
			continue
		var name := str((raw_record as Dictionary).get("display_name", (raw_record as Dictionary).get("name", ""))).strip_edges()
		if not name.is_empty() and not names.has(name):
			names.append(name)
	names.sort()
	return names


func _npc_kinds(raw_records: Variant) -> Array[String]:
	var kinds: Array[String] = []
	for raw_record: Variant in raw_records:
		if not raw_record is Dictionary:
			continue
		var kind := str((raw_record as Dictionary).get("kind", "")).strip_edges()
		if not kind.is_empty() and not kinds.has(kind):
			kinds.append(kind)
	kinds.sort()
	return kinds


func _portal_summaries(raw_records: Variant) -> Array[String]:
	var summaries: Array[String] = []
	for raw_record: Variant in raw_records:
		if not raw_record is Dictionary:
			continue
		var record: Dictionary = raw_record
		summaries.append("%d|%s|%s" % [
			int(record.get("target_map_id", -1)),
			str(record.get("target_map_key", "")),
			str(record.get("label", "")),
		])
	summaries.sort()
	return summaries
