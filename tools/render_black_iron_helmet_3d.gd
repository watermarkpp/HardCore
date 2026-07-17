extends SceneTree

const BASELINE_PATH := "res://outputs/resource_catalog/black_iron_helmet/death_pose_baseline.json"
const BODY_PATH := "res://assets/art/characters/warrior/male/warrior_death.png"
const OUTPUT_ROOT := "res://outputs/visual_acceptance/black_iron_helmet_3d"
const CELL := Vector2i(192, 160)
const RENDER_SIZE := Vector2i(192, 192)
const DIRECTION_NAMES := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]

var viewport: SubViewport
var helmet_root: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline := _load_json(BASELINE_PATH)
	if baseline.is_empty():
		push_error("Missing or invalid death pose baseline")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	_setup_renderer()
	await process_frame
	RenderingServer.force_draw(false)

	var death_atlas := Image.create(CELL.x * 4, CELL.y * 8, false, Image.FORMAT_RGBA8)
	death_atlas.fill(Color(0, 0, 0, 0))
	var rendered_records: Array[Dictionary] = []
	for untyped_record in baseline.get("records", []):
		var record: Dictionary = untyped_record
		var pose: Dictionary = record.get("recommendedGodotPose", {})
		var direction := int(record.get("directionRow", -1))
		var frame := int(record.get("frame", -1))
		if direction < 0 or direction >= 8 or frame < 0 or frame >= 4:
			push_error("Invalid pose record: %s" % record)
			quit(1)
			return
		var yaw := float(pose.get("yawDegrees", 0.0))
		var fall := float(pose.get("fallDegrees", 0.0))
		var rendered := await _render_pose(yaw, fall)
		var used := rendered.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			push_error("Godot produced an empty helmet render")
			quit(1)
			return
		var crop := rendered.get_region(used)
		var width_summary: Dictionary = record.get("clientHelmetWidth", {})
		var height_summary: Dictionary = record.get("clientHelmetHeight", {})
		var target_size := Vector2i(
			maxi(1, roundi(float(width_summary.get("median", 18.0)))),
			maxi(1, roundi(float(height_summary.get("median", 19.0))))
		)
		var opaque_summary: Dictionary = record.get("clientHelmetOpaquePixels", {})
		var target_opaque_pixels := float(opaque_summary.get("median", target_size.x * target_size.y * 0.5))
		var fitted := _fit_image(crop, target_size, target_opaque_pixels)
		var client_centroid: Dictionary = record.get("clientHelmetCentroid", {})
		var client_x: Dictionary = client_centroid.get("x", {})
		var client_y: Dictionary = client_centroid.get("y", {})
		var hair_centroid: Array = record.get("hairAnchorCentroid", [96.0, 80.0])
		var centre := Vector2(
			float(client_x.get("median", hair_centroid[0])),
			float(client_y.get("median", hair_centroid[1]))
		)
		var paste := Vector2i(
			roundi(centre.x - fitted.get_width() * 0.5),
			roundi(centre.y - fitted.get_height() * 0.5)
		)
		death_atlas.blend_rect(
			fitted,
			Rect2i(Vector2i.ZERO, fitted.get_size()),
			Vector2i(frame * CELL.x + paste.x, direction * CELL.y + paste.y)
		)
		var pose_path := "%s/death_%s_f%d.png" % [OUTPUT_ROOT, str(record.get("direction", "unknown")).to_lower(), frame]
		fitted.save_png(pose_path)
		rendered_records.append({
			"direction": record.get("direction"),
			"directionRow": direction,
			"frame": frame,
			"yawDegrees": yaw,
			"fallDegrees": fall,
			"targetScreenDegrees": pose.get("targetScreenDegrees"),
			"projectedScreenDegrees": pose.get("projectedScreenDegrees"),
			"fitErrorDegrees": pose.get("fitErrorDegrees"),
			"helmetAnchorCentroid": [centre.x, centre.y],
			"targetEnvelope": [target_size.x, target_size.y],
			"targetOpaquePixels": target_opaque_pixels,
			"renderedOpaquePixels": _opaque_pixel_count(fitted),
			"renderedSize": [fitted.get_width(), fitted.get_height()],
			"paste": [paste.x, paste.y],
			"path": pose_path,
		})

	var death_path := "%s/black_iron_helmet_death_3d.png" % OUTPUT_ROOT
	death_atlas.save_png(death_path)
	var body := Image.load_from_file(BODY_PATH)
	if body == null or body.get_size() != death_atlas.get_size():
		push_error("Unexpected body death atlas")
		quit(1)
		return
	var overlay := body.duplicate()
	overlay.blend_rect(death_atlas, Rect2i(Vector2i.ZERO, death_atlas.get_size()), Vector2i.ZERO)
	var overlay_path := "%s/black_iron_helmet_death_overlay.png" % OUTPUT_ROOT
	overlay.save_png(overlay_path)
	var zoom_path := "%s/black_iron_helmet_death_head_zoom.png" % OUTPUT_ROOT
	_build_zoom_sheet(overlay, baseline.get("records", []), zoom_path)
	var standing_path := "%s/black_iron_helmet_standing_8_directions.png" % OUTPUT_ROOT
	await _build_standing_sheet(baseline, standing_path)

	var report := {
		"schemaVersion": 1,
		"renderer": "Godot 4.7 orthographic 3D",
		"geometry": "single complete faceted close-helm mesh with a narrow neck closure reused by all views",
		"poseSource": BASELINE_PATH,
		"bodyAtlas": BODY_PATH,
		"deathAtlas": death_path,
		"overlay": overlay_path,
		"headZoom": zoom_path,
		"standingDirections": standing_path,
		"mappingRule": "Each output cell consumes the same direction row and frame column from the 32-record evidence table.",
		"records": rendered_records,
	}
	var report_file := FileAccess.open("%s/manifest.json" % OUTPUT_ROOT, FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "  ") + "\n")
	report_file.close()
	print("BLACK_IRON_HELMET_GODOT_3D_PASS records=%d atlas=%s zoom=%s" % [rendered_records.size(), death_path, zoom_path])
	quit(0)


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _setup_renderer() -> void:
	viewport = SubViewport.new()
	viewport.name = "BlackIronHelmetViewport"
	viewport.size = RENDER_SIZE
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = false
	viewport.world_3d = World3D.new()
	root.add_child(viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("74787c")
	environment.ambient_light_energy = 1.15
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.35
	camera.position = Vector3(0.0, 3.0, 5.0)
	camera.current = true
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)

	var key := DirectionalLight3D.new()
	key.light_color = Color("767a7e")
	key.light_energy = 0.38
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	viewport.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color("4b4f53")
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(35.0, 145.0, 0.0)
	viewport.add_child(fill)

	helmet_root = Node3D.new()
	helmet_root.name = "CompleteBlackIronHelmet"
	viewport.add_child(helmet_root)
	_build_helmet_geometry()


func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.albedo_texture = _forged_iron_texture(colour)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = false
	material.uv1_scale = Vector3(3.2, 3.2, 3.2)
	material.metallic = 0.0
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _forged_iron_texture(base_colour: Color) -> ImageTexture:
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	var base_value := (base_colour.r + base_colour.g + base_colour.b) / 3.0
	for y in range(size):
		for x in range(size):
			# Deterministic broad strata plus sparse blunt hammer pits.
			var coarse := sin(float(x) * 0.43 + sin(float(y) * 0.17) * 1.9)
			var cross := sin(float(y) * 0.71 + float(x) * 0.11)
			var hashed := float((x * 37 + y * 61 + x * y * 7) % 23) / 22.0
			var pit := -0.075 if ((x * 17 + y * 29) % 47) == 0 else 0.0
			var value := clampf(base_value + coarse * 0.026 + cross * 0.018 + (hashed - 0.5) * 0.025 + pit, 0.025, 0.29)
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	return ImageTexture.create_from_image(image)


func _mesh_instance(mesh: Mesh, material: Material, position: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	helmet_root.add_child(instance)
	return instance


func _box(size: Vector3, position: Vector3, material: Material, rotation_degrees: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := _mesh_instance(mesh, material, position)
	instance.rotation_degrees = rotation_degrees
	return instance


func _build_helmet_geometry() -> void:
	var shell_material := _material(Color("292929"))
	var plate_material := _material(Color("1d1d1d"))
	var edge_material := _material(Color("363636"))
	var cavity_material := _material(Color("050607"))

	_mesh_instance(_radial_shell(), shell_material)

	# Broad brow and centre bar match the approved meteoric close-helm silhouette.
	_box(Vector3(1.00, 0.14, 0.14), Vector3(0.0, 0.10, 0.535), edge_material)
	_box(Vector3(0.13, 0.74, 0.15), Vector3(0.0, -0.22, 0.60), plate_material)
	_add_cheek_plate(-1.0, plate_material)
	_add_cheek_plate(1.0, plate_material)
	_add_side_plate(-1.0, plate_material)
	_add_side_plate(1.0, plate_material)
	_box(Vector3(0.34, 0.095, 0.06), Vector3(-0.25, 0.01, 0.675), cavity_material)
	_box(Vector3(0.34, 0.095, 0.06), Vector3(0.25, 0.01, 0.675), cavity_material)
	# Closed chin and inward neck lip; no bell-shaped lower rim.
	_box(Vector3(0.76, 0.15, 0.17), Vector3(0.0, -0.57, 0.51), plate_material)
	_box(Vector3(0.49, 0.11, 0.14), Vector3(0.0, -0.69, 0.38), shell_material)
	_box(Vector3(0.72, 0.065, 0.07), Vector3(0.0, -0.46, 0.665), edge_material)
	# Low-contrast centre ridge breaks the silhouette without adding shine.
	_box(Vector3(0.075, 0.48, 0.055), Vector3(0.0, 0.47, 0.24), edge_material, Vector3(-19.0, 0.0, 0.0))
	_box(Vector3(0.075, 0.34, 0.055), Vector3(0.0, 0.53, -0.16), edge_material, Vector3(24.0, 0.0, 0.0))


func _radial_shell() -> ArrayMesh:
	# Eight broad crown facets, a low flat top and a visibly inward neck.
	var profile := PackedVector2Array([
		Vector2(-0.68, 0.30),
		Vector2(-0.54, 0.40),
		Vector2(-0.16, 0.52),
		Vector2(0.18, 0.54),
		Vector2(0.43, 0.47),
		Vector2(0.62, 0.33),
		Vector2(0.72, 0.18),
	])
	var segments := 8
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(profile.size() - 1):
		for segment in range(segments):
			var next_segment := (segment + 1) % segments
			var a := _shell_vertex(profile[ring], segment, segments)
			var b := _shell_vertex(profile[ring], next_segment, segments)
			var c := _shell_vertex(profile[ring + 1], next_segment, segments)
			var d := _shell_vertex(profile[ring + 1], segment, segments)
			_add_triangle(surface, a, b, c)
			_add_triangle(surface, a, c, d)
	var bottom_centre := Vector3(0.0, profile[0].x, 0.0)
	for segment in range(segments):
		var next_segment := (segment + 1) % segments
		_add_triangle(
			surface,
			bottom_centre,
			_shell_vertex(profile[0], next_segment, segments),
			_shell_vertex(profile[0], segment, segments)
		)
	var top_centre := Vector3(0.0, profile[profile.size() - 1].x, 0.0)
	for segment in range(segments):
		var next_segment := (segment + 1) % segments
		_add_triangle(
			surface,
			top_centre,
			_shell_vertex(profile[profile.size() - 1], segment, segments),
			_shell_vertex(profile[profile.size() - 1], next_segment, segments)
		)
	surface.generate_normals()
	return surface.commit()


func _shell_vertex(profile_point: Vector2, segment: int, segments: int) -> Vector3:
	var angle := TAU * float(segment) / float(segments)
	return Vector3(
		cos(angle) * profile_point.y,
		profile_point.x,
		sin(angle) * profile_point.y * 0.84
	)


func _add_cheek_plate(side: float, material: Material) -> void:
	var polygon := PackedVector2Array([
		Vector2(0.14 * side, 0.06),
		Vector2(0.49 * side, 0.02),
		Vector2(0.38 * side, -0.58),
		Vector2(0.11 * side, -0.68),
	])
	var mesh := _extruded_polygon(polygon, 0.525, 0.665)
	_mesh_instance(mesh, material)


func _add_side_plate(side: float, material: Material) -> void:
	# Wrap the face guard around the temple so E/W are full profiles, not lines.
	var polygon := PackedVector2Array([
		Vector2(0.58, 0.05),
		Vector2(0.02, 0.03),
		Vector2(-0.12, -0.30),
		Vector2(0.04, -0.60),
		Vector2(0.34, -0.62),
	])
	var inner_x := 0.44 * side
	var outer_x := 0.55 * side
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1, polygon.size() - 1):
		_add_triangle(
			surface,
			Vector3(outer_x, polygon[0].y, polygon[0].x),
			Vector3(outer_x, polygon[index].y, polygon[index].x),
			Vector3(outer_x, polygon[index + 1].y, polygon[index + 1].x)
		)
		_add_triangle(
			surface,
			Vector3(inner_x, polygon[0].y, polygon[0].x),
			Vector3(inner_x, polygon[index + 1].y, polygon[index + 1].x),
			Vector3(inner_x, polygon[index].y, polygon[index].x)
		)
	for index in range(polygon.size()):
		var next := (index + 1) % polygon.size()
		var a := Vector3(inner_x, polygon[index].y, polygon[index].x)
		var b := Vector3(inner_x, polygon[next].y, polygon[next].x)
		var c := Vector3(outer_x, polygon[next].y, polygon[next].x)
		var d := Vector3(outer_x, polygon[index].y, polygon[index].x)
		_add_triangle(surface, a, b, c)
		_add_triangle(surface, a, c, d)
	surface.generate_normals()
	_mesh_instance(surface.commit(), material)


func _extruded_polygon(polygon: PackedVector2Array, back_z: float, front_z: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1, polygon.size() - 1):
		_add_triangle(surface,
			Vector3(polygon[0].x, polygon[0].y, front_z),
			Vector3(polygon[index].x, polygon[index].y, front_z),
			Vector3(polygon[index + 1].x, polygon[index + 1].y, front_z))
		_add_triangle(surface,
			Vector3(polygon[0].x, polygon[0].y, back_z),
			Vector3(polygon[index + 1].x, polygon[index + 1].y, back_z),
			Vector3(polygon[index].x, polygon[index].y, back_z))
	for index in range(polygon.size()):
		var next := (index + 1) % polygon.size()
		var a := Vector3(polygon[index].x, polygon[index].y, back_z)
		var b := Vector3(polygon[next].x, polygon[next].y, back_z)
		var c := Vector3(polygon[next].x, polygon[next].y, front_z)
		var d := Vector3(polygon[index].x, polygon[index].y, front_z)
		_add_triangle(surface, a, b, c)
		_add_triangle(surface, a, c, d)
	surface.generate_normals()
	return surface.commit()


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.set_smooth_group(-1)
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


func _render_pose(yaw_degrees: float, fall_degrees: float) -> Image:
	var yaw := Quaternion(Vector3.UP, deg_to_rad(yaw_degrees))
	var fall := Quaternion(Vector3.RIGHT, deg_to_rad(fall_degrees))
	helmet_root.quaternion = yaw * fall
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	return viewport.get_texture().get_image()


func _fit_image(source: Image, envelope: Vector2i, target_opaque_pixels: float) -> Image:
	var envelope_scale := minf(float(envelope.x) / source.get_width(), float(envelope.y) / source.get_height())
	var source_opaque := maxf(1.0, float(_opaque_pixel_count(source)))
	var area_scale := sqrt(maxf(1.0, target_opaque_pixels) / source_opaque)
	var scale := minf(envelope_scale, area_scale)
	var size := Vector2i(
		maxi(1, roundi(source.get_width() * scale)),
		maxi(1, roundi(source.get_height() * scale))
	)
	var result := source.duplicate()
	result.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return result


func _opaque_pixel_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.5:
				count += 1
	return count


func _build_zoom_sheet(overlay: Image, records: Array, target: String) -> void:
	var tile := Vector2i(128, 104)
	var sheet := Image.create(tile.x * 4, tile.y * 8, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("101216"))
	for untyped_record in records:
		var record: Dictionary = untyped_record
		var direction := int(record.get("directionRow", 0))
		var frame := int(record.get("frame", 0))
		var client_centroid: Dictionary = record.get("clientHelmetCentroid", {})
		var client_x: Dictionary = client_centroid.get("x", {})
		var client_y: Dictionary = client_centroid.get("y", {})
		var hair_centroid: Array = record.get("hairAnchorCentroid", [96.0, 80.0])
		var centre := Vector2i(
			roundi(float(client_x.get("median", hair_centroid[0]))),
			roundi(float(client_y.get("median", hair_centroid[1])))
		)
		var cell_origin := Vector2i(frame * CELL.x, direction * CELL.y)
		var source_rect := Rect2i(cell_origin + centre - Vector2i(32, 26), Vector2i(64, 52))
		var crop := overlay.get_region(source_rect)
		crop.resize(tile.x, tile.y, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, tile), Vector2i(frame * tile.x, direction * tile.y))
	sheet.save_png(target)


func _build_standing_sheet(baseline: Dictionary, target: String) -> void:
	var sheet := Image.create(128 * 8, 144, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("55585c"))
	var records: Array = baseline.get("records", [])
	for direction in range(8):
		var record: Dictionary = records[direction * 4]
		var pose: Dictionary = record.get("recommendedGodotPose", {})
		var rendered := await _render_pose(float(pose.get("yawDegrees", 0.0)), 0.0)
		var used := rendered.get_used_rect()
		var crop := rendered.get_region(used)
		crop.save_png("%s/standing_%s.png" % [OUTPUT_ROOT, DIRECTION_NAMES[direction]])
		var scale := minf(104.0 / crop.get_width(), 110.0 / crop.get_height())
		crop.resize(roundi(crop.get_width() * scale), roundi(crop.get_height() * scale), Image.INTERPOLATE_NEAREST)
		var paste := Vector2i(direction * 128 + (128 - crop.get_width()) / 2, (128 - crop.get_height()) / 2)
		sheet.blend_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), paste)
	sheet.save_png(target)
