extends Node

const CasterSkillRuntime := preload("res://scripts/caster_skill_runtime.gd")
const CasterSkillVisualEffectScript := preload("res://scripts/caster_skill_visual_effect.gd")
const CasterSkillAnimationPlayer := preload("res://scripts/caster_skill_animation_player.gd")

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

func _ready() -> void:
	var owner := PlayerCharacter.new()
	owner.name = "owner"
	var target := Node2D.new()
	owner.global_position = Vector2(120, 200)
	target.global_position = Vector2(280, 200)
	add_child(owner)
	add_child(target)

	var plan := CasterSkillRuntime.resolve("wizard.lightning", _context())
	var nodes := CasterSkillRuntime.create_cast_nodes(
		plan,
		owner.global_position,
		target.global_position,
		Vector2.RIGHT,
		Color.WHITE,
		target,
		owner,
		30,
		40
	)
	print("nodes.size=", nodes.size())
	assert(nodes.size() == 1)
	var strike := nodes[0] as CasterSkillVisualEffectScript
	assert(strike != null)
	print("visual rejection=", strike.rejection_reason)
	print("visual loaded=", strike.visual_loaded)
	print("visual sprites=", strike._sprites.size())
	assert(strike.visual_loaded)
	print("visual radius=", strike.radius)
	print("visual phase=", strike.phase_id)
	print("visual role=", strike.visual_role)

	add_child(strike)
	assert(not strike.rejection_reason.is_empty() == false)
	assert(strike.radius > 0.0)

	if strike._sprites.is_empty():
		print("no sprites found")
		get_tree().quit(1)
		return
	var sprite := strike._sprites[0] as CasterSkillAnimationPlayer
	assert(sprite != null)
	print("sprite texture=", sprite.texture)
	print("sprite frame_count=", sprite.frame_count())
	print("sprite loaded=", sprite.visual_loaded)
	print("sprite scale=", sprite.scale)
	print("sprite current_frame=", sprite.current_frame_index)
	print("sprite playback_complete=", sprite.playback_complete)
	print("sprite fitted_bounds=", sprite.fitted_visual_bounds())

	for step: int in range(1, 7):
		strike._process(0.05)
		print("tick=%d frame=%d complete=%s elapsed=%0.3f radius=%0.2f" % [
			step,
			sprite.current_frame_index,
			sprite.playback_complete,
			sprite._elapsed,
			strike.radius
		])

	if strike._process(0.0) == null:
		print("process check")
	get_tree().quit(0)
