extends Node

const PANEL_CASES := [
	{"name": "inventory", "script": preload("res://scripts/inventory_panel.gd")},
	{"name": "shop", "script": preload("res://scripts/shop_panel.gd")},
	{"name": "warehouse", "script": preload("res://scripts/warehouse_panel.gd")},
	{"name": "quest", "script": preload("res://scripts/quest_panel.gd")},
	{"name": "map", "script": preload("res://scripts/map_panel.gd")},
	{"name": "skill", "script": preload("res://scripts/skill_panel.gd")},
	{"name": "profession", "script": preload("res://scripts/profession_panel.gd")},
]
const VIEWPORT_CASES := [
	{"name": "reference", "size": Vector2i(1280, 720), "insets": Vector4(24, 16, 24, 16)},
	{"name": "wide_phone", "size": Vector2i(1920, 1080), "insets": Vector4(64, 24, 64, 24)},
	{"name": "android_cutout", "size": Vector2i(2400, 1080), "insets": Vector4(120, 32, 96, 40)},
]
const MIN_COMPACT_TOUCH := 40.0
const MIN_PRIMARY_TOUCH := 56.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	for viewport_case: Dictionary in VIEWPORT_CASES:
		for panel_case: Dictionary in PANEL_CASES:
			await _audit_panel(viewport_case, panel_case)
		await _audit_system_menu(viewport_case)
		await _audit_character_hall(viewport_case)
	print("UI_FINAL_CONSISTENCY_PASS：7个主面板、暂停菜单与人物大厅通过1280×720、宽屏手机和Android挖孔安全区验收")
	get_tree().quit(0)


func _audit_panel(viewport_case: Dictionary, panel_case: Dictionary) -> void:
	var fixture := _make_fixture(viewport_case.size)
	var panel: Control = panel_case.script.new()
	fixture.root.add_child(panel)
	await get_tree().process_frame
	var safe_rect := _safe_rect(viewport_case)
	var panel_rect := panel.get_global_rect()
	assert(safe_rect.encloses(panel_rect), "%s/%s 主面板越出安全区：%s / %s" % [viewport_case.name, panel_case.name, panel_rect, safe_rect])
	var viewport_size: Vector2 = Vector2(viewport_case.get("size", Vector2i.ZERO))
	var expected_position: Vector2 = (viewport_size - panel.size) * 0.5
	assert(panel_rect.position.distance_to(expected_position) <= 1.0, "%s/%s 主面板没有居中" % [viewport_case.name, panel_case.name])
	_audit_controls(panel, panel_rect, "%s/%s" % [viewport_case.name, panel_case.name])
	fixture.viewport.queue_free()
	await get_tree().process_frame


func _audit_system_menu(viewport_case: Dictionary) -> void:
	var fixture := _make_fixture(viewport_case.size)
	var menu: Control = preload("res://scripts/system_menu_panel.gd").new()
	fixture.root.add_child(menu)
	await get_tree().process_frame
	var modal_rect: Rect2 = menu.modal.get_global_rect()
	assert(_safe_rect(viewport_case).encloses(modal_rect), "%s/system_menu 越出安全区" % viewport_case.name)
	var viewport_size: Vector2 = Vector2(viewport_case.get("size", Vector2i.ZERO))
	var expected_position: Vector2 = (viewport_size - menu.modal.size) * 0.5
	assert(modal_rect.position.distance_to(expected_position) <= 1.0, "%s/system_menu 没有在宽屏居中" % viewport_case.name)
	_audit_controls(menu.modal, modal_rect, "%s/system_menu" % viewport_case.name)
	fixture.viewport.queue_free()
	await get_tree().process_frame


func _audit_character_hall(viewport_case: Dictionary) -> void:
	var fixture := _make_fixture(viewport_case.size)
	var hall: Control = load("res://scenes/character_select.tscn").instantiate()
	hall.suppress_scene_change_for_test = true
	fixture.root.add_child(hall)
	await get_tree().process_frame
	var viewport_size: Vector2 = Vector2(viewport_case.get("size", Vector2i.ZERO))
	var expected_position: Vector2 = (viewport_size - hall.content_root.size) * 0.5
	assert(hall.content_root.get_global_rect().position.distance_to(expected_position) <= 1.0, "%s/character_hall 内容画布没有在宽屏居中" % viewport_case.name)
	var safe_rect := _safe_rect(viewport_case)
	for node_name: String in ["RosterPanel", "CharacterPreviewPanel", "CreationPanel"]:
		var panel := hall.content_root.get_node(node_name) as Control
		assert(safe_rect.encloses(panel.get_global_rect()), "%s/character_hall/%s 越出安全区" % [viewport_case.name, node_name])
		_audit_controls(panel, panel.get_global_rect(), "%s/character_hall/%s" % [viewport_case.name, node_name])
	fixture.viewport.queue_free()
	await get_tree().process_frame


func _audit_controls(root: Control, owner_rect: Rect2, context: String) -> void:
	for child: Node in root.find_children("*", "Control", true, false):
		var control := child as Control
		if not control.visible:
			continue
		assert(is_finite(control.position.x) and is_finite(control.position.y), "%s/%s 坐标无效" % [context, control.name])
		assert(control.size.x >= 0.0 and control.size.y >= 0.0, "%s/%s 尺寸无效" % [context, control.name])
		if control is Button:
			assert(control.size.x >= MIN_COMPACT_TOUCH and control.size.y >= MIN_COMPACT_TOUCH, "%s/%s 触控区不足40px：%s" % [context, control.name, control.size])
			if _is_primary_action(control):
				assert(control.size.y >= MIN_PRIMARY_TOUCH, "%s/%s 主操作触控高度不足56px：%s" % [context, control.name, control.size])
			if not _has_scroll_ancestor(control, root):
				assert(owner_rect.grow(0.5).encloses(control.get_global_rect()), "%s/%s 按钮越出所属主框" % [context, control.name])
		if control is Label and control.get_parent() is Control:
			var parent := control.get_parent() as Control
			if not parent is Container and parent.size.x > 0.0 and parent.size.y > 0.0:
				assert(
					parent.get_global_rect().grow(0.5).encloses(control.get_global_rect()),
					"%s/%s 文字越出直接父框：child=%s parent=%s" % [context, control.name, control.get_global_rect(), parent.get_global_rect()]
				)


func _is_primary_action(button: Button) -> bool:
	if button is CheckButton:
		return false
	var stable_id := str(button.get_meta("stable_id", ""))
	if stable_id.begins_with("system_menu.") or stable_id in ["character.launch", "character.create"]:
		return true
	return button.name in [
		"CloseButton",
		"ActionButton",
		"AbandonButton",
		"BuyButton",
		"SellOneButton",
		"SellQuantityButton",
		"ConfirmProfession",
		"TeleportButton",
	]


func _has_scroll_ancestor(control: Control, root: Control) -> bool:
	var cursor := control.get_parent()
	while cursor != null and cursor != root:
		if cursor is ScrollContainer:
			return true
		cursor = cursor.get_parent()
	return false


func _make_fixture(viewport_size: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.disable_3d = true
	viewport.gui_embed_subwindows = true
	add_child(viewport)
	var root := Control.new()
	root.name = "FixtureRoot"
	root.position = Vector2.ZERO
	root.size = Vector2(viewport_size)
	viewport.add_child(root)
	return {"viewport": viewport, "root": root}


func _safe_rect(viewport_case: Dictionary) -> Rect2:
	var size := Vector2(viewport_case.size)
	var insets: Vector4 = viewport_case.insets
	return Rect2(insets.x, insets.y, size.x - insets.x - insets.z, size.y - insets.y - insets.w)
