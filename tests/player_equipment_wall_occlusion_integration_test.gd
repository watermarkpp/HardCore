extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	var visual: CanvasItem = player.visual
	assert(visual is Node2D, "PlayerVisual must be one non-Y-sorted canvas subtree")
	assert(not visual is CanvasGroup, "CanvasGroup does not collapse child world Z planes")
	assert(visual.z_index == 0)
	assert(visual.z_as_relative)
	assert(not visual.y_sort_enabled)
	assert(not visual.show_behind_parent)
	assert(not visual.is_set_as_top_level())
	assert(str(visual.get_meta("actor_render_domain", "")) == "actor_y_sort")
	assert(
		str(visual.get_meta("actor_composite_sort_contract", ""))
		== EquipmentRules.ACTOR_VISUAL_SORT_CONTRACT_ID
	)
	var body := visual.get_node("BodySprite") as Sprite2D
	var hair := visual.get_node("ClientHairLayer") as Sprite2D
	var weapon := visual.get_node("ClientWeaponLayer") as Sprite2D
	var helmet := visual.get_node("ClientHelmetLayer") as Sprite2D
	var skill_effect := visual.get_node("ClientSkillEffect") as Sprite2D
	assert(body != null and hair != null and weapon != null and helmet != null)
	assert(body.get_parent() == visual)
	assert(hair.get_parent() == visual)
	assert(weapon.get_parent() == visual)
	assert(helmet.get_parent() == visual)
	assert(
		body.z_index == 0
		and hair.z_index == 0
		and weapon.z_index == 0
		and helmet.z_index == 0
	)
	assert(skill_effect != null and skill_effect.z_index == 0, "skill effect escaped actor wall-sort plane")
	for direction_row: int in range(8):
		visual.set("current_direction", direction_row)
		visual.set("_equipment_layer_direction", -1)
		visual.call("_update_equipment_layers")
		assert(body.get_index() < hair.get_index())
		assert(body.get_index() < helmet.get_index())
		if EquipmentRules.weapon_draws_behind_actor(direction_row):
			assert(weapon.get_index() < body.get_index(), "back weapon order wrong for row %d" % direction_row)
		else:
			assert(hair.get_index() < weapon.get_index(), "front weapon order wrong for row %d" % direction_row)
			assert(weapon.get_index() < helmet.get_index(), "helmet must remain frontmost for row %d" % direction_row)
	for child: Node in visual.get_children():
		if child is CanvasItem:
			assert(not (child as CanvasItem).is_set_as_top_level())
			assert((child as CanvasItem).z_index == 0, "%s escaped actor Z=0 plane" % child.name)
	assert(player.health_bar.get_parent() == player)
	assert(player.health_bar.get_parent() != visual, "health bar remains outside wall composite")
	print("PLAYER_EQUIPMENT_WALL_OCCLUSION_INTEGRATION_PASS")
	get_tree().quit(0)
