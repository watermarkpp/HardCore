extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillAnimationPlayer := preload("res://scripts/caster_skill_animation_player.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")

func _ready() -> void:
	Loader.reload_data()
	print("idx\tendpoint\tfitted\tdiff\tframe_dir\tvisual_axis")
	var owner := PlayerCharacter.new()
	add_child(owner)
	for sample_index: int in range(16):
		var plan := _line_plan("wizard.laser", 8.0, sample_index)
		var endpoint: Vector2 = (plan.geometry_screen_points_px as Array).back()
		var aim_axis := endpoint.normalized()
		var close_effect := _visual_from_cast_nodes(plan, aim_axis * 24.0, aim_axis, owner)
		if close_effect == null:
			print(sample_index, "null")
			continue
		var close_sprite := close_effect._sprites[0] as CasterSkillAnimationPlayer
		var forward := close_sprite.fitted_visual_forward_extent(aim_axis)
		var diff := forward - endpoint.length()
		print("%02d\t%8.4f\t%8.4f\t%+8.5f\t%2d\t(%.3f, %.3f)\tlen=%.4f" % [
			sample_index,
			endpoint.length(),
			forward,
			diff,
			close_sprite.direction_index,
			close_effect._visual_axis_screen_px.x,
			close_effect._visual_axis_screen_px.y,
			close_effect._visual_axis_screen_px.length(),
		])
		close_effect.free()
	owner.free()
	get_tree().quit(0)


func _visual_from_cast_nodes(
	plan: Dictionary,
	target_position: Vector2,
	direction: Vector2,
	owner: PlayerCharacter
) -> CasterSkillVisualEffect:
	var nodes := CasterSkillRuntime.create_cast_nodes(
		plan,
		Vector2.ZERO,
		target_position,
		direction,
		Color.WHITE,
		null,
		owner
	)
	for node: Node2D in nodes:
		if node is CasterSkillVisualEffect:
			return node
	return null

func _line_plan(
	skill_id: String,
	length_tiles: float,
	sample_index: int
) -> Dictionary:
	var tile_aim := Vector2.from_angle(TAU * float(sample_index) / 16.0)
	var strip := SpellGeometry.continuous_line_strip_ground_gu(
		Vector2.ZERO,
		tile_aim,
		Vector2.RIGHT,
		length_tiles,
		1.0,
		skill_id,
		"stability_%s_%02d" % [skill_id, sample_index]
	)
	var world_points := SpellGeometry.continuous_line_screen_points_px(
		strip,
		func(tile: Vector2) -> Vector2:
			return DirectionSpace.ground_delta_gu_to_screen_delta_px(tile)
	)
	var plan := CasterSkillRuntime.resolve(skill_id, {
		"skill_level": 3,
		"caster_level": 40,
		"owner_level": 40,
		"target_level": 20,
		"target_max_hp": 500,
		"magic_stat_roll": 30,
		"random_0_to_10": 0,
	})
	plan["canonical_geometry_contract"] = (
		SpellGeometry.GAME_ROOT_SCREEN_POINT_CONTRACT_ID
	)
	plan["geometry_origin_screen_px"] = Vector2.ZERO
	plan["geometry_grid_cells"] = []
	plan["geometry_screen_points_px"] = world_points
	plan["skill_footprint_snapshot"] = strip.skill_footprint_snapshot
	return plan

