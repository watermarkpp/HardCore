extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistry := preload("res://scripts/caster_skill_visual_registry.gd")
const CasterSkillVisualEffect := preload("res://scripts/caster_skill_visual_effect.gd")
const CasterSkillSkyStrikeVisualEffect := preload("res://scripts/caster_skill_sky_strike_visual_effect.gd")
const PlayerCharacter := preload("res://scripts/player.gd")
const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const SkillFootprintSnapshot := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)

const DIRECTION_NAMES := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
const DIRECTION_VECTORS: Array[Vector2] = [
	Vector2.DOWN, Vector2(-0.707, 0.707), Vector2.LEFT, Vector2(-0.707, -0.707),
	Vector2.UP, Vector2(0.707, -0.707), Vector2.RIGHT, Vector2(0.707, 0.707),
]


func _context() -> Dictionary:
	return {
		"skill_level": 3, "caster_level": 40, "owner_level": 40,
		"target_level": 20, "target_max_hp": 500,
		"magic_stat_roll": 30, "spiritual_stat_roll": 30, "random_0_to_10": 0,
	}


func _ready() -> void:
	var runtime_profile := CasterSkillVisualRegistry.visual_profile("wizard.hell_lightning")
	assert(CasterSkillVisualRegistry.visual_type("wizard.hell_lightning") == "impact_area")
	assert(runtime_profile.get("anchor", {}).get("type", "origin") == "origin")

	var owner := PlayerCharacter.new()
	owner.global_position = Vector2(320.0, 240.0)
	add_child(owner)

	var ring_cells: Array[Vector2i] = []
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			if x != 0 or y != 0:
				ring_cells.append(Vector2i(x, y))
	var plan := Fixtures.build_canonical_presentation_plan(
		"wizard.hell_lightning",
		3,
		40,
		owner.global_position,
		Vector2.RIGHT,
		owner.global_position,
		Fixtures.cell_union_snapshot(
			self,
			"wizard.hell_lightning",
			"q3c:visual:hell_lightning",
			1,
			Vector2(0, 0),
			ring_cells
		)
	)
	assert(
		bool(plan.get("rejection", {}).get("accepted", false)),
		"canonical hell-lightning plan must be accepted"
	)
	var snapshot_validation_context := (
		SkillFootprintSnapshot.make_absolute_runtime_context(
			1,
			Vector2.ZERO,
			Vector2.ZERO,
			Callable(self, "_ground_to_screen")
		)
	)
	plan["snapshot_validation_context"] = snapshot_validation_context
	for action: Dictionary in plan.get("presentation_actions", []):
		action["snapshot_validation_context"] = snapshot_validation_context

	var results: Array[Dictionary] = []

	for dir_index: int in range(8):
		var dir_name: String = DIRECTION_NAMES[dir_index]
		var dir_vec: Vector2 = DIRECTION_VECTORS[dir_index]

		var nodes := CasterSkillRuntime.create_cast_nodes_from_canonical_plan(
			plan, owner.global_position, dir_vec, Color.WHITE, owner, owner
		)
		assert(nodes.size() >= 1, "visual created for %s" % dir_name)
		var node := nodes[0]
		assert(node is CasterSkillVisualEffect, "node is visual effect for %s" % dir_name)
		assert(not (node is CasterSkillSkyStrikeVisualEffect), "not sky_strike for %s" % dir_name)
		add_child(node)
		assert(
			(node.get("_formal_core_polygons") as Array).is_empty(),
			"hell lightning must not render a translucent range polygon for %s" % dir_name
		)
		assert(
			not node.has_meta("formal_snapshot_visual_core_contract"),
			"hell lightning must not publish a visible formal range core for %s" % dir_name
		)

		var sprites: Array = node.get("_sprites")
		assert(sprites.size() > 0, "sprites exist for %s" % dir_name)
		var sprite: Sprite2D = sprites[0]

		var bounds := _visible_bounds(sprite)
		var entry := {
			"direction": dir_name,
			"dir_index": dir_index,
			"visual_class": node.get_class(),
			"sequence_index": sprite.get("sequence_index") if sprite.has_method("get_sequence_index") else 0,
			"sprite_scale": sprite.scale,
			"sprite_transform": sprite.transform,
			"sprite_global_position": sprite.global_position,
			"bounds_position": bounds.position,
			"bounds_size": bounds.size,
			"bounds_center": bounds.position + bounds.size * 0.5,
			"modulate_a": sprite.modulate.a,
			"self_modulate_a": sprite.self_modulate.a,
		}
		results.append(entry)

	# Print data table.
	print("")
	print("=== HELL_LIGHTNING 8-DIRECTION DATA ===")
	var headers := ["dir", "class", "scale", "transform_origin", "global_pos", "bounds_size", "bounds_center", "mod_a", "self_a"]
	print(" | ".join(headers))
	for entry: Dictionary in results:
		var line := "%3s | %s | %s | %s | %s | %s | %s | %.4f | %.4f" % [
			entry.direction,
			entry.visual_class,
			str(Vector2(entry.sprite_scale)),
			str(Vector2(entry.sprite_transform.origin)),
			str(entry.sprite_global_position),
			str(entry.bounds_size),
			str(entry.bounds_center),
			entry.modulate_a,
			entry.self_modulate_a,
		]
		print(line)
	print("=== END DATA TABLE ===")
	print("")

	# Assertions.
	var baseline := results[0]
	for i: int in range(1, 8):
		var entry := results[i]
		var dir_label := "%s vs %s" % [baseline.direction, entry.direction]

		# visual_class != sky_strike
		assert(entry.visual_class != "CasterSkillSkyStrikeVisualEffect", "%s: not sky_strike" % dir_label)

		# sequence_index identical
		assert(entry.sequence_index == baseline.sequence_index,
			"%s: sequence_index %d != %d" % [dir_label, entry.sequence_index, baseline.sequence_index])

		# scale identical
		assert(entry.sprite_scale.is_equal_approx(baseline.sprite_scale),
			"%s: scale %s != %s" % [dir_label, str(entry.sprite_scale), str(baseline.sprite_scale)])

		# transform identical
		assert(_transform_equal(entry.sprite_transform, baseline.sprite_transform),
			"%s: transform differs" % dir_label)

		# global_position within 0.5px
		var pos_diff: float = entry.sprite_global_position.distance_to(baseline.sprite_global_position)
		assert(pos_diff <= 0.5, "%s: global_pos diff %.3f" % [dir_label, pos_diff])

		# bounds size within 0.5px
		var size_diff: float = entry.bounds_size.distance_to(baseline.bounds_size)
		assert(size_diff <= 0.5, "%s: bounds_size diff %.3f" % [dir_label, size_diff])

		# bounds_center within 0.5px
		var center_diff: float = entry.bounds_center.distance_to(baseline.bounds_center)
		assert(center_diff <= 0.5, "%s: bounds_center diff %.3f" % [dir_label, center_diff])

		# modulate.a >= 0.99
		assert(entry.modulate_a >= 0.99, "%s: modulate.a %.4f < 0.99" % [dir_label, entry.modulate_a])

		# self_modulate.a >= 0.99
		assert(entry.self_modulate_a >= 0.99, "%s: self_modulate.a %.4f < 0.99" % [dir_label, entry.self_modulate_a])

	# Cleanup.
	for entry: Dictionary in results:
		var node: Node = entry.get("node", null)
		if is_instance_valid(node):
			node.queue_free()
	owner.queue_free()

	print("HELL_LIGHTNING_SELF_AREA_VISUAL_TEST_PASS: all 8 directions invariant")
	get_tree().quit(0)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _visible_bounds(sprite: Sprite2D) -> Dictionary:
	if not is_instance_valid(sprite):
		return {"position": Vector2.ZERO, "size": Vector2.ZERO}
	var texture := sprite.texture
	if texture == null:
		return {"position": Vector2.ZERO, "size": Vector2.ZERO}
	var src_size := Vector2(texture.get_width(), texture.get_height())
	var scaled_size := src_size * sprite.scale
	var pos := sprite.global_position - scaled_size * 0.5
	return {"position": pos, "size": scaled_size}


func _transform_equal(a: Transform2D, b: Transform2D) -> bool:
	return a.origin.is_equal_approx(b.origin) and a.get_scale().is_equal_approx(b.get_scale()) and is_equal_approx(a.get_rotation(), b.get_rotation())
