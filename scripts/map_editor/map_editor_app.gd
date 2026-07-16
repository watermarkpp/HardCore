class_name MapEditorApp
extends Control

var current_document: Dictionary = {}
var map_id_edit: LineEdit
var runtime_id_edit: SpinBox
var display_name_edit: LineEdit
var map_type_option: OptionButton
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
var manual_collision_start := Vector2i(-1, -1)
var manual_polygon_points: Array[Vector2i] = []
var semantic_kind_option: OptionButton
var semantic_content_id: LineEdit
var semantic_content_option: OptionButton
var semantic_target_map: LineEdit
var semantic_radius: SpinBox
var semantic_count: SpinBox
var semantic_respawn: SpinBox
var semantic_max_alive: SpinBox
var semantic_facing: OptionButton
var semantic_place_toggle: CheckBox
var semantic_catalog_tree: Tree
var random_region_fill_toggle: CheckBox
var point_erase_toggle: CheckBox
var region_fill_menu: PopupMenu
var asset_size_menu: PopupMenu
var asset_size_menu_asset_id := ""
var instance_size_menu: PopupMenu
var instance_size_menu_instance_id := ""
var pending_fill_tiles: Array[Vector2i] = []
var active_tool_mode := "select"


func _notification(what:int)->void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		if not current_document.is_empty(): MapEditorSaveService.save_document(current_document)
		get_tree().quit()


func _ready() -> void:
	_build_ui()
	var recent_path := MapEditorSaveService.default_path("sandbox_64")
	if FileAccess.file_exists(recent_path):
		_open_document_path(recent_path)
	else:
		_create_map("sandbox_64", "quest_room", 990001, "64格沙盒")


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
	map_id_edit = _field(sidebar, "地图 ID", "sandbox_64")
	display_name_edit = _field(sidebar, "显示名称", "64格沙盒")
	var runtime_label := Label.new(); runtime_label.text = "运行地图 ID"; sidebar.add_child(runtime_label)
	runtime_id_edit = SpinBox.new(); runtime_id_edit.min_value = 1; runtime_id_edit.max_value = 9999999; runtime_id_edit.value = 990001; sidebar.add_child(runtime_id_edit)
	var type_label := Label.new(); type_label.text = "地图类型"; sidebar.add_child(type_label)
	map_type_option = OptionButton.new()
	for entry: Dictionary in MapDesignCatalogService._read_json(MapDesignCatalogService.TEMPLATE_PATH).get("templates", []):
		map_type_option.add_item(_map_type_chinese(str(entry.id))); map_type_option.set_item_metadata(map_type_option.item_count - 1, str(entry.id))
	map_type_option.select(_find_type_index("quest_room")); sidebar.add_child(map_type_option)
	var create_button := Button.new(); create_button.text = "按单机目录新建"; create_button.pressed.connect(_on_create_pressed); sidebar.add_child(create_button)
	var bich_button := Button.new(); bich_button.text = "打开 BICH-MAP-1 比奇正式地图"; bich_button.pressed.connect(func(): _open_document_path(MapEditorSaveService.default_path("bich_province"))); sidebar.add_child(bich_button)
	size_label = Label.new(); size_label.text = "设计尺寸：-"; sidebar.add_child(size_label)
	path_label = Label.new(); path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; path_label.modulate = Color("8fb9c7"); sidebar.add_child(path_label)
	var ground_button := Button.new(); ground_button.text = "初始化虚拟地面 Chunk"; ground_button.pressed.connect(_on_initialize_ground_pressed); sidebar.add_child(ground_button)
	var paint_button := Button.new(); paint_button.text = "中心格模拟首次地面编辑"; paint_button.pressed.connect(_on_demo_ground_edit_pressed); sidebar.add_child(paint_button)
	var save_button := Button.new(); save_button.text = "保存工作文件"; save_button.pressed.connect(_on_save_pressed); sidebar.add_child(save_button)
	var open_button := Button.new(); open_button.text = "重新打开工作文件"; open_button.pressed.connect(_on_open_pressed); sidebar.add_child(open_button)
	var note := Label.new(); note.text = "原图尺寸只用于审计。\n地面仅视觉；碰撞由对象和手工区域生成。\n工作文件位于 map_editor_workspace/。"; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.modulate = Color("9da7b3"); sidebar.add_child(note)
	var asset_title := Label.new(); asset_title.text = "素材目录"; asset_title.add_theme_font_size_override("font_size", 13); sidebar.add_child(asset_title)
	asset_tree = Tree.new(); asset_tree.custom_minimum_size.y = 260; asset_tree.hide_root = true; asset_tree.select_mode = Tree.SELECT_MULTI; asset_tree.item_selected.connect(_on_asset_tree_selected); asset_tree.multi_selected.connect(_on_asset_tree_multi_selected); asset_tree.gui_input.connect(_on_asset_tree_gui_input); sidebar.add_child(asset_tree); _refresh_asset_tree()
	brush_label = Label.new(); brush_label.text = "地面笔刷：暗色草地 01"; brush_label.modulate = Color("d7aa62"); sidebar.add_child(brush_label)
	var normal_place_button := Button.new(); normal_place_button.text = "单素材左键铺设 / 摆放"; normal_place_button.pressed.connect(_activate_normal_placement); sidebar.add_child(normal_place_button)
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
	for shape: Array in [["矩形","rect"],["椭圆","ellipse"],["多边形","polygon"]]:
		collision_shape_option.add_item(shape[0]); collision_shape_option.set_item_metadata(collision_shape_option.item_count-1,shape[1])
	sidebar.add_child(collision_shape_option)
	collision_draw_toggle = CheckBox.new(); collision_draw_toggle.text = "在画布绘制碰撞（右键取消）"; collision_draw_toggle.toggled.connect(_on_collision_draw_toggled); sidebar.add_child(collision_draw_toggle)
	var semantic_title := Label.new(); semantic_title.text = "NPC、怪物与地图功能点"; semantic_title.add_theme_font_size_override("font_size", 13); sidebar.add_child(semantic_title)
	semantic_kind_option = OptionButton.new()
	for kind: Array in [["NPC","npc"],["普通怪物刷新点","monster_spawn"],["Boss刷新点","boss_spawn"],["地图出入口","door"],["安全区与回城点","safe_area"],["光效点","light"],["区域触发器","region_trigger"]]:
		semantic_kind_option.add_item(kind[0]); semantic_kind_option.set_item_metadata(semantic_kind_option.item_count-1,kind[1])
	semantic_kind_option.item_selected.connect(_on_semantic_kind_selected); semantic_kind_option.pressed.connect(_activate_semantic_placement)
	sidebar.add_child(semantic_kind_option)
	var content_label := Label.new(); content_label.text = "NPC / 怪物 / Boss 目录"; sidebar.add_child(content_label)
	semantic_content_option = OptionButton.new(); semantic_content_option.fit_to_longest_item = false; semantic_content_option.item_selected.connect(_on_semantic_content_selected); semantic_content_option.pressed.connect(_activate_semantic_placement); sidebar.add_child(semantic_content_option)
	semantic_catalog_tree = Tree.new(); semantic_catalog_tree.hide_root = true; semantic_catalog_tree.custom_minimum_size.y = 150; semantic_catalog_tree.item_selected.connect(_on_semantic_catalog_selected); semantic_catalog_tree.gui_input.connect(_on_semantic_catalog_gui_input); sidebar.add_child(semantic_catalog_tree); _refresh_semantic_catalog_tree()
	semantic_content_id = _field(sidebar, "内容ID（高级选项，可手工覆盖）", "")
	semantic_target_map = _field(sidebar, "出口连接的目标地图ID", "")
	semantic_radius = _spin_field(sidebar, "刷新/区域半径（格；Boss 可为 0）", 0, 64); semantic_radius.value = 3
	semantic_count = _spin_field(sidebar, "刷新数量", 1, 200); semantic_count.value = 1
	semantic_respawn = _spin_field(sidebar, "刷新间隔（秒）", 1, 86400); semantic_respawn.value = 60
	semantic_max_alive = _spin_field(sidebar, "最大存活数", 1, 200); semantic_max_alive.value = 1
	var facing_label := Label.new(); facing_label.text = "NPC 朝向"; sidebar.add_child(facing_label)
	semantic_facing = OptionButton.new()
	for facing: Array in [["下","south"],["左下","south_west"],["左","west"],["左上","north_west"],["上","north"],["右上","north_east"],["右","east"],["右下","south_east"]]:
		semantic_facing.add_item(facing[0]); semantic_facing.set_item_metadata(semantic_facing.item_count-1,facing[1])
	sidebar.add_child(semantic_facing)
	semantic_place_toggle = CheckBox.new(); semantic_place_toggle.text = "开启放置：左键把当前NPC／刷新点／出口放到地图"; semantic_place_toggle.toggled.connect(_on_semantic_place_toggled); sidebar.add_child(semantic_place_toggle)
	var semantic_place_button := Button.new(); semantic_place_button.text="使用当前NPC／刷新点／出口进行左键放置"; semantic_place_button.pressed.connect(_activate_semantic_placement); sidebar.add_child(semantic_place_button)
	var door_note := Label.new(); door_note.text = "出入口采用两步：先像普通素材一样放入口美术，再选择“地图出入口”、填写目标地图ID，并在入口中心放置功能点。程序不会根据图片猜测出口。"; door_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; door_note.modulate=Color("b8c3cf"); sidebar.add_child(door_note)
	var bake_button := Button.new(); bake_button.text = "烘焙 Dirty Chunk 预览"; bake_button.pressed.connect(_on_bake_dirty_pressed); sidebar.add_child(bake_button)
	var build_runtime_button := Button.new(); build_runtime_button.text = "批准并构建 Runtime 快照"; build_runtime_button.pressed.connect(_on_approve_and_build_runtime_pressed); sidebar.add_child(build_runtime_button)
	var calibration_title := Label.new(); calibration_title.text = "素材校准（Expansion覆盖）"; calibration_title.add_theme_font_size_override("font_size", 13); sidebar.add_child(calibration_title)
	calibration_anchor_x = _spin_field(sidebar, "锚点 X", 0, 2048)
	calibration_anchor_y = _spin_field(sidebar, "锚点 Y", 0, 2048)
	calibration_footprint_x = _spin_field(sidebar, "占地宽度（格）", 1, 16)
	calibration_footprint_y = _spin_field(sidebar, "占地高度（格）", 1, 16)
	var collision_label := Label.new(); collision_label.text = "碰撞策略"; sidebar.add_child(collision_label)
	calibration_collision = OptionButton.new()
	for policy: Array in [["无碰撞","none"],["素材预设碰撞","preset"],["手工碰撞","manual"],["按地形印章生成","terrain_stamp_generated"],["整个占地阻挡","solid_footprint"],["自定义多边形","custom_polygon"]]:
		calibration_collision.add_item(policy[0]); calibration_collision.set_item_metadata(calibration_collision.item_count-1,policy[1])
	sidebar.add_child(calibration_collision)
	calibration_occlusion = CheckBox.new(); calibration_occlusion.text = "遮挡玩家"; sidebar.add_child(calibration_occlusion)
	var save_calibration := Button.new(); save_calibration.text = "保存当前素材校准覆盖"; save_calibration.pressed.connect(_on_save_calibration_pressed); sidebar.add_child(save_calibration)
	status_label = Label.new(); status_label.text = "就绪"; status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sidebar.add_child(status_label)
	preview = MapEditorCanvasPreview.new(); preview.paint_requested.connect(_on_ground_paint_requested); preview.erase_tile_requested.connect(_on_erase_tile_requested); preview.lasso_context_requested.connect(_on_lasso_context_requested); preview.tile_hovered.connect(_on_tile_hovered); preview.manual_collision_tile_clicked.connect(_on_manual_collision_tile_clicked); preview.manual_collision_cancelled.connect(_on_manual_collision_cancelled); preview.semantic_tile_clicked.connect(_on_semantic_tile_clicked); preview.selectable_selected.connect(_on_selectable_selected); preview.selectable_move_requested.connect(_on_selectable_move_requested); preview.selectable_delete_requested.connect(_on_selectable_delete_requested); preview.selectable_context_requested.connect(_on_selectable_context_requested); preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL; preview.size_flags_vertical = Control.SIZE_EXPAND_FILL; preview.custom_minimum_size = Vector2(640, 480); preview.focus_mode=Control.FOCUS_ALL; layout.add_child(preview)
	region_fill_menu = PopupMenu.new(); region_fill_menu.add_item("用素材列表已选地面随机填充", 1); region_fill_menu.add_item("删除套索内地面和对象", 3); region_fill_menu.add_separator(); region_fill_menu.add_item("取消", 2); region_fill_menu.id_pressed.connect(_on_region_fill_menu_pressed); add_child(region_fill_menu)
	asset_size_menu = PopupMenu.new(); asset_size_menu.add_item("放大一格", 1); asset_size_menu.add_item("缩小一格", 2); asset_size_menu.add_separator(); asset_size_menu.add_item("恢复初始占位", 3); asset_size_menu.id_pressed.connect(_on_asset_size_menu_pressed); add_child(asset_size_menu)
	instance_size_menu = PopupMenu.new(); instance_size_menu.add_item("放大当前地图素材", 1); instance_size_menu.add_item("缩小当前地图素材", 2); instance_size_menu.id_pressed.connect(_on_instance_size_menu_pressed); add_child(instance_size_menu)
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


func _find_type_index(map_type: String) -> int:
	for i in map_type_option.item_count:
		if str(map_type_option.get_item_metadata(i)) == map_type: return i
	return 0


func _map_type_chinese(map_type: String) -> String:
	return {"bich_city_outdoor":"城镇与野外复合地图","outdoor_province":"大型野外省份","outdoor_field":"普通野外","city_embedded":"嵌入式城镇","shop_interior":"商店室内","palace_room":"宫殿房间","dungeon_floor":"地下城楼层","mine_floor":"矿洞楼层","temple_floor":"神殿楼层","corridor":"走廊地图","maze_room":"迷宫房间","boss_room":"Boss房间","quest_room":"任务房间","arena_room":"竞技场"}.get(map_type,"其他地图")


func _on_create_pressed() -> void:
	var map_type := str(map_type_option.get_item_metadata(map_type_option.selected))
	_create_map(map_id_edit.text.strip_edges(), map_type, int(runtime_id_edit.value), display_name_edit.text.strip_edges())


func _create_map(map_id: String, map_type: String, runtime_map_id: int, display_name: String) -> void:
	if map_id.is_empty(): status_label.text = "地图 ID 不能为空"; return
	current_document = MapEditorTypes.new_map_from_catalog(map_id, map_type, runtime_map_id, display_name)
	map_id_edit.text = str(current_document.map_id); display_name_edit.text = str(current_document.display_name); runtime_id_edit.value = int(current_document.runtime_map_id)
	map_type_option.select(_find_type_index(str(current_document.design.map_type)))
	var design_size: Array = current_document.design.design_size
	size_label.text = "设计尺寸：%d × %d（64×32 等距格）" % [int(design_size[0]), int(design_size[1])]
	path_label.text = "工作文件：%s" % ProjectSettings.globalize_path(MapEditorSaveService.default_path(map_id))
	status_label.text = "已新建；source_size 不会覆盖 design_size"
	preview.set_document(current_document)
	var initialized := MapEditorGroundService.initialize(current_document)
	if initialized.ok:
		status_label.text = "已新建：%d 个虚拟空白 Chunk，尚未落盘地面图" % (initialized.manifest.chunks as Array).size()
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
		var thumbnail := load("res://" + image_path) as Texture2D if not image_path.is_empty() else null
		var item := asset_tree.create_item(parent)
		item.set_text(0, str(asset.get("display_name", asset.get("asset_id", ""))))
		item.set_metadata(0, {"asset_id": str(asset.get("asset_id", ""))})
		if thumbnail != null:
			item.set_icon(0, thumbnail)
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
	var result := MapEditorSaveService.save_document(current_document)
	status_label.text = "保存成功：%s" % result.get("path", "") if result.get("ok", false) else "保存失败：%s" % result.get("errors", [])


func _on_open_pressed() -> void:
	_open_document_path(MapEditorSaveService.default_path(map_id_edit.text.strip_edges()))


func _open_document_path(path: String) -> void:
	var result := MapEditorLoadService.load_document(path)
	if result.get("ok", false):
		current_document = result.document
		_migrate_loaded_instances_to_class_profiles()
		MapEditorGameplaySemanticService.repair_duplicate_ids(current_document)
		_ensure_map_portal_semantics()
		MapEditorSaveService.save_document(current_document,path)
		map_id_edit.text = str(current_document.get("map_id", "")); display_name_edit.text = str(current_document.get("display_name", "")); runtime_id_edit.value = int(current_document.get("runtime_map_id", 0))
		preview.set_document(current_document)
		var initialized := MapEditorGroundService.initialize(current_document)
		if initialized.ok: preview.set_ground_state(initialized.state)
		status_label.text = "正式地图打开成功：%s" % path
	else: status_label.text = "打开失败：%s" % result.get("errors", [])


func _ensure_map_portal_semantics() -> void:
	var linked := {}
	for door: Dictionary in current_document.layers.get("door_points", []):
		var visual_id := str(door.get("linked_visual_instance_id", ""))
		if not visual_id.is_empty(): linked[visual_id] = true
	for instance: Dictionary in MapEditorInstanceService.all_instances(current_document):
		var asset := MapAssetCatalogService.find_asset(str(instance.get("asset_id", "")))
		if str(asset.get("object_class", "")) != "map_entrance": continue
		var instance_id := str(instance.get("instance_id", ""))
		var raw_tile: Array = instance.get("tile", [0,0])
		if linked.has(instance_id):
			MapEditorGameplaySemanticService.sync_linked_instance_tile(current_document, instance_id, Vector2i(int(raw_tile[0]), int(raw_tile[1])))
			continue
		MapEditorGameplaySemanticService.add_entry(current_document,"door",Vector2i(int(raw_tile[0]),int(raw_tile[1])),{
			"door_id":"door.%s"%instance_id,"target_map_id":"待配置","target_tile":[0,0],
			"display_name":"待配置地图传送门","linked_visual_instance_id":instance_id,
			"auto_created_from_asset":true,"semantic_role":"map_portal","trigger_on_enter":true,"blocks_movement":false,
		})


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
			if not bool(instance.get("instance_custom_scale", false)):
				for key:String in ["footprint_tiles","occupancy_footprint_tiles","collision_footprint_tiles","collision_profile_id","collision_policy","placement_anchor_px","selection_shape"]:
					if asset.has(key):instance[key]=asset[key]
				instance["anchor_px"]=asset.get("placement_anchor_px",asset.get("anchor_px",instance.get("anchor_px",[0,0])))
				instance["scale"]=[float(asset.get("approved_scale",1.0)),float(asset.get("approved_scale",1.0))]
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
	var asset := MapAssetCatalogService.find_asset(asset_size_menu_asset_id)
	var base := MapAssetCatalogService.find_base_asset(asset_size_menu_asset_id)
	if asset.is_empty() or base.is_empty():
		return
	if str(asset.get("asset_type", "")) == "ground_brush":
		status_label.text = "地面素材固定为 1×1 格，不能缩放"
		return
	var base_fp: Array = base.get("base_footprint_tiles", base.get("footprint_tiles", [1, 1]))
	var current_fp: Array = asset.get("footprint_tiles", base_fp)
	var level := int(asset.get("logical_scale_level", 0))
	if action_id == 1: level += 1
	elif action_id == 2: level -= 1
	else: level = 0
	var new_fp := [maxi(1, int(base_fp[0]) + level), maxi(1, int(base_fp[1]) + level)]
	# Once both dimensions have reached one tile, further shrinking is a no-op.
	level = maxi(level, 1 - mini(int(base_fp[0]), int(base_fp[1])))
	new_fp = [maxi(1, int(base_fp[0]) + level), maxi(1, int(base_fp[1]) + level)]
	var scale_ratio := minf(float(new_fp[0]) / float(base_fp[0]), float(new_fp[1]) / float(base_fp[1]))
	var collision_fp: Array = asset.get("collision_footprint_tiles", [0, 0])
	if int(collision_fp[0]) > 0 or int(collision_fp[1]) > 0:
		collision_fp = new_fp.duplicate()
	var draft := {
		"footprint_tiles": new_fp, "visual_footprint_tiles": new_fp,
		"occupancy_footprint_tiles": new_fp, "collision_footprint_tiles": collision_fp,
		"approved_scale": scale_ratio, "logical_scale_level": level,
	}
	var result := MapAssetCalibrationService.save_override(asset_size_menu_asset_id, draft)
	if result.get("ok", false):
		MapAssetCatalogService.invalidate_cache()
		_refresh_asset_tree()
		selected_asset_id = asset_size_menu_asset_id
		preview.set_selected_brush(selected_asset_id)
		status_label.text = "素材占位已调整为 %d×%d 格" % [new_fp[0], new_fp[1]]
	else:
		status_label.text = "素材尺寸调整失败：%s" % result.get("errors", [])


func _activate_asset_tree_item(item: TreeItem) -> void:
	var metadata: Variant = item.get_metadata(0)
	if not metadata is Dictionary:
		return
	var asset_id := str(metadata.get("asset_id", ""))
	if asset_id.is_empty():
		return
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
		var layer := "terrain_base" if str(selected_asset.get("asset_type", "")) == "terrain_stamp" else "object_base"
		var placed := MapEditorInstanceService.create_instance(current_document, asset_id, role, tile, layer)
		if placed.ok:
			var is_map_portal := str(selected_asset.get("object_class", "")) == "map_entrance"
			if is_map_portal:
				var door:=MapEditorGameplaySemanticService.add_entry(current_document,"door",tile,{"door_id":"door.%s"%placed.instance.instance_id,"target_map_id":"待配置","target_tile":[0,0],"display_name":"待配置地图传送门","linked_visual_instance_id":placed.instance.instance_id,"auto_created_from_asset":true,"semantic_role":"map_portal","trigger_on_enter":true,"blocks_movement":false})
				if door.ok: status_label.text="入口美术与门点已同时放置，请选中门点配置目标地图"
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
	status_label.text="选择工具：悬停高亮，左键选取，方向键移动一格，Delete删除"


func _set_active_tool(mode: String) -> void:
	if mode not in ["place", "select", "lasso", "erase", "manual_collision", "semantic"]:
		return
	active_tool_mode = mode
	if random_region_fill_toggle != null: random_region_fill_toggle.set_pressed_no_signal(mode == "lasso")
	if point_erase_toggle != null: point_erase_toggle.set_pressed_no_signal(mode == "erase")
	if collision_draw_toggle != null: collision_draw_toggle.set_pressed_no_signal(mode == "manual_collision")
	if semantic_place_toggle != null: semantic_place_toggle.set_pressed_no_signal(mode == "semantic")
	if preview == null:
		return
	if mode == "place":
		preview.activate_normal_placement(selected_asset_id)
	else:
		preview.set_region_paint_mode(mode == "lasso")
		preview.set_interaction_mode({"select":"select", "lasso":"place", "erase":"erase", "manual_collision":"manual_collision", "semantic":"semantic"}.get(mode, "place"))
	preview.grab_focus()


func _activate_semantic_placement() -> void:
	_set_active_tool("semantic")
	var kind := str(semantic_kind_option.get_item_metadata(semantic_kind_option.selected)) if semantic_kind_option != null and semantic_kind_option.selected >= 0 else "semantic"
	var content_id := semantic_content_id.text.strip_edges() if semantic_content_id != null else ""
	status_label.text = "功能点放置已启用：%s%s" % [kind, " / " + content_id if not content_id.is_empty() else ""]


func _on_selectable_selected(selectable_id:String,_additive:bool)->void:
	status_label.text="已选中：%s" % selectable_id if not selectable_id.is_empty() else "已清空选择"


func _on_selectable_context_requested(selectable_id:String,screen_position:Vector2)->void:
	if not selectable_id.begins_with("inst_"):return
	instance_size_menu_instance_id=selectable_id
	instance_size_menu.position=Vector2i(screen_position)
	instance_size_menu.popup()


func _on_instance_size_menu_pressed(action_id:int)->void:
	var result:=MapEditorInstanceService.resize_instance(current_document,instance_size_menu_instance_id,1 if action_id==1 else -1)
	if result.get("ok",false):
		preview.set_document(current_document)
		if preview.show_walkable_preview: preview.set_walkability_preview(MapEditorCollisionService.build_walkability(current_document),true)
		MapEditorSaveService.save_document(current_document)
		status_label.text="当前地图素材已%s，中心点、占地和碰撞已同步"%("放大" if action_id==1 else "缩小")
	else:status_label.text="缩放失败：%s"%result.get("errors",[])


func _on_selectable_move_requested(selectable_id:String,delta:Vector2i)->void:
	var result:Dictionary
	if selectable_id.begins_with("inst_"):
		var located:=MapEditorInstanceService._locate(current_document,selectable_id)
		if not located.ok:return
		var tile:Array=located.instance.tile
		var old_tile:=Vector2i(int(tile[0]),int(tile[1])); var new_tile:=old_tile+delta
		command_stack.execute({
			"do": func():
				result = MapEditorInstanceService.move_instance(current_document, selectable_id, new_tile)
				if result.get("ok", false): MapEditorGameplaySemanticService.sync_linked_instance_tile(current_document, selectable_id, new_tile),
			"undo": func():
				MapEditorInstanceService.move_instance(current_document, selectable_id, old_tile)
				MapEditorGameplaySemanticService.sync_linked_instance_tile(current_document, selectable_id, old_tile),
		})
	else:
		command_stack.execute({"do":func():result=MapEditorGameplaySemanticService.move_entry(current_document,selectable_id,delta),"undo":func():MapEditorGameplaySemanticService.move_entry(current_document,selectable_id,-delta)})
	preview.set_document(current_document)
	status_label.text="移动成功" if result.ok else "移动失败：%s"%result.get("errors",[])


func _on_selectable_delete_requested(selectable_id:String)->void:
	var result:=_delete_instance_with_linked_semantics(selectable_id) if selectable_id.begins_with("inst_") else MapEditorGameplaySemanticService.delete_entry(current_document,selectable_id)
	if result.ok:
		preview.selected_selectable_id=""
		preview.set_document(current_document)
	status_label.text="删除成功" if result.ok else "删除失败：%s"%result.get("errors",[])


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


func _on_semantic_kind_selected(index: int) -> void:
	var kind := str(semantic_kind_option.get_item_metadata(index))
	semantic_content_option.clear()
	for entry: Dictionary in MapEditorContentCatalogService.entries(kind, 4):
		var detail := ""
		if kind in ["monster_spawn", "boss_spawn"]:
			detail = "  等级%d  生命%d" % [int(entry.get("level", 0)), int(entry.get("hp", 0))]
		elif kind == "npc":
			detail = "  [%s]" % _service_role_chinese(str(entry.get("service_role", "dialogue")))
		semantic_content_option.add_item(str(entry.get("display_name", entry.get("content_id", ""))) + detail)
		semantic_content_option.set_item_metadata(semantic_content_option.item_count - 1, entry)
	semantic_content_option.visible = kind in ["npc", "monster_spawn", "boss_spawn"]
	semantic_content_id.visible = semantic_content_option.visible
	var is_spawn := kind in ["monster_spawn", "boss_spawn"]
	semantic_count.visible = is_spawn; semantic_respawn.visible = is_spawn; semantic_max_alive.visible = is_spawn
	semantic_facing.visible = kind == "npc"
	if kind == "boss_spawn": semantic_radius.value = 0
	elif kind == "monster_spawn" and semantic_radius.value <= 0: semantic_radius.value = 3
	if semantic_content_option.item_count > 0:
		semantic_content_option.select(0)
		_on_semantic_content_selected(0)
	if preview != null:
		_activate_semantic_placement()


func _refresh_semantic_catalog_tree() -> void:
	semantic_catalog_tree.clear()
	var root := semantic_catalog_tree.create_item()
	for group: Array in [["NPC目录", "npc"], ["怪物目录", "monster_spawn"], ["Boss目录", "boss_spawn"]]:
		var folder := semantic_catalog_tree.create_item(root); folder.set_text(0, group[0]); folder.set_selectable(0, false); folder.collapsed = true
		for entry: Dictionary in MapEditorContentCatalogService.entries(group[1], 4):
			var item := semantic_catalog_tree.create_item(folder)
			item.set_text(0, str(entry.get("display_name", entry.get("content_id", ""))))
			item.set_metadata(0, {"kind": group[1], "entry": entry})


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
	_activate_semantic_placement()
	status_label.text="已选择%s：%s；请在地图左键放置"%["NPC" if kind=="npc" else "怪物/Boss",str(entry.get("display_name",""))]


func _on_semantic_content_selected(index: int) -> void:
	var entry: Variant = semantic_content_option.get_item_metadata(index)
	if entry is Dictionary:
		semantic_content_id.text = str(entry.get("content_id", ""))
		if preview != null:
			_activate_semantic_placement()


func _service_role_chinese(role: String) -> String:
	return {"dialogue":"对话","shop":"商店","trainer":"训练师","quest":"任务","warehouse":"仓库","repair":"修理","teleport":"传送"}.get(role, "其他功能")


func _on_semantic_tile_clicked(tile: Vector2i) -> void:
	var kind := str(semantic_kind_option.get_item_metadata(semantic_kind_option.selected))
	var properties := {"radius_tiles": int(semantic_radius.value)}
	var content_id := semantic_content_id.text.strip_edges()
	if kind == "npc":
		properties["npc_id"] = content_id
		properties["content_id"] = content_id
		properties["facing"] = str(semantic_facing.get_item_metadata(semantic_facing.selected))
		var npc_entry := MapEditorContentCatalogService.find(kind, content_id)
		properties["display_name"] = str(npc_entry.get("display_name", content_id))
		properties["service_role"] = str(npc_entry.get("service_role", "dialogue"))
	elif kind == "monster_spawn":
		properties["monster_id"] = content_id
		properties["content_id"] = content_id
	elif kind == "boss_spawn":
		properties["boss_id"] = content_id
		properties["content_id"] = content_id
	elif kind == "door":
		properties["target_map_id"] = semantic_target_map.text.strip_edges()
	if kind in ["monster_spawn", "boss_spawn"]:
		var combat_entry := MapEditorContentCatalogService.find(kind, content_id)
		properties["display_name"] = str(combat_entry.get("display_name", content_id))
		properties["count"] = int(semantic_count.value)
		properties["respawn_seconds"] = int(semantic_respawn.value)
		properties["max_alive"] = int(semantic_max_alive.value)
	var result := MapEditorGameplaySemanticService.add_entry(current_document, kind, tile, properties)
	if result.ok:
		if kind=="npc": MapEditorNpcPlaceholderService.ensure_entry(current_document,str(result.entry.semantic_id))
		preview.queue_redraw()
		status_label.text = "放置成功：%s" % result.entry.semantic_id
	else:
		status_label.text = "功能点放置失败：%s" % result.get("errors", [])


func _on_collision_draw_toggled(enabled: bool) -> void:
	manual_collision_start = Vector2i(-1, -1)
	manual_polygon_points.clear()
	if enabled:
		_set_active_tool("manual_collision")
	elif active_tool_mode == "manual_collision":
		_set_active_tool("place")
	status_label.text = "碰撞绘制：左键设置点，右键取消；多边形按 Enter 完成" if enabled else "已返回素材放置"


func _on_manual_collision_tile_clicked(tile: Vector2i) -> void:
	var shape := str(collision_shape_option.get_item_metadata(collision_shape_option.selected))
	if shape == "polygon":
		manual_polygon_points.append(tile)
		status_label.text = "多边形点 %d：(%d,%d)，按 Enter 完成" % [manual_polygon_points.size(), tile.x, tile.y]
		return
	if manual_collision_start.x < 0:
		manual_collision_start = tile
		status_label.text = "碰撞起点：(%d,%d)，请点击终点" % [tile.x, tile.y]
		return
	var start := manual_collision_start
	manual_collision_start = Vector2i(-1, -1)
	var rect := [mini(start.x, tile.x), mini(start.y, tile.y), absi(tile.x - start.x) + 1, absi(tile.y - start.y) + 1]
	_commit_manual_collision(shape, {"rect": rect})


func _on_manual_collision_cancelled() -> void:
	manual_collision_start = Vector2i(-1, -1)
	manual_polygon_points.clear()
	status_label.text = "已取消手工碰撞绘制"


func _commit_manual_collision(shape: String, data: Dictionary) -> void:
	var result := MapEditorCollisionService.add_manual_shape(current_document, shape, data)
	if result.ok:
		preview.set_walkability_preview(MapEditorCollisionService.build_walkability(current_document), true)
		status_label.text = "已添加%s碰撞：%s" % [shape, result.collision.collision_id]
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
	if event.ctrl_pressed and event.keycode==KEY_Z:
		if command_stack.undo():preview.set_document(current_document);status_label.text="已撤销"
		return
	if event.ctrl_pressed and event.keycode==KEY_Y:
		if command_stack.redo():preview.set_document(current_document);status_label.text="已重做"
		return
	if event.keycode == KEY_ENTER and collision_draw_toggle.button_pressed and str(collision_shape_option.get_item_metadata(collision_shape_option.selected)) == "polygon":
		if manual_polygon_points.size() >= 3:
			var points: Array = []
			for point: Vector2i in manual_polygon_points: points.append([point.x, point.y])
			_commit_manual_collision("polygon", {"points": points})
			manual_polygon_points.clear()
		else: status_label.text = "多边形至少需要3个点"
		get_viewport().set_input_as_handled()
		return
	if not event.ctrl_pressed:
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
