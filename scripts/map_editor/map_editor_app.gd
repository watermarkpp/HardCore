class_name MapEditorApp
extends Control

const LAST_DOCUMENT_PATH_FILE := "user://mse_last_document_path.txt"
const InstanceProfileService := preload("res://scripts/map_editor/map_editor_instance_profile_service.gd")
const PortalAnchorService := preload("res://scripts/map_editor/map_editor_portal_anchor_service.gd")
const WallLoopService := preload("res://scripts/map_editor/map_editor_wall_loop_service.gd")

var current_document: Dictionary = {}
var current_document_path := ""
var map_id_edit: LineEdit
var runtime_id_edit: SpinBox
var display_name_edit: LineEdit
var map_type_option: OptionButton
var map_template_option: OptionButton
var template_info_label: Label
var save_map_button: Button
var open_template_button: Button
var create_map_button: Button
var create_map_dialog: ConfirmationDialog
var create_dialog_submit_button: Button
var create_chunk_x: SpinBox
var create_chunk_y: SpinBox
var create_size_preview: Label
var wall_loop_dialog: ConfirmationDialog
var wall_loop_family_option: OptionButton
var wall_loop_corner_option: OptionButton
var wall_loop_min_x: SpinBox
var wall_loop_min_y: SpinBox
var wall_loop_max_x: SpinBox
var wall_loop_max_y: SpinBox
var size_label: Label
var path_label: Label
var status_label: Label
var preview: MapEditorCanvasPreview
var asset_tree: Tree
var brush_label: Label
var command_stack := MapEditorCommandStack.new()
var selected_asset_id := ""
var calibration_anchor_x: SpinBox
var calibration_anchor_y: SpinBox
var calibration_footprint_x: SpinBox
var calibration_footprint_y: SpinBox
var calibration_collision: OptionButton
var calibration_occlusion: CheckBox
var object_role_option: OptionButton
var collision_shape_option: OptionButton
var collision_draw_toggle: CheckBox
var collision_erase_toggle: CheckBox
var collision_erase_whole_toggle: CheckBox
var collision_instruction_label: Label
var manual_collision_start := Vector2i(-1, -1)
var manual_polygon_points: Array[Vector2i] = []
var safe_polygon_points: Array[Vector2i] = []
var semantic_kind_option: OptionButton
var semantic_content_id: LineEdit
var semantic_content_option: OptionButton
var semantic_display_name: LineEdit
var semantic_target_map: LineEdit
var semantic_target_entrance: LineEdit
var semantic_radius: SpinBox
var semantic_count: SpinBox
var semantic_respawn: SpinBox
var semantic_max_alive: SpinBox
var semantic_facing: OptionButton
var semantic_place_toggle: CheckBox
var semantic_catalog_tree: Tree
var semantic_detail_scroll: ScrollContainer
var semantic_detail_label: Label
var random_region_fill_toggle: CheckBox
var point_erase_toggle: CheckBox
var region_fill_menu: PopupMenu
var asset_size_menu: PopupMenu
var asset_size_menu_asset_id := ""
var asset_delete_dialog: ConfirmationDialog
var pending_asset_delete_id := ""
var instance_size_menu: PopupMenu
var instance_size_menu_instance_id := ""
var pending_fill_tiles: Array[Vector2i] = []
var element_clipboard: Dictionary = {}
var active_tool_mode := "select"
var load_default_workspace_on_ready := true
var persist_last_document_path := true
## Keep startup work out of _ready so the editor shell can paint first.
var startup_document_load_scheduled := false
var startup_document_load_started := false
var startup_document_load_finished := false


func _notification(what:int)->void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and get_tree()!=null and get_tree().current_scene==self:
		if not current_document.is_empty(): _save_current_document()
		get_tree().quit()


func _ready() -> void:
	_build_ui()
	if not load_default_workspace_on_ready:
		return
	# Opening a document can migrate ground state, repair semantic IDs, and
	# rebuild the preview. Schedule it after the shell is in the tree so the
	# first frame shows a useful status instead of a black window.
	startup_document_load_scheduled = true
	status_label.text = "启动界面已就绪，正在加载最近地图…"
	print("MSE_STARTUP_SHELL_READY")
	print("MSE_STARTUP_DOCUMENT_LOAD_SCHEDULED")
	call_deferred("_load_default_workspace_deferred")


func _load_default_workspace_deferred() -> void:
	if not is_inside_tree() or not load_default_workspace_on_ready:
		return
	startup_document_load_started = true
	print("MSE_STARTUP_DOCUMENT_LOAD_STARTED")
	# Yield one frame after the deferred callback to give the shell a paint
	# opportunity before any document/ground work begins.
	await get_tree().process_frame
	if not is_inside_tree() or not load_default_workspace_on_ready:
		return
	var recent_path := _startup_document_path()
	if FileAccess.file_exists(recent_path):
		_open_document_path(recent_path)
	else:
		_create_map("sandbox_64", "quest_room", 990001, "64格沙盒")
	startup_document_load_finished = true
	print("MSE_STARTUP_DOCUMENT_LOAD_FINISHED")


func _startup_document_path() -> String:
	var recent_path := _load_last_document_path()
	if not recent_path.is_empty() and FileAccess.file_exists(recent_path):
		return recent_path
	var bich_path := MapEditorSaveService.default_path("bich_province")
	if FileAccess.file_exists(bich_path):
		return bich_path
	return MapEditorSaveService.default_path("sandbox_64")


func _build_ui() -> void:
	var compact_theme := Theme.new(); compact_theme.default_font_size = 12; theme = compact_theme
	var background := ColorRect.new()
	background.color = Color("101216")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := HBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)
	var sidebar_scroll := ScrollContainer.new()
	sidebar_scroll.custom_minimum_size.x = 310
	sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(sidebar_scroll)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 290
	sidebar.add_theme_constant_override("separation", 8)
	sidebar_scroll.add_child(sidebar)
	var title := Label.new(); title.text = "MSE-V3.5.1 场景编辑器"; title.add_theme_font_size_override("font_size", 15); sidebar.add_child(title)
	var subtitle := Label.new(); subtitle.text = "人类与 Codex 共用 Schema v4"; subtitle.modulate = Color("95a4b6"); sidebar.add_child(subtitle)
	var map_panel := PanelContainer.new()
	sidebar.add_child(map_panel)
	var map_actions := VBoxContainer.new()
	map_actions.add_theme_constant_override("separation", 6)
	map_panel.add_child(map_actions)
	var map_actions_title := Label.new(); map_actions_title.text = "地图"; map_actions_title.add_theme_font_size_override("font_size", 14); map_actions.add_child(map_actions_title)
	save_map_button = Button.new(); save_map_button.text = "保存地图"; save_map_button.pressed.connect(_on_save_pressed); map_actions.add_child(save_map_button)
	var save_map_note := Label.new(); save_map_note.text = "装饰物、地面、碰撞、NPC、刷新点、入口、出口、出生/复活点和安全区都用“保存地图”"; save_map_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; save_map_note.modulate = Color("8fb9c7"); map_actions.add_child(save_map_note)
	var template_label := Label.new(); template_label.text = "地图模板"; map_actions.add_child(template_label)
	map_template_option = OptionButton.new(); map_template_option.fit_to_longest_item = false
	_refresh_map_template_options()
	map_template_option.get_popup().about_to_popup.connect(_refresh_map_template_options)
	map_actions.add_child(map_template_option)
	template_info_label = Label.new(); template_info_label.modulate = Color("9da7b3"); map_actions.add_child(template_info_label)
	open_template_button = Button.new(); open_template_button.text = "打开地图模板"; open_template_button.pressed.connect(_on_open_template_pressed); map_actions.add_child(open_template_button)
	create_map_button = Button.new(); create_map_button.text = "创建地图模板"; create_map_button.pressed.connect(_on_create_map_dialog_requested); map_actions.add_child(create_map_button)
	var reload_button := Button.new(); reload_button.text = "重新载入当前地图"; reload_button.pressed.connect(_on_open_pressed); map_actions.add_child(reload_button)
	size_label = Label.new(); size_label.text = "设计尺寸：-"; map_actions.add_child(size_label)
	path_label = Label.new(); path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; path_label.modulate = Color("8fb9c7"); map_actions.add_child(path_label)
	_build_create_map_dialog()
	map_template_option.item_selected.connect(_on_map_template_selected)
	if map_template_option.item_count > 0:
		_on_map_template_selected(map_template_option.selected)
	var ground_title := Label.new(); ground_title.text = "地面与运行时"; ground_title.add_theme_font_size_override("font_size", 13); sidebar.add_child(ground_title)
	var ground_button := Button.new(); ground_button.text = "初始化虚拟地面 Chunk"; ground_button.pressed.connect(_on_initialize_ground_pressed); sidebar.add_child(ground_button)
	var paint_button := Button.new(); paint_button.text = "中心格模拟首次地面编辑"; paint_button.pressed.connect(_on_demo_ground_edit_pressed); sidebar.add_child(paint_button)
	var note := Label.new(); note.text = "原图尺寸只用于审计。\n地面仅视觉；碰撞由对象和手工区域生成。\n工作文件位于 map_editor_workspace/。"; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.modulate = Color("9da7b3"); sidebar.add_child(note)
	var asset_title := Label.new(); asset_title.text = "素材目录"; asset_title.add_theme_font_size_override("font_size", 13); sidebar.add_child(asset_title)
	asset_tree = Tree.new(); asset_tree.custom_minimum_size.y = 260; asset_tree.hide_root = true; asset_tree.select_mode = Tree.SELECT_MULTI; asset_tree.item_selected.connect(_on_asset_tree_selected); asset_tree.multi_selected.connect(_on_asset_tree_multi_selected); asset_tree.gui_input.connect(_on_asset_tree_gui_input); sidebar.add_child(asset_tree); _refresh_asset_tree()
	brush_label = Label.new(); brush_label.text = "地面笔刷：暗色草地 01"; brush_label.modulate = Color("d7aa62"); sidebar.add_child(brush_label)
	var normal_place_button := Button.new(); normal_place_button.text = "单素材左键铺设 / 摆放"; normal_place_button.pressed.connect(_activate_normal_placement); sidebar.add_child(normal_place_button)
	var wall_loop_button := Button.new()
	wall_loop_button.text = "生成闭合矩形墙体"
	wall_loop_button.tooltip_text = "自动预留四个角格、选择正确角件，并按墙体连接方向生成无重叠闭环"
	wall_loop_button.pressed.connect(_on_wall_loop_dialog_requested)
	sidebar.add_child(wall_loop_button)
	_build_wall_loop_dialog()
	var select_button:=Button.new(); select_button.text="选择工具（悬停高亮／左键选取／方向键移动）"; select_button.pressed.connect(_activate_select_tool); sidebar.add_child(select_button)
	random_region_fill_toggle = CheckBox.new(); random_region_fill_toggle.text = "自由套索选择模式"; random_region_fill_toggle.toggled.connect(_on_lasso_mode_toggled); sidebar.add_child(random_region_fill_toggle)
	point_erase_toggle = CheckBox.new(); point_erase_toggle.text = "点选/拖动擦除地面和对象"; point_erase_toggle.toggled.connect(_on_point_erase_toggled); sidebar.add_child(point_erase_toggle)
	var role_label := Label.new(); role_label.text = "对象语义角色"; sidebar.add_child(role_label)
	object_role_option = OptionButton.new()
	for role: Array in [["装饰物","decoration"],["障碍物","obstacle"],["建筑","building"],["可交互物","interactable"],["地形结构","terrain"]]:
		object_role_option.add_item(role[0]); object_role_option.set_item_metadata(object_role_option.item_count-1,role[1])
	sidebar.add_child(object_role_option)
	var walkable_button := CheckBox.new(); walkable_button.text = "显示不可走区域"; walkable_button.toggled.connect(_on_walkable_preview_toggled); sidebar.add_child(walkable_button)
	var collision_title := Label.new(); collision_title.text = "手工碰撞"; collision_title.add_theme_font_size_override("font_size", 13); sidebar.add_child(collision_title)
	collision_shape_option = OptionButton.new()
	for shape: Array in [["单格（左键点击或拖动）","cell"],["矩形（两点）","rect"],["椭圆（两点）","ellipse"],["多边形（逐点，Enter完成）","polygon"]]:
		collision_shape_option.add_item(shape[0]); collision_shape_option.set_item_metadata(collision_shape_option.item_count-1,shape[1])
	collision_shape_option.item_selected.connect(_on_collision_shape_selected)
	sidebar.add_child(collision_shape_option)
	collision_draw_toggle = CheckBox.new(); collision_draw_toggle.text = "在画布绘制碰撞（右键取消）"; collision_draw_toggle.toggled.connect(_on_collision_draw_toggled); sidebar.add_child(collision_draw_toggle)
	collision_erase_toggle = CheckBox.new(); collision_erase_toggle.text = "单格擦除碰撞（左键点击或拖动，右键退出）"; collision_erase_toggle.toggled.connect(_on_collision_erase_toggled); sidebar.add_child(collision_erase_toggle)
	collision_erase_whole_toggle = CheckBox.new(); collision_erase_whole_toggle.text = "整块擦除碰撞（删除形状或禁用素材碰撞）"; collision_erase_whole_toggle.toggled.connect(_on_collision_erase_whole_toggled); sidebar.add_child(collision_erase_whole_toggle)
	collision_instruction_label = Label.new(); collision_instruction_label.text = "选择形状后将自动进入碰撞绘制"; collision_instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; collision_instruction_label.modulate = Color("d7aa62"); sidebar.add_child(collision_instruction_label)
	var semantic_title := Label.new(); semantic_title.text = "NPC、怪物与地图功能点"; semantic_title.add_theme_font_size_override("font_size", 13); sidebar.add_child(semantic_title)
	semantic_kind_option = OptionButton.new()
	for kind: Array in [
		["NPC","npc"],["普通怪物刷新点","monster_spawn"],["精英与Boss刷新点","boss_spawn"],["特殊地图怪物","special_monster"],
		["地图传送点（默认双向）","map_exit"],["独立到达点（特殊用途）","map_entrance"],
		["出生／复活点","respawn_point"],["多边形安全区","safe_area"],
		["光效点","light"],["区域触发器","region_trigger"],
	]:
		semantic_kind_option.add_item(kind[0]); semantic_kind_option.set_item_metadata(semantic_kind_option.item_count-1,kind[1])
	semantic_kind_option.item_selected.connect(_on_semantic_kind_selected); semantic_kind_option.pressed.connect(_activate_semantic_placement)
	sidebar.add_child(semantic_kind_option)
	var content_label := Label.new(); content_label.text = "NPC / 怪物 / Boss / 特殊地图目录"; sidebar.add_child(content_label)
	semantic_content_option = OptionButton.new(); semantic_content_option.fit_to_longest_item = false; semantic_content_option.item_selected.connect(_on_semantic_content_selected); semantic_content_option.pressed.connect(_activate_semantic_placement); sidebar.add_child(semantic_content_option)
	semantic_catalog_tree = Tree.new(); semantic_catalog_tree.hide_root = true; semantic_catalog_tree.custom_minimum_size.y = 150; semantic_catalog_tree.item_selected.connect(_on_semantic_catalog_selected); semantic_catalog_tree.gui_input.connect(_on_semantic_catalog_gui_input); sidebar.add_child(semantic_catalog_tree); _refresh_semantic_catalog_tree()
	semantic_detail_scroll = ScrollContainer.new()
	semantic_detail_scroll.custom_minimum_size = Vector2(0, 180)
	semantic_detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	semantic_detail_label = Label.new()
	semantic_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	semantic_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	semantic_detail_scroll.add_child(semantic_detail_label)
	sidebar.add_child(semantic_detail_scroll)
	semantic_content_id = _field(sidebar, "内容ID（高级选项，可手工覆盖）", "")
	semantic_display_name = _field(sidebar, "标注名称", "")
	semantic_target_map = _field(sidebar, "传送点连接的目标地图 ID（由连接工具配置）", "")
	semantic_target_entrance = _field(sidebar, "目标传送点 ID（由连接工具配置）", "")
	semantic_radius = _spin_field(sidebar, "刷新/区域半径（格；Boss 可为 0）", 0, 64); semantic_radius.value = 3
	semantic_count = _spin_field(sidebar, "刷新数量", 1, 200); semantic_count.value = 1
	semantic_respawn = _spin_field(sidebar, "刷新间隔（秒）", 1, 86400); semantic_respawn.value = 60
	semantic_max_alive = _spin_field(sidebar, "最大存活数", 1, 200); semantic_max_alive.value = 1
	var facing_label := Label.new(); facing_label.text = "NPC 朝向"; sidebar.add_child(facing_label)
	semantic_facing = OptionButton.new()
	for facing: Array in [["下","south"],["左下","south_west"],["左","west"],["左上","north_west"],["上","north"],["右上","north_east"],["右","east"],["右下","south_east"]]:
		semantic_facing.add_item(facing[0]); semantic_facing.set_item_metadata(semantic_facing.item_count-1,facing[1])
	sidebar.add_child(semantic_facing)
	semantic_place_toggle = CheckBox.new(); semantic_place_toggle.text = "开启功能标注：在地图左键放置"; semantic_place_toggle.toggled.connect(_on_semantic_place_toggled); sidebar.add_child(semantic_place_toggle)
	var semantic_place_button := Button.new(); semantic_place_button.text="使用当前类型进行地图标注"; semantic_place_button.pressed.connect(_activate_semantic_placement); sidebar.add_child(semantic_place_button)
	var semantic_update_button := Button.new(); semantic_update_button.text = "更新当前选中的功能标注"; semantic_update_button.pressed.connect(_on_update_selected_semantic_pressed); sidebar.add_child(semantic_update_button)
	var door_note := Label.new(); door_note.text = "入口与出口必须分别手工标注：先摆放墙门美术，再选“地图入口”或“地图出口”点在门的位置。入口美术不会自动生成门点。安全区左键逐点，Enter 闭合，右键取消。"; door_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; door_note.modulate=Color("b8c3cf"); sidebar.add_child(door_note)
	var bake_button := Button.new(); bake_button.text = "烘焙 Dirty Chunk 预览"; bake_button.pressed.connect(_on_bake_dirty_pressed); sidebar.add_child(bake_button)
	var build_runtime_button := Button.new(); build_runtime_button.text = "批准并构建 Runtime 快照"; build_runtime_button.pressed.connect(_on_approve_and_build_runtime_pressed); sidebar.add_child(build_runtime_button)
	var calibration_title := Label.new(); calibration_title.text = "素材校准（Expansion覆盖）"; calibration_title.add_theme_font_size_override("font_size", 13); sidebar.add_child(calibration_title)
	calibration_anchor_x = _spin_field(sidebar, "锚点 X", 0, 2048)
	calibration_anchor_y = _spin_field(sidebar, "锚点 Y", 0, 2048)
	calibration_footprint_x = _spin_field(sidebar, "占地宽度（格）", 1, 16)
	calibration_footprint_y = _spin_field(sidebar, "占地高度（格）", 1, 16)
	var collision_label := Label.new(); collision_label.text = "碰撞策略"; sidebar.add_child(collision_label)
	calibration_collision = OptionButton.new()
	for policy: Array in [["无碰撞","none"],["素材预设碰撞","preset"],["手工碰撞","manual"],["按地形印章生成","terrain_stamp_generated"],["按墙体单元生成","wall_cells_generated"],["整个占地阻挡","solid_footprint"],["自定义多边形","custom_polygon"]]:
		calibration_collision.add_item(policy[0]); calibration_collision.set_item_metadata(calibration_collision.item_count-1,policy[1])
	sidebar.add_child(calibration_collision)
	calibration_occlusion = CheckBox.new(); calibration_occlusion.text = "遮挡玩家"; sidebar.add_child(calibration_occlusion)
	var save_calibration := Button.new(); save_calibration.text = "保存素材校准覆盖（不保存地图）"; save_calibration.pressed.connect(_on_save_calibration_pressed); sidebar.add_child(save_calibration)
	status_label = Label.new(); status_label.text = "就绪"; status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sidebar.add_child(status_label)
	preview = MapEditorCanvasPreview.new(); preview.paint_requested.connect(_on_ground_paint_requested); preview.erase_tile_requested.connect(_on_erase_tile_requested); preview.lasso_context_requested.connect(_on_lasso_context_requested); preview.tile_hovered.connect(_on_tile_hovered); preview.manual_collision_tile_clicked.connect(_on_manual_collision_tile_clicked); preview.manual_collision_erase_requested.connect(_on_manual_collision_erase_requested); preview.manual_collision_cancelled.connect(_on_manual_collision_cancelled); preview.semantic_tile_clicked.connect(_on_semantic_tile_clicked); preview.semantic_cancelled.connect(_on_semantic_cancelled); preview.selectable_selected.connect(_on_selectable_selected); preview.selectable_move_requested.connect(_on_selectable_move_requested); preview.selectable_delete_requested.connect(_on_selectable_delete_requested); preview.selectable_context_requested.connect(_on_selectable_context_requested); preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL; preview.size_flags_vertical = Control.SIZE_EXPAND_FILL; preview.custom_minimum_size = Vector2(640, 480); preview.focus_mode=Control.FOCUS_ALL; layout.add_child(preview)
	preview.clipboard_paste_requested.connect(_on_clipboard_paste_requested)
	preview.clipboard_paste_cancelled.connect(_on_clipboard_paste_cancelled)
	region_fill_menu = PopupMenu.new(); region_fill_menu.add_item("用素材列表已选地面随机填充", 1); region_fill_menu.add_item("删除套索内地面和对象", 3); region_fill_menu.add_separator(); region_fill_menu.add_item("取消", 2); region_fill_menu.id_pressed.connect(_on_region_fill_menu_pressed); add_child(region_fill_menu)
	asset_size_menu = PopupMenu.new(); asset_size_menu.add_item("放大一格", 1); asset_size_menu.add_item("缩小一格", 2); asset_size_menu.add_separator(); asset_size_menu.add_item("恢复初始占位", 3); asset_size_menu.add_separator(); asset_size_menu.add_item("删除素材", 4); asset_size_menu.id_pressed.connect(_on_asset_size_menu_pressed); add_child(asset_size_menu)
	_build_asset_delete_dialog()
	instance_size_menu = PopupMenu.new(); instance_size_menu.add_item("放大当前地图素材", 1); instance_size_menu.add_item("缩小当前地图素材", 2); instance_size_menu.add_separator(); instance_size_menu.add_item("提高一层（仅素材间）", 3); instance_size_menu.add_item("下降一层（仅素材间）", 4); instance_size_menu.id_pressed.connect(_on_instance_size_menu_pressed); add_child(instance_size_menu)
	_on_semantic_kind_selected(0)
	var first_asset := _first_asset_tree_item()
	if first_asset != null:
		first_asset.select(0)
		_activate_asset_tree_item(first_asset)
	_activate_select_tool()


func _field(parent: Control, label_text: String, initial: String) -> LineEdit:
	var label := Label.new(); label.text = label_text; parent.add_child(label)
	var edit := LineEdit.new(); edit.text = initial; parent.add_child(edit); return edit


func _spin_field(parent: Control, label_text: String, minimum: float, maximum: float) -> SpinBox:
	var label := Label.new(); label.text = label_text; parent.add_child(label)
	var spin := SpinBox.new(); spin.min_value = minimum; spin.max_value = maximum; spin.step = 1.0; parent.add_child(spin); return spin


func _build_create_map_dialog() -> void:
	create_map_dialog = ConfirmationDialog.new()
	create_map_dialog.title = "创建地图模板"
	create_map_dialog.dialog_text = "填写地图模板名称、地图 ID，并选择地图占用多少个布局 Chunk。"
	create_map_dialog.get_ok_button().hide()
	create_map_dialog.get_cancel_button().hide()
	add_child(create_map_dialog)
	var form := VBoxContainer.new()
	form.custom_minimum_size = Vector2(480, 0)
	create_map_dialog.add_child(form)
	var chunk_note := Label.new()
	chunk_note.text = "每个布局 Chunk（不是贴图像素 Chunk）= 16×16 个逻辑格；例如 5×5 = 80×80 格，10×10 = 160×160 格。"
	chunk_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chunk_note.modulate = Color("9da7b3")
	form.add_child(chunk_note)
	var fields := GridContainer.new()
	fields.columns = 2
	fields.add_theme_constant_override("h_separation", 12)
	fields.add_theme_constant_override("v_separation", 4)
	form.add_child(fields)
	display_name_edit = _field(fields, "地图模板名称", "新地图模板")
	map_id_edit = _field(fields, "地图 ID", "new_map")
	var runtime_label := Label.new(); runtime_label.text = "运行地图 ID"; fields.add_child(runtime_label)
	runtime_id_edit = SpinBox.new(); runtime_id_edit.min_value = 1; runtime_id_edit.max_value = 9999999; runtime_id_edit.value = 990100; fields.add_child(runtime_id_edit)
	var type_label := Label.new(); type_label.text = "地图类型"; fields.add_child(type_label)
	map_type_option = OptionButton.new()
	for entry: Dictionary in MapDesignCatalogService._read_json(MapDesignCatalogService.TEMPLATE_PATH).get("templates", []):
		map_type_option.add_item(_map_type_chinese(str(entry.id)))
		map_type_option.set_item_metadata(map_type_option.item_count - 1, str(entry.id))
	fields.add_child(map_type_option)
	map_type_option.select(_find_type_index("quest_room"))
	create_chunk_x = _spin_field(fields, "横向布局 Chunk 数", 1, 32); create_chunk_x.value = 5
	create_chunk_y = _spin_field(fields, "纵向布局 Chunk 数", 1, 32); create_chunk_y.value = 5
	create_chunk_x.value_changed.connect(func(_value: float): _refresh_create_size_preview())
	create_chunk_y.value_changed.connect(func(_value: float): _refresh_create_size_preview())
	create_size_preview = Label.new()
	create_size_preview.modulate = Color("d7aa62")
	form.add_child(create_size_preview)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	form.add_child(actions)
	var cancel_button := Button.new(); cancel_button.text = "取消"; cancel_button.pressed.connect(create_map_dialog.hide); actions.add_child(cancel_button)
	create_dialog_submit_button = Button.new(); create_dialog_submit_button.text = "创建地图模板"; create_dialog_submit_button.pressed.connect(_on_create_pressed); actions.add_child(create_dialog_submit_button)
	_refresh_create_size_preview()


func _build_asset_delete_dialog() -> void:
	asset_delete_dialog = ConfirmationDialog.new()
	asset_delete_dialog.title = "删除素材"
	asset_delete_dialog.get_ok_button().text = "删除素材"
	asset_delete_dialog.get_cancel_button().text = "取消"
	asset_delete_dialog.confirmed.connect(_on_asset_delete_confirmed)
	asset_delete_dialog.canceled.connect(_on_asset_delete_cancelled)
	add_child(asset_delete_dialog)


func _refresh_create_size_preview() -> void:
	if create_chunk_x == null or create_chunk_y == null or create_size_preview == null:
		return
	var chunks := Vector2i(int(create_chunk_x.value), int(create_chunk_y.value))
	var design_size := Vector2i(
		chunks.x * MapEditorTypes.AUTHORING_CHUNK_SIZE_TILES.x,
		chunks.y * MapEditorTypes.AUTHORING_CHUNK_SIZE_TILES.y
	)
	create_size_preview.text = "将创建地图模板：%d×%d Chunk，地图尺寸 %d×%d 格" % [chunks.x, chunks.y, design_size.x, design_size.y]


func _build_wall_loop_dialog() -> void:
	wall_loop_dialog = ConfirmationDialog.new()
	wall_loop_dialog.title = "生成闭合矩形墙体"
	wall_loop_dialog.dialog_text = "四条边会预留角格并自动使用匹配连接方向的角件。边界上同墙族的旧墙体会被替换，装饰物、碰撞和功能标注不会改动。"
	wall_loop_dialog.confirmed.connect(_on_wall_loop_confirmed)
	add_child(wall_loop_dialog)
	var form := GridContainer.new()
	form.columns = 2
	form.custom_minimum_size = Vector2(500, 0)
	form.add_theme_constant_override("h_separation", 12)
	form.add_theme_constant_override("v_separation", 6)
	wall_loop_dialog.add_child(form)
	var family_label := Label.new()
	family_label.text = "墙体系列"
	form.add_child(family_label)
	wall_loop_family_option = OptionButton.new()
	wall_loop_family_option.fit_to_longest_item = false
	form.add_child(wall_loop_family_option)
	var corner_label := Label.new()
	corner_label.text = "角件类型"
	form.add_child(corner_label)
	wall_loop_corner_option = OptionButton.new()
	for entry: Array in [["外圈墙体", "outer_corner"], ["内圈墙体", "inner_corner"]]:
		wall_loop_corner_option.add_item(entry[0])
		wall_loop_corner_option.set_item_metadata(
			wall_loop_corner_option.item_count - 1,
			entry[1]
		)
	form.add_child(wall_loop_corner_option)
	wall_loop_min_x = _spin_field(form, "左上格 X", 0, 1024)
	wall_loop_min_y = _spin_field(form, "左上格 Y", 0, 1024)
	wall_loop_max_x = _spin_field(form, "右下格 X", 2, 1024)
	wall_loop_max_y = _spin_field(form, "右下格 Y", 2, 1024)


func _on_wall_loop_dialog_requested() -> void:
	if current_document.is_empty():
		status_label.text = "请先创建或打开地图模板"
		return
	wall_loop_family_option.clear()
	var preferred_family := str(
		current_document.get("design", {}).get(
			"dungeon_structure",
			{}
		).get("wall_family_id", "")
	)
	var selected_family_index := 0
	for family: Dictionary in WallLoopService.available_families():
		wall_loop_family_option.add_item(str(family.display_name))
		wall_loop_family_option.set_item_metadata(
			wall_loop_family_option.item_count - 1,
			str(family.wall_family_id)
		)
		if str(family.wall_family_id) == preferred_family:
			selected_family_index = wall_loop_family_option.item_count - 1
	if wall_loop_family_option.item_count == 0:
		status_label.text = "素材库中没有可用的洞穴或地下城墙体系列"
		return
	wall_loop_family_option.select(selected_family_index)
	var raw_size: Array = current_document.design.design_size
	var map_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	for spin: SpinBox in [wall_loop_min_x, wall_loop_max_x]:
		spin.max_value = map_size.x - 1
	for spin: SpinBox in [wall_loop_min_y, wall_loop_max_y]:
		spin.max_value = map_size.y - 1
	wall_loop_min_x.value = 0
	wall_loop_min_y.value = 0
	wall_loop_max_x.value = map_size.x - 1
	wall_loop_max_y.value = map_size.y - 1
	wall_loop_dialog.popup_centered()


func _on_wall_loop_confirmed() -> void:
	var minimum := Vector2i(int(wall_loop_min_x.value), int(wall_loop_min_y.value))
	var maximum := Vector2i(int(wall_loop_max_x.value), int(wall_loop_max_y.value))
	if maximum.x - minimum.x < 2 or maximum.y - minimum.y < 2:
		status_label.text = "闭合墙体至少需要 3×3 格"
		return
	var family_id := str(
		wall_loop_family_option.get_item_metadata(wall_loop_family_option.selected)
	)
	var corner_topology := str(
		wall_loop_corner_option.get_item_metadata(wall_loop_corner_option.selected)
	)
	var bounds := Rect2i(minimum, maximum - minimum + Vector2i.ONE)
	var before_layers: Dictionary = current_document.layers.duplicate(true)
	var before_design: Dictionary = current_document.design.duplicate(true)
	var result: Dictionary = WallLoopService.apply_closed_rectangle(
		current_document,
		family_id,
		bounds,
		corner_topology,
		"terrain_base",
		true
	)
	if not bool(result.get("ok", false)):
		status_label.text = "生成闭合墙体失败：%s" % result.get("errors", [])
		return
	var after_layers: Dictionary = current_document.layers.duplicate(true)
	var after_design: Dictionary = current_document.design.duplicate(true)
	command_stack.execute({
		"do": func():
			current_document.layers = after_layers.duplicate(true)
			current_document.design = after_design.duplicate(true)
			preview.set_document(current_document),
		"undo": func():
			current_document.layers = before_layers.duplicate(true)
			current_document.design = before_design.duplicate(true)
			preview.set_document(current_document),
	})
	preview.set_document(current_document)
	status_label.text = (
		"闭合墙体已生成：新增 %d 段，替换 %d 段。确认后点击“保存地图”。"
		% [int(result.added_count), int(result.removed_count)]
	)


func _find_type_index(map_type: String) -> int:
	for i in map_type_option.item_count:
		if str(map_type_option.get_item_metadata(i)) == map_type: return i
	return 0


func _map_type_chinese(map_type: String) -> String:
	return {"bich_city_outdoor":"城镇与野外复合地图","outdoor_province":"大型野外省份","outdoor_field":"普通野外","city_embedded":"嵌入式城镇","shop_interior":"商店室内","palace_room":"宫殿房间","dungeon_floor":"地下城楼层","mine_floor":"矿洞楼层","temple_floor":"神殿楼层","corridor":"走廊地图","maze_room":"迷宫房间","boss_room":"Boss房间","quest_room":"任务房间","arena_room":"竞技场"}.get(map_type,"其他地图")


func _on_create_pressed() -> void:
	var map_id := map_id_edit.text.strip_edges()
	var display_name := display_name_edit.text.strip_edges()
	if display_name.is_empty():
		status_label.text = "创建地图模板失败：模板名称不能为空"
		return
	var id_pattern := RegEx.new()
	id_pattern.compile("^[A-Za-z0-9][A-Za-z0-9_-]*$")
	if map_id.is_empty() or id_pattern.search(map_id) == null:
		status_label.text = "创建地图模板失败：地图 ID 只能使用英文、数字、下划线或短横线"
		return
	var target_path := MapEditorSaveService.default_path(map_id)
	var ground_manifest_path := "res://map_editor_workspace/%s/ground/ground_manifest.json" % map_id
	if FileAccess.file_exists(target_path) or FileAccess.file_exists(ground_manifest_path):
		create_map_dialog.dialog_text = "地图 ID「%s」已存在！请更换地图 ID，或关闭本窗口后在地图模板下拉菜单中找到并打开它。" % map_id
		status_label.text = "创建地图模板失败：地图工作区 %s 已存在，请勿重复创建" % map_id
		return
	var map_type := str(map_type_option.get_item_metadata(map_type_option.selected))
	var chunk_grid := Vector2i(int(create_chunk_x.value), int(create_chunk_y.value))
	var document := MapEditorTypes.new_custom_map(map_id, int(runtime_id_edit.value), display_name, map_type, chunk_grid)
	_adopt_new_document(document, "已创建地图模板")
	var saved := _save_current_document()
	if saved.get("ok", false):
		_refresh_map_template_options()
		_select_template_for_map_id(map_id)
		status_label.text = "地图模板已创建、打开并保存：%s（%d×%d Chunk）" % [display_name, chunk_grid.x, chunk_grid.y]
		create_map_dialog.hide()
	else:
		status_label.text = "地图模板已创建但保存失败：%s" % saved.get("errors", [])


func _on_create_map_dialog_requested() -> void:
	display_name_edit.text = "新地图模板"
	runtime_id_edit.value = 990100
	map_type_option.select(_find_type_index("quest_room"))
	create_chunk_x.value = 5
	create_chunk_y.value = 5
	map_id_edit.text = _next_default_map_id(str(map_type_option.get_item_metadata(map_type_option.selected)))
	_refresh_create_size_preview()
	create_map_dialog.dialog_text = "填写地图模板名称、地图 ID，并选择地图占用多少个布局 Chunk。"
	create_map_dialog.popup_centered(Vector2i(520, 330))
	display_name_edit.grab_focus()
	display_name_edit.select_all()


func _next_default_map_id(map_type := "") -> String:
	var base := _map_type_id_prefix(map_type)
	var taken := _all_existing_map_ids()
	var i := 1
	while taken.has("%s_%d" % [base, i]):
		i += 1
	return "%s_%d" % [base, i]


func _all_existing_map_ids() -> Dictionary:
	var taken := {}
	for template: Dictionary in MapDesignCatalogService.blank_templates():
		taken[str(template.get("map_id", ""))] = true
	for entry: Dictionary in MapDesignCatalogService.load_catalog().get("maps", []):
		taken[str(entry.get("map_id", ""))] = true
	var dir := DirAccess.open(MapEditorSaveService.EDITOR_ROOT)
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if dir.current_is_dir():
				taken[name] = true
			name = dir.get_next()
		dir.list_dir_end()
	return taken


func _map_type_id_prefix(map_type: String) -> String:
	return {
		"outdoor_province": "province",
		"outdoor_field": "field",
		"dungeon_floor": "dungeon",
		"mine_floor": "mine",
		"temple_floor": "temple",
		"corridor": "corridor",
		"maze_room": "maze",
		"boss_room": "boss_room",
		"quest_room": "quest",
		"arena_room": "arena",
		"shop_interior": "shop",
		"palace_room": "palace",
		"city_embedded": "city",
		"bich_city_outdoor": "bich_city",
	}.get(map_type, "custom_map")


func _on_open_template_pressed() -> void:
	if map_template_option.selected < 0:
		status_label.text = "请选择要打开的地图模板"
		return
	var meta: Variant = map_template_option.get_item_metadata(map_template_option.selected)
	if meta is Dictionary and str(meta.get("kind", "")) == "workspace":
		_open_workspace_map(meta)
		return
	_open_template_by_id(str(meta))


func _open_workspace_map(meta: Dictionary) -> void:
	var path := str(meta.get("path", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		status_label.text = "自建地图文件不存在：%s" % path
		return
	_open_document_path(path)


func _template_option_key(meta: Variant) -> String:
	if meta is Dictionary:
		return "workspace::" + str(meta.get("map_id", ""))
	return str(meta)


func _refresh_map_template_options(preferred_template_id := "") -> void:
	if map_template_option == null:
		return
	var selected_key := preferred_template_id
	if selected_key.is_empty() and map_template_option.selected >= 0:
		selected_key = _template_option_key(map_template_option.get_item_metadata(map_template_option.selected))
	map_template_option.clear()
	var selected_index := 0
	for template: Dictionary in MapDesignCatalogService.blank_templates():
		var template_size: Array = template.get("design_size", [0, 0])
		map_template_option.add_item(
			"%s · %d×%d"
			% [
				str(template.get("display_name", template.get("map_id", ""))),
				int(template_size[0]),
				int(template_size[1]),
			]
		)
		var index := map_template_option.item_count - 1
		var template_id := str(template.get("template_id", ""))
		map_template_option.set_item_metadata(index, template_id)
		if template_id == selected_key:
			selected_index = index
	for workspace_map: Dictionary in MapEditorSaveService.list_workspace_maps():
		var design_size: Array = workspace_map.get("design_size", [0, 0])
		map_template_option.add_item(
			"%s · %d×%d"
			% [
				str(workspace_map.get("display_name", workspace_map.get("map_id", ""))),
				int(design_size[0]),
				int(design_size[1]),
			]
		)
		var index := map_template_option.item_count - 1
		var meta := {"kind": "workspace", "map_id": str(workspace_map.get("map_id", "")), "display_name": str(workspace_map.get("display_name", "")), "design_size": design_size, "path": str(workspace_map.get("path", ""))}
		map_template_option.set_item_metadata(index, meta)
		if _template_option_key(meta) == selected_key:
			selected_index = index
	if map_template_option.item_count > 0:
		map_template_option.select(selected_index)
		if template_info_label != null:
			_on_map_template_selected(selected_index)


func _open_template_by_id(template_id: String, document_path := "", workspace_override := "") -> bool:
	var template := MapDesignCatalogService.find_blank_template(template_id)
	if template.is_empty():
		status_label.text = "地图模板不存在：%s" % template_id
		return false
	var path := document_path if not document_path.is_empty() else MapEditorSaveService.default_path(str(template.get("map_id", "")))
	if FileAccess.file_exists(path):
		return _open_document_path(path)
	var document := MapEditorTypes.new_map_from_blank_template(template_id)
	if document.is_empty():
		status_label.text = "无法创建地图模板：%s" % template_id
		return false
	if not workspace_override.is_empty():
		document.editor_meta["workspace"] = workspace_override
	_adopt_new_document(document, "已从所选模板新建并打开", path)
	var saved := _save_current_document()
	if saved.get("ok", false):
		status_label.text = "地图模板已创建、打开并保存：%s" % str(document.get("display_name", document.get("map_id", "")))
		return true
	else:
		status_label.text = "地图模板已打开，但保存失败：%s" % saved.get("errors", [])
		return false


func _on_map_template_selected(index: int) -> void:
	if index < 0 or index >= map_template_option.item_count:
		return
	var meta: Variant = map_template_option.get_item_metadata(index)
	if meta is Dictionary:
		var design_size: Array = meta.get("design_size", [0, 0])
		template_info_label.text = "自建地图：%d×%d 格；将直接打开已保存的地图" % [int(design_size[0]), int(design_size[1])]
		return
	var template := MapDesignCatalogService.find_blank_template(str(meta))
	if template.is_empty():
		return
	var design_size: Array = template.get("design_size", [0, 0])
	template_info_label.text = "所选模板：%d×%d 格；尚未创建时会自动新建并打开" % [int(design_size[0]), int(design_size[1])]


func _select_template_for_map_id(map_id: String) -> void:
	for index in map_template_option.item_count:
		var meta: Variant = map_template_option.get_item_metadata(index)
		if meta is Dictionary:
			if str(meta.get("map_id", "")) == map_id:
				map_template_option.select(index)
				_on_map_template_selected(index)
				return
		else:
			var template := MapDesignCatalogService.find_blank_template(str(meta))
			if str(template.get("map_id", "")) == map_id:
				map_template_option.select(index)
				_on_map_template_selected(index)
				return


func _create_map(map_id: String, map_type: String, runtime_map_id: int, display_name: String) -> void:
	if map_id.is_empty(): status_label.text = "地图 ID 不能为空"; return
	_adopt_new_document(MapEditorTypes.new_map_from_catalog(map_id, map_type, runtime_map_id, display_name), "已新建")


func _adopt_new_document(document: Dictionary, status_prefix: String, document_path := "") -> void:
	_reset_document_session_state()
	current_document = document
	map_id_edit.text = str(current_document.map_id); display_name_edit.text = str(current_document.display_name); runtime_id_edit.value = int(current_document.runtime_map_id)
	map_type_option.select(_find_type_index(str(current_document.design.map_type)))
	_select_template_for_map_id(str(current_document.map_id))
	var design_size: Array = current_document.design.design_size
	size_label.text = "设计尺寸：%d × %d（64×32 等距格）" % [int(design_size[0]), int(design_size[1])]
	var resolved_document_path := document_path if not document_path.is_empty() else MapEditorSaveService.default_path(str(current_document.map_id))
	current_document_path = resolved_document_path
	path_label.text = "工作文件：%s" % ProjectSettings.globalize_path(resolved_document_path)
	status_label.text = "%s；source_size 不会覆盖 design_size" % status_prefix
	preview.set_document(current_document)
	_set_active_tool("select")
	var initialized := MapEditorGroundService.initialize(current_document)
	if initialized.ok:
		initialized = _ensure_ground_coordinate_contract(initialized)
	if initialized.ok:
		status_label.text = "%s：%d 个地面 Chunk 使用统一格子中心坐标" % [status_prefix, (initialized.manifest.chunks as Array).size()]
		preview.set_ground_state(initialized.state)


func _refresh_asset_tree() -> void:
	asset_tree.clear()
	var root := asset_tree.create_item()
	var folders := {}
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if not bool(asset.get("placeable", false)):
			continue
		var parent := root
		var accumulated := ""
		for part: String in str(asset.get("palette_path", "未分类")).split("/", false):
			accumulated = part if accumulated.is_empty() else accumulated + "/" + part
			if not folders.has(accumulated):
				var folder := asset_tree.create_item(parent)
				folder.set_text(0, part)
				folder.set_metadata(0, {"folder": accumulated})
				folder.set_selectable(0, false)
				folder.collapsed = accumulated.count("/") > 0
				folders[accumulated] = folder
			parent = folders[accumulated]
		var raw_image: Variant = asset.get("thumbnail", asset.get("image", ""))
		var image_path := "" if raw_image == null else str(raw_image)
		var item := asset_tree.create_item(parent)
		item.set_text(0, str(asset.get("display_name", asset.get("asset_id", ""))))
		item.set_metadata(0, {"asset_id": str(asset.get("asset_id", "")), "thumbnail": image_path})


func _ensure_asset_tree_item_icon(item: TreeItem) -> void:
	if item == null or item.get_icon(0) != null:
		return
	var metadata: Variant = item.get_metadata(0)
	if not metadata is Dictionary:
		return
	var image_path := str(metadata.get("thumbnail", ""))
	if image_path.is_empty():
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://" + image_path))
	if image == null or image.is_empty():
		return
	var maximum_dimension := maxi(image.get_width(), image.get_height())
	if maximum_dimension > 64:
		var ratio := 64.0 / float(maximum_dimension)
		image.resize(maxi(1, roundi(image.get_width() * ratio)), maxi(1, roundi(image.get_height() * ratio)), Image.INTERPOLATE_BILINEAR)
	item.set_icon(0, ImageTexture.create_from_image(image))
	item.set_icon_max_width(0, 64)


func _first_asset_tree_item() -> TreeItem:
	var item := asset_tree.get_root().get_next_in_tree()
	while item != null:
		var metadata: Variant = item.get_metadata(0)
		if metadata is Dictionary and not str(metadata.get("asset_id", "")).is_empty():
			return item
		item = item.get_next_in_tree()
	return null


func _on_save_pressed() -> void:
	if current_document.is_empty():
		status_label.text = "保存失败：当前没有打开地图"
		return
	var result := _save_current_document()
	status_label.text = "地图已保存：%s → %s" % [str(current_document.get("map_id", "")), result.get("path", "")] if result.get("ok", false) else "保存地图失败：%s" % result.get("errors", [])


func _on_open_pressed() -> void:
	if current_document.is_empty():
		status_label.text = "当前没有可重新载入的地图"
		return
	MapAssetCatalogService.invalidate_cache()
	_refresh_asset_tree()
	_refresh_map_template_options(
		"blank.%s" % str(current_document.get("map_id", ""))
	)
	_open_document_path(_resolved_current_document_path())


func _resolved_current_document_path() -> String:
	var map_id := str(current_document.get("map_id", ""))
	var expected_file := "%s.editor.json" % map_id
	if current_document_path.is_empty() or current_document_path.get_file() != expected_file:
		return MapEditorSaveService.default_path(map_id)
	return current_document_path


func _save_current_document() -> Dictionary:
	var path := _resolved_current_document_path()
	var initialized := MapEditorGroundService.initialize(current_document)
	if not initialized.get("ok", false):
		return initialized
	initialized = _ensure_ground_coordinate_contract(initialized)
	if not initialized.get("ok", false):
		return initialized
	var result := MapEditorSaveService.save_document(current_document, path)
	if result.get("ok", false):
		preview.reload_ground_state(initialized.state)
		current_document_path = path
		path_label.text = "工作文件：%s" % ProjectSettings.globalize_path(path)
		_remember_current_document_path(path)
	return result


func _load_last_document_path() -> String:
	if not persist_last_document_path or not FileAccess.file_exists(LAST_DOCUMENT_PATH_FILE):
		return ""
	var file := FileAccess.open(LAST_DOCUMENT_PATH_FILE, FileAccess.READ)
	return file.get_as_text().strip_edges() if file != null else ""


func _remember_current_document_path(path: String) -> void:
	if not persist_last_document_path:
		return
	var file := FileAccess.open(LAST_DOCUMENT_PATH_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(path)


func _open_document_path(path: String) -> bool:
	var result := MapEditorLoadService.load_document(path)
	if result.get("ok", false):
		_reset_document_session_state()
		current_document = result.document
		current_document_path = path
		_migrate_loaded_blank_ground_policy()
		_migrate_loaded_instances_to_class_profiles()
		MapEditorGameplaySemanticService.repair_duplicate_ids(current_document)
		_ensure_map_portal_semantics()
		map_id_edit.text = str(current_document.get("map_id", "")); display_name_edit.text = str(current_document.get("display_name", "")); runtime_id_edit.value = int(current_document.get("runtime_map_id", 0))
		map_type_option.select(_find_type_index(str(current_document.design.get("map_type", ""))))
		_select_template_for_map_id(str(current_document.get("map_id", "")))
		var design_size: Array = current_document.design.get("design_size", [0, 0])
		size_label.text = "设计尺寸：%d × %d（64×32 等距格）" % [int(design_size[0]), int(design_size[1])]
		path_label.text = "工作文件：%s" % ProjectSettings.globalize_path(path)
		preview.set_document(current_document)
		_set_active_tool("select")
		var initialized := MapEditorGroundService.initialize(current_document)
		if initialized.ok:
			initialized = _ensure_ground_coordinate_contract(initialized)
		if not initialized.ok:
			status_label.text = "地面坐标迁移失败：%s" % initialized.get("errors", [])
			return false
		preview.set_ground_state(initialized.state)
		status_label.text = "地图打开成功：%s" % path
		_remember_current_document_path(path)
		return true
	status_label.text = "打开失败：%s" % result.get("errors", [])
	return false


func _ensure_ground_coordinate_contract(initialized: Dictionary) -> Dictionary:
	if not initialized.get("ok", false):
		return initialized
	if (initialized.get("state", {}).get("dirty_chunks", []) as Array).is_empty():
		return initialized
	var bake := MapEditorChunkBakeService.bake_dirty_chunks(current_document)
	if not bake.get("ok", false):
		return bake
	return MapEditorGroundService.initialize(current_document)


func _reset_document_session_state() -> void:
	command_stack.clear()
	manual_collision_start = Vector2i(-1, -1)
	manual_polygon_points.clear()
	safe_polygon_points.clear()
	pending_fill_tiles.clear()
	asset_size_menu_asset_id = ""
	pending_asset_delete_id = ""
	instance_size_menu_instance_id = ""
	if preview != null:
		preview.reset_for_document_open()
	_reset_semantic_draft_fields()


func _reset_semantic_draft_fields() -> void:
	if semantic_content_id != null:
		semantic_content_id.text = ""
	if semantic_display_name != null:
		semantic_display_name.text = ""
	if semantic_target_map != null:
		semantic_target_map.text = ""
	if semantic_target_entrance != null:
		semantic_target_entrance.text = ""


func _migrate_loaded_blank_ground_policy() -> void:
	var template_kind := str(current_document.get("editor_meta", {}).get("template_kind", ""))
	if template_kind not in ["empty_map", "custom_empty_map"]:
		return
	var ground: Dictionary = current_document.get("ground", {})
	ground["blank_generated"] = false
	ground["blank_fill_asset_id"] = ""
	ground["blank_chunk_policy"] = "transparent_until_painted"
	current_document["ground"] = ground


func _ensure_map_portal_semantics() -> void:
	# Portal artwork is visual evidence only. Never infer an entrance or exit
	# from its image; only keep explicitly linked semantics synchronized.
	for entry: Dictionary in MapEditorGameplaySemanticService.all_entries(current_document):
		var visual_id := str(entry.get("linked_visual_instance_id", ""))
		if visual_id.is_empty():
			continue
		var located := MapEditorInstanceService._locate(current_document, visual_id)
		if not bool(located.get("ok", false)):
			continue
		PortalAnchorService.synchronize_linked_semantics(
			current_document,
			visual_id
		)


func _migrate_loaded_instances_to_class_profiles()->void:
	var legacy_ground_paints:Array[Dictionary]=[]
	var used_instance_ids := {}
	var next_instance_number := 1
	for layer_name:String in ["terrain_base","terrain_front","object_base","object_front"]:
		var entries:Array=current_document.layers.get(layer_name,[])
		var migrated_entries:Array=[]
		for index in entries.size():
			var instance:Dictionary=entries[index]
			if not instance.has("asset_id"):continue
			var iid := str(instance.get("instance_id", ""))
			if iid.is_empty() or used_instance_ids.has(iid):
				while used_instance_ids.has("inst_%06d" % next_instance_number): next_instance_number += 1
				iid = "inst_%06d" % next_instance_number
				instance["instance_id"] = iid
			used_instance_ids[iid] = true
			var asset:=MapAssetCatalogService.find_asset(str(instance.asset_id)); if asset.is_empty():continue
			if str(asset.get("asset_type","")) in ["ground_brush","procedural_ground"]:
				legacy_ground_paints.append({"op":"paint_tile","tile":instance.get("tile",[0,0]),"asset_id":str(instance.asset_id)})
				continue
			var design_raw: Array = current_document.design.get(
				"design_size",
				[0, 0]
			)
			InstanceProfileService.refresh_from_asset(
				instance,
				asset,
				Vector2i(int(design_raw[0]), int(design_raw[1]))
			)
			migrated_entries.append(instance)
		current_document.layers[layer_name]=migrated_entries
	if not legacy_ground_paints.is_empty():MapEditorGroundService.record_tile_paint_batch(current_document,legacy_ground_paints)


func _on_initialize_ground_pressed() -> void:
	var result := MapEditorGroundService.initialize(current_document)
	if result.ok:
		status_label.text = "地面就绪：%d 个虚拟 Chunk，dirty=0" % (result.manifest.chunks as Array).size()
	else:
		status_label.text = "地面初始化失败：%s" % result.get("errors", [])


func _on_demo_ground_edit_pressed() -> void:
	var raw_size: Array = current_document.design.design_size
	var tile := Vector2i(int(raw_size[0]) / 2, int(raw_size[1]) / 2)
	var result := MapEditorGroundService.record_tile_paint(current_document, tile, "ground.dark_grass.001")
	if result.ok:
		status_label.text = "中心格首次编辑已物化 %s；dirty=%d" % [result.chunk_id, result.dirty_count]
		preview.set_ground_state(result.state)
	else:
		status_label.text = "地面编辑失败：%s" % result.get("errors", [])


func _on_asset_tree_selected() -> void:
	var item := asset_tree.get_selected()
	if item != null:
		_activate_asset_tree_item(item)


func _on_asset_tree_multi_selected(item: TreeItem, _column: int, selected: bool) -> void:
	if selected:
		_activate_asset_tree_item(item)


func _on_asset_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_ensure_asset_tree_item_icon(asset_tree.get_item_at_position(event.position))
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_RIGHT or not event.pressed:
		return
	var item := asset_tree.get_item_at_position(event.position)
	if item == null:
		return
	var metadata: Variant = item.get_metadata(0)
	if not metadata is Dictionary or str(metadata.get("asset_id", "")).is_empty():
		return
	asset_size_menu_asset_id = str(metadata.get("asset_id", ""))
	item.select(0)
	_activate_asset_tree_item(item)
	asset_size_menu.position = Vector2i(event.global_position)
	asset_size_menu.popup()
	asset_tree.accept_event()


func _on_asset_size_menu_pressed(action_id: int) -> void:
	if action_id == 4:
		_request_asset_delete(asset_size_menu_asset_id)
		return
	var asset := MapAssetCatalogService.find_asset(asset_size_menu_asset_id)
	var base := MapAssetCatalogService.find_base_asset(asset_size_menu_asset_id)
	if asset.is_empty() or base.is_empty():
		return
	if str(asset.get("asset_type", "")) == "ground_brush":
		status_label.text = "地面素材固定为 1×1 格，不能缩放"
		return
	var draft := build_asset_resize_draft(asset, base, action_id)
	var new_fp: Array = draft.get("footprint_tiles", [1, 1])
	var result := MapAssetCalibrationService.save_override(asset_size_menu_asset_id, draft)
	if result.get("ok", false):
		MapAssetCatalogService.invalidate_cache()
		_refresh_asset_tree()
		selected_asset_id = asset_size_menu_asset_id
		preview.set_selected_brush(selected_asset_id)
		status_label.text = "素材占位已调整为 %d×%d 格" % [new_fp[0], new_fp[1]]
	else:
		status_label.text = "素材尺寸调整失败：%s" % result.get("errors", [])


func _request_asset_delete(asset_id: String) -> void:
	var asset := MapAssetCatalogService.find_asset(asset_id)
	if asset.is_empty():
		status_label.text = "删除素材失败：找不到素材 %s" % asset_id
		return
	pending_asset_delete_id = asset_id
	asset_delete_dialog.dialog_text = (
		"确定从素材列表删除“%s”吗？\n\n"
		+ "原图文件和地图中已放置的内容会保留，避免破坏已有地图。"
	) % str(asset.get("display_name", asset_id))
	asset_delete_dialog.popup_centered(Vector2i(460, 180))


func _on_asset_delete_confirmed() -> void:
	var asset_id := pending_asset_delete_id
	pending_asset_delete_id = ""
	if asset_id.is_empty():
		return
	var asset := MapAssetCatalogService.find_asset(asset_id)
	var display_name := str(asset.get("display_name", asset_id))
	var result := MapAssetCalibrationService.delete_from_palette(asset_id)
	if not result.get("ok", false):
		status_label.text = "删除素材失败：%s" % result.get("errors", [])
		return
	MapAssetCatalogService.invalidate_cache()
	selected_asset_id = ""
	preview.set_selected_brush("")
	_refresh_asset_tree()
	var first_asset := _first_asset_tree_item()
	if first_asset != null:
		first_asset.select(0)
		_activate_asset_tree_item(first_asset)
	status_label.text = "已从素材列表删除：%s（原图和地图实例已保留）" % display_name


func _on_asset_delete_cancelled() -> void:
	pending_asset_delete_id = ""


static func build_asset_resize_draft(asset: Dictionary, base: Dictionary, action_id: int) -> Dictionary:
	var base_fp: Array = base.get("base_footprint_tiles", base.get("footprint_tiles", [1, 1]))
	var current_fp: Array = asset.get("footprint_tiles", base_fp)
	var inferred_level := int(current_fp[0]) - int(base_fp[0])
	var level := int(asset.get("logical_scale_level", inferred_level))
	if action_id == 1: level += 1
	elif action_id == 2: level -= 1
	else: level = 0
	var new_fp := [maxi(1, int(base_fp[0]) + level), maxi(1, int(base_fp[1]) + level)]
	# Once both dimensions have reached one tile, further shrinking is a no-op.
	level = maxi(level, 1 - mini(int(base_fp[0]), int(base_fp[1])))
	new_fp = [maxi(1, int(base_fp[0]) + level), maxi(1, int(base_fp[1]) + level)]
	var current_scale := Vector2(float(asset.get("approved_scale", 1.0)), float(asset.get("approved_scale", 1.0)))
	var next_scale := Vector2(float(base.get("approved_scale", 1.0)), float(base.get("approved_scale", 1.0))) if action_id == 3 \
		else MapEditorInstanceService.resized_visual_scale(current_scale, current_fp, new_fp)
	var collision_probe := {
		"collision_policy": str(asset.get("collision_policy", "none")),
		"collision_footprint_tiles": asset.get("collision_footprint_tiles", [0, 0]).duplicate(),
	}
	if action_id == 3:
		collision_probe["collision_footprint_tiles"] = base.get("collision_footprint_tiles", [0, 0]).duplicate()
	else:
		MapEditorInstanceService._resize_instance_collision(collision_probe, current_fp, new_fp)
	var collision_fp: Array = collision_probe.get("collision_footprint_tiles", [0, 0])
	return {
		"footprint_tiles": new_fp, "visual_footprint_tiles": new_fp,
		"occupancy_footprint_tiles": new_fp, "collision_footprint_tiles": collision_fp,
		"approved_scale": next_scale.x, "logical_scale_level": level,
	}


func _activate_asset_tree_item(item: TreeItem) -> void:
	var metadata: Variant = item.get_metadata(0)
	if not metadata is Dictionary:
		return
	var asset_id := str(metadata.get("asset_id", ""))
	if asset_id.is_empty():
		return
	_ensure_asset_tree_item_icon(item)
	selected_asset_id = asset_id
	preview.set_selected_brush(asset_id)
	var asset := MapAssetCatalogService.find_asset(asset_id)
	var is_ground := str(asset.get("asset_type", "")) == "ground_brush"
	# A normal click selects one active brush and immediately restores ordinary
	# left-click placement. Ctrl/Command clicks only extend the lasso fill pool.
	if not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_META):
		_activate_normal_placement()
	if not is_ground:
		random_region_fill_toggle.button_pressed = false
		point_erase_toggle.button_pressed = false
	var target_layer := "ground_base" if is_ground else "terrain_base" if str(asset.get("asset_type", "")) == "terrain_stamp" else "object_base"
	preview.set_placement_layer(target_layer)
	brush_label.text = ("地面笔刷：" if is_ground else "对象放置：") + item.get_text(0)
	var default_role := str(asset.get("default_object_role", "decoration"))
	for role_index in object_role_option.item_count:
		if str(object_role_option.get_item_metadata(role_index)) == default_role: object_role_option.select(role_index)
	var anchor: Array = asset.get("anchor_px", [0, 0])
	var footprint: Array = asset.get("footprint_tiles", [1, 1])
	calibration_anchor_x.value = int(anchor[0]); calibration_anchor_y.value = int(anchor[1])
	calibration_footprint_x.value = int(footprint[0]); calibration_footprint_y.value = int(footprint[1])
	var policy := str(asset.get("collision_policy", "none"))
	for policy_index in calibration_collision.item_count:
		if str(calibration_collision.get_item_metadata(policy_index)) == policy: calibration_collision.select(policy_index)
	calibration_occlusion.button_pressed = bool(asset.get("occlusion", false))


func _on_ground_paint_requested(tile: Vector2i, asset_id: String) -> void:
	var selected_asset := MapAssetCatalogService.find_asset(asset_id)
	if str(selected_asset.get("asset_type", "")) != "ground_brush":
		var role := str(object_role_option.get_item_metadata(object_role_option.selected))
		var asset_type := str(selected_asset.get("asset_type", ""))
		var layer := (
			str(selected_asset.get("default_layer", "terrain_base"))
			if asset_type == "wall_module"
			else "terrain_base" if asset_type == "terrain_stamp" else "object_base"
		)
		var placed := MapEditorInstanceService.create_instance(current_document, asset_id, role, tile, layer)
		if placed.ok:
			var is_map_portal := str(selected_asset.get("object_class", "")) == "map_entrance"
			if is_map_portal:
				status_label.text = "墙门美术已放置；请再用“地图入口”或“地图出口”在门的位置手工标注"
			preview.set_document(current_document)
			if not is_map_portal: status_label.text = "放置 %s｜%s｜%s" % [placed.instance.instance_id, role, placed.instance.scene_intent]
		else:
			status_label.text = "放置拒绝：%s" % placed.get("errors", [])
		return
	var paint_result := {}
	var erase_result := {}
	var command := {
		"do": func(): paint_result = MapEditorGroundService.record_tile_paint(current_document, tile, asset_id),
		"undo": func(): erase_result = MapEditorGroundService.record_tile_erase(current_document, tile),
	}
	if command_stack.execute(command) and paint_result.get("ok", false):
		preview.set_ground_state(paint_result.state)
		status_label.text = "绘制 %s @ (%d,%d)，dirty=%d" % [asset_id, tile.x, tile.y, paint_result.dirty_count]
	else:
		status_label.text = "绘制失败：%s" % paint_result.get("errors", [])


func _on_lasso_context_requested(tiles: Array, screen_position: Vector2) -> void:
	pending_fill_tiles.clear()
	for tile: Vector2i in tiles:
		pending_fill_tiles.append(tile)
	region_fill_menu.position = Vector2i(screen_position)
	region_fill_menu.popup()


func _on_region_fill_menu_pressed(id: int) -> void:
	if id == 3:
		_delete_lasso_tiles(pending_fill_tiles)
		return
	if id != 1:
		return
	var selected_ground: Array = []
	var selected_item := asset_tree.get_next_selected(null)
	while selected_item != null:
		var selected_metadata: Variant = selected_item.get_metadata(0)
		var asset_id := str(selected_metadata.get("asset_id", "")) if selected_metadata is Dictionary else ""
		if str(MapAssetCatalogService.find_asset(asset_id).get("asset_type", "")) == "ground_brush":
			selected_ground.append(asset_id)
		selected_item = asset_tree.get_next_selected(selected_item)
	if selected_ground.is_empty():
		status_label.text = "请先在素材列表按 Ctrl 多选至少一种地面素材"
		return
	_fill_tiles_with_assets(pending_fill_tiles, selected_ground)


func _on_lasso_mode_toggled(enabled: bool) -> void:
	if enabled:
		_set_active_tool("lasso")
	elif active_tool_mode == "lasso":
		_set_active_tool("place")
	status_label.text = "左键自由套索，松开完成；选区内右键选择填充或删除" if enabled else "已退出套索模式"


func _activate_normal_placement() -> void:
	_set_active_tool("place")
	status_label.text = "普通铺设已启用：左键放置 %s" % (selected_asset_id if not selected_asset_id.is_empty() else "当前素材")


func _activate_select_tool()->void:
	_set_active_tool("select")
	status_label.text="选择工具：左键选取，方向键移动，Delete删除，Ctrl+C复制，Ctrl+V后随鼠标左键放置"


func _set_active_tool(mode: String) -> void:
	if mode not in ["place", "select", "lasso", "erase", "manual_collision", "manual_collision_erase", "manual_collision_erase_whole", "semantic"]:
		return
	if mode != "semantic" and not safe_polygon_points.is_empty():
		safe_polygon_points.clear()
		if preview != null:
			preview.set_semantic_polygon_draft(safe_polygon_points)
	active_tool_mode = mode
	if random_region_fill_toggle != null: random_region_fill_toggle.set_pressed_no_signal(mode == "lasso")
	if point_erase_toggle != null: point_erase_toggle.set_pressed_no_signal(mode == "erase")
	if collision_draw_toggle != null: collision_draw_toggle.set_pressed_no_signal(mode == "manual_collision")
	if collision_erase_toggle != null: collision_erase_toggle.set_pressed_no_signal(mode == "manual_collision_erase")
	if collision_erase_whole_toggle != null: collision_erase_whole_toggle.set_pressed_no_signal(mode == "manual_collision_erase_whole")
	if semantic_place_toggle != null: semantic_place_toggle.set_pressed_no_signal(mode == "semantic")
	if preview == null:
		return
	if mode == "place":
		preview.activate_normal_placement(selected_asset_id)
	else:
		preview.set_region_paint_mode(mode == "lasso")
		preview.set_interaction_mode({"select":"select", "lasso":"place", "erase":"erase", "manual_collision":"manual_collision", "manual_collision_erase":"manual_collision_erase", "manual_collision_erase_whole":"manual_collision_erase_whole", "semantic":"semantic"}.get(mode, "place"))
	preview.grab_focus()


func _activate_semantic_placement() -> void:
	_set_active_tool("semantic")
	var kind := str(semantic_kind_option.get_item_metadata(semantic_kind_option.selected)) if semantic_kind_option != null and semantic_kind_option.selected >= 0 else "semantic"
	var content_id := semantic_content_id.text.strip_edges() if semantic_content_id != null else ""
	var kind_name := str({
		"monster_spawn": "普通怪物刷新", "boss_spawn": "精英与Boss刷新", "special_monster": "特殊地图怪物",
		"map_entrance": "独立到达点", "map_exit": "地图传送点",
		"respawn_point": "出生／复活点", "safe_area": "多边形安全区",
	}.get(kind, kind))
	status_label.text = "功能标注已启用：%s%s" % [kind_name, " / " + content_id if not content_id.is_empty() else ""]


func _on_selectable_selected(selectable_id:String,_additive:bool)->void:
	if selectable_id.is_empty():
		status_label.text = "已清空选择"
		return
	var semantic := MapEditorGameplaySemanticService.find_entry(current_document, selectable_id)
	if not semantic.is_empty():
		_select_semantic_kind(str(semantic.get("kind", "")), false)
		_sync_semantic_editor_fields(semantic)
		semantic_display_name.text = str(semantic.get("display_name", ""))
		semantic_target_map.text = str(semantic.get("target_map_id", ""))
		semantic_target_entrance.text = str(semantic.get("target_entrance_id", ""))
		status_label.text = "已选中功能标注：%s；修改参数后点击“更新当前选中的功能标注”" % selectable_id
		return
	status_label.text="已选中：%s" % selectable_id


func _select_semantic_kind(kind: String, activate_placement := true) -> void:
	for index in semantic_kind_option.item_count:
		if str(semantic_kind_option.get_item_metadata(index)) == kind:
			semantic_kind_option.select(index)
			_on_semantic_kind_selected(index, activate_placement)
			return


func _sync_semantic_editor_fields(entry: Dictionary) -> void:
	var kind := str(entry.get("kind", ""))
	var content_id := str(entry.get("content_id", ""))
	if kind == "npc" and content_id.is_empty():
		content_id = str(entry.get("npc_id", ""))
	if kind in ["monster_spawn", "boss_spawn", "special_monster"] and content_id.is_empty():
		var numeric_id := int(entry.get("monster_id", -1))
		var catalog_entry := MapEditorContentCatalogService.find_by_monster_id(kind, numeric_id)
		if catalog_entry.is_empty() and kind != "special_monster":
			catalog_entry = MapEditorContentCatalogService.find_by_monster_id("special_monster", numeric_id)
		content_id = str(catalog_entry.get("content_id", ""))
	semantic_content_id.text = content_id
	var selectable_content_id := content_id
	if kind == "npc":
		var canonical_entry := MapEditorContentCatalogService.find("npc", content_id)
		if not canonical_entry.is_empty():
			selectable_content_id = str(canonical_entry.get("content_id", content_id))
	for index in semantic_content_option.item_count:
		var metadata: Variant = semantic_content_option.get_item_metadata(index)
		if metadata is Dictionary and str(metadata.get("content_id", "")) == selectable_content_id:
			semantic_content_option.select(index)
			break
	semantic_radius.value = int(entry.get("radius_tiles", semantic_radius.value))
	semantic_count.value = int(entry.get("count", semantic_count.value))
	semantic_respawn.value = int(entry.get("respawn_seconds", semantic_respawn.value))
	semantic_max_alive.value = int(entry.get("max_alive", semantic_max_alive.value))
	var facing := str(entry.get("facing", "south"))
	for index in semantic_facing.item_count:
		if str(semantic_facing.get_item_metadata(index)) == facing:
			semantic_facing.select(index)
			break


func _on_update_selected_semantic_pressed() -> void:
	var semantic_id := preview.selected_selectable_id if preview != null else ""
	if semantic_id.is_empty() or semantic_id.begins_with("inst_"):
		status_label.text = "请先使用选择工具选中一个地图功能标注"
		return
	var entry := MapEditorGameplaySemanticService.find_entry(current_document, semantic_id)
	if entry.is_empty():
		status_label.text = "未找到选中的地图功能标注"
		return
	var properties := {"display_name": semantic_display_name.text.strip_edges()}
	var kind := str(entry.get("kind", ""))
	if kind in ["map_exit", "door"]:
		properties["target_map_id"] = semantic_target_map.text.strip_edges()
	if kind == "map_exit":
		properties["target_entrance_id"] = semantic_target_entrance.text.strip_edges()
	var result := MapEditorGameplaySemanticService.update_entry(current_document, semantic_id, properties)
	if result.get("ok", false):
		preview.queue_redraw()
		status_label.text = "功能标注已更新；点击“保存地图”写入工作文件"
	else:
		status_label.text = "功能标注更新失败：%s" % result.get("errors", [])


func _on_selectable_context_requested(selectable_id:String,screen_position:Vector2)->void:
	if not selectable_id.begins_with("inst_"):return
	instance_size_menu_instance_id=selectable_id
	instance_size_menu.position=Vector2i(screen_position)
	instance_size_menu.popup()


func _on_instance_size_menu_pressed(action_id:int)->void:
	if action_id in [3, 4]:
		var layer_result := MapEditorInstanceService.adjust_material_layer_order(
			current_document,
			instance_size_menu_instance_id,
			1 if action_id == 3 else -1
		)
		if layer_result.get("ok", false):
			preview.set_document(current_document)
			_save_current_document()
			status_label.text = "素材覆盖层级已%s至 %d（不会影响人物或怪物）" % [
				"提高" if action_id == 3 else "下降",
				int(layer_result.get("material_layer_order", 0)),
			]
		else:
			status_label.text = "调整素材覆盖层级失败：%s" % layer_result.get("errors", [])
		return
	var result:=MapEditorInstanceService.resize_instance(current_document,instance_size_menu_instance_id,1 if action_id==1 else -1)
	if result.get("ok",false):
		preview.set_document(current_document)
		if preview.show_walkable_preview: preview.set_walkability_preview(MapEditorCollisionService.build_walkability(current_document),true)
		_save_current_document()
		status_label.text="当前地图素材已%s，中心点、占地和碰撞已同步"%("放大" if action_id==1 else "缩小")
	else:status_label.text="缩放失败：%s"%result.get("errors",[])


func _on_selectable_move_requested(selectable_id:String,delta:Vector2i)->void:
	var result_holder := {"value": {"ok": false, "errors": ["move_not_executed"]}}
	if selectable_id.begins_with("inst_"):
		var located:=MapEditorInstanceService._locate(current_document,selectable_id)
		if not located.ok:return
		var tile:Array=located.instance.tile
		var old_tile:=Vector2i(int(tile[0]),int(tile[1])); var new_tile:=old_tile+delta
		command_stack.execute({
			"do": func():
				result_holder["value"] = MapEditorInstanceService.move_instance(current_document, selectable_id, new_tile)
				if result_holder["value"].get("ok", false): PortalAnchorService.synchronize_linked_semantics(current_document, selectable_id),
			"undo": func():
				MapEditorInstanceService.move_instance(current_document, selectable_id, old_tile)
				PortalAnchorService.synchronize_linked_semantics(current_document, selectable_id),
		})
	else:
		command_stack.execute({
			"do": func(): result_holder["value"] = MapEditorGameplaySemanticService.move_entry(current_document, selectable_id, delta),
			"undo": func(): MapEditorGameplaySemanticService.move_entry(current_document, selectable_id, -delta),
		})
	var result: Dictionary = result_holder["value"]
	preview.set_document(current_document)
	status_label.text="移动成功" if result.get("ok", false) else "移动失败：%s"%result.get("errors",[])


func _on_selectable_delete_requested(selectable_id:String)->void:
	var result:=_delete_instance_with_linked_semantics(selectable_id) if selectable_id.begins_with("inst_") else MapEditorGameplaySemanticService.delete_entry(current_document,selectable_id)
	if result.ok:
		preview.selected_selectable_id=""
		preview.hovered_selectable_id=""
		preview.set_document(current_document)
	status_label.text="删除成功；点击“保存地图”写入工作文件" if result.ok else "删除失败：%s"%result.get("errors",[])


func _select_new_semantic_marker(semantic_id: String) -> void:
	if preview == null:
		return
	preview.selected_selectable_id = semantic_id
	preview.hovered_selectable_id = ""
	preview.queue_redraw()


func _copy_selected_element() -> void:
	if preview == null or preview.selected_selectable_id.is_empty():
		status_label.text = "请先选中一个素材、刷新点、NPC或地图功能标注"
		return
	var selectable_id := preview.selected_selectable_id
	if selectable_id.begins_with("inst_"):
		var located := MapEditorInstanceService._locate(current_document, selectable_id)
		if not located.ok:
			status_label.text = "复制失败：未找到选中的地图素材"
			return
		element_clipboard = {
			"element_type": "instance",
			"snapshot": located.instance.duplicate(true),
		}
	else:
		var semantic := MapEditorGameplaySemanticService.find_entry(
			current_document,
			selectable_id
		)
		if semantic.is_empty():
			status_label.text = "复制失败：未找到选中的地图标注"
			return
		element_clipboard = {
			"element_type": "semantic",
			"snapshot": semantic.duplicate(true),
		}
	status_label.text = "已复制当前元素；按 Ctrl+V 后移动鼠标并左键放置"


func _begin_clipboard_paste() -> void:
	if element_clipboard.is_empty():
		status_label.text = "剪贴板为空；请先选中元素并按 Ctrl+C"
		return
	preview.begin_clipboard_paste(element_clipboard)
	preview.grab_focus()
	status_label.text = "粘贴预览已固定到鼠标：左键放置，右键取消"


func _on_clipboard_paste_requested(tile: Vector2i) -> void:
	var element_type := str(element_clipboard.get("element_type", ""))
	var snapshot: Dictionary = element_clipboard.get("snapshot", {})
	var result: Dictionary
	if element_type == "instance":
		result = MapEditorInstanceService.duplicate_instance_snapshot(
			current_document,
			snapshot,
			tile
		)
	elif element_type == "semantic":
		result = MapEditorGameplaySemanticService.duplicate_entry_snapshot(
			current_document,
			snapshot,
			tile
		)
	else:
		result = {"ok": false, "errors": ["invalid_clipboard_element"]}
	if not result.get("ok", false):
		status_label.text = "粘贴位置无效：%s；移动鼠标后重新左键放置" % result.get("errors", [])
		return
	preview.end_clipboard_paste()
	var pasted_id := ""
	if element_type == "instance":
		pasted_id = str(result.instance.instance_id)
	else:
		pasted_id = str(result.entry.semantic_id)
		if str(result.entry.get("kind", "")) == "npc":
			MapEditorNpcPlaceholderService.ensure_entry(current_document, pasted_id)
	preview.selected_selectable_id = pasted_id
	preview.hovered_selectable_id = ""
	preview.set_document(current_document)
	preview.grab_focus()
	status_label.text = "副本已放置并选中；点击“保存地图”写入工作文件"


func _on_clipboard_paste_cancelled() -> void:
	status_label.text = "已取消本次粘贴；原复制内容仍可再次按 Ctrl+V 使用"


func _on_point_erase_toggled(enabled: bool) -> void:
	if enabled:
		_set_active_tool("erase")
	elif active_tool_mode == "erase":
		_set_active_tool("place")
	status_label.text = "左键点选或拖动擦除地面与对象" if enabled else "已退出擦除模式"


func _on_erase_tile_requested(tile: Vector2i) -> void:
	var ground_result := MapEditorGroundService.record_tile_erase(current_document, tile)
	var instances := _instance_ids_touching_tiles([tile])
	for instance_id: String in instances: _delete_instance_with_linked_semantics(instance_id)
	if ground_result.ok: preview.set_ground_state(ground_result.state)
	preview.set_document(current_document)
	status_label.text = "已擦除 Tile(%d,%d)，对象 %d 个" % [tile.x, tile.y, instances.size()]


func _delete_lasso_tiles(tiles: Array[Vector2i]) -> void:
	if tiles.is_empty(): return
	var ground_result := MapEditorGroundService.record_tile_erase_batch(current_document, tiles)
	var instances := _instance_ids_touching_tiles(tiles)
	for instance_id: String in instances: _delete_instance_with_linked_semantics(instance_id)
	if ground_result.ok: preview.set_ground_state(ground_result.state)
	preview.set_document(current_document)
	status_label.text = "套索删除完成：地面 %d 格，对象 %d 个" % [tiles.size(), instances.size()]


func _instance_ids_touching_tiles(tiles: Array[Vector2i]) -> Array[String]:
	var keys := {}
	for tile: Vector2i in tiles: keys["%d,%d" % [tile.x, tile.y]] = true
	var ids: Array[String] = []
	for instance: Dictionary in MapEditorInstanceService.all_instances(current_document):
		var origin: Array = instance.get("tile", [0, 0]); var footprint: Array = instance.get("footprint_tiles", [1, 1]); var touched := false
		for y in range(int(origin[1]), int(origin[1]) + int(footprint[1])):
			for x in range(int(origin[0]), int(origin[0]) + int(footprint[0])):
				if keys.has("%d,%d" % [x, y]): touched = true; break
			if touched: break
		if touched: ids.append(str(instance.instance_id))
	return ids


func _delete_instance_with_linked_semantics(instance_id: String) -> Dictionary:
	var result := MapEditorInstanceService.delete_instance(current_document, instance_id)
	if result.get("ok", false):
		MapEditorGameplaySemanticService.delete_linked_instance_entries(current_document, instance_id)
	return result


func _on_ground_region_paint_requested(region: Rect2i, asset_id: String) -> void:
	var selected := MapAssetCatalogService.find_asset(asset_id)
	if str(selected.get("asset_type", "")) != "ground_brush":
		status_label.text = "框选随机填充只适用于地面素材"
		return
	if region.size.x * region.size.y > 1024:
		status_label.text = "单次框选最多 1024 格，请缩小范围"
		return
	var candidates: Array = []
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if str(asset.get("asset_type", "")) == "ground_brush" and str(asset.get("terrain_type", "")) == str(selected.get("terrain_type", "")) and str(asset.get("ground_brush_role", "")) == str(selected.get("ground_brush_role", "")):
			candidates.append(str(asset.asset_id))
	_fill_region_with_assets(region, candidates)


func _fill_region_with_assets(region: Rect2i, candidates: Array) -> void:
	var tiles: Array[Vector2i] = []
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			tiles.append(Vector2i(x, y))
	_fill_tiles_with_assets(tiles, candidates)


func _fill_tiles_with_assets(tiles: Array[Vector2i], candidates: Array) -> void:
	if tiles.is_empty() or candidates.is_empty():
		status_label.text = "套索选区或填充素材为空"
		return
	if tiles.size() > 4096:
		status_label.text = "单次套索最多填充 4096 格，当前 %d 格" % tiles.size()
		return
	var paints: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for tile: Vector2i in tiles:
		paints.append({"tile": [tile.x, tile.y], "asset_id": candidates[rng.randi_range(0, candidates.size() - 1)]})
	var result := MapEditorGroundService.record_tile_paint_batch(current_document, paints)
	if result.get("ok", false):
		preview.set_ground_state(result.state)
		status_label.text = "套索随机填充完成：%d 格，使用 %d 种素材" % [tiles.size(), candidates.size()]
	else:
		status_label.text = "随机填充失败：%s" % result.get("errors", [])


func _on_tile_hovered(tile: Vector2i) -> void:
	if not status_label.text.begins_with("绘制"):
		status_label.text = "Tile (%d, %d)｜左键绘制，拖动连续绘制" % [tile.x, tile.y]


func _on_approve_and_build_runtime_pressed() -> void:
	var approval := MapEditorBuildRuntimeService.approve_for_runtime(current_document)
	if not approval.ok:
		status_label.text = "Runtime 审核未通过：%s" % approval.get("errors", [])
		return
	var build := MapEditorBuildRuntimeService.build(current_document)
	status_label.text = "Runtime 快照已构建：%s" % build.get("path", "") if build.ok else "Runtime 构建失败：%s" % build.get("errors", [])


func _on_bake_dirty_pressed() -> void:
	var result := MapEditorChunkBakeService.bake_dirty_chunks(current_document)
	if result.ok:
		var initialized := MapEditorGroundService.initialize(current_document)
		if initialized.ok:
			preview.reload_ground_state(initialized.state)
		status_label.text = "已烘焙 %d 个Chunk预览，运行时目录未写入" % (result.get("baked_chunks", []) as Array).size()
	else:
		status_label.text = "烘焙失败：%s" % result.get("errors", [])


func _on_walkable_preview_toggled(enabled: bool) -> void:
	preview.set_walkability_preview(MapEditorCollisionService.build_walkability(current_document), enabled)
	status_label.text = "不可走区域预览已开启" if enabled else "不可走区域预览已关闭"


func _on_semantic_place_toggled(enabled: bool) -> void:
	if enabled:
		_activate_semantic_placement()
	elif active_tool_mode == "semantic":
		_set_active_tool("place")
	status_label.text = "Click canvas to place gameplay semantics; doors require a target map ID." if enabled else "Returned to asset placement."


func _on_semantic_kind_selected(index: int, activate_placement := true) -> void:
	var kind := str(semantic_kind_option.get_item_metadata(index))
	# Draft fields belong to the selected semantic kind, not to the previous
	# map or marker. In particular, a selected monster's hidden display name
	# must never leak into a subsequently placed entrance or exit.
	_reset_semantic_draft_fields()
	if kind != "safe_area" and not safe_polygon_points.is_empty():
		safe_polygon_points.clear()
		if preview != null:
			preview.set_semantic_polygon_draft(safe_polygon_points)
	semantic_content_option.clear()
	var catalog_kind := "special_monster" if kind == "special_monster" else kind
	for entry: Dictionary in MapEditorContentCatalogService.entries(catalog_kind, 4):
		var detail := ""
		if kind in ["monster_spawn", "boss_spawn", "special_monster"]:
			if bool(entry.get("attributes_verified", false)):
				detail = "  等级%s  生命%s  攻击%s-%s  防御%s-%s  魔防%s-%s  经验%s" % [entry.get("level", ""), entry.get("hp", ""), entry.get("attack_min", ""), entry.get("attack_max", ""), entry.get("defense_min", ""), entry.get("defense_max", ""), entry.get("magic_defense_min", ""), entry.get("magic_defense_max", ""), entry.get("experience", "")]
			else:
				detail = "  属性未验证（禁止新放置）"
			detail += "  %s  %s  默认%d秒" % [str(entry.get("classification", "")), str(entry.get("drop_summary", "")), int(entry.get("default_respawn_seconds", 60))]
		elif kind == "npc":
			detail = "  [%s]" % _service_role_chinese(str(entry.get("service_role", "dialogue")))
		semantic_content_option.add_item(str(entry.get("display_name", entry.get("content_id", ""))) + detail)
		semantic_content_option.set_item_metadata(semantic_content_option.item_count - 1, entry)
	semantic_content_option.visible = kind in ["npc", "monster_spawn", "boss_spawn", "special_monster"]
	semantic_content_id.visible = semantic_content_option.visible
	semantic_display_name.visible = kind in ["map_entrance", "map_exit", "respawn_point", "safe_area", "light", "region_trigger"]
	semantic_target_map.visible = kind == "map_exit"
	semantic_target_entrance.visible = kind == "map_exit"
	var is_spawn := kind in ["monster_spawn", "boss_spawn", "special_monster"]
	semantic_count.visible = is_spawn; semantic_respawn.visible = is_spawn; semantic_max_alive.visible = is_spawn
	semantic_facing.visible = kind == "npc"
	semantic_radius.visible = kind in ["monster_spawn", "boss_spawn", "special_monster", "light", "region_trigger"]
	if kind == "boss_spawn": semantic_radius.value = 0
	elif kind == "monster_spawn" and semantic_radius.value <= 0: semantic_radius.value = 3
	if kind in ["monster_spawn", "boss_spawn", "special_monster"]:
		semantic_respawn.value = 60 if kind == "monster_spawn" else 1800
	if semantic_content_option.item_count > 0:
		semantic_content_option.select(0)
		var first_entry: Variant = semantic_content_option.get_item_metadata(0)
		if first_entry is Dictionary:
			semantic_content_id.text = str(first_entry.get("content_id", ""))
			_apply_semantic_combat_entry_defaults(kind, first_entry)
			_refresh_semantic_detail(first_entry)
	if preview != null and activate_placement:
		_activate_semantic_placement()


func _refresh_semantic_catalog_tree() -> void:
	semantic_catalog_tree.clear()
	var root := semantic_catalog_tree.create_item()
	for group: Array in [["NPC目录", "npc"], ["怪物目录", "monster_spawn"], ["精英与Boss目录", "boss_spawn"], ["特殊地图怪物", "special_monster"]]:
		var folder := semantic_catalog_tree.create_item(root); folder.set_text(0, group[0]); folder.set_selectable(0, false); folder.collapsed = true
		for entry: Dictionary in MapEditorContentCatalogService.entries(group[1], 4):
			var item := semantic_catalog_tree.create_item(folder)
			item.set_text(0, _semantic_catalog_tree_label(group[1], entry))
			item.set_metadata(0, {"kind": group[1], "entry": entry})


func _semantic_catalog_tree_label(kind: String, entry: Dictionary) -> String:
	var label := str(entry.get("display_name", entry.get("content_id", "")))
	if kind not in ["monster_spawn", "boss_spawn", "special_monster"]:
		return label
	if bool(entry.get("attributes_verified", false)):
		label += "｜Lv%s HP%s 攻%s-%s 防%s-%s 魔防%s-%s 经验%s" % [
			entry.get("level", ""), entry.get("hp", ""), entry.get("attack_min", ""), entry.get("attack_max", ""),
			entry.get("defense_min", ""), entry.get("defense_max", ""), entry.get("magic_defense_min", ""),
			entry.get("magic_defense_max", ""), entry.get("experience", ""),
		]
	else:
		label += "｜属性未验证（禁止新放置）"
	label += "｜%s｜%s｜默认%s秒" % [
		str(entry.get("classification", "")), str(entry.get("drop_summary", "")), str(entry.get("default_respawn_seconds", 60)),
	]
	if kind == "special_monster":
		label += "｜实际%s" % ("Boss刷新" if str(entry.get("placement_kind", "")) == "boss_spawn" else "普通刷新")
	return label


func _on_semantic_catalog_selected() -> void:
	var item := semantic_catalog_tree.get_selected(); if item == null:return
	_activate_semantic_catalog_item(item)


func _on_semantic_catalog_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var item := semantic_catalog_tree.get_item_at_position(event.position)
	if item == null or not item.get_metadata(0) is Dictionary:
		return
	item.select(0)
	_activate_semantic_catalog_item(item)


func _activate_semantic_catalog_item(item: TreeItem) -> void:
	var metadata:Variant=item.get_metadata(0); if not metadata is Dictionary:return
	var kind:=str(metadata.get("kind","")); var entry:Dictionary=metadata.get("entry",{})
	for index in semantic_kind_option.item_count:
		if str(semantic_kind_option.get_item_metadata(index))==kind: semantic_kind_option.select(index); _on_semantic_kind_selected(index); break
	semantic_content_id.text=str(entry.get("content_id",""))
	_apply_semantic_combat_entry_defaults(kind, entry)
	_refresh_semantic_detail(entry)
	_activate_semantic_placement()
	var catalog_name := "NPC" if kind == "npc" else "特殊地图怪物" if kind == "special_monster" else "怪物/Boss"
	status_label.text="已选择%s：%s；请在地图左键放置"%[catalog_name,str(entry.get("display_name",""))]


func _on_semantic_content_selected(index: int) -> void:
	var entry: Variant = semantic_content_option.get_item_metadata(index)
	if entry is Dictionary:
		semantic_content_id.text = str(entry.get("content_id", ""))
		var kind := str(semantic_kind_option.get_item_metadata(semantic_kind_option.selected))
		_apply_semantic_combat_entry_defaults(kind, entry)
		_refresh_semantic_detail(entry)
		if preview != null:
			_activate_semantic_placement()


func _apply_semantic_combat_entry_defaults(kind: String, entry: Variant) -> void:
	if kind not in ["monster_spawn", "boss_spawn", "special_monster"] or not entry is Dictionary:
		return
	semantic_respawn.value = int(entry.get(
		"default_respawn_seconds",
		60 if kind == "monster_spawn" else 1800
	))
	var placement_kind := str(entry.get("placement_kind", kind))
	if placement_kind == "boss_spawn":
		semantic_radius.value = 0
	elif placement_kind == "monster_spawn" and semantic_radius.value <= 0:
		semantic_radius.value = 3


func _refresh_semantic_detail(entry: Variant) -> void:
	if semantic_detail_label == null:
		return
	if not entry is Dictionary:
		semantic_detail_label.text = ""
		return
	var lines: Array[String] = []
	lines.append("名称：%s（ID %d）" % [str(entry.get("display_name", "")), int(entry.get("monster_id", -1))])
	lines.append("分类：%s   实际语义：%s" % [
		str(entry.get("classification", "")),
		"Boss刷新" if str(entry.get("placement_kind", "")) == "boss_spawn" else "普通刷新",
	])
	lines.append("允许放置：%s" % ("是" if bool(entry.get("placement_allowed", false)) else "否"))
	var rejection := str(entry.get("placement_rejection_reason", ""))
	if not rejection.is_empty():
		lines.append("禁止原因：%s" % rejection)
	if bool(entry.get("attributes_verified", false)):
		lines.append("等级 %s  生命 %s  攻击 %s-%s  防御 %s-%s  魔防 %s-%s  经验 %s" % [
			entry.get("level", ""), entry.get("hp", ""),
			entry.get("attack_min", ""), entry.get("attack_max", ""),
			entry.get("defense_min", ""), entry.get("defense_max", ""),
			entry.get("magic_defense_min", ""), entry.get("magic_defense_max", ""),
			entry.get("experience", ""),
		])
		lines.append("AI：%s" % str(entry.get("ai_code", "")))
	else:
		lines.append("属性未验证（禁止新放置）")
	lines.append("贴图状态：%s" % str(entry.get("appearance_status", "")))
	lines.append("掉落：%s   来源：%s   证据：%s" % [
		str(entry.get("drop_summary", "")),
		str(entry.get("drop_source", "")),
		str(entry.get("evidence_status", "")),
	])
	var drop_entries: Array = entry.get("drop_entries", [])
	if not drop_entries.is_empty():
		lines.append("── 完整掉落（%d 项）──" % drop_entries.size())
		for row: Variant in drop_entries:
			if not row is Dictionary:
				continue
			var raw := str(row.get("raw_text", "")).strip_edges()
			if raw.is_empty():
				raw = "%s %s" % [str(row.get("chance", "")), str(row.get("item", ""))]
				if row.has("gold"):
					raw += " %d" % int(row.get("gold", 0))
			var resolution := str(row.get("item_resolution_status", ""))
			if not resolution.is_empty() and resolution != "resolved":
				raw += "  [%s]" % resolution
			lines.append(raw)
	else:
		lines.append("完整掉落：无")
	semantic_detail_label.text = "\n".join(lines)


func _service_role_chinese(role: String) -> String:
	return {"dialogue":"对话","shop":"商店","trainer":"训练师","quest":"任务","warehouse":"仓库","repair":"修理","teleport":"传送"}.get(role, "其他功能")


func _on_semantic_tile_clicked(tile: Vector2i) -> void:
	var kind := str(semantic_kind_option.get_item_metadata(semantic_kind_option.selected))
	if kind == "safe_area":
		safe_polygon_points.append(tile)
		preview.set_semantic_polygon_draft(safe_polygon_points)
		status_label.text = "安全区已记录第 %d 点：(%d,%d)；继续左键加点，Enter 闭合，右键取消" % [safe_polygon_points.size(), tile.x, tile.y]
		return
	var actual_kind := kind
	var combat_entry: Dictionary = {}
	var content_id := semantic_content_id.text.strip_edges()
	if kind in ["monster_spawn", "boss_spawn", "special_monster"]:
		combat_entry = MapEditorContentCatalogService.find(kind, content_id)
		if combat_entry.is_empty():
			status_label.text = "放置拒绝：目录中未找到内容 %s" % content_id
			return
		if not bool(combat_entry.get("placement_allowed", false)):
			status_label.text = "放置拒绝：该条目的属性尚未通过主源核验，不能新建刷新点"
			return
		if kind == "special_monster":
			actual_kind = str(combat_entry.get("placement_kind", ""))
			if actual_kind not in ["monster_spawn", "boss_spawn"]:
				status_label.text = "放置拒绝：特殊条目没有有效的运行时刷新类型"
				return
	var properties := {}
	if actual_kind in ["monster_spawn", "boss_spawn", "light", "region_trigger"]:
		properties["radius_tiles"] = int(semantic_radius.value)
	var marker_name := semantic_display_name.text.strip_edges()
	if not marker_name.is_empty():
		properties["display_name"] = marker_name
	if kind == "npc":
		properties["npc_id"] = content_id
		properties["content_id"] = content_id
		properties["facing"] = str(semantic_facing.get_item_metadata(semantic_facing.selected))
		var npc_entry := MapEditorContentCatalogService.find(kind, content_id)
		properties["display_name"] = str(npc_entry.get("display_name", content_id))
		properties["service_role"] = str(npc_entry.get("service_role", "dialogue"))
		properties["service_identity_id"] = str(npc_entry.get("service_identity_id", ""))
	elif actual_kind in ["monster_spawn", "boss_spawn"]:
		properties["monster_id"] = int(combat_entry.get("monster_id", -1))
	elif kind == "door":
		properties["target_map_id"] = semantic_target_map.text.strip_edges()
	elif kind == "map_exit":
		properties["target_map_id"] = semantic_target_map.text.strip_edges()
		properties["target_entrance_id"] = semantic_target_entrance.text.strip_edges()
	if actual_kind in ["monster_spawn", "boss_spawn"]:
		properties["display_name"] = str(combat_entry.get("display_name", content_id))
		properties["count"] = int(semantic_count.value)
		properties["respawn_seconds"] = int(semantic_respawn.value)
		properties["max_alive"] = int(semantic_max_alive.value)
	var result := MapEditorGameplaySemanticService.add_entry(current_document, actual_kind, tile, properties)
	if result.ok:
		if actual_kind=="npc": MapEditorNpcPlaceholderService.ensure_entry(current_document,str(result.entry.semantic_id))
		_select_new_semantic_marker(str(result.entry.semantic_id))
		preview.queue_redraw()
		if kind == "map_exit" and str(result.entry.get("target_map_id", "")).is_empty():
			status_label.text = "地图出口已标注：%s；目标地图可以稍后填写，保存地图即可保留" % result.entry.semantic_id
		elif kind == "respawn_point":
			status_label.text = "出生／复活点已标注并设为本图默认：%s；点击“保存地图”" % result.entry.semantic_id
		else:
			status_label.text = "放置成功：%s；点击“保存地图”" % result.entry.semantic_id
	else:
		status_label.text = "功能点放置失败：%s" % result.get("errors", [])


func _on_semantic_cancelled() -> void:
	if not safe_polygon_points.is_empty():
		safe_polygon_points.clear()
		preview.set_semantic_polygon_draft(safe_polygon_points)
		status_label.text = "已取消本次安全区多边形；标注工具仍然开启，再次右键可退出"
		return
	_set_active_tool("place")
	status_label.text = "已退出地图功能标注，并返回素材放置"


func _commit_safe_area_polygon() -> void:
	if safe_polygon_points.size() < 3:
		status_label.text = "安全区多边形至少需要 3 个点"
		return
	var points: Array = []
	for point: Vector2i in safe_polygon_points:
		points.append([point.x, point.y])
	var center := _polygon_tile_center(safe_polygon_points)
	var properties := {
		"shape": "polygon",
		"polygon_tiles": points,
		"radius_tiles": 0,
		"display_name": semantic_display_name.text.strip_edges() if not semantic_display_name.text.strip_edges().is_empty() else "安全区",
	}
	var result := MapEditorGameplaySemanticService.add_entry(current_document, "safe_area", center, properties)
	if result.get("ok", false):
		safe_polygon_points.clear()
		preview.set_semantic_polygon_draft(safe_polygon_points)
		_select_new_semantic_marker(str(result.entry.semantic_id))
		preview.queue_redraw()
		status_label.text = "多边形安全区已完成：%s；点击“保存地图”写入工作文件" % result.entry.semantic_id
	else:
		status_label.text = "安全区创建失败：%s" % result.get("errors", [])


static func _polygon_tile_center(points: Array[Vector2i]) -> Vector2i:
	var total := Vector2.ZERO
	for point: Vector2i in points:
		total += Vector2(point)
	return Vector2i(roundi(total.x / float(points.size())), roundi(total.y / float(points.size())))


func _on_collision_draw_toggled(enabled: bool) -> void:
	manual_collision_start = Vector2i(-1, -1)
	manual_polygon_points.clear()
	_sync_manual_collision_draft()
	if enabled:
		_set_active_tool("manual_collision")
	elif active_tool_mode == "manual_collision":
		_set_active_tool("place")
	var shape := _selected_collision_shape()
	collision_instruction_label.text = _collision_shape_help(shape) if enabled else "选择形状后将自动进入碰撞绘制"
	status_label.text = collision_instruction_label.text if enabled else "已返回素材放置"


func _on_collision_erase_toggled(enabled: bool) -> void:
	manual_collision_start = Vector2i(-1, -1)
	manual_polygon_points.clear()
	_sync_manual_collision_draft()
	if enabled:
		_set_active_tool("manual_collision_erase")
		preview.set_walkability_preview(MapEditorCollisionService.build_walkability(current_document), true)
		collision_instruction_label.text = "单格擦除：左键点击或拖动；每次只把鼠标所在的一格改为可走"
		status_label.text = "已开启单格碰撞擦除；右键退出"
	elif active_tool_mode == "manual_collision_erase":
		_set_active_tool("place")
		collision_instruction_label.text = "选择形状后将自动进入碰撞绘制"
		status_label.text = "已退出单格碰撞擦除，并返回素材放置"


func _on_collision_erase_whole_toggled(enabled: bool) -> void:
	manual_collision_start = Vector2i(-1, -1)
	manual_polygon_points.clear()
	_sync_manual_collision_draft()
	if enabled:
		_set_active_tool("manual_collision_erase_whole")
		preview.set_walkability_preview(MapEditorCollisionService.build_walkability(current_document), true)
		collision_instruction_label.text = "整块擦除：删除命中的完整手工形状，并禁用命中素材的当前地图碰撞"
		status_label.text = "已开启整块碰撞擦除；右键退出"
	elif active_tool_mode == "manual_collision_erase_whole":
		_set_active_tool("place")
		collision_instruction_label.text = "选择形状后将自动进入碰撞绘制"
		status_label.text = "已退出整块碰撞擦除，并返回素材放置"


func _on_collision_shape_selected(_index: int) -> void:
	manual_collision_start = Vector2i(-1, -1)
	manual_polygon_points.clear()
	_set_active_tool("manual_collision")
	var shape := _selected_collision_shape()
	collision_instruction_label.text = _collision_shape_help(shape)
	status_label.text = "已选择%s；%s" % [collision_shape_option.get_item_text(collision_shape_option.selected), collision_instruction_label.text]
	_sync_manual_collision_draft()


func _selected_collision_shape() -> String:
	if collision_shape_option == null or collision_shape_option.selected < 0:
		return "rect"
	return str(collision_shape_option.get_item_metadata(collision_shape_option.selected))


func _collision_shape_help(shape: String) -> String:
	if shape == "cell":
		return "单格：左键点击或拖动，每次只增加一格碰撞；右键退出"
	if shape == "polygon":
		return "多边形：左键逐点，Enter完成；右键取消本次绘制"
	return "%s：左键点起点和终点；右键取消本次绘制" % ("椭圆" if shape == "ellipse" else "矩形")


func _sync_manual_collision_draft() -> void:
	if preview != null:
		preview.set_manual_collision_draft(_selected_collision_shape(), manual_collision_start, manual_polygon_points)


func _on_manual_collision_tile_clicked(tile: Vector2i) -> void:
	var shape := _selected_collision_shape()
	if shape == "cell":
		var cell_result := MapEditorCollisionService.paint_collision_cell(current_document, tile)
		if cell_result.ok:
			preview.set_walkability_preview(MapEditorCollisionService.build_walkability(current_document), true)
			status_label.text = "已绘制单格碰撞：(%d,%d)；点击“保存地图”写入工作文件" % [tile.x, tile.y]
		else:
			status_label.text = "单格碰撞绘制失败：%s" % cell_result.get("errors", [])
		return
	if shape == "polygon":
		manual_polygon_points.append(tile)
		_sync_manual_collision_draft()
		status_label.text = "多边形已记录第 %d 点：(%d,%d)，继续左键加点，Enter完成，右键取消" % [manual_polygon_points.size(), tile.x, tile.y]
		return
	if manual_collision_start.x < 0:
		manual_collision_start = tile
		_sync_manual_collision_draft()
		status_label.text = "%s起点：(%d,%d)，请左键点击终点，右键取消" % ["椭圆" if shape == "ellipse" else "矩形", tile.x, tile.y]
		return
	var start := manual_collision_start
	manual_collision_start = Vector2i(-1, -1)
	var rect := [mini(start.x, tile.x), mini(start.y, tile.y), absi(tile.x - start.x) + 1, absi(tile.y - start.y) + 1]
	_sync_manual_collision_draft()
	_commit_manual_collision(shape, {"rect": rect})


func _on_manual_collision_cancelled() -> void:
	if active_tool_mode in ["manual_collision_erase", "manual_collision_erase_whole"]:
		_set_active_tool("place")
		collision_instruction_label.text = "选择形状后将自动进入碰撞绘制"
		status_label.text = "已退出碰撞擦除，并返回素材放置"
		return
	var had_unfinished_shape := manual_collision_start.x >= 0 or not manual_polygon_points.is_empty()
	manual_collision_start = Vector2i(-1, -1)
	manual_polygon_points.clear()
	_sync_manual_collision_draft()
	if had_unfinished_shape:
		status_label.text = "已取消本次碰撞形状；碰撞绘制仍然开启，再次右键可退出"
		collision_instruction_label.text = _collision_shape_help(_selected_collision_shape())
	else:
		_set_active_tool("place")
		collision_instruction_label.text = "选择形状后将自动进入碰撞绘制"
		status_label.text = "已退出手工碰撞绘制，并返回素材放置"


func _on_manual_collision_erase_requested(tile: Vector2i) -> void:
	var whole_shape := active_tool_mode == "manual_collision_erase_whole"
	var result := MapEditorCollisionService.erase_collision_at_tile(current_document, tile) if whole_shape else MapEditorCollisionService.erase_collision_cell(current_document, tile)
	if result.ok:
		preview.set_walkability_preview(MapEditorCollisionService.build_walkability(current_document), true)
		preview.queue_redraw()
		if whole_shape:
			status_label.text = "已整块擦除：手工形状 %d 个，素材实例 %d 个；点击“保存地图”" % [int(result.manual_count), int(result.instance_count)]
		else:
			status_label.text = "已单格擦除碰撞：(%d,%d)；点击“保存地图”写入工作文件" % [tile.x, tile.y]
	else:
		status_label.text = "该格没有可擦除的碰撞"


func _commit_manual_collision(shape: String, data: Dictionary) -> void:
	var result := MapEditorCollisionService.add_manual_shape(current_document, shape, data)
	if result.ok:
		preview.set_walkability_preview(MapEditorCollisionService.build_walkability(current_document), true)
		_sync_manual_collision_draft()
		status_label.text = "已添加%s碰撞：%s；可以继续绘制，右键退出" % [shape, result.collision.collision_id]
	else:
		status_label.text = "碰撞添加失败：%s" % result.get("errors", [])


func _on_save_calibration_pressed() -> void:
	if selected_asset_id.is_empty():
		status_label.text = "请先选择素材"
		return
	var draft := {
		"anchor_px": [int(calibration_anchor_x.value), int(calibration_anchor_y.value)],
		"footprint_tiles": [int(calibration_footprint_x.value), int(calibration_footprint_y.value)],
		"collision_policy": str(calibration_collision.get_item_metadata(calibration_collision.selected)),
		"occlusion": calibration_occlusion.button_pressed,
		"calibration_status": "placeable", "placeable": true,
	}
	var result := MapAssetCalibrationService.save_override(selected_asset_id, draft)
	status_label.text = "校准覆盖已保存：%s" % selected_asset_id if result.ok else "校准未保存：%s" % result.get("errors", [])


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var shortcut_pressed: bool = event.ctrl_pressed or event.meta_pressed
	if shortcut_pressed and event.keycode == KEY_C:
		_copy_selected_element()
		get_viewport().set_input_as_handled()
		return
	if shortcut_pressed and event.keycode == KEY_V:
		_begin_clipboard_paste()
		get_viewport().set_input_as_handled()
		return
	# Keep deletion available when focus has moved from the canvas to another
	# non-editing control. LineEdit consumes its own Delete/Backspace first, so
	# editing marker names cannot accidentally delete the selected marker.
	if event.keycode in [KEY_DELETE, KEY_BACKSPACE] and preview != null:
		var selected_id := preview.selected_selectable_id
		if not selected_id.is_empty():
			_on_selectable_delete_requested(selected_id)
			get_viewport().set_input_as_handled()
			return
	if shortcut_pressed and event.keycode==KEY_Z:
		if command_stack.undo():preview.set_document(current_document);status_label.text="已撤销"
		return
	if shortcut_pressed and event.keycode==KEY_Y:
		if command_stack.redo():preview.set_document(current_document);status_label.text="已重做"
		return
	if event.keycode == KEY_ENTER and active_tool_mode == "semantic" \
			and str(semantic_kind_option.get_item_metadata(semantic_kind_option.selected)) == "safe_area":
		_commit_safe_area_polygon()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ENTER and collision_draw_toggle.button_pressed and str(collision_shape_option.get_item_metadata(collision_shape_option.selected)) == "polygon":
		if manual_polygon_points.size() >= 3:
			var points: Array = []
			for point: Vector2i in manual_polygon_points: points.append([point.x, point.y])
			_commit_manual_collision("polygon", {"points": points})
			manual_polygon_points.clear()
			_sync_manual_collision_draft()
		else: status_label.text = "多边形至少需要3个点"
		get_viewport().set_input_as_handled()
		return
	if not shortcut_pressed:
		return
	if event.keycode == KEY_Z and command_stack.undo():
		_refresh_ground_preview()
		status_label.text = "已撤销最近一次地面操作"
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Y and command_stack.redo():
		_refresh_ground_preview()
		status_label.text = "已重做最近一次地面操作"
		get_viewport().set_input_as_handled()


func _refresh_ground_preview() -> void:
	var initialized := MapEditorGroundService.initialize(current_document)
	if initialized.ok:
		preview.set_ground_state(initialized.state)
