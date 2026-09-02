class_name MapUIPresentationProjection
extends RefCounted

const CONTRACT_ID := "ui.map.presentation_projection.v1"


static func from_runtime(runtime: Dictionary) -> Dictionary:
	var semantics: Dictionary = runtime.get("semantics", {})
	var monster_names: Array[String] = []
	var boss_names: Array[String] = []
	var npc_kinds: Array[String] = []
	var portals: Array[Dictionary] = []
	for raw_spawn: Variant in semantics.get("monster_spawn", []):
		if raw_spawn is Dictionary:
			_append_unique_name(monster_names, raw_spawn as Dictionary)
	for raw_boss: Variant in semantics.get("boss_spawn", []):
		if raw_boss is Dictionary:
			_append_unique_name(boss_names, raw_boss as Dictionary)
	for raw_npc: Variant in semantics.get("npc_points", []):
		if not raw_npc is Dictionary:
			continue
		var kind := str((raw_npc as Dictionary).get("service_role", "dialogue")).strip_edges()
		if not kind.is_empty() and not npc_kinds.has(kind):
			npc_kinds.append(kind)
	for portal_group: String in ["door_points", "map_exit_points"]:
		for raw_portal: Variant in semantics.get(portal_group, []):
			if not raw_portal is Dictionary:
				continue
			var portal: Dictionary = raw_portal
			var target_map_id := int(portal.get("target_map_id", -1))
			if not bool(portal.get("target_configured", true)) or target_map_id <= 0:
				continue
			portals.append({
				"target_map_id": target_map_id,
				"target_map_key": str(portal.get("target_map_key", "")),
				"label": str(portal.get("display_name", portal.get("label", ""))).strip_edges(),
			})
	return {
		"contract_id": CONTRACT_ID,
		"runtime_build_sha256": str(runtime.get("build_sha256", "")),
		"monster_names": monster_names,
		"boss_names": boss_names,
		"npc_kinds": npc_kinds,
		"has_safe_area": not (semantics.get("safe_area", []) as Array).is_empty(),
		"portals": portals,
	}


static func validate(projection: Dictionary, approved_build_sha256: String) -> Array[String]:
	var errors: Array[String] = []
	if str(projection.get("contract_id", "")) != CONTRACT_ID:
		errors.append("map_ui_projection_contract_invalid")
	if approved_build_sha256.is_empty() or str(projection.get("runtime_build_sha256", "")) != approved_build_sha256:
		errors.append("map_ui_projection_build_hash_mismatch")
	for field: String in ["monster_names", "boss_names", "npc_kinds", "portals"]:
		if not projection.get(field, null) is Array:
			errors.append("map_ui_projection_%s_invalid" % field)
	for raw_portal: Variant in projection.get("portals", []):
		if not raw_portal is Dictionary or int((raw_portal as Dictionary).get("target_map_id", -1)) <= 0:
			errors.append("map_ui_projection_portal_invalid")
	return errors


static func content_from_projection(projection: Dictionary) -> Dictionary:
	var approved_hash := str(projection.get("runtime_build_sha256", ""))
	if not validate(projection, approved_hash).is_empty():
		return {}
	var spawns: Array[Dictionary] = []
	for raw_name: Variant in projection.get("monster_names", []):
		var display_name := str(raw_name).strip_edges()
		if not display_name.is_empty():
			spawns.append({"name": display_name, "display_name": display_name})
	var bosses: Array[Dictionary] = []
	for raw_name: Variant in projection.get("boss_names", []):
		var display_name := str(raw_name).strip_edges()
		if not display_name.is_empty():
			bosses.append({"name": display_name, "display_name": display_name})
	var npcs: Array[Dictionary] = []
	for raw_kind: Variant in projection.get("npc_kinds", []):
		var kind := str(raw_kind).strip_edges()
		if not kind.is_empty():
			npcs.append({"kind": kind})
	return {
		"spawns": spawns,
		"bosses": bosses,
		"npcs": npcs,
		"portals": (projection.get("portals", []) as Array).duplicate(true),
		"safe_areas": [{}] if bool(projection.get("has_safe_area", false)) else [],
	}


static func _append_unique_name(target: Array[String], source: Dictionary) -> void:
	var display_name := str(source.get("display_name", source.get("name", ""))).strip_edges()
	if not display_name.is_empty() and not target.has(display_name):
		target.append(display_name)
