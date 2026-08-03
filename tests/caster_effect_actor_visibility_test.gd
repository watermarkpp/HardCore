extends Node


class ActiveShieldOwner:
	extends Node2D

	func magic_shield_snapshot() -> Dictionary:
		return {"active": true}


func _ready() -> void:
	var owner := ActiveShieldOwner.new()
	add_child(owner)
	owner.global_position = Vector2(123.4, 77.6)
	for skill_id: String in [
		"wizard.magic_shield",
		"wizard.hell_lightning",
		"wizard.hellfire",
		"wizard.laser",
		"wizard.exploding_flame",
		"wizard.lightning",
	]:
		var role := CasterSkillVisualRegistry.visual_role(skill_id)
		var attachment := str(
			CasterSkillVisualRegistry.render_policy(skill_id).get(
				"attachment_policy", "world_anchor"
			)
		)
		var follow_node: Node2D = (
			owner if attachment in ["caster_actor", "target_actor"] else null
		)
		var effect := CasterSkillVisualEffect.new()
		effect.setup(
			owner.global_position,
			skill_id,
			160.0,
			1.0,
			Vector2.DOWN,
			follow_node
		)
		add_child(effect)
		assert(effect.visual_role == role)
		assert(effect.z_as_relative)
		assert(
			effect.z_index == CasterSkillVisualEffect.ACTOR_VISIBILITY_Z_INDEX
		)
		assert(
			effect.get_meta("actor_visibility_render_contract", "")
			== CasterSkillVisualEffect.ACTOR_VISIBILITY_RENDER_CONTRACT_ID
		)
		if follow_node != null:
			assert(effect.global_position.is_equal_approx(owner.global_position))
		effect.free()
	owner.free()
	print(
		"CASTER_EFFECT_ACTOR_VISIBILITY_PASS: generic target/self/area/line effects use z=-1 below z=0 actors at exact footpoints"
	)
	get_tree().quit(0)
