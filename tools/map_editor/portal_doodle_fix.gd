extends SceneTree

## Portal-doodle occlusion fix v2 (geometric ground truth).
##
## v1 failed the user: it flagged only doodles whose ANCHOR TILE equals the
## portal visual's tile. chiyue_valley's graffiti is anchored one tile up-left
## of the portal ([21,117] vs [22,118]) and its 3x3 visual still covers the
## portal - anchor equality is not the occlusion relation.
##
## v2 detects the actual occlusion relation the way the renderer does:
##   1. build the authoritative painter order via
##      MapEditorRuntimeVisualGeometryService.sorted_draw_commands
##   2. world rects per command (texture size + runtime_command_geometry)
##   3. a doodle COVERS a portal iff some doodle command paints AFTER the
##      portal's last command and their world rects intersect
## This is self-idempotent: after the fix the doodle paints before the
## portal, so it is no longer "covering" and will not be re-flagged.
##
## Transform scope stays the user's demonstrated class: mse.ground_graffiti.*
## (move material_layer_order strictly below the portal's, shrink 10% x3 =
## instance_scale_level -3 + instance_custom_scale true). Other covering
## instances are reported only.
##
## Modes:
##   godot --headless -s tools/map_editor/portal_doodle_fix.gd -- scan
##   godot --headless -s tools/map_editor/portal_doodle_fix.gd -- apply
##   godot --headless -s tools/map_editor/portal_doodle_fix.gd -- verify

const REGISTRY_PATH := "res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
const PORTAL_ASSET_PREFIX := "user.portal_gate."
const DOODLE_ASSET_PREFIX := "mse.ground_graffiti."


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "scan"
	if args.size() >= 1:
		mode = args[0]
	assert(mode in ["scan", "apply", "verify"], "mode must be scan|apply|verify")
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		REGISTRY_PATH
	))
	var totals := {
		"maps": 0, "portals": 0, "covering": 0, "fixed": 0, "other": 0,
	}
	for entry: Dictionary in registry.get("maps", []):
		var map_key := str(entry.get("map_key", ""))
		_process_map(map_key, mode, totals)
	print(
		"PORTAL_DOODLE2_%s maps=%d portals=%d covering=%d fixed=%d other=%d" % [
			mode.to_upper(), int(totals["maps"]), int(totals["portals"]),
			int(totals["covering"]), int(totals["fixed"]), int(totals["other"]),
		]
	)
	quit(0)


func _process_map(map_key: String, mode: String, totals: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(
		"res://map_editor_workspace/%s/%s.editor.json" % [map_key, map_key]
	)
	if not FileAccess.file_exists(path):
		return
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var object_base: Array = doc.get("layers", {}).get("object_base", [])
	if object_base.is_empty():
		return
	var design: Array = doc.get("design", {}).get("design_size", [32, 64])
	var design_size := Vector2i(
		int(design[0]) if design.size() > 0 else 32,
		int(design[1]) if design.size() > 1 else 64
	)
	var commands := MapEditorRuntimeVisualGeometryService.sorted_draw_commands(
		object_base
	)
	if commands.is_empty():
		return
	# Portal visual instance ids and their last command index (paint order).
	var portal_last_index := {}
	var doodle_commands: Array[Dictionary] = []
	var texture_sizes := {}
	for index: int in commands.size():
		var command: Dictionary = commands[index]
		var instance_id := str(command.get("instance", {}).get(
			"instance_id", ""
		))
		var asset_id := str(command.get("instance", {}).get("asset_id", ""))
		if asset_id.begins_with(PORTAL_ASSET_PREFIX):
			portal_last_index[instance_id] = index
		elif asset_id.begins_with(DOODLE_ASSET_PREFIX):
			var image_path := str(command.get("image_path", ""))
			if not texture_sizes.has(image_path):
				var size := _load_texture_size(image_path)
				texture_sizes[image_path] = size
			var rect := _command_world_rect(
				command, design_size, texture_sizes[image_path]
			)
			if rect.size.x > 0.0:
				doodle_commands.append({
					"instance_id": instance_id,
					"index": index,
					"rect": rect,
					"asset_id": asset_id,
				})
	totals["portals"] = int(totals["portals"]) + portal_last_index.size()
	if portal_last_index.is_empty() or doodle_commands.is_empty():
		return
	# Portal world rects (union of their commands).
	var portal_rects := {}
	for index: int in commands.size():
		var command: Dictionary = commands[index]
		var instance_id := str(command.get("instance", {}).get(
			"instance_id", ""
		))
		if not portal_last_index.has(instance_id):
			continue
		var image_path := str(command.get("image_path", ""))
		if not texture_sizes.has(image_path):
			texture_sizes[image_path] = _load_texture_size(image_path)
		var rect := _command_world_rect(
			command, design_size, texture_sizes[image_path]
		)
		if rect.size.x <= 0.0:
			continue
		if not portal_rects.has(instance_id):
			portal_rects[instance_id] = rect
		else:
			portal_rects[instance_id] = (portal_rects[instance_id] as Rect2).merge(
				rect
			)
	# Covering detection: doodle command after portal's last command,
	# rects intersect.
	var covering_by_doodle := {}
	var other_covering := {}
	for portal_id: String in portal_last_index:
		var portal_last := int(portal_last_index[portal_id])
		var portal_rect: Rect2 = portal_rects.get(portal_id, Rect2())
		if portal_rect.size.x <= 0.0:
			continue
		for doodle: Dictionary in doodle_commands:
			if int(doodle["index"]) <= portal_last:
				continue
			if not (doodle["rect"] as Rect2).intersects(portal_rect):
				continue
			covering_by_doodle[str(doodle["instance_id"])] = portal_id
	if covering_by_doodle.is_empty():
		return
	totals["maps"] = int(totals["maps"]) + 1
	var object_index := {}
	for instance: Dictionary in object_base:
		object_index[str(instance.get("instance_id", ""))] = instance
	var portal_min_mlo := {}
	for doodle_id: String in covering_by_doodle:
		var doodle: Dictionary = object_index.get(doodle_id, {})
		var asset_id := str(doodle.get("asset_id", ""))
		var portal_id := str(covering_by_doodle[doodle_id])
		if not asset_id.begins_with(DOODLE_ASSET_PREFIX):
			totals["other"] = int(totals["other"]) + 1
			print(
				"PORTAL_DOODLE2_OTHER map=%s doodle=%s(%s) covers=%s (left untouched)" % [
					map_key, doodle_id, asset_id, portal_id,
				]
			)
			continue
		if mode == "apply":
			var portal: Dictionary = object_index.get(portal_id, {})
			var portal_mlo := float(portal.get("material_layer_order", 0.0))
			var depth := int(portal_min_mlo.get(portal_id, 0)) + 1
			portal_min_mlo[portal_id] = depth
			doodle["instance_custom_scale"] = true
			doodle["instance_scale_level"] = (
				int(doodle.get("instance_scale_level", 0)) - 3
			)
			doodle["material_layer_order"] = portal_mlo - float(depth)
			totals["fixed"] = int(totals["fixed"]) + 1
			print(
				"PORTAL_DOODLE2_FIXED map=%s doodle=%s asset=%s mlo->%s scale_level->%d covers=%s" % [
					map_key, doodle_id, asset_id,
					str(doodle["material_layer_order"]),
					int(doodle["instance_scale_level"]), portal_id,
				]
			)
		else:
			totals["covering"] = int(totals["covering"]) + 1
			print(
				"PORTAL_DOODLE2_HIT map=%s doodle=%s(%s) tile=%s covers=%s" % [
					map_key, doodle_id, asset_id,
					str(doodle.get("tile", [])), portal_id,
				]
			)
	if mode == "apply":
		var out := FileAccess.open(path, FileAccess.WRITE)
		assert(out != null, "cannot write %s" % path)
		out.store_string(JSON.stringify(doc, "  ") + "\n")
		out.close()


func _command_world_rect(
	command: Dictionary,
	design_size: Vector2i,
	texture_size: Vector2i
) -> Rect2:
	if texture_size.x <= 0:
		return Rect2()
	var geometry := MapEditorRuntimeVisualGeometryService.runtime_command_geometry(
		command,
		Vector2(design_size),
		Vector2(texture_size),
	)
	if geometry.is_empty():
		return Rect2()
	var center: Vector2 = geometry.get("center", Vector2.ZERO)
	var anchor: Vector2 = geometry.get("anchor", Vector2.ZERO)
	var scale: Vector2 = geometry.get("visual_scale", Vector2.ONE)
	var size := Vector2(texture_size) * scale
	return Rect2(center - anchor * scale, size)


func _load_texture_size(image_path: String) -> Vector2i:
	if image_path.is_empty():
		return Vector2i.ZERO
	var resolved := image_path
	if resolved.begins_with("res://"):
		resolved = ProjectSettings.globalize_path(resolved)
	var image := Image.load_from_file(resolved)
	if image == null:
		return Vector2i.ZERO
	return image.get_size()
