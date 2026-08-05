extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualRegistry := preload(
	"res://scripts/caster_skill_visual_registry.gd"
)
const CasterSkillSkyStrikeVisualEffect := preload(
	"res://scripts/caster_skill_sky_strike_visual_effect.gd"
)
const PlayerCharacter := preload("res://scripts/player.gd")


func _context() -> Dictionary:
	return {
		"skill_level": 3,
		"caster_level": 40,
		"owner_level": 40,
		"target_level": 20,
		"target_max_hp": 500,
		"magic_stat_roll": 30,
		"spiritual_stat_roll": 30,
		"random_0_to_10": 0,
	}


func _anchor_offset() -> Vector2:
	var profile: Dictionary = CasterSkillVisualRegistry.visual_profile("wizard.lightning")
	var anchor_profile: Dictionary = profile.get("anchor", {})
	var raw_offset: Variant = anchor_profile.get("offset", [0.0, 0.0])
	if raw_offset is Array and raw_offset.size() >= 2:
		return Vector2(float(raw_offset[0]), float(raw_offset[1]))
	return Vector2.ZERO


func _ready() -> void:
	var owner := PlayerCharacter.new()
	var target := Node2D.new()
	owner.global_position = Vector2(160.0, 88.0)
	target.global_position = Vector2(420.0, 296.0)
	add_child(owner)
	add_child(target)

	var plan := CasterSkillRuntime.resolve("wizard.lightning", _context())
	var offset: Vector2 = _anchor_offset()
	var base_node := CasterSkillRuntime.create_visual(
		plan,
		owner.global_position,
		Vector2.RIGHT,
		target,
		""
	)
	assert(base_node != null)
	add_child(base_node)
	assert(base_node is CasterSkillSkyStrikeVisualEffect)
	base_node._process(0.0)
	assert(
		base_node.global_position == (target.global_position + offset).round(),
		"Lightning profile anchor should use target footprint-derived anchor"
	)

	var runtime_map_plan := plan.duplicate(true)
	runtime_map_plan["visual_geometry_context"] = {
		"gameplay_geometry": {
			"origin": Vector2(1000.0, 640.0),
		},
	}
	var runtime_map_node := CasterSkillRuntime.create_visual(
		runtime_map_plan,
		owner.global_position,
		Vector2.RIGHT,
		target,
		""
	)
	assert(runtime_map_node != null)
	assert(runtime_map_node is CasterSkillSkyStrikeVisualEffect)
	add_child(runtime_map_node)
	runtime_map_node._process(0.0)
	assert(
		runtime_map_node.global_position == (target.global_position + offset).round(),
		"Sky strike should not drift from runtime map gameplay geometry origin"
	)

	target.global_position = Vector2(470.0, 320.0)
	var moved_plan := plan.duplicate(true)
	var moved_node := CasterSkillRuntime.create_visual(
		moved_plan,
		owner.global_position,
		Vector2.RIGHT,
		target,
		""
	)
	add_child(moved_node)
	moved_node._process(0.0)
	assert(
		moved_node.global_position == (target.global_position + offset).round(),
		"Lightning anchor should continue following runtime target"
	)

	base_node.free()
	runtime_map_node.free()
	moved_node.free()
	owner.free()
	target.free()
	print("LIGHTNING_RUNTIME_MAP_VISUAL_TEST_PASS")
	get_tree().quit(0)
