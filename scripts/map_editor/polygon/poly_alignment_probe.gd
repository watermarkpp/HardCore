extends Node2D
## Opt-in actual-node evidence. No per-frame work in normal gameplay.
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const Visual := preload("res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd")
var outlines: Array[PackedVector2Array] = []

static func instance_projection_error(instance: Dictionary, asset: Dictionary, size_gu: Vector2i, texture_size := Vector2(128, 160)) -> float:
	var editor := Visual.editor_instance_geometry(instance, asset, size_gu, Vector2.ZERO, 1.0, texture_size)
	var runtime := Visual.runtime_instance_geometry(instance, asset, size_gu, texture_size)
	var editor_center: Vector2 = editor.center - Coord.ground_pixel_center(size_gu)
	var error := editor_center.distance_to(runtime.center)
	var a := Transform2D(editor.rotation, editor.visual_scale, 0.0, editor_center)
	var b := Transform2D(runtime.rotation, runtime.visual_scale, 0.0, runtime.center)
	for corner: Vector2 in [Vector2.ZERO, Vector2(texture_size.x, 0), texture_size, Vector2(0, texture_size.y)]:
		error = maxf(error, (a * (corner - editor.anchor)).distance_to(b * (corner - runtime.anchor)))
	return error

static func world_corners(geometry: Dictionary, texture_size: Vector2) -> PackedVector2Array:
	var transform := Transform2D(geometry.rotation, geometry.visual_scale, 0.0, geometry.center)
	var result := PackedVector2Array()
	for corner: Vector2 in [Vector2.ZERO, Vector2(texture_size.x, 0), texture_size, Vector2(0, texture_size.y)]:
		result.append(transform * (corner - geometry.anchor))
	return result

static func actual_art_report(background: Variant) -> Dictionary:
	var pending: Array[Node] = []
	pending.append(background.get_parent() if background.get_parent() != null else background)
	var count := 0
	var error := 0.0
	var bad: Array[String] = []
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.is_queued_for_deletion():
			continue
		for child: Node in node.get_children():
			pending.append(child)
		if not node is Sprite2D or not node.has_meta("hc_expected_visual_corners_world"):
			continue
		if int(node.get_meta("hc_precision_generation", -1)) != background._generation_token():
			continue
		var sprite := node as Sprite2D
		if sprite.texture == null:
			bad.append(str(sprite.name))
			continue
		var expected: PackedVector2Array = sprite.get_meta("hc_expected_visual_corners_world")
		var size_px := sprite.texture.get_size()
		var corners := PackedVector2Array([Vector2.ZERO, Vector2(size_px.x,0), size_px, Vector2(0,size_px.y)])
		if expected.size() != 4 or sprite.centered:
			bad.append(str(sprite.name))
			continue
		for i: int in range(4):
			error = maxf(error, (sprite.global_transform * (corners[i] + sprite.offset)).distance_to(expected[i]))
		count += 1
	return {"ok": bad.is_empty() and error <= .01, "checked_art_sprites":count,
		"max_actual_art_corner_error_px":error, "invalid_art_sprites":bad}

static func actual_physics_report(background: Variant) -> Dictionary:
	var count := 0
	var error := 0.0
	var bad: Array[String] = []
	for body: Node in background.get_children():
		if not body is StaticBody2D or not body.has_meta("hc_polygon_expected_world"):
			continue
		var expected: PackedVector2Array = body.get_meta("hc_polygon_expected_world")
		for shape_node: Node in body.get_children():
			if not shape_node is CollisionShape2D or not (shape_node as CollisionShape2D).shape is ConvexPolygonShape2D:
				continue
			var actual: PackedVector2Array = ((shape_node as CollisionShape2D).shape as ConvexPolygonShape2D).points
			if actual.size() != expected.size():
				bad.append(str(body.name))
				continue
			for i: int in range(actual.size()):
				error = maxf(error, ((shape_node as CollisionShape2D).global_transform * actual[i]).distance_to(expected[i]))
			count += 1
	return {"ok": bad.is_empty() and error <= 0.01, "checked_physics_shapes": count,
		"max_actual_physics_vertex_error_px": error, "invalid_shapes": bad}

static func attach_if_enabled(background: Variant) -> void:
	if OS.get_environment("HC_POLYGON_DEBUG") != "1":
		return
	var snapshot: Dictionary = background.get("_editor_runtime_collision_snapshot")
	if not snapshot.has("poly_index"):
		return
	var overlay_script: Script = load("res://scripts/map_editor/polygon/poly_alignment_probe.gd")
	var overlay: Variant = overlay_script.new()
	overlay.name = "HCCollisionAlignmentOverlay"
	overlay.top_level = true
	overlay.z_index = 4000
	for polygon: PackedVector2Array in snapshot.poly_index.parts:
		var world := PackedVector2Array()
		for p: Vector2 in polygon:
			world.append(Coord.ground_position_gu_to_screen_position_px(p, snapshot.design_size))
		overlay.outlines.append(world)
	background.add_child(overlay)
	background._environment_nodes.append(overlay)
	background.get_tree().debug_collisions_hint = true
	var report := actual_physics_report(background)
	var art := actual_art_report(background)
	report["art"] = art
	report["ok"] = bool(report.ok) and bool(art.ok)
	if int(report.checked_physics_shapes) != snapshot.poly_index.parts.size():
		report["ok"] = false
		report["missing_physics_shapes"] = true
	report["runtime_map_id"] = snapshot.runtime_map_id
	report["build_sha256"] = snapshot.build_sha256
	report["note"] = "cyan=published exact polygons; engine wireframe=actual physics; actor foot radius is not obstacle translation"
	background.set_meta("hc_collision_alignment_report", report)
	print("HC_COLLISION_ALIGNMENT " + JSON.stringify(report, "", true, true))
	overlay.queue_redraw()

func _draw() -> void:
	for p: PackedVector2Array in outlines:
		if p.size() < 3:
			continue
		var closed := p.duplicate()
		closed.append(p[0])
		draw_polyline(closed, Color(0.1, 1.0, 1.0, 0.9), 1.0, true)
