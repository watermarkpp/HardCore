extends Node

const InventoryPanelScript := preload("res://scripts/inventory_panel.gd")
const MapPanelScript := preload("res://scripts/map_panel.gd")
const SkillPanelScript := preload("res://scripts/skill_panel.gd")
const WarehousePanelScript := preload("res://scripts/warehouse_panel.gd")
const ShopPanelScript := preload("res://scripts/shop_panel.gd")
const QuestPanelScript := preload("res://scripts/quest_panel.gd")
const DeathPanelScript := preload("res://scripts/death_revival_panel.gd")
const GothicFrameFillScript := preload("res://scripts/gothic_frame_fill.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	viewport.add_child(root)
	add_child(viewport)
	for script in [InventoryPanelScript, MapPanelScript, SkillPanelScript, WarehousePanelScript, ShopPanelScript, QuestPanelScript]:
		var panel := script.new() as Control
		root.add_child(panel)
		await get_tree().process_frame
		var surface := panel.get_node("ModalSurface") as Control
		assert(surface != null and surface.get_script() == GothicFrameFillScript, "%s level-1 fill is not code-drawn" % panel.name)
		var expected_surface := Rect2(
			GothicFrameFactoryScript.MODAL_INNER_POSITION,
			panel.size - GothicFrameFactoryScript.MODAL_INNER_POSITION - GothicFrameFactoryScript.MODAL_INNER_END_INSET,
		)
		assert(surface.get_rect().is_equal_approx(expected_surface), "%s level-1 fill is not locked to the measured inner opening" % panel.name)
		assert(surface.show_behind_parent, "%s level-1 fill can cover the double-ring frame" % panel.name)
		var overlay := panel.get_node_or_null("ModalFrameSafetyOverlay") as Control
		if panel.get_script() != SkillPanelScript:
			assert(overlay != null, "%s is missing the modal safety overlay" % panel.name)
			assert(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s overlay must ignore mouse input" % panel.name)
			assert(overlay.z_index == GothicFrameFactoryScript.MODAL_OVERLAY_Z_INDEX, "%s overlay z plane drifted" % panel.name)
			var sealed_close_controls := _find_close_controls(panel)
			assert(not sealed_close_controls.is_empty(), "%s must expose a close control" % panel.name)
			for close_control in sealed_close_controls:
				assert(close_control.z_index > overlay.z_index, "%s close control must draw above overlay" % panel.name)
		else:
			assert(overlay == null, "skill panel must remain unsealed")
			var skill_close_controls := _find_close_controls(panel)
			assert(not skill_close_controls.is_empty(), "skill panel must expose a close control")
			for close_control in skill_close_controls:
				assert(close_control.get_parent() == panel and close_control.z_index >= 0, "skill close control must remain on root frame")
		for child in panel.get_children():
			if not child is Control:
				continue
			var section := child as Control
			if overlay != null and section != overlay and not (section.name == &"CloseButton" or section.theme_type_variation == &"GothicComponentCloseButton"):
				assert(section.z_index < overlay.z_index, "%s/%s ordinary section must remain below overlay" % [panel.name, section.name])
			var decoration := section.get_node_or_null("%sDecoration" % section.name) as Control
			if decoration == null:
				continue
			var fill := decoration.get_node_or_null("%sFill" % section.name) as Control
			var frame := decoration.get_node_or_null("%sFrame" % section.name) as Panel
			assert(fill != null and fill.get_script() == GothicFrameFillScript, "%s/%s level-2 fill is not code-drawn" % [panel.name, section.name])
			assert(frame != null and frame.theme_type_variation == "GothicInsetFrame", "%s/%s single-ring frame is missing" % [panel.name, section.name])
			assert(fill.get_rect().is_equal_approx(Rect2(Vector2.ZERO, decoration.size)), "%s/%s fill does not track decoration size" % [panel.name, section.name])
			assert(frame.get_rect().is_equal_approx(Rect2(Vector2.ZERO, decoration.size)), "%s/%s frame does not track decoration size" % [panel.name, section.name])
		panel.queue_free()
		await get_tree().process_frame
	var death := DeathPanelScript.new() as Control
	root.add_child(death)
	await get_tree().process_frame
	var death_modal := death.get_node("DeathRevivalModal") as Control
	var death_surface := death_modal.get_node("ModalSurface") as Control
	assert(death_surface != null and death_modal != null and death_surface.get_script() == GothicFrameFillScript)
	assert(death_surface.show_behind_parent)
	viewport.queue_free()
	await get_tree().process_frame
	print("UI_MODAL_SURFACE_CONTAINMENT_PASS")
	get_tree().quit(0)


func _find_close_controls(root: Node) -> Array[Control]:
	var result: Array[Control] = []
	_find_close_controls_recursive(root, result)
	return result


func _find_close_controls_recursive(node: Node, result: Array[Control]) -> void:
	if node is Control:
		var control := node as Control
		if control.name == &"CloseButton" or control.theme_type_variation == &"GothicComponentCloseButton":
			result.append(control)
	for child in node.get_children():
		_find_close_controls_recursive(child, result)
