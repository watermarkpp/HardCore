extends Node2D

const VisualGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)

const PUBLISHED_VERTICAL_SLICE_MAPS := {
	406: "bich_mine_1",
	408: "bich_mine_2",
	1578: "corpse_king_hall",
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var map_406_front_commands: Array[Dictionary] = []
	var covered_maps := 0
	var total_front_commands := 0
	for runtime_map_id: int in PUBLISHED_VERTICAL_SLICE_MAPS:
		var map_key := str(PUBLISHED_VERTICAL_SLICE_MAPS[runtime_map_id])
		var loaded := MapEditorRuntimeMapService.load_runtime(
			"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
		)
		assert(loaded.ok, "%s:%s" % [map_key, loaded.get("errors", [])])
		var front_commands := _wall_front_commands(loaded.runtime.instances)
		assert(not front_commands.is_empty(), "%s has no wall fronts" % map_key)
		for command: Dictionary in front_commands:
			var expected := (
				Vector2(command.sort_tile)
				+ VisualGeometry.WALL_PART_SORT_BASELINE_TILE_OFFSET
			)
			assert(
				Vector2(command.sort_baseline_tile).is_equal_approx(expected),
				"%s:%s foreground sorts at a cell corner" % [
					map_key,
					command.instance.get("instance_id", ""),
				]
			)
		if runtime_map_id == 406:
			map_406_front_commands = front_commands
		covered_maps += 1
		total_front_commands += front_commands.size()

	assert(covered_maps == PUBLISHED_VERTICAL_SLICE_MAPS.size())
	assert(not map_406_front_commands.is_empty())
	await _assert_real_map_406_runtime(map_406_front_commands)
	print(
		(
			"CLIENT_MAP_VERTICAL_SLICE_WALL_OCCLUSION_E2E_PASS "
			+ "contract=%s maps=%d map406_fronts=%d total_fronts=%d"
		)
		% [
			VisualGeometry.OCCLUSION_SORT_CONTRACT_ID,
			covered_maps,
			map_406_front_commands.size(),
			total_front_commands,
		]
	)
	get_tree().quit(0)


func _assert_real_map_406_runtime(
	front_commands: Array[Dictionary]
) -> void:
	var runtime_root := Node2D.new()
	runtime_root.name = "Map406ActorYSort"
	runtime_root.y_sort_enabled = true
	add_child(runtime_root)
	var background := WorldBackground.new()
	background.name = "Map406WorldBackground"
	runtime_root.add_child(background)
	var loaded := MapEditorRuntimeMapService.load_runtime(
		"res://assets/data/runtime/map_editor/bich_mine_1.runtime.json"
	)
	assert(loaded.ok)
	background._build_editor_runtime_instances(loaded.runtime)
	await get_tree().process_frame

	var wrappers := _runtime_wall_front_wrappers(
		runtime_root, front_commands
	)
	assert(
		wrappers.size() == front_commands.size(),
		"map406 did not instantiate every wall foreground in actor_y_sort"
	)
	var sample_count := mini(16, front_commands.size())
	for index in sample_count:
		var command: Dictionary = front_commands[index]
		var wrapper: Node2D = wrappers[index]
		var expected_world := VisualGeometry.command_actor_sort_world(
			command, Vector2i(50, 50)
		)
		assert(
			wrapper.global_position.is_equal_approx(expected_world),
			"map406 wall wrapper lost its per-cell centre baseline"
		)
		assert(
			bool(wrapper.get_meta("editor_runtime_actor_occluder", false)),
			"map406 wall foreground escaped the actor Y-sort domain"
		)
		var behind_actor := CharacterBody2D.new()
		behind_actor.position = expected_world + Vector2(0.0, -16.0)
		runtime_root.add_child(behind_actor)
		var front_actor := CharacterBody2D.new()
		front_actor.position = expected_world + Vector2(0.0, 16.0)
		runtime_root.add_child(front_actor)
		assert(
			behind_actor.global_position.y < wrapper.global_position.y,
			"map406 actor behind wall did not sort behind its foreground"
		)
		assert(
			front_actor.global_position.y > wrapper.global_position.y,
			"map406 actor in front of wall did not cross its foreground"
		)
		assert(
			behind_actor.z_index == wrapper.z_index
			and front_actor.z_index == wrapper.z_index,
			"map406 actors and wall foreground do not share one Y-sort plane"
		)


func _wall_front_commands(instances: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for command: Dictionary in VisualGeometry.sorted_draw_commands(instances):
		if (
			str(command.asset.get("asset_type", "")) == "wall_module"
			and int(command.image_pass) == 2
			and str(command.render_domain)
			== VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT
		):
			result.append(command)
	return result


func _runtime_wall_front_wrappers(
	root: Node,
	front_commands: Array[Dictionary]
) -> Array[Node2D]:
	var expected := {}
	for command: Dictionary in front_commands:
		var key := "%s|%s" % [
			command.instance.get("instance_id", ""),
			command.image_path,
		]
		expected[key] = int(expected.get(key, 0)) + 1
	var result: Array[Node2D] = []
	_collect_runtime_wall_front_wrappers(root, expected, result)
	result.sort_custom(
		func(a: Node2D, b: Node2D) -> bool:
			return int(a.get_meta("editor_runtime_command_index", -1)) < int(
				b.get_meta("editor_runtime_command_index", -1)
			)
	)
	return result


func _collect_runtime_wall_front_wrappers(
	node: Node,
	expected: Dictionary,
	result: Array[Node2D]
) -> void:
	for child: Node in node.get_children():
		if child is Sprite2D:
			var sprite := child as Sprite2D
			var key := "%s|%s" % [
				sprite.get_meta("editor_runtime_instance_id", ""),
				sprite.get_meta("editor_runtime_image_path", ""),
			]
			if (
				expected.has(key)
				and str(sprite.get_meta("editor_runtime_render_domain", ""))
				== VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT
			):
				var wrapper := sprite.get_parent() as Node2D
				wrapper.set_meta(
					"editor_runtime_command_index",
					int(sprite.get_meta("editor_runtime_command_index", -1))
				)
				result.append(wrapper)
		_collect_runtime_wall_front_wrappers(child, expected, result)
