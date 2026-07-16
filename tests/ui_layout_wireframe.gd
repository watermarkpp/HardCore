extends Control

const DESIGN_SIZE := Vector2(1280, 720)
const SAFE_RECT := Rect2(24, 16, 1232, 688)
const TOUCH_MIN := 56.0
const MODES := ["hud", "inventory", "shop", "warehouse", "quest", "map", "skill", "profession"]
const TOP_CAPTION_NODES := [
	"AttributeSection", "CharacterSection", "BagSection", "CategorySection", "GoodsSection", "DetailSection",
	"TransferSection", "StashSection", "QuestList", "QuestDetail", "MapList", "MapCanvas", "MapDetail",
	"SkillList", "SkillDetail", "Assignment", "ProfessionIdentity", "GrowthPath", "Unlocks",
]

const COLOR_BG := Color("10141a")
const COLOR_WORLD := Color("1a2329")
const COLOR_PANEL := Color("252a32")
const COLOR_SECTION := Color("343b46")
const COLOR_TEXT := Color("f1eee6")
const COLOR_MUTED := Color("aeb7c3")
const COLOR_GOLD := Color("a8843f")
const COLOR_RED := Color("a84545")
const COLOR_BLUE := Color("3f6f9d")
const COLOR_GREEN := Color("3f8562")
const COLOR_PURPLE := Color("725c8f")
const COLOR_ORANGE := Color("a86537")

var _mode := "hud"


func _ready() -> void:
	_mode = OS.get_environment("UI_LAYOUT_MODE").to_lower()
	if _mode not in MODES:
		_mode = "hud"
	_build_canvas()
	await get_tree().process_frame
	if OS.get_environment("UI_LAYOUT_CAPTURE") == "1":
		await get_tree().process_frame
		_capture_and_quit()


func _build_canvas() -> void:
	_add_color_rect(self, "Background", Rect2(Vector2.ZERO, DESIGN_SIZE), COLOR_BG)
	if _mode == "hud":
		_build_hud()
	else:
		_build_modal_background()
		match _mode:
			"inventory":
				_build_inventory()
			"shop":
				_build_shop()
			"warehouse":
				_build_warehouse()
			"quest":
				_build_quest()
			"map":
				_build_map()
			"skill":
				_build_skill()
			"profession":
				_build_profession()
	_build_safe_guide()
	_build_legend()


func _build_modal_background() -> void:
	_add_color_rect(self, "WorldBackdrop", Rect2(0, 0, 1280, 720), COLOR_WORLD)
	for x in range(0, 1280, 80):
		_add_color_rect(self, "GridV%d" % x, Rect2(x, 0, 1, 720), Color(0.35, 0.42, 0.47, 0.12))
	for y in range(0, 720, 80):
		_add_color_rect(self, "GridH%d" % y, Rect2(0, y, 1280, 1), Color(0.35, 0.42, 0.47, 0.12))
	_add_color_rect(self, "ModalDim", Rect2(0, 0, 1280, 720), Color(0.02, 0.025, 0.03, 0.58))


func _build_hud() -> void:
	_add_color_rect(self, "World", Rect2(0, 0, 1280, 720), COLOR_WORLD)
	for x in range(0, 1280, 80):
		_add_color_rect(self, "WorldGridV%d" % x, Rect2(x, 0, 1, 720), Color(0.35, 0.42, 0.47, 0.12))
	for y in range(0, 720, 80):
		_add_color_rect(self, "WorldGridH%d" % y, Rect2(0, y, 1280, 1), Color(0.35, 0.42, 0.47, 0.12))
	_add_label(self, "WorldLabel", Rect2(480, 270, 320, 56), "游戏世界可视区域", 28, COLOR_MUTED, HORIZONTAL_ALIGNMENT_CENTER)

	_add_panel(self, "TargetPanel", Rect2(440, 52, 400, 64), "怪物名称\n目标生命值", COLOR_RED)
	_add_panel(self, "ZonePanel", Rect2(984, 48, 246, 100), "区域 / 坐标 / 时间", COLOR_SECTION)
	_add_touch(self, "AutoLockButton", Rect2(984, 156, 246, 56), "自动锁定", COLOR_PURPLE)
	_add_touch(self, "MapButton", Rect2(984, 220, 116, 56), "地图", COLOR_BLUE)
	_add_touch(self, "MenuButton", Rect2(1114, 220, 116, 56), "菜单", COLOR_PURPLE)
	_add_touch(self, "BagButton", Rect2(984, 284, 116, 56), "背包", COLOR_ORANGE)
	_add_touch(self, "SkillBookButton", Rect2(1114, 284, 116, 56), "技能", COLOR_ORANGE)

	_add_touch(self, "Joystick", Rect2(42, 548, 138, 138), "移动摇杆", COLOR_BLUE)
	_add_panel(self, "LootNotice", Rect2(460, 390, 360, 56), "拾取与战斗反馈", COLOR_SECTION)

	_add_label(self, "SkillModeHint", Rect2(420, 454, 460, 32), "4个技能槽：按技能属性显示开关或点击施放", 14, COLOR_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	for index in range(4):
		var profession_slot := _add_touch(self, "ProfessionSkillSlot%d" % (index + 1), Rect2(456 + index * 100, 494, 88, 64), "技能槽%d\n开关/施放" % (index + 1), COLOR_PURPLE)
		profession_slot.add_to_group("hud_profession_skill_slot")
		profession_slot.set_meta("activation_mode_source", "skill.activation_mode")
		profession_slot.set_meta("warrior_policy", "toggle")
		profession_slot.set_meta("mage_tao_policy", "instant_or_toggle")

	var integrated_frame := _add_outline(self, "IntegratedResourceItemFrame", Rect2(310, 574, 690, 124), Color(0.45, 0.92, 0.78, 0.88), 3)
	integrated_frame.add_to_group("integrated_resource_item_frame")
	integrated_frame.set_meta("background_alpha", 0.0)
	integrated_frame.set_meta("contents", ["health_orb", "four_item_slots", "mana_orb"])
	_add_label(self, "IntegratedFrameHint", Rect2(420, 574, 470, 24), "一体式美术框：生命球 · 4物品 · 魔法球", 13, Color(0.55, 1.0, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
	_add_touch(self, "HealthOrb", Rect2(326, 584, 112, 104), "生命球", COLOR_RED)
	_add_touch(self, "ManaOrb", Rect2(872, 584, 112, 104), "魔法球", COLOR_BLUE)
	for index in range(4):
		var item_slot := _add_touch(self, "ItemSlot%d" % (index + 1), Rect2(497 + index * 82, 610, 70, 70), "物品%d" % (index + 1), COLOR_GOLD)
		item_slot.add_to_group("hud_item_slot")

	var quick_skill_1 := _add_touch(self, "Skill1", Rect2(1068, 612, 72, 72), "技能1", COLOR_GOLD)
	var quick_skill_2 := _add_touch(self, "Skill2", Rect2(1060, 516, 72, 72), "技能2", COLOR_GOLD)
	var quick_skill_3 := _add_touch(self, "Skill3", Rect2(1148, 488, 72, 72), "技能3", COLOR_GOLD)
	quick_skill_1.add_to_group("hud_attack_ring_skill")
	quick_skill_2.add_to_group("hud_attack_ring_skill")
	quick_skill_3.add_to_group("hud_attack_ring_skill")
	_add_touch(self, "AttackButton", Rect2(1148, 588, 104, 104), "攻击", COLOR_RED)
	_add_touch(self, "InteractButton", Rect2(1186, 346, 68, 68), "交互", COLOR_GREEN)
	_add_touch(self, "SwitchTarget", Rect2(1146, 422, 108, 56), "切换敌人", COLOR_BLUE)


func _build_inventory() -> void:
	var panel := _modal_shell("InventoryPanel", "人物与背包", "属性、装备与物品在一个横屏页面完成", Rect2(30, 40, 1220, 650))
	_add_panel(panel, "AttributeSection", Rect2(20, 78, 280, 548), "人物属性", COLOR_SECTION)
	_add_panel(panel, "CharacterSection", Rect2(312, 78, 356, 548), "人物穿戴预览", COLOR_SECTION)
	_add_panel(panel, "BagSection", Rect2(680, 78, 520, 548), "综合背包 40 格", COLOR_SECTION)
	_add_panel(panel, "Stats", Rect2(38, 138, 244, 210), "生命 / 魔法\n攻击 / 防御\n准确 / 敏捷\n负重 / 幸运", Color("414b58"))
	_add_panel(panel, "ItemDetail", Rect2(38, 366, 244, 238), "选中物品详情\n属性比较\n穿戴要求", Color("414b58"))
	_add_panel(panel, "PaperDoll", Rect2(386, 142, 208, 304), "人物纸娃娃", Color("414b58"))
	for index in range(8):
		var column := index % 2
		var row := index / 2
		_add_touch(panel, "EquipmentSlot%d" % index, Rect2(326 + column * 272, 126 + row * 92, 72, 72), "装%d" % (index + 1), COLOR_GOLD)
	for index in range(40):
		var column := index % 8
		var row := index / 8
		_add_touch(panel, "BagSlot%d" % index, Rect2(698 + column * 61, 142 + row * 76, 56, 64), str(index + 1), COLOR_GOLD)
	_add_touch(panel, "SortButton", Rect2(826, 548, 110, 56), "整理", COLOR_BLUE)
	_add_touch(panel, "SplitButton", Rect2(948, 548, 110, 56), "拆分", COLOR_PURPLE)
	_add_touch(panel, "UseButton", Rect2(1070, 548, 110, 56), "使用", COLOR_GREEN)


func _build_shop() -> void:
	var panel := _modal_shell("ShopPanel", "商店", "购买、出售与修理", Rect2(100, 48, 1080, 636))
	_add_panel(panel, "CategorySection", Rect2(20, 78, 170, 534), "商品分类", COLOR_SECTION)
	for index in range(6):
		_add_touch(panel, "Category%d" % index, Rect2(34, 128 + index * 70, 142, 58), ["武器", "衣服", "首饰", "药品", "卷轴", "杂物"][index], COLOR_BLUE)
	_add_panel(panel, "GoodsSection", Rect2(202, 78, 540, 534), "商品方格", COLOR_SECTION)
	for index in range(12):
		var column := index % 3
		var row := index / 3
		_add_shop_item(panel, index, Vector2(218 + column * 174, 134 + row * 98))
	_add_panel(panel, "DetailSection", Rect2(754, 78, 306, 534), "物品详情与角色对比", COLOR_SECTION)
	_add_panel(panel, "ItemPreview", Rect2(778, 132, 96, 96), "图标", Color("414b58"))
	_add_panel(panel, "ItemStats", Rect2(888, 132, 148, 354), "名称 / 类型\n基础属性\n特殊属性\n穿戴要求\n对比结果", Color("414b58"))
	_add_touch(panel, "RepairButton", Rect2(778, 536, 88, 56), "修理", COLOR_PURPLE)
	_add_touch(panel, "SellButton", Rect2(876, 536, 78, 56), "出售", COLOR_ORANGE)
	_add_touch(panel, "BuyButton", Rect2(964, 536, 72, 56), "购买", COLOR_GREEN)


func _build_warehouse() -> void:
	var panel := _modal_shell("WarehousePanel", "仓库", "左右对照并支持快速转移", Rect2(70, 48, 1140, 636))
	_add_panel(panel, "BagSection", Rect2(20, 78, 466, 534), "角色背包", COLOR_SECTION)
	_add_panel(panel, "TransferSection", Rect2(498, 78, 124, 534), "转移", COLOR_SECTION)
	_add_panel(panel, "StashSection", Rect2(634, 78, 486, 534), "账号仓库", COLOR_SECTION)
	for index in range(30):
		var column := index % 6
		var row := index / 6
		_add_touch(panel, "BagCell%d" % index, Rect2(38 + column * 72, 134 + row * 78, 64, 64), str(index + 1), COLOR_GOLD)
		_add_touch(panel, "StashCell%d" % index, Rect2(652 + column * 72, 134 + row * 78, 64, 64), str(index + 1), COLOR_GOLD)
	_add_touch(panel, "DepositButton", Rect2(516, 236, 88, 72), "存入 →", COLOR_GREEN)
	_add_touch(panel, "WithdrawButton", Rect2(516, 326, 88, 72), "← 取出", COLOR_BLUE)
	_add_touch(panel, "SortStashButton", Rect2(516, 474, 88, 64), "整理", COLOR_PURPLE)


func _build_quest() -> void:
	var panel := _modal_shell("QuestPanel", "任务日志", "任务列表、目标和奖励", Rect2(130, 48, 1020, 636))
	_add_panel(panel, "QuestList", Rect2(20, 78, 330, 534), "任务列表", COLOR_SECTION)
	for index in range(6):
		_add_touch(panel, "Quest%d" % index, Rect2(38, 128 + index * 70, 294, 58), "任务 %d　%s" % [index + 1, "进行中" if index < 3 else "可接取"], COLOR_ORANGE if index < 3 else COLOR_BLUE)
	_add_panel(panel, "QuestDetail", Rect2(362, 78, 638, 534), "任务详情", COLOR_SECTION)
	_add_panel(panel, "Story", Rect2(386, 132, 590, 150), "任务名称\n剧情说明与来源 NPC", Color("414b58"))
	_add_panel(panel, "Objectives", Rect2(386, 296, 590, 132), "目标 1：怪物进度\n目标 2：物品收集\n目标区域", Color("414b58"))
	_add_panel(panel, "Rewards", Rect2(386, 442, 350, 146), "奖励预览\n经验 / 金币 / 物品", Color("414b58"))
	_add_touch(panel, "TrackButton", Rect2(752, 470, 104, 56), "追踪", COLOR_BLUE)
	_add_touch(panel, "ActionButton", Rect2(870, 470, 106, 56), "接取/提交", COLOR_GREEN)


func _build_map() -> void:
	var panel := _modal_shell("MapPanel", "世界地图", "搜索、筛选、查看并前往区域", Rect2(60, 40, 1160, 650))
	_add_panel(panel, "MapList", Rect2(20, 78, 270, 548), "地图列表", COLOR_SECTION)
	_add_touch(panel, "Search", Rect2(38, 126, 234, 56), "搜索地图", COLOR_BLUE)
	for index in range(5):
		_add_touch(panel, "MapEntry%d" % index, Rect2(38, 198 + index * 70, 234, 58), "区域 %d" % (index + 1), COLOR_ORANGE)
	_add_panel(panel, "MapCanvas", Rect2(302, 78, 520, 548), "地图预览与门点", Color("414b58"))
	_add_panel(panel, "MapRoute", Rect2(336, 142, 452, 360), "路线、区域边界\nNPC / 门点 / 目标标记", Color("263846"))
	_add_panel(panel, "MapDetail", Rect2(834, 78, 306, 548), "区域信息", COLOR_SECTION)
	_add_panel(panel, "MapDescription", Rect2(852, 132, 270, 300), "区域名称\n推荐等级\n怪物类型\n可达区域\n任务提示", Color("414b58"))
	_add_touch(panel, "PinButton", Rect2(852, 528, 126, 64), "设为目标", COLOR_BLUE)
	_add_touch(panel, "TravelButton", Rect2(992, 528, 130, 64), "前往", COLOR_GREEN)


func _build_skill() -> void:
	var panel := _modal_shell("SkillPanel", "技能典籍", "查看技能并配置右下三个技能按钮", Rect2(36, 40, 1208, 650))
	_add_panel(panel, "SkillList", Rect2(20, 78, 310, 548), "人物技能", COLOR_SECTION)
	for index in range(6):
		_add_touch(panel, "SkillEntry%d" % index, Rect2(38, 126 + index * 76, 274, 64), "技能 %d　Lv.3" % (index + 1), COLOR_GOLD)
	_add_panel(panel, "SkillDetail", Rect2(342, 78, 500, 548), "技能详情", COLOR_SECTION)
	_add_panel(panel, "SkillIcon", Rect2(370, 132, 112, 112), "图标", Color("414b58"))
	_add_panel(panel, "SkillStats", Rect2(500, 132, 314, 276), "名称 / 等级 / 熟练度\n类型 / 消耗 / 冷却\n范围 / 目标方式\n说明与数据来源", Color("414b58"))
	_add_touch(panel, "EnableSkill", Rect2(370, 532, 204, 64), "启用自动技能", COLOR_PURPLE)
	_add_touch(panel, "AssignSkill", Rect2(590, 532, 224, 64), "配置技能按钮", COLOR_GREEN)
	_add_panel(panel, "Assignment", Rect2(854, 78, 334, 548), "技能按钮配置", COLOR_SECTION)
	for index in range(3):
		_add_touch(panel, "SkillSlot%d" % index, Rect2(876, 144 + index * 136, 290, 112), "技能按钮 %d" % (index + 1), COLOR_RED if index == 0 else COLOR_GOLD)


func _build_profession() -> void:
	var panel := _modal_shell("ProfessionPanel", "职业成长", "职业定位、成长路线与解锁内容", Rect2(90, 48, 1100, 636))
	_add_panel(panel, "ProfessionTabs", Rect2(20, 78, 1060, 88), "", COLOR_SECTION)
	for index in range(3):
		_add_touch(panel, "Profession%d" % index, Rect2(38 + index * 346, 94, 326, 56), ["战士", "法师", "道士"][index], COLOR_RED if index == 0 else COLOR_BLUE)
	_add_panel(panel, "ProfessionIdentity", Rect2(20, 178, 316, 434), "职业定位", COLOR_SECTION)
	_add_panel(panel, "ProfessionPortrait", Rect2(44, 228, 268, 180), "职业人物预览", Color("414b58"))
	_add_panel(panel, "RoleText", Rect2(44, 424, 268, 160), "近战 / 爆发 / 生存\n主属性与推荐装备", Color("414b58"))
	_add_panel(panel, "GrowthPath", Rect2(348, 178, 440, 434), "成长路线", COLOR_SECTION)
	for index in range(4):
		_add_touch(panel, "GrowthNode%d" % index, Rect2(372, 226 + index * 86, 392, 68), "阶段 %d　属性与技能解锁" % (index + 1), COLOR_GOLD)
	_add_panel(panel, "Unlocks", Rect2(800, 178, 280, 434), "解锁内容", COLOR_SECTION)
	_add_panel(panel, "UnlockList", Rect2(824, 228, 232, 238), "技能\n装备类型\n职业机制\n成长奖励", Color("414b58"))
	_add_touch(panel, "ConfirmProfession", Rect2(824, 504, 232, 64), "确认职业", COLOR_GREEN)


func _add_shop_item(parent: Control, index: int, at: Vector2) -> void:
	var card := _add_touch(parent, "Goods%d" % index, Rect2(at, Vector2(164, 88)), "", COLOR_GOLD)
	var icon := _add_panel(card, "ItemIcon", Rect2(6, 6, 76, 76), "图标", Color("414b58"))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_label(card, "ItemName", Rect2(88, 6, 70, 76), "商品%d\n价格" % (index + 1), 13, COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER)


func _modal_shell(node_name: String, title: String, subtitle: String, rect: Rect2) -> Panel:
	var panel := _add_panel(self, node_name, rect, "", COLOR_PANEL)
	panel.add_to_group("wireframe_modal")
	_add_label(panel, "Title", Rect2(20, 12, rect.size.x - 130, 36), title, 28, COLOR_TEXT)
	_add_label(panel, "Subtitle", Rect2(20, 46, rect.size.x - 130, 26), subtitle, 15, COLOR_MUTED)
	_add_touch(panel, "CloseButton", Rect2(rect.size.x - 82, 12, 62, 56), "关闭", COLOR_PURPLE)
	return panel


func _build_safe_guide() -> void:
	var guide := Panel.new()
	guide.name = "SafeAreaGuide"
	guide.position = SAFE_RECT.position
	guide.size = SAFE_RECT.size
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0.25, 0.92, 0.72, 0.78)
	style.set_border_width_all(2)
	guide.add_theme_stylebox_override("panel", style)
	add_child(guide)
	_add_label(guide, "SafeAreaLabel", Rect2(994, 2, 220, 24), "Android 安全区边界", 13, Color(0.55, 1.0, 0.82), HORIZONTAL_ALIGNMENT_RIGHT)


func _build_legend() -> void:
	var legend := _add_panel(self, "Legend", Rect2(30, 8, 860, 34), "", Color(0.04, 0.05, 0.07, 0.92))
	var entries := [
		["红：主要战斗", COLOR_RED],
		["金：物品/技能", COLOR_GOLD],
		["蓝：导航", COLOR_BLUE],
		["绿：确认", COLOR_GREEN],
		["紫：系统/状态", COLOR_PURPLE],
	]
	for index in range(entries.size()):
		_add_label(legend, "Legend%d" % index, Rect2(10 + index * 166, 4, 158, 26), entries[index][0], 13, entries[index][1])


func _add_outline(parent: Control, node_name: String, rect: Rect2, border: Color, width: int) -> Panel:
	var outline := Panel.new()
	outline.name = node_name
	outline.position = rect.position
	outline.size = rect.size
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(18)
	outline.add_theme_stylebox_override("panel", style)
	parent.add_child(outline)
	return outline


func _add_touch(parent: Control, node_name: String, rect: Rect2, text_value: String, color: Color) -> Button:
	var button := Button.new()
	button.name = node_name
	button.position = rect.position
	button.size = rect.size
	button.text = text_value
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style(color, color.lightened(0.24), 2, 7))
	button.add_theme_stylebox_override("hover", _style(color.lightened(0.08), Color.WHITE, 2, 7))
	button.add_theme_stylebox_override("pressed", _style(color.darkened(0.15), Color.WHITE, 3, 7))
	button.add_to_group("wireframe_touch_target")
	button.set_meta("wireframe_role", "touch_target")
	parent.add_child(button)
	return button


func _add_panel(parent: Control, node_name: String, rect: Rect2, text_value: String, color: Color) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", _style(color, color.lightened(0.18), 1, 5))
	parent.add_child(panel)
	if not text_value.is_empty():
		var caption_rect := Rect2(8, 8, rect.size.x - 16, 30) if node_name in TOP_CAPTION_NODES else Rect2(8, 8, rect.size.x - 16, rect.size.y - 16)
		_add_label(panel, "Caption", caption_rect, text_value, 16, COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	return panel


func _add_color_rect(parent: Control, node_name: String, rect: Rect2, color: Color) -> ColorRect:
	var block := ColorRect.new()
	block.name = node_name
	block.position = rect.position
	block.size = rect.size
	block.color = color
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(block)
	return block


func _add_label(parent: Control, node_name: String, rect: Rect2, text_value: String, font_size: int, color: Color, horizontal := HORIZONTAL_ALIGNMENT_LEFT, vertical := VERTICAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = rect.position
	label.size = rect.size
	label.text = text_value
	label.horizontal_alignment = horizontal
	label.vertical_alignment = vertical
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _style(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _capture_and_quit() -> void:
	var image := get_viewport().get_texture().get_image()
	var output_dir := ProjectSettings.globalize_path("res://outputs/visual_acceptance/ui_layout_wireframe")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("%s_1280x720.png" % _mode)
	var error := image.save_png(output_path)
	assert(error == OK, "无法保存UI布局线框截图：%s" % output_path)
	print("UI_LAYOUT_WIREFRAME_CAPTURE_PASS mode=%s output=%s" % [_mode, output_path])
	get_tree().quit(0)
