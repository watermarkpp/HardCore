class_name MapPanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")

signal map_selected(map_id: int)
signal teleport_availability_requested(map_ids: Array)
signal teleport_requested(request: Dictionary)
signal closed

const PANEL_SIZE := Vector2(1160, 650)
const MODAL_SURFACE_INSET := Vector4(32, 38, 32, 34)
const MAP_CARD_SIZE := Vector2(226, 58)
const WORLD_NODE_SIZE := Vector2(430, 50)
const WORLD_TREE_BLUEPRINT := [
	{"node_id": "mafa_world", "label": "HardCore 世界", "depth": 0},
	{"node_id": "bich_province", "label": "比奇省", "depth": 1, "regions": ["比奇地区"]},
	{"node_id": "orc_tomb", "label": "兽人古墓／骷髅洞", "depth": 2, "map_groups": ["兽人古墓"]},
	{"node_id": "natural_cave", "label": "天然洞穴", "depth": 2, "map_groups": ["天然洞穴"]},
	{"node_id": "bich_mine", "label": "比奇矿区／僵尸洞", "depth": 2, "map_groups": ["比奇矿区"]},
	{"node_id": "wooma_forest", "label": "沃玛森林", "depth": 1, "regions": ["沃玛地区"]},
	{"node_id": "wooma_temple", "label": "沃玛寺庙", "depth": 2, "map_groups": ["沃玛寺庙"]},
	{"node_id": "white_sun_red_moon", "label": "白日门／赤月峡谷", "depth": 2, "regions": ["白日门区"]},
	{"node_id": "fengmo_valley", "label": "封魔谷", "depth": 2, "regions": ["封魔谷区"]},
	{"node_id": "viper_valley", "label": "毒蛇山谷", "depth": 1, "regions": ["毒蛇地区"]},
	{"node_id": "mengzhong_province", "label": "盟重省", "depth": 1, "regions": ["盟重地区"]},
	{"node_id": "xiangshi_tomb", "label": "沙巴克密道／香石古墓", "depth": 2, "name_terms": ["沙巴克密道", "香石"]},
	{"node_id": "stone_tomb", "label": "石墓／猪洞", "depth": 2, "map_groups": ["石墓"]},
	{"node_id": "zuma_temple", "label": "祖玛寺庙", "depth": 2, "map_groups": ["祖玛寺庙"]},
	{"node_id": "centipede_cave", "label": "蜈蚣洞／死亡山谷", "depth": 2, "map_groups": ["蜈蚣洞"]},
	{"node_id": "cangyue_island", "label": "苍月岛", "depth": 1, "regions": ["苍月地区"]},
	{"node_id": "corpse_cave", "label": "尸魔洞", "depth": 2, "map_groups": ["尸魔洞"]},
	{"node_id": "bone_cave", "label": "骨魔洞", "depth": 2, "map_groups": ["骨魔洞"]},
	{"node_id": "cow_temple", "label": "牛魔寺庙", "depth": 2, "map_groups": ["牛魔寺庙"]},
]

var search_box: LineEdit
var later_toggle: CheckButton
var map_list: ItemList
var map_list_container: VBoxContainer
var detail_label: RichTextLabel
var count_label: Label
var map_name_label: Label
var teleport_button: Button
var world_tree_scroll: ScrollContainer
var world_tree_container: VBoxContainer
var world_tree_nodes: Array = WORLD_TREE_BLUEPRINT.duplicate(true)
var world_node_buttons: Dictionary = {}
var map_entries: Array = []
var map_buttons: Array[Button] = []
var teleport_rules: Dictionary = {}
var _selected_map_id := -1
var _selected_world_node_id := "mafa_world"
var _detail_base_text := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_top = -PANEL_SIZE.y * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_bottom = PANEL_SIZE.y * 0.5
	z_index = 75
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GothicUIThemeScript.build()
	theme_type_variation = "GothicModalFrame"
	_build_modal_surface()
	_build_header()
	_build_map_list_section()
	_build_world_tree_section()
	_build_map_detail_section()
	_build_compatibility_list()
	_rebuild_world_tree()
	refresh()


func _build_modal_surface() -> void:
	var surface := Panel.new()
	surface.name = "ModalSurface"
	surface.position = Vector2(MODAL_SURFACE_INSET.x, MODAL_SURFACE_INSET.y)
	surface.size = PANEL_SIZE - Vector2(MODAL_SURFACE_INSET.x + MODAL_SURFACE_INSET.z, MODAL_SURFACE_INSET.y + MODAL_SURFACE_INSET.w)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(350, 4)
	title_frame.size = Vector2(460, 64)
	title_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_frame.theme_type_variation = "GothicTitleBar"
	add_child(title_frame)
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "世界地图"
	title.position = Vector2(30, 15)
	title.size = Vector2(400, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f1cc88"))
	title_frame.add_child(title)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.position = Vector2(1080, 8)
	close_button.size = Vector2(56, 56)
	close_button.theme_type_variation = "GothicComponentCloseButton"
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(_close)
	add_child(close_button)


func _build_map_list_section() -> void:
	var panel := _framed_section("MapListPanel", Rect2(20, 76, 270, 548))
	panel.add_child(_section_title("区域地图", 270))
	search_box = LineEdit.new()
	search_box.name = "SearchBox"
	search_box.placeholder_text = "在当前区域搜索"
	search_box.position = Vector2(18, 54)
	search_box.size = Vector2(234, 50)
	search_box.theme_type_variation = "GothicSearchField"
	search_box.text_changed.connect(func(_value: String) -> void: refresh())
	panel.add_child(search_box)
	later_toggle = CheckButton.new()
	later_toggle.name = "LaterContentToggle"
	later_toggle.text = "显示1.76后期地图"
	later_toggle.position = Vector2(18, 112)
	later_toggle.size = Vector2(234, 44)
	later_toggle.theme_type_variation = "GothicContentToggle"
	later_toggle.toggled.connect(_on_later_toggled)
	panel.add_child(later_toggle)
	var scroll := ScrollContainer.new()
	scroll.name = "MapListScroll"
	scroll.position = Vector2(18, 164)
	scroll.size = Vector2(234, 326)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	map_list_container = VBoxContainer.new()
	map_list_container.name = "MapCards"
	map_list_container.custom_minimum_size = Vector2(226, 0)
	map_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list_container.add_theme_constant_override("separation", 7)
	scroll.add_child(map_list_container)
	count_label = Label.new()
	count_label.name = "CountLabel"
	count_label.position = Vector2(18, 500)
	count_label.size = Vector2(234, 24)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(count_label)


func _build_world_tree_section() -> void:
	var panel := _framed_section("MapPreviewPanel", Rect2(302, 76, 520, 548))
	panel.add_child(_section_title("HardCore 世界地图树", 520))
	var hint := Label.new()
	hint.name = "WorldTreeHint"
	hint.text = "选择大地图节点，在左侧展开其包含的全部地图"
	hint.position = Vector2(24, 54)
	hint.size = Vector2(472, 28)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.theme_type_variation = "GothicMutedLabel"
	panel.add_child(hint)
	world_tree_scroll = ScrollContainer.new()
	world_tree_scroll.name = "WorldTreeScroll"
	world_tree_scroll.position = Vector2(24, 88)
	world_tree_scroll.size = Vector2(472, 420)
	world_tree_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	world_tree_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(world_tree_scroll)
	world_tree_container = VBoxContainer.new()
	world_tree_container.name = "WorldTree"
	world_tree_container.custom_minimum_size = Vector2(454, 0)
	world_tree_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_tree_container.add_theme_constant_override("separation", 7)
	world_tree_scroll.add_child(world_tree_container)


func _build_map_detail_section() -> void:
	var panel := _framed_section("MapDetailPanel", Rect2(834, 76, 306, 548))
	panel.add_child(_section_title("区域信息", 306))
	map_name_label = Label.new()
	map_name_label.name = "MapName"
	map_name_label.position = Vector2(24, 58)
	map_name_label.size = Vector2(258, 36)
	map_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	map_name_label.add_theme_font_size_override("font_size", 21)
	map_name_label.add_theme_color_override("font_color", Color("f2c783"))
	panel.add_child(map_name_label)
	detail_label = RichTextLabel.new()
	detail_label.name = "MapDetail"
	detail_label.position = Vector2(24, 104)
	detail_label.size = Vector2(258, 330)
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.theme_type_variation = "GothicDetailText"
	detail_label.add_theme_font_size_override("normal_font_size", 15)
	panel.add_child(detail_label)
	teleport_button = Button.new()
	teleport_button.name = "TeleportButton"
	teleport_button.text = "传送未开放"
	teleport_button.position = Vector2(20, 452)
	teleport_button.size = Vector2(266, 54)
	teleport_button.theme_type_variation = "GothicComponentSelectedButton"
	teleport_button.add_theme_font_size_override("font_size", 18)
	teleport_button.disabled = true
	teleport_button.pressed.connect(_teleport_selected)
	panel.add_child(teleport_button)


func _build_compatibility_list() -> void:
	map_list = ItemList.new()
	map_list.name = "CompatibilityMapList"
	map_list.visible = false
	map_list.item_selected.connect(_show_selected)
	map_list.item_activated.connect(func(_index: int) -> void: _teleport_selected())
	add_child(map_list)


func open_panel() -> void:
	later_toggle.set_pressed_no_signal(PlayerState.later_content_enabled)
	refresh()
	show()


func set_world_tree(new_nodes: Array) -> void:
	if new_nodes.is_empty():
		return
	world_tree_nodes = new_nodes.duplicate(true)
	_selected_world_node_id = str(world_tree_nodes[0].get("node_id", "mafa_world"))
	_rebuild_world_tree()
	refresh()


func set_teleport_availability(rules: Dictionary) -> void:
	teleport_rules = rules.duplicate(true)
	_refresh_teleport_button()


func refresh() -> void:
	if map_list == null:
		return
	map_entries.clear()
	map_list.clear()
	var node := _world_node(_selected_world_node_id)
	var query := search_box.text.strip_edges().to_lower()
	for map_data: Variant in GameData.get_available_maps(PlayerState.later_content_enabled):
		if not map_data is Dictionary or not _node_matches_map(node, map_data):
			continue
		var searchable := "%s %s %s" % [map_data.get("name", ""), map_data.get("region", ""), map_data.get("mapGroup", "")]
		if not query.is_empty() and query not in searchable.to_lower():
			continue
		map_entries.append(map_data)
		var later_marker := "［后期］" if str(map_data.get("versionTag", "")).begins_with("1.76后期") else ""
		map_list.add_item("%s%s　%s" % [later_marker, map_data.get("name", "未命名"), map_data.get("mapGroup", "")])
	_rebuild_map_cards()
	var node_label := str(node.get("label", "HardCore 世界"))
	count_label.text = "%s · %d 张" % [node_label, map_entries.size()]
	var selected_index := _index_for_map_id(_selected_map_id)
	if selected_index >= 0:
		map_list.select(selected_index)
		_show_selected(selected_index)
	else:
		_clear_map_selection()
	teleport_availability_requested.emit(_visible_map_ids())


func _rebuild_world_tree() -> void:
	for child: Node in world_tree_container.get_children():
		child.queue_free()
	world_node_buttons.clear()
	for value: Variant in world_tree_nodes:
		if not value is Dictionary:
			continue
		var node: Dictionary = value
		var node_id := str(node.get("node_id", ""))
		var depth := maxi(0, int(node.get("depth", 0)))
		var holder := Control.new()
		holder.name = "WorldNodeHolder_%s" % node_id
		holder.custom_minimum_size = Vector2(454, WORLD_NODE_SIZE.y)
		world_tree_container.add_child(holder)
		var button := Button.new()
		button.name = "WorldNode_%s" % node_id
		button.position = Vector2(12, 0)
		button.size = WORLD_NODE_SIZE
		button.toggle_mode = true
		button.text = str(node.get("label", "地图节点"))
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_size_override("font_size", 15)
		button.set_pressed_no_signal(node_id == _selected_world_node_id)
		button.theme_type_variation = "GothicComponentSelectedButton" if node_id == _selected_world_node_id else "GothicComponentButton"
		button.pressed.connect(_select_world_node.bind(node_id))
		button.set_meta("world_node_id", node_id)
		button.set_meta("world_node_depth", depth)
		holder.add_child(button)
		world_node_buttons[node_id] = button


func _rebuild_map_cards() -> void:
	for child: Node in map_list_container.get_children():
		child.queue_free()
	map_buttons.clear()
	for index in range(map_entries.size()):
		var map_data: Dictionary = map_entries[index]
		var button := Button.new()
		button.name = "MapCard_%d" % int(map_data.get("mapId", -1))
		button.custom_minimum_size = MAP_CARD_SIZE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.text = ""
		button.set_pressed_no_signal(int(map_data.get("mapId", -1)) == _selected_map_id)
		button.theme_type_variation = "GothicComponentSelectedButton" if int(map_data.get("mapId", -1)) == _selected_map_id else "GothicComponentButton"
		button.pressed.connect(_select_map.bind(index))
		button.set_meta("map_id", int(map_data.get("mapId", -1)))
		var name_label := Label.new()
		name_label.name = "MapName"
		name_label.text = str(map_data.get("name", "未命名"))
		name_label.position = Vector2(10, 7)
		name_label.size = Vector2(206, 20)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", 15)
		button.add_child(name_label)
		var sub_label := Label.new()
		sub_label.name = "MapSubtitle"
		sub_label.text = "%s · ID %s" % [map_data.get("region", "未分类"), _source_id_label(map_data.get("sourceMapId", map_data.get("mapId", -1)))]
		sub_label.position = Vector2(10, 28)
		sub_label.size = Vector2(206, 17)
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sub_label.clip_text = true
		sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub_label.add_theme_font_size_override("font_size", 12)
		sub_label.add_theme_color_override("font_color", Color("c5a878"))
		button.add_child(sub_label)
		map_list_container.add_child(button)
		map_buttons.append(button)


func _select_world_node(node_id: String) -> void:
	if _world_node(node_id).is_empty():
		return
	_selected_world_node_id = node_id
	_selected_map_id = -1
	search_box.text = ""
	for key: Variant in world_node_buttons.keys():
		var button := world_node_buttons[key] as Button
		var selected := str(key) == node_id
		button.set_pressed_no_signal(selected)
		button.theme_type_variation = "GothicComponentSelectedButton" if selected else "GothicComponentButton"
	refresh()
	if world_node_buttons.has(node_id):
		world_tree_scroll.call_deferred("ensure_control_visible", world_node_buttons[node_id])


func _select_map(index: int) -> void:
	if index < 0 or index >= map_entries.size():
		return
	map_list.select(index)
	_show_selected(index)


func _show_selected(index: int) -> void:
	if index < 0 or index >= map_entries.size():
		return
	var map_data: Dictionary = map_entries[index]
	_selected_map_id = int(map_data.get("mapId", -1))
	for button_index in range(map_buttons.size()):
		var button := map_buttons[button_index]
		var selected := button_index == index
		button.set_pressed_no_signal(selected)
		button.theme_type_variation = "GothicComponentSelectedButton" if selected else "GothicComponentButton"
	var content := RegionContent.get_map_content(_selected_map_id)
	var bosses := GameData.get_bosses_for_map(map_data)
	var boss_names: Array[String] = []
	for boss: Variant in bosses:
		var boss_name := str(boss.get("name", "Boss"))
		if not boss_names.has(boss_name):
			boss_names.append(boss_name)
	for boss: Variant in content.get("bosses", []):
		if boss is Dictionary and not boss_names.has(str(boss.get("name", "Boss"))):
			boss_names.append(str(boss.get("name", "Boss")))
	map_name_label.text = str(map_data.get("name", "未命名地图"))
	_detail_base_text = "[color=#d8c8ae]所属大地图：%s\n地区：%s\n地图组：%s\n\n资料ID：%s\n运行时ID：%d\n版本：%s\n资料状态：%s\n可信度：%s\n\n门点：%d　怪物点：%d\n关联Boss：%s[/color]" % [
		_world_node(_selected_world_node_id).get("label", "HardCore 世界"),
		map_data.get("region", "未分类"),
		map_data.get("mapGroup", "未分类"),
		_source_id_label(map_data.get("sourceMapId", map_data.get("mapId", -1))),
		_selected_map_id,
		map_data.get("versionTag", "未标注"),
		map_data.get("recordStatus", content.get("status", "未标注")),
		map_data.get("confidence", "?"),
		content.get("portals", []).size(),
		content.get("spawns", []).size(),
		"、".join(boss_names) if not boss_names.is_empty() else "暂无可靠关联",
	]
	_refresh_teleport_button()


func _clear_map_selection() -> void:
	_selected_map_id = -1
	_detail_base_text = ""
	map_name_label.text = "请选择地图"
	detail_label.text = "[color=#a99479]先在中间选择省份、主城或洞穴群，再从左侧选择具体地图。[/color]"
	teleport_button.text = "传送未开放"
	teleport_button.disabled = true
	teleport_button.tooltip_text = "该地图尚未获得玩法层传送授权"


func _refresh_teleport_button() -> void:
	if teleport_button == null or _selected_map_id <= 0:
		return
	var rule := _teleport_rule(_selected_map_id)
	var enabled := bool(rule.get("enabled", false))
	teleport_button.disabled = not enabled
	teleport_button.text = "传送" if enabled else "传送未开放"
	var destination_label := str(rule.get("destination_label", ""))
	var reason := str(rule.get("reason", "该地图尚未开放传送"))
	teleport_button.tooltip_text = destination_label if enabled and not destination_label.is_empty() else reason
	var status_text := "[color=#78a87c]传送开放：%s[/color]" % destination_label if enabled else "[color=#8f7d6a]传送状态：%s[/color]" % reason
	detail_label.text = "%s\n\n%s" % [_detail_base_text, status_text]


func _teleport_selected() -> void:
	if _selected_map_id <= 0:
		return
	var rule := _teleport_rule(_selected_map_id)
	if not bool(rule.get("enabled", false)):
		return
	var destination_map_id := int(rule.get("destination_map_id", _selected_map_id))
	var request := {
		"contract_id": "ui.map.teleport.v1",
		"selected_map_id": _selected_map_id,
		"destination_map_id": destination_map_id,
		"arrival_anchor_id": str(rule.get("arrival_anchor_id", "")),
		"rule_id": str(rule.get("rule_id", "")),
	}
	teleport_requested.emit(request.duplicate(true))
	map_selected.emit(destination_map_id)
	hide()


func _travel_selected() -> void:
	_teleport_selected()


func _on_later_toggled(enabled: bool) -> void:
	PlayerState.set_later_content_enabled(enabled)
	refresh()


func _world_node(node_id: String) -> Dictionary:
	for value: Variant in world_tree_nodes:
		if value is Dictionary and str(value.get("node_id", "")) == node_id:
			return value
	return {}


func _node_matches_map(node: Dictionary, map_data: Dictionary) -> bool:
	var explicit_ids: Array = node.get("map_ids", [])
	if not explicit_ids.is_empty():
		return int(map_data.get("mapId", -1)) in explicit_ids
	var groups: Array = node.get("map_groups", [])
	if not groups.is_empty() and str(map_data.get("mapGroup", "")) not in groups:
		return false
	var regions: Array = node.get("regions", [])
	if not regions.is_empty() and str(map_data.get("region", "")) not in regions:
		return false
	var terms: Array = node.get("name_terms", [])
	if not terms.is_empty():
		var searchable := "%s %s" % [map_data.get("name", ""), map_data.get("mapGroup", "")]
		for term: Variant in terms:
			if str(term) in searchable:
				return true
		return false
	return true


func _teleport_rule(map_id: int) -> Dictionary:
	if teleport_rules.has(map_id) and teleport_rules[map_id] is Dictionary:
		return teleport_rules[map_id]
	var string_id := str(map_id)
	if teleport_rules.has(string_id) and teleport_rules[string_id] is Dictionary:
		return teleport_rules[string_id]
	return {}


func _visible_map_ids() -> Array:
	var result: Array = []
	for map_data: Variant in map_entries:
		if map_data is Dictionary:
			result.append(int(map_data.get("mapId", -1)))
	return result


func _index_for_map_id(map_id: int) -> int:
	for index in range(map_entries.size()):
		if int(map_entries[index].get("mapId", -1)) == map_id:
			return index
	return -1


func _source_id_label(value: Variant) -> String:
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	return str(value)


func _framed_section(node_name: String, rect: Rect2) -> Panel:
	var surface := Panel.new()
	surface.name = "%sSurface" % node_name
	surface.position = rect.position + Vector2(8, 8)
	surface.size = rect.size - Vector2(16, 16)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)
	var frame := Panel.new()
	frame.name = node_name
	frame.position = rect.position
	frame.size = rect.size
	frame.theme_type_variation = "GothicInsetFrame"
	add_child(frame)
	return frame


func _section_title(text_value: String, section_width: float) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = Vector2(24, 18)
	label.size = Vector2(section_width - 48.0, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicSectionTitle"
	return label


func _close() -> void:
	hide()
	closed.emit()
