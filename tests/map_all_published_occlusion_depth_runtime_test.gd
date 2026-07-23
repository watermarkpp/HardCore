extends Node2D

const VisualGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)

const PUBLISHED_RUNTIME_MAPS := {
	4: "bich_province",
	217: "orc_tomb_1",
	218: "orc_tomb_2",
	221: "orc_tomb_3",
	268: "wooma_forest",
	313: "wooma_temple_1",
	314: "wooma_temple_2",
	315: "wooma_temple_3",
	406: "bich_mine_1",
	408: "bich_mine_2",
	1578: "corpse_king_hall",
}

const OCCLUDER_COLOR := Color(0.05, 0.15, 0.95, 1.0)
const BEHIND_ACTOR_COLOR := Color(0.95, 0.10, 0.10, 1.0)
const FRONT_ACTOR_COLOR := Color(0.05, 0.95, 0.15, 1.0)

var _samples: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var covered_maps := 0
	var corrected_far_corner_thresholds := 0
	var row := 0
	for runtime_map_id: int in PUBLISHED_RUNTIME_MAPS:
		var map_key := str(PUBLISHED_RUNTIME_MAPS[runtime_map_id])
		var loaded := MapEditorRuntimeMapService.load_runtime(
			"res://assets/data/runtime/map_editor/%s.runtime.json" % map_key
		)
		assert(loaded.ok, "%s:%s" % [map_key, loaded.get("errors", [])])
		var runtime: Dictionary = loaded.runtime
		var raw_size: Array = runtime.design.design_size
		var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
		var command := _occluder_command(runtime.instances)
		assert(not command.is_empty(), "%s actor-sorted occluder missing" % map_key)
		var wall_part := str(command.asset.get("asset_type", "")) == "wall_module"
		var expected_tile := (
			(
				Vector2(command.sort_tile)
				+ VisualGeometry.WALL_PART_SORT_BASELINE_TILE_OFFSET
			)
			if wall_part
			else VisualGeometry.instance_sort_baseline_tile(
				command.instance, command.asset
			)
		)
		assert(
			Vector2(command.sort_baseline_tile).is_equal_approx(expected_tile),
			"%s command baseline diverged from authored visual foot" % map_key
		)
		var baseline_world := VisualGeometry.command_actor_sort_world(
			command, design_size
		)
		var expected_offset := (
			Vector2.ZERO
			if wall_part
			else VisualGeometry.instance_sort_baseline_world_offset(
				command.instance, command.asset
			)
		)
		var expected_world := (
			MapEditorCoordinate.tile_to_world(expected_tile, design_size)
			+ expected_offset
		)
		assert(baseline_world.is_equal_approx(expected_world),
			"%s pixel-shifted visual foot lost by sort wrapper" % map_key)
		if not Vector2(command.sort_tile).is_equal_approx(expected_tile):
			corrected_far_corner_thresholds += 1
		var y := 34.0 + float(row) * 60.0
		_add_crossing_probe(
			baseline_world, Vector2(70.0, y), false, "player",
			"%s player behind baseline" % map_key
		)
		_add_crossing_probe(
			baseline_world, Vector2(150.0, y), true, "player",
			"%s player in front of baseline" % map_key
		)
		_add_crossing_probe(
			baseline_world, Vector2(230.0, y), false, "monster",
			"%s monster behind baseline" % map_key
		)
		_add_crossing_probe(
			baseline_world, Vector2(310.0, y), true, "monster",
			"%s monster in front of baseline" % map_key
		)
		covered_maps += 1
		row += 1

	_assert_bich_family_baselines()
	_assert_default_family_crossings()
	_assert_author_override_is_independent()
	assert(covered_maps == PUBLISHED_RUNTIME_MAPS.size())
	assert(corrected_far_corner_thresholds > 0)
	await get_tree().process_frame
	for sample: Dictionary in _samples:
		var plane: Node2D = sample.plane
		var wrapper: Node2D = sample.wrapper
		var actor: CharacterBody2D = sample.actor
		assert(plane.y_sort_enabled, "%s Y-sort plane disabled" % sample.label)
		assert(wrapper.z_index == actor.z_index,
			"%s escaped the shared Y-sort z-domain" % sample.label)
		if bool(sample.front):
			assert(
				actor.global_position.y > wrapper.global_position.y,
				"%s actor did not cross in front of baseline" % sample.label
			)
		else:
			assert(
				actor.global_position.y < wrapper.global_position.y,
				"%s actor did not remain behind baseline" % sample.label
			)
	print(
		(
			"MAP_ALL_PUBLISHED_OCCLUSION_DEPTH_RUNTIME_PASS "
			+ "contract=%s maps=%d crossings=%d families=4 bich_regressions=3"
		)
		% [
			VisualGeometry.OCCLUSION_SORT_CONTRACT_ID,
			covered_maps,
			_samples.size(),
		]
	)
	get_tree().quit(0)


func _occluder_command(instances: Array) -> Dictionary:
	var fallback := {}
	for command: Dictionary in VisualGeometry.sorted_draw_commands(instances):
		if (
			str(command.get("render_domain", ""))
			!= VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT
		):
			continue
		if fallback.is_empty():
			fallback = command
		if (
			str(command.asset.get("asset_type", "")) != "wall_module"
			and str(command.instance.get("object_role", "")) in [
			"building", "obstacle",
		]
		):
			return command
	return fallback


func _add_crossing_probe(
	baseline_world: Vector2,
	screen_center: Vector2,
	actor_in_front: bool,
	actor_kind: String,
	label: String
) -> void:
	var plane := Node2D.new()
	plane.y_sort_enabled = true
	plane.position = screen_center - baseline_world
	add_child(plane)
	var wrapper := Node2D.new()
	wrapper.position = baseline_world
	wrapper.set_meta("map_occlusion_sort_contract_id",
		VisualGeometry.OCCLUSION_SORT_CONTRACT_ID)
	var occluder := _solid_sprite(OCCLUDER_COLOR)
	wrapper.add_child(occluder)
	var actor := CharacterBody2D.new()
	actor.name = "%sDepthProbe" % actor_kind.capitalize()
	actor.add_to_group("player" if actor_kind == "player" else "enemies")
	var actor_sprite := _solid_sprite(
		FRONT_ACTOR_COLOR if actor_in_front else BEHIND_ACTOR_COLOR
	)
	actor.add_child(actor_sprite)
	actor.position = baseline_world + Vector2(
		0.0, 4.0 if actor_in_front else -4.0
	)
	# Oppose scene-tree order in both cases so the sampled result proves that
	# Godot's real Y-sort key, not insertion order, controls the overlap.
	if actor_in_front:
		plane.add_child(actor)
		plane.add_child(wrapper)
	else:
		plane.add_child(wrapper)
		plane.add_child(actor)
	_samples.append({
		"plane": plane,
		"wrapper": wrapper,
		"actor": actor,
		"front": actor_in_front,
		"label": label,
	})


func _solid_sprite(color: Color) -> Sprite2D:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sprite


func _assert_bich_family_baselines() -> void:
	var loaded := MapEditorRuntimeMapService.load_runtime(
		"res://assets/data/runtime/map_editor/bich_province.runtime.json"
	)
	assert(loaded.ok)
	var expected_old_deltas := {
		"inst_000005": 96.0,
		"inst_000018": 48.0,
		"inst_000009": 56.0,
	}
	for instance_id: String in expected_old_deltas:
		var command := _command_by_instance(loaded.runtime.instances, instance_id)
		assert(not command.is_empty(), instance_id)
		var foot := VisualGeometry.instance_foot_tile(
			command.instance, command.asset
		)
		assert(Vector2(command.sort_baseline_tile).is_equal_approx(foot),
			"%s did not use its independent visual foot" % instance_id)
		var old_far_corner_world := MapEditorCoordinate.tile_to_world(
			Vector2(command.sort_tile), Vector2i(80, 80)
		)
		var new_baseline_world := VisualGeometry.command_actor_sort_world(
			command, Vector2i(80, 80)
		)
		assert(is_equal_approx(
			old_far_corner_world.y - new_baseline_world.y,
			float(expected_old_deltas[instance_id])
		), "%s regression delta changed" % instance_id)


func _assert_default_family_crossings() -> void:
	var families := {
		"house": [8, 8],
		"tree": [4, 6],
		"fence_wall": [6, 2],
		"rock": [3, 3],
	}
	var family_index := 0
	for family: String in families:
		var footprint: Array = families[family]
		var instance := {
			"instance_id": "family_%s" % family,
			"tile": [10, 10],
			"footprint_tiles": footprint,
			"object_role": "building" if family == "house" else "obstacle",
			"occlusion": true,
		}
		var asset := {
			"asset_type": "large_prop",
			"image": "%s.png" % family,
			"footprint_tiles": footprint,
			"occlusion": true,
		}
		var commands := VisualGeometry.instance_draw_commands(instance, asset)
		assert(commands.size() == 1)
		var command: Dictionary = commands[0]
		assert(command.render_domain
			== VisualGeometry.RENDER_DOMAIN_ACTOR_Y_SORT)
		var baseline_world := VisualGeometry.command_actor_sort_world(
			command, Vector2i(80, 80)
		)
		var y := 60.0 + float(family_index) * 140.0
		_add_crossing_probe(
			baseline_world, Vector2(430.0, y), false, "player",
			"%s player behind default baseline" % family
		)
		_add_crossing_probe(
			baseline_world, Vector2(510.0, y), true, "monster",
			"%s monster in front of default baseline" % family
		)
		family_index += 1


func _assert_author_override_is_independent() -> void:
	var instance := {
		"tile": [4, 5],
		"footprint_tiles": [8, 6],
		"sort_baseline_tile": [7.25, 9.5],
		"sort_baseline_offset_px": [3, -4],
		"collision_footprint_tiles": [99, 77],
		"anchor_px": [900, 800],
	}
	var asset := {
		"asset_type": "large_prop",
		"footprint_tiles": [8, 6],
		"occlusion": true,
	}
	assert(VisualGeometry.instance_sort_baseline_tile(
		instance, asset
	).is_equal_approx(Vector2(7.25, 9.5)))
	assert(VisualGeometry.instance_sort_baseline_world_offset(
		instance, asset
	).is_equal_approx(Vector2(3, -4)))


func _command_by_instance(instances: Array, instance_id: String) -> Dictionary:
	for command: Dictionary in VisualGeometry.sorted_draw_commands(instances):
		if str(command.instance.get("instance_id", "")) == instance_id:
			return command
	return {}
