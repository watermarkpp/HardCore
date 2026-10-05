extends Node

const Geometry := preload("res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()

func _ready() -> void:
	var size := Vector2i(32, 32)
	var wall := {"instance": {"material_layer_order": 0}, "sort_baseline_tile": Vector2(10, 10)}
	var behind := {"instance": {"material_layer_order": 1}, "sort_tile": Vector2i(1, 1)}
	var front := {"instance": {"material_layer_order": -1}, "sort_tile": Vector2i(20, 20)}
	proof.record(Geometry.static_authored_sort_world(behind, size).y < Geometry.command_actor_sort_world(wall, size).y, "higher authored layer deliberately conflicts with geometric depth")
	proof.record(not Geometry.static_authored_command_is_in_front_of_wall(behind, wall, size), "higher static layer retains existing geometric cut instead of acquiring a new actor occlusion range")
	proof.record(Geometry.static_authored_sort_world(front, size).y > Geometry.command_actor_sort_world(wall, size).y, "lower authored layer deliberately conflicts with geometric depth")
	proof.record(not Geometry.static_authored_command_is_in_front_of_wall(front, wall, size), "lower authored layer takes precedence over geometric depth")
	behind.instance.material_layer_order = 0
	front.instance.material_layer_order = 0
	proof.record(not Geometry.static_authored_command_is_in_front_of_wall(behind, wall, size), "same layer retains behind-wall geometric order")
	proof.record(Geometry.static_authored_command_is_in_front_of_wall(front, wall, size), "same layer retains in-front geometric order")
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var top_command: Dictionary = wall.duplicate(true)
	top_command.instance.material_layer_order = 1
	var lower_command: Dictionary = wall.duplicate(true)
	lower_command.instance.material_layer_order = -1
	var record := {"aabb": Rect2i(0, 0, 2, 2), "used_world_aabb": Rect2i(0, 0, 2, 2), "used_rect": Rect2i(0, 0, 2, 2), "image": image, "inverse_transform": Transform2D.IDENTITY, "group_key": "top"}
	var lower_record: Dictionary = record.duplicate(true)
	lower_record.group_key = "lower"
	var background := WorldBackground.new()
	var groups := {"top": {"wall_command": top_command, "wall_sort_y": 0.0, "material_layer_order": 1}, "lower": {"wall_command": lower_command, "wall_sort_y": 0.0, "material_layer_order": -1}}
	var metrics := {"wall_resolve_queries": 0, "wall_alpha_samples": 0, "wall_owner_samples": 0}
	var records: Array[Dictionary] = [record, lower_record]
	var pass_grid := {"grid": {Vector2i.ZERO: [0, 1]}, "records": records}
	var object_record := {"command": front, "static_sort_y": 1000000.0, "material_layer_order": 0}
	proof.record(Geometry.static_authored_command_is_in_front_of_wall(front, lower_command, size), "lower wall can initially admit this decoration candidate")
	var owner := background._static_wall_bridge_resolve_owner(Vector2i.ZERO, object_record, groups, pass_grid, metrics)
	proof.record(owner.is_empty(), "actual pixel owner rejects a decoration below the top opaque wall even when another wall admitted it")
	top_command.instance.material_layer_order = 0
	groups.top.material_layer_order = 0
	owner = background._static_wall_bridge_resolve_owner(Vector2i.ZERO, object_record, groups, pass_grid, metrics)
	proof.record(not owner.is_empty() and str(owner.get("group_key", "")) == "top", "same-layer decoration still restores pixels on the top wall owner")
	background.free()
	var failed := 0
	for row: Dictionary in proof.records:
		failed += 0 if bool(row.passed) else 1
	var written := proof.write_receipt(scene_file_path.get_file().get_basename(), proof.records.size(), failed)
	print("STATIC_WALL_MATERIAL_PRECEDENCE_", "PASS" if written and failed == 0 else "FAIL", " checks=", proof.records.size(), " failed=", failed)
	get_tree().quit(0 if written and failed == 0 else 1)
