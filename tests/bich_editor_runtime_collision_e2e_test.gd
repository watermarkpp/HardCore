extends Node2D

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const VisualGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)

const MAP_KEY := "bich_province"
const HOUSE_INSTANCE_ID := "inst_000005"
const HOUSE_MANUAL_COLLISION_ID := "manual_000039"
const HOUSE_BLOCKED_CELL := Vector2i(21, 28)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var source_loaded := MapEditorLoadService.load_document(
		"res://map_editor_workspace/bich_province/bich_province.editor.json"
	)
	assert(source_loaded.ok, str(source_loaded.get("errors", [])))
	var document: Dictionary = source_loaded.document
	var runtime_loaded := MapEditorRuntimeMapService.load_runtime(
		"res://assets/data/runtime/map_editor/bich_province.runtime.json"
	)
	assert(runtime_loaded.ok, str(runtime_loaded.get("errors", [])))
	var runtime: Dictionary = runtime_loaded.runtime
	var rebuilt := MapEditorCollisionService.build_walkability(document)
	var published := CollisionGeometry.blocked_cell_set(runtime.collision)
	assert(rebuilt.blocked_tiles.size() == published.size())
	for key: String in rebuilt.blocked_tiles:
		assert(published.has(key), "source/runtime blocked mismatch: %s" % key)

	var raw_size: Array = runtime.design.design_size
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var visual := _read_json(
		"res://assets/data/runtime/map_editor/bich_province.visual.json"
	)
	var raw_center: Array = visual.ground_pixel_center
	var ground_center := Vector2(float(raw_center[0]), float(raw_center[1]))
	var house := _instance_by_id(document, HOUSE_INSTANCE_ID)
	assert(not house.is_empty(), HOUSE_INSTANCE_ID)
	var asset := MapAssetCatalogService.find_asset(str(house.asset_id))
	var foot_tile := VisualGeometry.instance_foot_tile(house, asset)
	var editor_foot_world := (
		MapEditorCoordinate.tile_to_ground_px(foot_tile, design_size)
		- ground_center
	)
	var runtime_foot_world := MapEditorCoordinate.tile_to_world(
		foot_tile, design_size
	)
	assert(editor_foot_world.is_equal_approx(runtime_foot_world),
		"house visual foot shifted between editor and runtime")

	var manual := _manual_by_id(document, HOUSE_MANUAL_COLLISION_ID)
	assert(not manual.is_empty(), HOUSE_MANUAL_COLLISION_ID)
	var source_rect: Array = manual.data.rect
	var editor_manual_world := PackedVector2Array()
	for tile_point: Vector2 in _rect_tile_polygon(source_rect):
		editor_manual_world.append(
			MapEditorCoordinate.tile_to_ground_px(tile_point, design_size)
			- ground_center
		)
	var runtime_manual_world := CollisionGeometry.manual_shape_polygon_world(
		manual, design_size
	)
	assert(editor_manual_world == runtime_manual_world,
		"house red source collision shifted during runtime projection")

	var key := "%d,%d" % [HOUSE_BLOCKED_CELL.x, HOUSE_BLOCKED_CELL.y]
	assert(rebuilt.blocked_tiles.has(key), "source red cell missing: %s" % key)
	assert(published.has(key), "published red cell missing: %s" % key)
	var editor_cell_world := PackedVector2Array()
	for ground_point: Vector2 in MapEditorCoordinate.cell_polygon_ground_px(
		HOUSE_BLOCKED_CELL, design_size
	):
		editor_cell_world.append(ground_point - ground_center)
	var runtime_cell_world := CollisionGeometry.cell_polygon_world(
		HOUSE_BLOCKED_CELL, design_size
	)
	assert(editor_cell_world == runtime_cell_world,
		"house blocked cell lost editor foot alignment")

	# Exercise the actual game renderer and Physics2D builder together. This
	# catches the actor Y-sort wrapper regression where the command center was
	# made parent-relative but its anchor/scale/rotation/material were dropped.
	var runtime_root := Node2D.new()
	runtime_root.y_sort_enabled = true
	add_child(runtime_root)
	var background := WorldBackground.new()
	background.zone_data = {"mapId": 4}
	runtime_root.add_child(background)
	await get_tree().process_frame
	await get_tree().physics_frame
	var runtime_sprite := _runtime_sprite(runtime_root, HOUSE_INSTANCE_ID)
	assert(runtime_sprite != null, "house runtime sprite missing")
	var command := _runtime_command(runtime.instances, HOUSE_INSTANCE_ID)
	assert(not command.is_empty(), "house runtime draw command missing")
	var runtime_geometry := VisualGeometry.runtime_command_geometry(
		command, design_size, runtime_sprite.texture.get_size()
	)
	assert(runtime_sprite.global_position.is_equal_approx(runtime_geometry.center),
		"house draw foot shifted by actor Y-sort parent")
	assert(runtime_sprite.global_position.is_equal_approx(editor_foot_world),
		"house editor foot and actual runtime draw foot differ")
	assert(runtime_sprite.offset.is_equal_approx(-runtime_geometry.anchor),
		"house runtime anchor dropped")
	assert(runtime_sprite.scale.is_equal_approx(runtime_geometry.visual_scale),
		"house runtime visual scale dropped")
	assert(is_equal_approx(runtime_sprite.rotation, runtime_geometry.rotation),
		"house runtime rotation dropped")
	assert(
		int(runtime_sprite.get_meta("material_layer_order", -1))
		== MapEditorInstanceService.material_layer_order(house),
		"house runtime material layer dropped"
	)
	assert(
		str(runtime_sprite.get_meta("editor_runtime_render_domain", ""))
		== VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT,
		"house must remain an actor Y-sort occluder"
	)
	assert(bool(runtime_sprite.get_parent().get_meta(
		"editor_runtime_actor_occluder", false
	)), "house sprite lost actor Y-sort wrapper")
	var sort_world := VisualGeometry.command_actor_sort_world(
		command, design_size
	)
	assert(runtime_sprite.get_parent().global_position.is_equal_approx(sort_world),
		"house actor-sort wrapper is not at authored visual foot")
	assert(Vector2(command.sort_baseline_tile).is_equal_approx(foot_tile),
		"house occlusion baseline reused build/collision geometry")
	assert(sort_world.is_equal_approx(runtime_geometry.center),
		"house occlusion baseline diverged from its rendered visual foot")
	assert(not Vector2(command.sort_baseline_tile).is_equal_approx(
		Vector2(command.sort_tile)
	), "house occlusion baseline retained the footprint far corner")
	var blocked_center := CollisionGeometry.cell_center_world(
		HOUSE_BLOCKED_CELL, design_size
	)
	assert(background._editor_runtime_blocks_world(blocked_center),
		"house published cell missing software collision")
	assert(not _physics_hits(blocked_center).is_empty(),
		"house published cell missing final Physics2D polygon")
	print(
		"BICH_EDITOR_RUNTIME_COLLISION_E2E_PASS "
		+ "source_blocked=%d runtime_blocked=%d house=%s manual=%s"
		% [
			rebuilt.blocked_tiles.size(), published.size(),
			HOUSE_INSTANCE_ID, HOUSE_MANUAL_COLLISION_ID,
		]
	)
	get_tree().quit(0)


func _runtime_sprite(node: Node, instance_id: String) -> Sprite2D:
	for child: Node in node.get_children():
		if (
			child is Sprite2D
			and str(child.get_meta("editor_runtime_instance_id", ""))
			== instance_id
		):
			return child as Sprite2D
		var nested := _runtime_sprite(child, instance_id)
		if nested != null:
			return nested
	return null


func _runtime_command(instances: Array, instance_id: String) -> Dictionary:
	for command: Dictionary in VisualGeometry.sorted_draw_commands(instances):
		if str(command.instance.get("instance_id", "")) == instance_id:
			return command
	return {}


func _instance_by_id(document: Dictionary, instance_id: String) -> Dictionary:
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if str(instance.get("instance_id", "")) == instance_id:
			return instance
	return {}


func _manual_by_id(document: Dictionary, collision_id: String) -> Dictionary:
	for manual: Dictionary in document.layers.collision:
		if str(manual.get("collision_id", "")) == collision_id:
			return manual
	return {}


func _rect_tile_polygon(rect: Array) -> PackedVector2Array:
	var minimum := Vector2(float(rect[0]), float(rect[1]))
	var maximum := minimum + Vector2(float(rect[2]), float(rect[3]))
	return PackedVector2Array([
		minimum,
		Vector2(maximum.x, minimum.y),
		maximum,
		Vector2(minimum.x, maximum.y),
	])


func _physics_hits(world_position: Vector2) -> Array[Dictionary]:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_point(query, 8)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "%s missing" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert(parsed is Dictionary, "%s invalid" % path)
	return parsed
