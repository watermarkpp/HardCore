extends Node2D

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Geometry := preload("res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd")
const MAP_IDS := {"mengzhong_zuma_pavilion": 913105, "mengzhong_zuma_leader_home": 913106}
const CARPET_IDS := ["user.bb920cfc9a26359e", "user.7d2522ffc19caee4"]

@export var map_key := "mengzhong_zuma_pavilion"
@export var staged := false
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = false
	check(OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"), "isolated native user data")
	MapAssetCatalogService.invalidate_cache()
	MapEditorRuntimeBridge.invalidate_release_registry()
	var runtime := MapEditorRuntimeBridge.load_map(int(MAP_IDS[map_key]))
	check(not runtime.is_empty() and int(runtime.get("runtime_map_id", 0)) == int(MAP_IDS[map_key]), "real map loads through formal release registry")
	if runtime.is_empty():
		_finish()
		return
	var raw_size: Array = runtime.design.design_size
	var size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var authoring: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://map_editor_workspace/%s/%s.editor.json" % [map_key, map_key]))
	var authored := {}
	for instance: Dictionary in MapEditorInstanceService.all_instances(authoring):
		authored[str(instance.instance_id)] = instance
	var commands := Geometry.sorted_draw_commands(runtime.instances, runtime.get("visual_asset_snapshot", {}))
	var carpets := {}
	var wall_commands: Array[Dictionary] = []
	for command: Dictionary in commands:
		if Geometry.is_atomic_wall_pass(command) and int(command.image_pass) == 1:
			wall_commands.append(command)
		if not str(command.instance.asset_id) in CARPET_IDS:
			continue
		var id := str(command.instance.instance_id)
		carpets[id] = command
		check(authored.has(id), "%s exists in authoring" % id)
		check(MapEditorInstanceService.material_layer_order(command.instance) == MapEditorInstanceService.material_layer_order(authored.get(id, {})) and MapEditorInstanceService.material_layer_order(command.instance) < 0, "%s retains authored lower layer" % id)
		check(not Geometry.instance_is_occluder(command.instance, command.asset) and command.render_domain == Geometry.RENDER_DOMAIN_STATIC_BACKGROUND, "%s remains a non-occluding ground decoration" % id)
	check(not carpets.is_empty() and not wall_commands.is_empty(), "real carpets and atomic walls are both covered")
	var lower_layer_far_corner_pairs := 0
	for id: String in carpets:
		var command: Dictionary = carpets[id]
		for wall: Dictionary in wall_commands:
			if Geometry.static_authored_sort_world(command, size).y <= Geometry.command_actor_sort_world(wall, size).y:
				continue
			lower_layer_far_corner_pairs += 1
			check(not Geometry.static_authored_command_is_in_front_of_wall(command, wall, size), "%s lower authored layer cannot be promoted by far-corner depth (%s)" % [id, wall.actor_sort_group])
	check(lower_layer_far_corner_pairs > 0, "fixture exercises lower layer with misleading greater far-corner depth")
	var plane := Node2D.new()
	plane.y_sort_enabled = true
	add_child(plane)
	var background := WorldBackground.new()
	check(background.defer_initial_legacy_build_to_coordinator(), "avoid unrelated initial legacy map build")
	plane.add_child(background)
	if staged:
		var descriptors: Array = []
		background._append_instance_descriptors(descriptors, runtime, int(MAP_IDS[map_key]))
		for descriptor: Dictionary in descriptors:
			background.build_one_map_item(descriptor)
		background.finish_map_build()
	else:
		background._build_editor_runtime_instances(runtime)
	var static_carpets := {}
	for node: Node in background.get_children():
		var id := str(node.get_meta("editor_runtime_instance_id", ""))
		if not carpets.has(id):
			continue
		static_carpets[id] = true
		check(node is Sprite2D and node.get_parent() == background and (node as CanvasItem).z_as_relative and background.z_index + (node as CanvasItem).z_index < 0, "%s original carpet stays below world actors" % id)
	check(static_carpets.size() == carpets.size(), "all authored carpets keep original static sprites")
	var promoted_carpets := {}
	var wall_roots := 0
	for root: Node in plane.get_children():
		if not bool(root.get_meta("editor_runtime_actor_occluder", false)):
			continue
		wall_roots += 1
		check(root is Node2D and (root as Node2D).z_index == 0, "wall keeps shared actor Y-sort domain")
		for node: Node in root.get_children():
			if not bool(node.get_meta("static_authored_wall_bridge", false)):
				continue
			for id: String in node.get_meta("static_wall_bridge_source_instance_ids", []):
				if carpets.has(id):
					promoted_carpets[id] = true
	check(wall_roots > 0, "actual wall occluder wrappers were constructed")
	check(promoted_carpets.is_empty(), "actual wall overlays contain no pixels from the lower-layer carpets: %s" % str(promoted_carpets.keys()))
	var actor := CharacterBody2D.new()
	plane.add_child(actor)
	var baseline := Geometry.command_actor_sort_world(wall_commands[0], size)
	actor.position = baseline - Vector2(0, 1)
	check(actor.z_index == 0 and actor.position.y < baseline.y, "actor behind wall retains wall occlusion")
	actor.position = baseline + Vector2(0, 1)
	check(actor.z_index == 0 and actor.position.y > baseline.y, "actor crossing in front retains Y-sort relation")
	print("ZUMA_MATERIAL_LAYER_OBSERVATION map=", map_key, " staged=", staged, " carpets=", carpets.keys(), " misleading_pairs=", lower_layer_far_corner_pairs, " promoted=", promoted_carpets.keys(), " bridge=", background.static_wall_bridge_stats())
	plane.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	var written := proof.write_receipt(scene_file_path.get_file().get_basename(), proof.records.size(), failures.size())
	print("ZUMA_MATERIAL_LAYER_RUNTIME_", "PASS" if written and failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failure_count=", failures.size(), " first_failure=", "" if failures.is_empty() else failures[0])
	get_tree().quit(0 if written and failures.is_empty() else 1)
