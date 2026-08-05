extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const GeometryService := preload("res://scripts/skills/skill_geometry_service.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")
const CasterSkillAnimationPlayer := preload("res://scripts/caster_skill_animation_player.gd")
const PlayerCharacter := preload("res://scripts/player.gd")

func _ready() -> void:
	var origin_tile := Vector2i(9, 11)
	var origin_world := Vector2(0, 0)
	var plan := _build_laser_plan()
	var owner := PlayerCharacter.new()
	add_child(owner)
	var effect := CasterSkillRuntime.create_visual(plan, origin_world, Vector2.DOWN, owner)
	assert(effect != null)
	assert(not effect._sprites.is_empty())
	add_child(effect)
	print("effect desired_axis=%0.6f desired_cross=%0.6f desired_extent=%0.6f desired_footprint=%s" % [
		float(effect._desired_sprite_axis_extent_px),
		float(effect._desired_sprite_cross_axis_extent_px),
		float(effect._desired_sprite_extent_px),
		str(effect._desired_sprite_footprint_px)
	])
	print("beam context length=%0.6f axis=%s" % [
		float(effect._beam_length_px),
		str(effect._beam_axis_screen_px)
	])
	for idx: int in range(effect._sprites.size()):
		var raw_sprite := effect._sprites[idx]
		if not raw_sprite is CasterSkillAnimationPlayer:
			continue
		var sprite := raw_sprite as CasterSkillAnimationPlayer
		print("sprite_%d direction_index=%d source_axis=%s forward=%0.6f cross=%0.6f wanted=256/45.254" % [
			idx,
			int(sprite.direction_index),
			str(sprite._source_axis_local),
			sprite.fitted_visual_forward_extent(Vector2.DOWN),
			sprite.fitted_visual_cross_extent(Vector2.DOWN)
		])
		var expected_cross := float(sqrt(64.0 * 32.0))
		print("frame0 forward=%0.6f cross=%0.6f visible_cross=%0.6f" % [
			sprite.fitted_visual_forward_extent(Vector2.DOWN),
			sprite.fitted_visual_cross_extent(Vector2.DOWN),
			sprite.current_frame_visible_cross_extent(Vector2.DOWN)
		])
	print("done")
	get_tree().quit(0)

func _build_laser_plan() -> Dictionary:
	var plan := CasterSkillRuntime.resolve("wizard.laser", {
		"skill_level": 3,
		"caster_level": 40,
		"owner_level": 40,
		"target_level": 20,
		"target_max_hp": 500,
		"magic_stat_roll": 30,
		"random_0_to_10": 0,
	})
	var cells := GeometryService.cells(
		CasterSkillRuntime.resolve("wizard.laser", {
			"skill_level": 3,
			"caster_level": 40,
			"owner_level": 40,
			"target_level": 20,
			"target_max_hp": 500,
			"magic_stat_roll": 30,
			"random_0_to_10": 0,
		}).get("visual",{}),
		Vector2i.ZERO,
		Vector2i.DOWN
	)
	var world_points: Array[Vector2] = []
	for cell: Vector2i in cells:
		world_points.append(Vector2(cell) * 32.0)
	plan["canonical_geometry_contract"] = SpellGeometry.GAME_ROOT_SCREEN_POINT_CONTRACT_ID
	plan["geometry_origin_screen_px"] = Vector2.ZERO
	plan["geometry_grid_cells"] = cells
	plan["geometry_screen_points_px"] = world_points
	plan["skill_footprint_snapshot"] = {}
	plan["geometry_screen_offsets_px"] = world_points
	return plan
