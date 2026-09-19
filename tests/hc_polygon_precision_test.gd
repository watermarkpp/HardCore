extends Node
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Binding := preload("res://scripts/map_editor/polygon/poly_instance_binding.gd")
const Pixel := preload("res://scripts/map_editor/polygon/poly_pixel_layout.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const Probe := preload("res://scripts/map_editor/polygon/poly_alignment_probe.gd")
const Collision := preload("res://scripts/map_editor/map_editor_collision_service.gd")
const Author := preload("res://scripts/map_editor/polygon/poly_authoring.gd")
var errors: Array[String] = []
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors.append(message)
		push_error("HC_POLYGON_PRECISION: " + message)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	for size_gu: Vector2i in [Vector2i(80,80), Vector2i(256,256), Vector2i(80,96)]:
		for point: Vector2 in [Vector2(.137,.421), Vector2(10.317,20.789), Vector2(30.001,4.125)]:
			var canvas_point := Coord.tile_to_ground_px(point, size_gu)
			var runtime_point := Coord.ground_position_gu_to_screen_position_px(point, size_gu)
			check((canvas_point - Coord.ground_pixel_center(size_gu)).distance_to(runtime_point) < .005, "editor/runtime origin parity")
			for zoom: float in [.182, .28, .731, 1.12]:
				var pan := Vector2(171.37,-92.31)
				var pointer := pan + canvas_point * zoom
				var inverse := Coord.ground_px_to_tile((pointer - pan) / zoom, size_gu)
				check(inverse.distance_to(point) < .0001, "free pointer inverse independent of zoom and pan")
		var material := {"tile":[20,21], "footprint_tiles":[3,2], "anchor_px":[64,127], "scale":[1.3,.85], "offset_px":[.25,-.625], "rotation_deg":0.0}
		var asset := {"asset_id":"precision_fixture", "asset_type":"large_prop", "anchor_px":[64,127]}
		var local := PackedVector2Array([Vector2(52.3,119.7),Vector2(77.125,124.35),Vector2(68.875,136.55),Vector2(48.9,133.125)])
		for angle: float in [0.0, 17.0, 90.0, -135.0]:
			material.rotation_deg = angle
			var ground := Binding.to_ground(local, material, asset, size_gu)
			var roundtrip := Binding.to_local(ground, material, asset, size_gu)
			check(roundtrip.size() == local.size(), "binding roundtrip count")
			for i: int in range(local.size()):
				check(local[i].distance_to(roundtrip[i]) < .01, "binding includes image anchor, nonuniform scale and rotation")
			check(Probe.instance_projection_error(material, asset, size_gu) < .01, "full image corner parity")
			for delta: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				var moved := Pixel.nudged(material, delta, asset)
				var moved_ground := Binding.to_ground(local, moved, asset, size_gu)
				check(moved.tile == material.tile, "pixel nudge never changes tile")
				for i: int in range(local.size()):
					var a := Coord.ground_position_gu_to_screen_position_px(ground[i], size_gu)
					var b := Coord.ground_position_gu_to_screen_position_px(moved_ground[i], size_gu)
					check((b - a).distance_to(delta) < .01, "every bound vertex follows exact one screen pixel")
	var base := {"design":{"design_size":[12,12]}, "editor_meta":{}, "layers":{"collision":[],"collision_erase":[]}}
	var cells := base.duplicate(true)
	var rects := base.duplicate(true)
	check(Collision.paint_collision_cell(cells, Vector2i(3,5)).ok, "old cell authoring")
	check(Collision.add_manual_shape(rects,"rect",{"rect":[3,5,1,1]}).ok, "old rect authoring")
	check(Collision.build_walkability(cells).blocked_tiles == Collision.build_walkability(rects).blocked_tiles, "single cell and equal rect share exact coordinates")
	var migrated := Author.migrate(cells, Collision.build_walkability(cells))
	check(migrated.ok, "old cell migrates without shifting")
	if migrated.ok:
		check(Author.walkability(migrated.document).blocked_tiles == Collision.build_walkability(cells).blocked_tiles, "migrated cell occupies same cell")
	if errors.is_empty(): print("HC_POLYGON_PRECISION_TEST_PASS checks=",checks)
	get_tree().quit(0 if errors.is_empty() else 1)
