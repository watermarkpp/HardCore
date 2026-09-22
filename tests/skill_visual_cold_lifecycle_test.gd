extends Node2D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 10000
	player.current_hp = 10000
	player.max_mp = 1000
	player.apply_magic_shield(60.0, 0.5)
	CasterSkillVisualRegistry.clear_frame_texture_cache()
	CasterSkillVisualRegistry.set_loading_window_active(false)
	var effect := CasterSkillVisualEffect.new()
	effect.setup(Vector2.ZERO, "wizard.magic_shield", 72.0, 0.8, Vector2.DOWN, player)
	add_child(effect)
	effect.set_process(false)
	var sprite: CasterSkillAnimationPlayer = effect._sprites[0]
	sprite.set_process(false)
	assert(not sprite.visual_loaded, "cold fixture must wait for the real frame sequence")
	# Advance the owner through a long frame while the real async queue is not
	# yet serviced. A resource wait is not elapsed animation playback.
	player.take_damage(1, true, {}, true)
	assert(player.struck_reaction_snapshot().reaction_lock_remaining > 0.0)
	effect._process(5.0)
	assert(not effect.is_queued_for_deletion(), "active magic shield was destroyed while its sequence was warming")
	assert(sprite.current_frame_index == 0 and not sprite.playback_complete)
	for path: String in CasterSkillVisualRegistry.animation_sequence_paths("wizard.magic_shield", sprite.direction_index, ""):
		CasterSkillVisualRegistry.retain_loaded_texture(path, load(path))
	sprite._process(0.0)
	assert(sprite.visual_loaded and sprite.current_frame_index == 0)
	sprite._process(sprite.animation_duration() * 0.5)
	var halfway := sprite.current_frame_index
	effect._process(5.0)
	assert(not effect.is_queued_for_deletion(), "owner timeout truncated shield formation after a stall")
	sprite._process(sprite.animation_duration())
	assert(sprite.playback_complete and sprite.current_frame_index == sprite.frame_count() - 1 and halfway > 0)
	effect._process(10.0)
	assert(not effect.is_queued_for_deletion(), "active shield must retain its final frame")
	var replacement := CasterSkillVisualEffect.new()
	replacement.setup(Vector2.ZERO, "wizard.magic_shield", 72.0, 0.8, Vector2.DOWN, player)
	add_child(replacement)
	assert(effect.is_queued_for_deletion(), "recast must release the replaced shield owner")
	player.shield_capacity = 0.0
	replacement._process(0.0)
	assert(replacement.is_queued_for_deletion(), "shield depletion must still remove its visual")
	await get_tree().process_frame
	for skill: String in ["wizard.repulsion_ring", "taoist.healing", "wizard.hellfire"]:
		await _cold_one_shot(skill, player)
	player.queue_free()
	await get_tree().process_frame
	print("SKILL_VISUAL_COLD_LIFECYCLE_PASS")
	get_tree().quit()

func _cold_one_shot(skill: String, player: PlayerCharacter) -> void:
	CasterSkillVisualRegistry.clear_frame_texture_cache()
	var effect := CasterSkillVisualEffect.new()
	effect.setup(Vector2.ZERO, skill, 72.0, 0.8, Vector2.DOWN, player)
	add_child(effect)
	effect.set_process(false)
	assert(not effect._sprites.is_empty(), skill)
	for sprite: CasterSkillAnimationPlayer in effect._sprites:
		sprite.set_process(false)
		assert(not sprite.visual_loaded, skill)
	var emissions := effect._hellfire_emissions
	effect._process(5.0)
	assert(not effect.is_queued_for_deletion(), "cold one-shot truncated: " + skill)
	assert(effect._hellfire_emissions == emissions, "cold hellfire must not consume invisible trail emissions")
	for sprite: CasterSkillAnimationPlayer in effect._sprites:
		for path: String in CasterSkillVisualRegistry.animation_sequence_paths(skill, sprite.direction_index, ""):
			CasterSkillVisualRegistry.retain_loaded_texture(path, load(path))
		sprite._process(0.0)
		assert(sprite.visual_loaded, skill)
	# Parent runs first in a long frame; its child still gets to complete.
	effect._process(0.01)
	if skill != "wizard.hellfire":
		effect._process(5.0)
		assert(not effect.is_queued_for_deletion(), "long parent tick truncated live child playback: " + skill)
		for sprite: CasterSkillAnimationPlayer in effect._sprites:
			sprite._process(sprite.animation_duration() + 0.01)
			assert(sprite.playback_complete, skill)
	effect._process(5.0)
	assert(effect.is_queued_for_deletion(), "completed effect must clean up: " + skill)
	await get_tree().process_frame
