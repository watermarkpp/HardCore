extends Node

const InventoryPanelScript := preload("res://scripts/inventory_panel.gd")
const MapPanelScript := preload("res://scripts/map_panel.gd")
const SkillPanelScript := preload("res://scripts/skill_panel.gd")
const WarehousePanelScript := preload("res://scripts/warehouse_panel.gd")
const DeathPanelScript := preload("res://scripts/death_revival_panel.gd")

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
	for script in [InventoryPanelScript, MapPanelScript, SkillPanelScript, WarehousePanelScript]:
		var panel := script.new() as Control
		root.add_child(panel)
		await get_tree().process_frame
		var surface := panel.get_node("ModalSurface") as Control
		assert(surface != null and Rect2(Vector2.ZERO, panel.size).encloses(surface.get_rect()), "%s modal surface escapes outer frame" % panel.name)
		assert(surface.get_theme_stylebox("panel").bg_color != Color.BLACK)
		var outer_gap := surface.position.y + surface.size.y
		for child in panel.get_children():
			if child is Control and child.name.ends_with("Panel"):
				assert((child as Control).position.y + (child as Control).size.y <= outer_gap - 8.0)
		for child in panel.get_children():
			if child.name.ends_with("Panel") and child is Control:
				var section := child as Control
				var section_surface := panel.get_node_or_null("%sSurface" % child.name) as Control
				if section_surface != null:
					assert(section_surface.get_theme_stylebox("panel").bg_color != Color.BLACK)
					var inset: Vector2 = section_surface.position - section.position
					assert(inset.x >= 8.0 and inset.y >= 8.0)
					assert(section.size.x - section_surface.size.x - inset.x >= 8.0)
					assert(section.size.y - section_surface.size.y - inset.y >= 8.0)
		panel.queue_free()
		await get_tree().process_frame
	var death := DeathPanelScript.new() as Control
	root.add_child(death)
	await get_tree().process_frame
	var death_surface := death.get_node("ModalSurface") as Control
	var death_modal := death.get_node("DeathRevivalModal") as Control
	assert(death_surface != null and death_modal != null)
	assert(Rect2(death_modal.position, death_modal.size).encloses(death_surface.get_rect()))
	viewport.queue_free()
	await get_tree().process_frame
	print("UI_MODAL_SURFACE_CONTAINMENT_PASS")
	get_tree().quit(0)
