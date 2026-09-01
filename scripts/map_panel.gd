class_name MapPanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const GothicFrameFactoryScript := preload("res://scripts/gothic_frame_factory.gd")
const UIRuntimeLayoutOverridesScript := preload("res://scripts/ui_runtime_layout_overrides.gd")
const TouchScrollSupportScript := preload("res://scripts/touch_scroll_support.gd")
const MapEditorRuntimeBridgeScript := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")

signal map_selected(map_id: int)
signal teleport_availability_requested(map_ids: Array)
signal teleport_requested(request: Dictionary)
signal closed

const PANEL_SIZE := Vector2(1160, 650)
const MODAL_SURFACE_INSET := Vector4(32, 38, 32, 34)
const SECTION_VERTICAL_SHIFT := 24.0
const MAP_CARD_SIZE := Vector2(226, 58)
const DEVICE_TO_LOGICAL_SCALE := 1598.0 / 2664.0
const WORLD_TREE_DEVICE_WIDTH := 650.0
const WORLD_TREE_SCROLL_WIDTH := WORLD_TREE_DEVICE_WIDTH * DEVICE_TO_LOGICAL_SCALE
const WORLD_TREE_SIDE_GUTTER := 12.0
const WORLD_TREE_CONTAINER_WIDTH := WORLD_TREE_SCROLL_WIDTH - 24.0
const WORLD_NODE_SIZE := Vector2(WORLD_TREE_CONTAINER_WIDTH - WORLD_TREE_SIDE_GUTTER * 2.0, 50)

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
var world_tree_nodes: Array = []
var world_node_buttons: Dictionary = {}
var map_entries: Array = []
var map_buttons: Array[Button] = []
var teleport_rules: Dictionary = {}
var _selected_map_id := -1
var _selected_world_node_id := "bich_province"
var _detail_base_text := ""
var _teleport_request_locked := false
var _presentation_snapshot_key := ""
var _presentation_maps: Array = []
var _presentation_by_id: Dictionary = {}
var _presentation_by_region: Dictionary = {}
var _incoming_routes_by_destination: Dictionary = {}
var _last_entry_ids: Array[int] = []
var _layout_profile_applied := false
var _debug_operation_counters := {"snapshot_scans": 0, "snapshot_builds": 0, "content_resolves": 0, "world_tree_rebuilds": 0, "card_rebuilds": 0, "layout_applies": 0}


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
	GothicFrameFactoryScript.seal_modal_rings(self)
	_ensure_presentation_snapshot()
	world_tree_nodes = _build_runtime_catalog()
	_selected_world_node_id = _first_filterable_node_id(world_tree_nodes)
	_rebuild_world_tree()
	refresh(true)


func _build_modal_surface() -> void:
	GothicFrameFactoryScript.add_modal_fill(self, PANEL_SIZE)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(350, 10)
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
	panel.add_child(_section_title("MapListTitle", "区域地图", 270))
	var scroll := ScrollContainer.new()
	scroll.name = "MapListScroll"
	scroll.position = Vector2(18, 54)
	scroll.size = Vector2(234, 470)
	scroll.set_meta("calibration_layout_dependencies", ["MapListPanel/SearchBox", "MapListPanel/LaterContentToggle", "MapListPanel/CountLabel"])
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	map_list_container = VBoxContainer.new()
	map_list_container.name = "MapCards"
	map_list_container.custom_minimum_size = Vector2(226, 0)
	map_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list_container.add_theme_constant_override("separation", 7)
	scroll.add_child(map_list_container)


func _build_world_tree_section() -> void:
	var panel := _framed_section("MapPreviewPanel", Rect2(302, 76, 520, 548))
	var tree_frame_width := WORLD_TREE_SCROLL_WIDTH + 32.0
	var tree_frame := GothicFrameFactoryScript.add_filled_section(panel, "MapListV3Frame", Rect2(8, 40, tree_frame_width, 486))
	tree_frame.set_meta("calibration_layer", "map_world_tree_decoration")
	tree_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.move_child(tree_frame, 0)
	panel.add_child(_section_title("WorldTreeTitle", "HardCore 世界地图树", 520))
	var hint := Label.new()
	hint.name = "WorldTreeHint"
	hint.text = "选择大地图节点，在左侧展开其包含的全部地图"
	hint.position = Vector2(24, 46)
	hint.size = Vector2(WORLD_TREE_SCROLL_WIDTH, 18)
	hint.set_meta("calibration_layout_revision", 2)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.theme_type_variation = "GothicMutedLabel"
	panel.add_child(hint)
	world_tree_scroll = ScrollContainer.new()
	world_tree_scroll.name = "WorldTreeScroll"
	world_tree_scroll.position = Vector2(24, 68)
	world_tree_scroll.size = Vector2(WORLD_TREE_SCROLL_WIDTH, 440)
	world_tree_scroll.set_meta("calibration_layout_dependencies", ["MapPreviewPanel/WorldTreeHint"])
	world_tree_scroll.set_meta("calibration_layout_revision", 2)
	world_tree_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	world_tree_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(world_tree_scroll)
	world_tree_container = VBoxContainer.new()
	world_tree_container.name = "WorldTree"
	world_tree_container.custom_minimum_size = Vector2(WORLD_TREE_CONTAINER_WIDTH, 0)
	world_tree_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_tree_container.add_theme_constant_override("separation", 7)
	world_tree_scroll.add_child(world_tree_container)


func _build_runtime_catalog() -> Array:
	var result: Array = []
	var region_nodes: Dictionary = {}
	for map_value: Variant in _presentation_maps:
		if not map_value is Dictionary:
			continue
		var map_data: Dictionary = map_value
		var region := str(map_data.get("region", "")).strip_edges()
		if region.is_empty():
			continue
		if not region_nodes.has(region):
			var region_id := _stable_catalog_id(region, "region")
			region_nodes[region] = {"node_id": region_id, "label": region.trim_suffix("地区").trim_suffix("区"), "depth": 0, "regions": [region]}
			result.append(region_nodes[region])
	return result


func _ensure_presentation_snapshot() -> bool:
	var key := "later:%s" % str(PlayerState.later_content_enabled)
	if key == _presentation_snapshot_key and not _presentation_maps.is_empty():
		return false
	_debug_operation_counters["snapshot_scans"] += 1
	_presentation_snapshot_key = key
	_presentation_maps.clear()
	_presentation_by_id.clear()
	_presentation_by_region.clear()
	_incoming_routes_by_destination.clear()
	for map_value: Variant in GameData.get_available_maps(PlayerState.later_content_enabled):
		if not map_value is Dictionary:
			continue
		var map_data: Dictionary = map_value
		var region := str(map_data.get("region", "")).strip_edges()
		if region.is_empty():
			continue
		var map_id := int(map_data.get("mapId", -1))
		if map_id <= 0:
			continue
		var content := MapEditorRuntimeBridgeScript.game_content_for_map(map_id)
		_debug_operation_counters["content_resolves"] += 1
		if content.is_empty():
			content = RegionContent.get_map_content(map_id)
		var summary := "探索区域"
		for boss: Variant in content.get("bosses", []):
			if boss is Dictionary and not str(boss.get("name", "")).strip_edges().is_empty():
				summary = "有首领"
				break
		var dto := {"map": map_data, "content": content, "summary": summary}
		_presentation_maps.append(map_data)
		_presentation_by_id[map_id] = dto
		if not _presentation_by_region.has(region):
			_presentation_by_region[region] = []
		(_presentation_by_region[region] as Array).append(map_data)
		for portal: Variant in content.get("portals", []):
			if not portal is Dictionary:
				continue
			var destination_id := int(portal.get("target_map_id", -1))
			if destination_id <= 0:
				continue
			if not _incoming_routes_by_destination.has(destination_id):
				_incoming_routes_by_destination[destination_id] = []
			var source_name := str(map_data.get("name", "相邻区域")).strip_edges()
			if not source_name.is_empty() and not (_incoming_routes_by_destination[destination_id] as Array).has(source_name):
				(_incoming_routes_by_destination[destination_id] as Array).append(source_name)
	_debug_operation_counters["snapshot_builds"] += 1
	return true


func debug_operation_counters() -> Dictionary:
	return _debug_operation_counters.duplicate(true)


func debug_reset_operation_counters() -> void:
	for key: Variant in _debug_operation_counters.keys():
		_debug_operation_counters[key] = 0


func _stable_catalog_id(value: String, suffix: String) -> String:
	var legacy := {"比奇地区": "bich_province", "沃玛地区": "wooma_forest", "盟重地区": "mengzhong_province", "苍月地区": "cangyue_island", "毒蛇地区": "viper_valley", "封魔谷区": "fengmo_valley", "白日门区": "white_sun_red_moon"}
	if legacy.has(value):
		return str(legacy[value])
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return "%s_%s" % [suffix, context.finish().hex_encode().substr(0, 12)]


func _build_map_detail_section() -> void:
	var panel := _framed_section("MapDetailPanel", Rect2(834, 76, 306, 548))
	panel.add_child(_section_title("MapDetailTitle", "区域信息", 306))
	map_name_label = Label.new()
	map_name_label.name = "MapName"
	map_name_label.set_meta("calibration_runtime_text", true)
	map_name_label.position = Vector2(24, 58)
	map_name_label.size = Vector2(258, 36)
	map_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	map_name_label.add_theme_font_size_override("font_size", 21)
	map_name_label.add_theme_color_override("font_color", Color("f2c783"))
	panel.add_child(map_name_label)
	detail_label = RichTextLabel.new()
	detail_label.name = "MapDetail"
	detail_label.set_meta("calibration_runtime_text", true)
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
	# Teleport is a transition action; map/world cards own persistent selection.
	teleport_button.theme_type_variation = "GothicComponentButton"
	teleport_button.add_theme_font_size_override("font_size", 18)
	teleport_button.disabled = true
	teleport_button.pressed.connect(_teleport_selected)
	panel.add_child(teleport_button)


func _build_compatibility_list() -> void:
	map_list = ItemList.new()
	map_list.name = "CompatibilityMapList"
	map_list.visible = false
	map_list.item_selected.connect(_on_map_list_item_selected)
	map_list.item_activated.connect(func(_index: int) -> void: _teleport_selected())
	add_child(map_list)


func open_panel() -> void:
	_teleport_request_locked = false
	GothicUIThemeScript.clear_button_feedback(teleport_button)
	var snapshot_changed := _ensure_presentation_snapshot()
	if snapshot_changed:
		var previous := _selected_world_node_id
		world_tree_nodes = _build_runtime_catalog()
		_selected_world_node_id = previous if not _world_node(previous).is_empty() else _first_filterable_node_id(world_tree_nodes)
		_rebuild_world_tree()
		refresh(true)
	else:
		_refresh_teleport_button()
		teleport_availability_requested.emit(_visible_map_ids())
	show()


func set_world_tree(new_nodes: Array) -> void:
	if new_nodes.is_empty():
		return
	world_tree_nodes = new_nodes.duplicate(true)
	_selected_world_node_id = _first_filterable_node_id(world_tree_nodes)
	_rebuild_world_tree()
	refresh(true)


func set_teleport_availability(rules: Dictionary) -> void:
	teleport_rules = rules.duplicate(true)
	_refresh_teleport_button()


func refresh(force_structure: bool = false) -> void:
	if map_list == null:
		return
	var snapshot_changed := _ensure_presentation_snapshot()
	if snapshot_changed:
		world_tree_nodes = _build_runtime_catalog()
		_selected_world_node_id = _first_filterable_node_id(world_tree_nodes) if _world_node(_selected_world_node_id).is_empty() else _selected_world_node_id
		_rebuild_world_tree()
	var node := _world_node(_selected_world_node_id)
	var next_entries: Array = []
	var candidates: Array = _presentation_maps
	var node_regions: Array = node.get("regions", [])
	if node_regions.size() == 1 and node.get("map_groups", []).is_empty() and node.get("map_ids", []).is_empty() and node.get("name_terms", []).is_empty():
		candidates = _presentation_by_region.get(str(node_regions[0]), [])
	for map_data: Variant in candidates:
		if not map_data is Dictionary or not _node_matches_map(node, map_data):
			continue
		next_entries.append(map_data)
	var next_ids: Array[int] = []
	for entry: Dictionary in next_entries:
		next_ids.append(int(entry.get("mapId", -1)))
	var structure_changed := force_structure or snapshot_changed or next_ids != _last_entry_ids
	map_entries = next_entries
	if structure_changed:
		map_list.clear()
		for map_data: Dictionary in map_entries:
			var later_marker := "［后期］" if str(map_data.get("versionTag", "")).begins_with("1.76后期") else ""
			map_list.add_item("%s%s" % [later_marker, map_data.get("name", "未命名")])
		_rebuild_map_cards()
		_last_entry_ids = next_ids
	var selected_index := _index_for_map_id(_selected_map_id)
	if selected_index >= 0:
		map_list.select(selected_index)
		_show_selected(selected_index)
	elif not map_entries.is_empty():
		map_list.select(0)
		_show_selected(0)
	else:
		_clear_map_selection()
	teleport_availability_requested.emit(_visible_map_ids())
	if not _layout_profile_applied:
		_layout_profile_applied = true
		_debug_operation_counters["layout_applies"] += 1
		UIRuntimeLayoutOverridesScript.apply_profile(self, "map")


func _rebuild_world_tree() -> void:
	_debug_operation_counters["world_tree_rebuilds"] += 1
	for child: Node in world_tree_container.get_children():
		world_tree_container.remove_child(child)
		child.free()
	world_node_buttons.clear()
	for value: Variant in world_tree_nodes:
		if not value is Dictionary:
			continue
		var node: Dictionary = value
		var node_id := str(node.get("node_id", ""))
		if not _node_has_filter_contract(node):
			continue
		var depth := maxi(0, int(node.get("depth", 0)))
		var holder := Control.new()
		holder.name = "WorldNodeHolder_%s" % node_id
		holder.custom_minimum_size = Vector2(WORLD_TREE_CONTAINER_WIDTH, WORLD_NODE_SIZE.y)
		world_tree_container.add_child(holder)
		var button := Button.new()
		button.name = "WorldNode_%s" % node_id
		button.position = Vector2(WORLD_TREE_SIDE_GUTTER, 0)
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
	_debug_operation_counters["card_rebuilds"] += 1
	for child: Node in map_list_container.get_children():
		map_list_container.remove_child(child)
		child.free()
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
		name_label.set_meta("calibration_runtime_text", true)
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
		sub_label.set_meta("calibration_runtime_text", true)
		sub_label.text = _map_card_summary(map_data)
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
	if TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	if _world_node(node_id).is_empty():
		return
	_selected_world_node_id = node_id
	_selected_map_id = -1
	for key: Variant in world_node_buttons.keys():
		var button := world_node_buttons[key] as Button
		var selected := str(key) == node_id
		button.set_pressed_no_signal(selected)
		button.theme_type_variation = "GothicComponentSelectedButton" if selected else "GothicComponentButton"
	refresh()
	if world_node_buttons.has(node_id):
		world_tree_scroll.call_deferred("ensure_control_visible", world_node_buttons[node_id])


func _select_map(index: int) -> void:
	if TouchScrollSupportScript.is_drag_active(get_tree()):
		return
	if index < 0 or index >= map_entries.size():
		return
	map_list.select(index)
	_show_selected(index)


func _on_map_list_item_selected(index: int) -> void:
	if TouchScrollSupportScript.is_drag_active(get_tree()):
		return
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
	var content := _player_map_content(_selected_map_id)
	var boss_names: Array[String] = []
	for boss: Variant in content.get("bosses", []):
		if boss is Dictionary and not boss_names.has(str(boss.get("name", "Boss"))):
			boss_names.append(str(boss.get("name", "Boss")))
	map_name_label.text = str(map_data.get("name", "未命名地图"))
	_detail_base_text = _player_map_detail(map_data, content, boss_names)
	_refresh_teleport_button()


func _player_map_content(map_id: int) -> Dictionary:
	var dto: Dictionary = _presentation_by_id.get(map_id, {})
	if not dto.has("content"):
		return {}
	var cached: Variant = dto["content"]
	return cached if cached is Dictionary else {}


func _map_card_summary(map_data: Dictionary) -> String:
	var dto: Dictionary = _presentation_by_id.get(int(map_data.get("mapId", -1)), {})
	return str(dto.get("summary", "探索区域"))


func _player_map_detail(map_data: Dictionary, content: Dictionary, boss_names: Array[String]) -> String:
	var map_name := str(map_data.get("name", "这片区域"))
	var map_id := int(map_data.get("mapId", -1))
	var safe_areas: Array = content.get("safe_areas", [])
	var npcs: Array = content.get("npcs", [])
	var has_camp := not safe_areas.is_empty()
	if not has_camp:
		for npc: Variant in npcs:
			if npc is Dictionary and str(npc.get("kind", "")) in ["shop", "trainer", "quest", "guide"]:
				has_camp = true
				break
	var monster_names: Array[String] = []
	for spawn: Variant in content.get("spawns", []):
		if not spawn is Dictionary:
			continue
		var monster_name := str(spawn.get("display_name", spawn.get("name", ""))).strip_edges()
		if not monster_name.is_empty() and not monster_names.has(monster_name):
			monster_names.append(monster_name)
	var portal_lines: Array[String] = []
	for portal: Variant in content.get("portals", []):
		if not portal is Dictionary:
			continue
		var target_id := int(portal.get("target_map_id", -1))
		var target_map := GameData.get_map_by_id(target_id)
		var target_name := str(target_map.get("name", "未知区域")).strip_edges()
		var portal_label := str(portal.get("label", "")).strip_edges()
		if portal_label.is_empty():
			portal_label = "通往%s" % target_name
		var line := "%s（目的地：%s）" % [portal_label, target_name]
		if not portal_lines.has(line):
			portal_lines.append(line)
	var description := "%s位于%s，是一处可供玩家探索的区域。" % [map_name, _world_node(_selected_world_node_id).get("label", "HardCore 世界")]
	var camp_text := "有安全营地，可在此休整。" if has_camp else "未发现可供休整的安全营地。"
	var monster_text := "、".join(monster_names) if not monster_names.is_empty() else "暂未发现常驻怪物"
	var boss_text := "会刷新：%s" % "、".join(boss_names) if not boss_names.is_empty() else "未发现首领刷新"
	var entrance_sources: Array = []
	for source_value: Variant in _incoming_route_names(map_id):
		entrance_sources.append(str(source_value))
	var entrance_text := "可从%s进入。" % "、".join(entrance_sources) if not entrance_sources.is_empty() else "入口线索暂无记录，需要继续探索。"
	var exit_text := "；".join(portal_lines) if not portal_lines.is_empty() else "未发现通往其他区域的出口。"
	return "[color=#d8c8ae]地图说明：%s\n\n营地：%s\n\n常见怪物：%s\n\n首领：%s\n\n入口：%s\n\n出口：%s[/color]" % [description, camp_text, monster_text, boss_text, entrance_text, exit_text]


func _incoming_route_names(destination_map_id: int) -> Array[String]:
	_ensure_presentation_snapshot()
	var cached: Variant = _incoming_routes_by_destination.get(destination_map_id, [])
	return (cached as Array).duplicate() if cached is Array else []


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
	teleport_button.disabled = _teleport_request_locked or not enabled
	teleport_button.text = "传送" if enabled else "传送未开放"
	var destination_label := str(rule.get("destination_label", ""))
	var reason := str(rule.get("reason", "该地图尚未开放传送"))
	teleport_button.tooltip_text = destination_label if enabled and not destination_label.is_empty() else reason
	var status_text := "[color=#78a87c]传送开放：%s[/color]" % destination_label if enabled else "[color=#8f7d6a]传送状态：%s[/color]" % reason
	detail_label.text = "%s\n\n%s" % [_detail_base_text, status_text]


func _teleport_selected() -> void:
	if _teleport_request_locked:
		return
	if _selected_map_id <= 0:
		return
	var rule := _teleport_rule(_selected_map_id)
	if not bool(rule.get("enabled", false)):
		return
	_teleport_request_locked = true
	GothicUIThemeScript.clear_button_feedback(teleport_button)
	GothicUIThemeScript.set_button_feedback(
		teleport_button,
		GothicUIThemeScript.BUTTON_FEEDBACK_TRANSITION,
		"map.teleport",
	)
	_refresh_teleport_button()
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


func _world_node(node_id: String) -> Dictionary:
	for value: Variant in world_tree_nodes:
		if value is Dictionary and str(value.get("node_id", "")) == node_id:
			return value
	return {}


func _node_matches_map(node: Dictionary, map_data: Dictionary) -> bool:
	if node.is_empty():
		return false
	var matched := false
	var explicit_ids: Array = node.get("map_ids", [])
	if not explicit_ids.is_empty():
		return int(map_data.get("mapId", -1)) in explicit_ids
	var groups: Array = node.get("map_groups", [])
	if not groups.is_empty() and str(map_data.get("mapGroup", "")) not in groups:
		return false
	if not groups.is_empty():
		matched = true
	var regions: Array = node.get("regions", [])
	if not regions.is_empty() and str(map_data.get("region", "")) not in regions:
		return false
	if not regions.is_empty():
		matched = true
	var terms: Array = node.get("name_terms", [])
	if not terms.is_empty():
		var searchable := "%s %s" % [map_data.get("name", ""), map_data.get("mapGroup", "")]
		for term: Variant in terms:
			if str(term) in searchable:
				return true
		return false
	return matched


func _first_filterable_node_id(nodes: Array) -> String:
	for value: Variant in nodes:
		if value is Dictionary and str(value.get("node_id", "")) == "bich_province":
			return "bich_province"
	for value: Variant in nodes:
		if value is Dictionary:
			var candidate: Dictionary = value
			if _node_has_filter_contract(candidate):
				return str(candidate.get("node_id", ""))
	return ""


func _node_has_filter_contract(node: Dictionary) -> bool:
	return not node.get("map_ids", []).is_empty() or not node.get("map_groups", []).is_empty() or not node.get("regions", []).is_empty() or not node.get("name_terms", []).is_empty()


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


func _framed_section(node_name: String, rect: Rect2) -> Control:
	var adjusted_rect := Rect2(rect.position + Vector2(0, -SECTION_VERTICAL_SHIFT), rect.size)
	return GothicFrameFactoryScript.add_filled_section(self, node_name, adjusted_rect)


func _section_title(node_name: String, text_value: String, section_width: float) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.position = Vector2(24, 18)
	label.size = Vector2(section_width - 48.0, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicSectionTitle"
	return label


func _close() -> void:
	_teleport_request_locked = false
	GothicUIThemeScript.clear_button_feedback(teleport_button)
	hide()
	closed.emit()
