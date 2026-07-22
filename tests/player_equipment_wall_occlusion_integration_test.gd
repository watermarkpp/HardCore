extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	var visual: CanvasItem = player.visual
	assert(visual is CanvasGroup, "PlayerVisual must be one composite CanvasItem")
	assert(visual.z_index == 0)
	assert(visual.z_as_relative)
	assert(not visual.y_sort_enabled)
	assert(not visual.show_behind_parent)
	assert(not visual.is_set_as_top_level())
	assert(str(visual.get_meta("actor_render_domain", "")) == "actor_y_sort")
	assert(
		str(visual.get_meta("actor_composite_sort_contract", ""))
		== "equipment_actor_visual_sort_unit_v1"
	)
	var body := visual.get_node("BodySprite") as Sprite2D
	var weapon := visual.get_node("ClientWeaponLayer") as Sprite2D
	var helmet := visual.get_node("ClientHelmetLayer") as Sprite2D
	assert(body != null and weapon != null and helmet != null)
	assert(body.get_parent() == visual)
	assert(weapon.get_parent() == visual)
	assert(helmet.get_parent() == visual)
	assert(helmet.z_index == 2, "helmet internal order must remain inside CanvasGroup")
	for child: Node in visual.get_children():
		if child is CanvasItem:
			assert(not (child as CanvasItem).is_set_as_top_level())
	assert(player.health_bar.get_parent() == player)
	assert(player.health_bar.get_parent() != visual, "health bar remains outside wall composite")
	print("PLAYER_EQUIPMENT_WALL_OCCLUSION_INTEGRATION_PASS")
	get_tree().quit(0)
