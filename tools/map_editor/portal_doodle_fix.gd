extends SceneTree

## Portal-doodle occlusion fix across all released maps (user order
## 2026-09-16, replicating the user's own manual editor fix on the five
## mengzhong dark-zone maps).
##
## Detection: a portal point (map_exit_points / map_entrance_points) links
## its portal visual via linked_visual_instance_id. A doodle is an
## object_base decoration instance whose anchor tile equals the linked
## portal visual's tile (the exact relation in the user's own fix:
## mse.ground_graffiti.* on the portal tile, both material_layer_order 0,
## doodle painting after the portal and covering it).
##
## Transform (exactly the user's editor operations):
##   - "shrink 10% x3": instance_custom_scale = true, instance_scale_level
##     decremented by 3 (their fix set -3 on previously-unscaled doodles)
##   - "move down one layer": material_layer_order pushed strictly below
##     the portal visual's value; multiple doodles on one portal get
##     -1, -2, ... which reproduces the user's own -1/-2 outcome
## Doodles already carrying scale_level <= -3 are treated as user-fixed
## and skipped (the five dark-zone maps must not be double-shrunk).
## Doodles without a portal on their tile are never touched.
##
## Modes:
##   godot --headless -s tools/map_editor/portal_doodle_fix.gd -- scan
##   godot --headless -s tools/map_editor/portal_doodle_fix.gd -- apply

const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const PORTAL_POINT_COLLECTIONS := ["map_exit_points", "map_entrance_points"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "scan"
	if args.size() >= 1:
		mode = args[0]
	assert(mode == "scan" or mode == "apply", "mode must be scan|apply")
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		REGISTRY_PATH
	))
	var totals := {"maps": 0, "portals": 0, "found": 0, "changed": 0, "skipped_fixed": 0}
	for entry: Dictionary in registry.get("maps", []):
		var map_key := str(entry.get("map_key", ""))
		_process_map(map_key, mode, totals)
	print(
		"PORTAL_DOODLE_%s maps=%d portals=%d found=%d changed=%d already_fixed=%d" % [
			mode.to_upper(), int(totals["maps"]), int(totals["portals"]),
			int(totals["found"]), int(totals["changed"]),
			int(totals["skipped_fixed"]),
		]
	)
	quit(0)


func _process_map(map_key: String, mode: String, totals: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(
		"res://map_editor_workspace/%s/%s.editor.json" % [map_key, map_key]
	)
	if not FileAccess.file_exists(path):
		print("PORTAL_DOODLE_SKIP map=%s reason=no_editor_doc" % map_key)
		return
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var layer: Dictionary = doc.get("layers", {})
	var portals: Array[Dictionary] = []
	for collection_name: String in PORTAL_POINT_COLLECTIONS:
		var points: Variant = layer.get(collection_name, [])
		if points is Array:
			for point: Dictionary in points:
				var linked := str(point.get("linked_visual_instance_id", ""))
				if not linked.is_empty():
					portals.append({
						"point_id": str(point.get("exit_id", point.get(
							"entrance_id", ""
						))),
						"linked_instance_id": linked,
					})
	totals["portals"] = int(totals["portals"]) + portals.size()
	if portals.is_empty():
		return
	totals["maps"] = int(totals["maps"]) + 1
	var object_base: Array = layer.get("object_base", [])
	# Resolve each portal visual's tile and layer order.
	var portal_by_id := {}
	for portal: Dictionary in portals:
		for instance: Dictionary in object_base:
			if str(instance.get("instance_id", "")) == str(
				portal["linked_instance_id"]
			):
				portal["tile"] = instance.get("tile", [])
				portal["mlo"] = float(instance.get(
					"material_layer_order", 0.0
				))
				portal_by_id[str(portal["linked_instance_id"])] = portal
				break
	# Find doodles anchored on a portal tile.
	var changed := 0
	var skipped := 0
	var per_portal_depth := {}
	var dirty := false
	for instance: Dictionary in object_base:
		var instance_id := str(instance.get("instance_id", ""))
		if portal_by_id.has(instance_id):
			continue
		var tile: Variant = instance.get("tile", null)
		if tile == null or not (tile is Array) or (tile as Array).size() < 2:
			continue
		for portal: Dictionary in portal_by_id.values():
			if not portal.has("tile"):
				continue
			var portal_tile: Array = portal["tile"]
			if _tile_matches(tile, portal_tile):
				if int(instance.get("instance_scale_level", 0)) <= -3:
					skipped += 1
					print(
						"PORTAL_DOODLE_SKIP_FIXED map=%s doodle=%s asset=%s tile=%s" % [
							map_key, instance_id,
							str(instance.get("asset_id", "")), str(tile),
						]
					)
					break
				# Transform scope: graffiti doodles only (the user's
				# demonstrated asset class). Non-graffiti overlaps are
				# reported but never modified.
				var asset_id := str(instance.get("asset_id", ""))
				if not asset_id.begins_with("mse.ground_graffiti."):
					print(
						"PORTAL_DOODLE_OTHER map=%s doodle=%s asset=%s tile=%s (not graffiti, left untouched)" % [
							map_key, instance_id, asset_id, str(tile),
						]
					)
					break
				if mode == "apply":
					instance["instance_custom_scale"] = true
					instance["instance_scale_level"] = (
						int(instance.get("instance_scale_level", 0)) - 3
					)
					var depth := int(per_portal_depth.get(
						str(portal["linked_instance_id"]), 0
					)) + 1
					per_portal_depth[str(portal["linked_instance_id"])] = depth
					var current_mlo := float(instance.get(
						"material_layer_order", 0.0
					))
					if current_mlo >= float(portal.get("mlo", 0.0)):
						instance["material_layer_order"] = (
							float(portal.get("mlo", 0.0)) - float(depth)
						)
					dirty = true
				changed += 1
				print(
					"PORTAL_DOODLE_HIT map=%s portal=%s(%s) doodle=%s asset=%s tile=%s" % [
						map_key, str(portal["point_id"]),
						str(portal["linked_instance_id"]), instance_id,
						str(instance.get("asset_id", "")),
						str(tile),
					]
				)
				break
	totals["found"] = int(totals["found"]) + changed + skipped
	totals["skipped_fixed"] = int(totals["skipped_fixed"]) + skipped
	if mode == "apply" and dirty:
		changed = changed
		var out := FileAccess.open(path, FileAccess.WRITE)
		assert(out != null, "cannot write %s" % path)
		out.store_string(JSON.stringify(doc, "  ") + "\n")
		out.close()
		totals["changed"] = int(totals["changed"]) + changed
		print("PORTAL_DOODLE_SAVED map=%s changed=%d" % [map_key, changed])


func _tile_matches(a: Variant, b: Array) -> bool:
	if not (a is Array) or (a as Array).size() < 2:
		return false
	return int(a[0]) == int(b[0]) and int(a[1]) == int(b[1])
