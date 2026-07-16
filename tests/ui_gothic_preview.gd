extends Control

const GOLD := Color("d7b56d")
const GOLD_BRIGHT := Color("f2d797")
const BONE := Color("e8dcc5")
const MUTED := Color("aa9a82")
const RED := Color("9e261f")
const RED_BRIGHT := Color("e64b32")
const DARK := Color("0c0909")
const PANEL := Color("151110e8")
const PANEL_ALT := Color("211918ed")
const IRON := Color("51463d")
const GREEN := Color("47794b")
const BLUE := Color("315b7e")
const FUNCTION_ICON_ATLAS := "res://assets/ui/gothic_preview/icons/hud_function_icon_atlas_v1.png"
const WARRIOR_EFFECT_ROOT := "res://assets/art/characters/warrior/effects"
const WARRIOR_SKILL_FRAME_ROOT := "res://assets/ui/gothic_preview/icons/source_skill_frames"
const BOTTOM_HUD_CHASSIS := "res://assets/ui/gothic_preview/frames/bottom_hud_chassis_runtime_v1.png"
const GOTHIC_SLOT_FRAME := "res://assets/ui/gothic_preview/frames/gothic_slot_frame_runtime_v1.png"
const ROUND_ACTION_FRAME := "res://assets/ui/gothic_preview/frames/round_action_frame_runtime_v2.png"
const HUD_FRAME_GEOMETRY := "res://assets/ui/gothic_preview/frames/gothic_hud_frame_geometry_v2.json"
const HUD_RUNTIME_ICON_ROOT := "res://assets/ui/gothic_preview/icons/runtime_v2"

var preview_mode := "character"
var hud_frame_geometry: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_hud_frame_geometry()
	preview_mode = OS.get_environment("UI_PREVIEW_MODE").strip_edges().to_lower()
	if preview_mode.is_empty():
		preview_mode = "character"
	_build_theme()
	match preview_mode:
		"exit":
			_build_exit_preview()
		"hud":
			_build_hud_preview()
		"skill":
			_build_skill_page_preview()
		_:
			_build_character_preview()
	if OS.get_environment("UI_PREVIEW_CAPTURE") == "1":
		_capture.call_deferred()


func _load_hud_frame_geometry() -> void:
	var source := FileAccess.get_file_as_string(HUD_FRAME_GEOMETRY)
	var parsed = JSON.parse_string(source)
	assert(parsed is Dictionary, "HUD美术框几何清单无法读取")
	hud_frame_geometry = parsed


func _build_theme() -> void:
	var ui_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Noto Sans SC", "Microsoft YaHei"])
	font.font_weight = 500
	ui_theme.default_font = font
	ui_theme.default_font_size = 18
	theme = ui_theme


func _style(bg: Color, border: Color = IRON, width := 1, radius := 5, shadow := 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = width
	box.border_width_top = width
	box.border_width_right = width
	box.border_width_bottom = width
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	if shadow > 0:
		box.shadow_color = Color(0, 0, 0, 0.75)
		box.shadow_size = shadow
		box.shadow_offset = Vector2(0, 4)
	return box


func _panel(parent: Node, rect: Rect2, bg: Color = PANEL, border: Color = IRON, radius := 6, width := 1) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.add_theme_stylebox_override("panel", _style(bg, border, width, radius, 8))
	parent.add_child(node)
	return node


func _label(parent: Node, text: String, rect: Rect2, font_size := 18, color: Color = BONE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.horizontal_alignment = align
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	node.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.96))
	node.add_theme_constant_override("shadow_offset_x", 2)
	node.add_theme_constant_override("shadow_offset_y", 2)
	node.add_theme_constant_override("outline_size", 2 if font_size <= 15 else 1)
	parent.add_child(node)
	return node


func _button(parent: Node, text: String, rect: Rect2, selected := false, danger := false) -> Button:
	var node := Button.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_size_override("font_size", 18)
	node.add_theme_color_override("font_color", GOLD_BRIGHT if selected else BONE)
	node.add_theme_color_override("font_hover_color", Color.WHITE)
	var normal_border := RED if selected else Color("615546")
	var normal_bg := Color("371613e8") if selected else Color("1d1816ed")
	if danger:
		normal_border = Color("8b3027")
		normal_bg = Color("351412f2")
	node.add_theme_stylebox_override("normal", _style(normal_bg, normal_border, 2 if selected else 1, 4))
	node.add_theme_stylebox_override("hover", _style(Color("4a211cf5") if danger else Color("342820f5"), GOLD, 2, 4))
	node.add_theme_stylebox_override("pressed", _style(Color("160d0cf5"), RED_BRIGHT, 2, 4))
	parent.add_child(node)
	return node


func _separator(parent: Node, rect: Rect2) -> void:
	var line := ColorRect.new()
	line.color = Color("765b38a8")
	line.position = rect.position
	line.size = rect.size
	parent.add_child(line)


func _transparent_panel(parent: Node, rect: Rect2, border: Color = IRON, radius := 6, width := 1) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.add_theme_stylebox_override("panel", _style(Color.TRANSPARENT, border, width, radius, 0))
	node.set_meta("background_alpha", 0.0)
	parent.add_child(node)
	return node


func _gothic_line(parent: Node, points: PackedVector2Array, color: Color, width := 2.0) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = color
	line.antialiased = true
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	parent.add_child(line)
	return line


func _decorate_transparent_panel(panel: Panel, accent := GOLD) -> void:
	var w := panel.size.x
	var h := panel.size.y
	_gothic_line(panel, PackedVector2Array([Vector2(2, 18), Vector2(2, 2), Vector2(18, 2)]), accent, 2.0)
	_gothic_line(panel, PackedVector2Array([Vector2(w - 18, 2), Vector2(w - 2, 2), Vector2(w - 2, 18)]), accent, 2.0)
	_gothic_line(panel, PackedVector2Array([Vector2(2, h - 18), Vector2(2, h - 2), Vector2(18, h - 2)]), accent, 2.0)
	_gothic_line(panel, PackedVector2Array([Vector2(w - 18, h - 2), Vector2(w - 2, h - 2), Vector2(w - 2, h - 18)]), accent, 2.0)


func _atlas_region_texture(path: String, region: Rect2) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var texture := AtlasTexture.new()
	texture.atlas = load(path)
	texture.region = region
	return texture


func _function_icon_texture(index: int) -> Texture2D:
	if not ResourceLoader.exists(FUNCTION_ICON_ATLAS):
		return null
	var atlas: Texture2D = load(FUNCTION_ICON_ATLAS)
	var cell := Vector2(float(atlas.get_width()) / 4.0, float(atlas.get_height()) / 4.0)
	var column := index % 4
	var row := int(index / 4)
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(Vector2(column, row) * cell, cell)
	return texture


func _skill_icon_texture(skill_name: String) -> Texture2D:
	match skill_name:
		"刺杀剑术":
			return load("%s/skill_long_hit.png" % HUD_RUNTIME_ICON_ROOT)
		"半月弯刀":
			return load("%s/skill_wide_hit.png" % HUD_RUNTIME_ICON_ROOT)
		"烈火剑法":
			return load("%s/skill_fire_hit.png" % HUD_RUNTIME_ICON_ROOT)
		"野蛮冲撞", "野蛮":
			return load("%s/skill_wild_rush.png" % HUD_RUNTIME_ICON_ROOT)
	return null


func _assign_button_icon(button: Button, texture: Texture2D, max_width: int, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if texture == null:
		return
	button.icon = texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", max_width)
	button.icon_alignment = alignment
	var source_path := texture.resource_path
	if texture is AtlasTexture and (texture as AtlasTexture).atlas != null:
		source_path = (texture as AtlasTexture).atlas.resource_path
	button.set_meta("icon_source", source_path)


func _button_icon_layer(button: Button, texture: Texture2D, rect: Rect2) -> TextureRect:
	if texture == null:
		return null
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = texture
	icon.position = rect.position
	icon.size = rect.size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var source_path := texture.resource_path
	if texture is AtlasTexture and (texture as AtlasTexture).atlas != null:
		source_path = (texture as AtlasTexture).atlas.resource_path
	button.set_meta("icon_source", source_path)
	return icon


func _gothic_slot_frame_layer(parent: Control, rect: Rect2, layer_name := "GothicSlotFrame") -> NinePatchRect:
	var frame := NinePatchRect.new()
	frame.name = layer_name
	frame.texture = load(GOTHIC_SLOT_FRAME)
	frame.position = rect.position
	frame.size = rect.size
	frame.patch_margin_left = 18
	frame.patch_margin_top = 18
	frame.patch_margin_right = 18
	frame.patch_margin_bottom = 18
	frame.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_meta("frame_source", GOTHIC_SLOT_FRAME)
	parent.add_child(frame)
	return frame


func _texture_frame_layer(parent: Control, texture_path: String, rect: Rect2, layer_name: String) -> TextureRect:
	var frame := TextureRect.new()
	frame.name = layer_name
	frame.texture = load(texture_path)
	frame.position = rect.position
	frame.size = rect.size
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.z_index = 5
	frame.set_meta("frame_source", texture_path)
	parent.add_child(frame)
	return frame


func _round_action_frame_layer(parent: Control, rect: Rect2, layer_name := "RoundActionFrame") -> TextureRect:
	var fill_rect := _round_frame_content_rect(rect, 1.04)
	var fill := _panel(parent, fill_rect, Color("0b0808f2"), Color.TRANSPARENT, int(fill_rect.size.x * 0.5), 0)
	fill.name = "%sFill" % layer_name
	fill.z_index = -1
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return _texture_frame_layer(parent, ROUND_ACTION_FRAME, rect, layer_name)


func _square_slot_frame_layer(parent: Control, rect: Rect2) -> TextureRect:
	return _texture_frame_layer(parent, GOTHIC_SLOT_FRAME, rect, "GothicSquareFrame")


func _scaled_hole_rect(frame_rect: Rect2, geometry_section: Dictionary, padding_scale := 0.92) -> Rect2:
	var source_size_array: Array = geometry_section.get("size", [1, 1])
	var hole: Dictionary = geometry_section.get("hole", {})
	var circle: Dictionary = hole.get("inscribedCircle", {})
	var center_array: Array = circle.get("center", [0, 0])
	var source_size := Vector2(float(source_size_array[0]), float(source_size_array[1]))
	var scale := frame_rect.size / source_size
	var center := frame_rect.position + Vector2(float(center_array[0]) * scale.x, float(center_array[1]) * scale.y)
	var radius := float(circle.get("radius", 0.0)) * minf(scale.x, scale.y) * padding_scale
	return Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))


func _round_frame_content_rect(frame_rect: Rect2, padding_scale := 0.92) -> Rect2:
	return _scaled_hole_rect(frame_rect, hud_frame_geometry.get("roundActionFrame", {}), padding_scale)


func _square_frame_content_rect(frame_rect: Rect2, padding_scale := 0.90) -> Rect2:
	return _scaled_hole_rect(frame_rect, hud_frame_geometry.get("squareSlotFrame", {}), padding_scale)


func _chassis_orb_rect(chassis_rect: Rect2, hole_key: String) -> Rect2:
	var chassis_geometry: Dictionary = hud_frame_geometry.get("bottomChassis", {})
	var source_size_array: Array = chassis_geometry.get("size", [1, 1])
	var source_size := Vector2(float(source_size_array[0]), float(source_size_array[1]))
	var scale := chassis_rect.size / source_size
	var circle: Dictionary = chassis_geometry.get(hole_key, {})
	var center_array: Array = circle.get("center", [0, 0])
	var center := chassis_rect.position + Vector2(float(center_array[0]) * scale.x, float(center_array[1]) * scale.y)
	var radius := float(circle.get("radius", 0.0)) * minf(scale.x, scale.y)
	return Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))


func _bottom_hud_chassis(parent: Node, rect: Rect2) -> TextureRect:
	var chassis := TextureRect.new()
	chassis.name = "BottomHudChassis"
	chassis.texture = load(BOTTOM_HUD_CHASSIS)
	chassis.position = rect.position
	chassis.size = rect.size
	chassis.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chassis.stretch_mode = TextureRect.STRETCH_SCALE
	chassis.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	chassis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chassis.add_to_group("gothic_bottom_hud_chassis")
	chassis.set_meta("frame_source", BOTTOM_HUD_CHASSIS)
	chassis.set_meta("central_outer_box", false)
	parent.add_child(chassis)
	return chassis


func _background(parent: Node, path: String, shade := 0.0) -> void:
	var texture_rect := TextureRect.new()
	texture_rect.texture = load(path)
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(texture_rect)
	if shade > 0.0:
		var overlay := ColorRect.new()
		overlay.color = Color(0.025, 0.012, 0.01, shade)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(overlay)


func _ornament_header(parent: Node, text: String, rect: Rect2, subtitle := "") -> void:
	_label(parent, "◆", Rect2(rect.position.x, rect.position.y, 28, rect.size.y), 18, RED_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(parent, text, Rect2(rect.position.x + 32, rect.position.y, rect.size.x - 64, rect.size.y), 28, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(parent, "◆", Rect2(rect.end.x - 28, rect.position.y, 28, rect.size.y), 18, RED_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	if not subtitle.is_empty():
		_label(parent, subtitle, Rect2(rect.position.x, rect.end.y - 2, rect.size.x, 26), 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER)


func _character_layer(parent: Node, path: String, rect: Rect2, region := Rect2(28, 640, 140, 160)) -> void:
	if not ResourceLoader.exists(path):
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path)
	atlas.region = region
	var sprite := TextureRect.new()
	sprite.texture = atlas
	sprite.position = rect.position
	sprite.size = rect.size
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sprite)


func _build_character_preview() -> void:
	_background(self, "res://assets/ui/gothic_preview/character_hall.png")
	var top_shade := ColorRect.new()
	top_shade.color = Color("080606b8")
	top_shade.position = Vector2.ZERO
	top_shade.size = Vector2(1280, 92)
	add_child(top_shade)
	_label(self, "人物殿堂", Rect2(48, 18, 300, 46), 34, GOLD_BRIGHT)
	_label(self, "选择传承，或在此铸造新的命运", Rect2(50, 57, 360, 24), 14, MUTED)
	_label(self, "玛法纪元 · 本地档案", Rect2(930, 24, 300, 34), 15, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_separator(self, Rect2(48, 87, 1184, 1))

	var roster := _panel(self, Rect2(38, 112, 304, 538), Color("100d0ce8"), Color("6c5539"), 8, 2)
	_ornament_header(roster, "已有角色", Rect2(22, 14, 260, 40), "2 / 6 个角色")
	_separator(roster, Rect2(22, 76, 260, 1))
	var card1 := _panel(roster, Rect2(16, 94, 272, 118), Color("371814eb"), RED, 5, 2)
	_label(card1, "北辰", Rect2(72, 12, 126, 30), 23, GOLD_BRIGHT)
	_label(card1, "Lv.26  战士", Rect2(72, 42, 150, 24), 15, BONE)
	_label(card1, "比奇城 · 安全区", Rect2(72, 70, 176, 22), 13, MUTED)
	var medal1 := _panel(card1, Rect2(14, 18, 46, 46), Color("2b1110"), RED_BRIGHT, 23, 2)
	_label(medal1, "战", Rect2(0, 0, 46, 46), 22, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(card1, "已选中", Rect2(198, 14, 60, 24), 12, RED_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	var card2 := _panel(roster, Rect2(16, 224, 272, 102), Color("181514df"), Color("4b443d"), 5, 1)
	_label(card2, "青灯", Rect2(72, 10, 126, 30), 21, BONE)
	_label(card2, "Lv.18  道士", Rect2(72, 40, 150, 24), 14, MUTED)
	_label(card2, "盟重省", Rect2(72, 66, 176, 20), 13, MUTED)
	var medal2 := _panel(card2, Rect2(14, 18, 46, 46), Color("161c18"), Color("66705d"), 23, 1)
	_label(medal2, "道", Rect2(0, 0, 46, 46), 22, Color("b7c49c"), HORIZONTAL_ALIGNMENT_CENTER)
	_button(roster, "＋ 创建新角色", Rect2(16, 344, 272, 58), false)
	_label(roster, "角色资料独立保存\n切换角色不会覆盖当前进度", Rect2(24, 420, 256, 64), 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER)

	# The character preview deliberately uses the same composited runtime layers as the game.
	_character_layer(self, "res://assets/art/characters/warrior/male/warrior_idle.png", Rect2(430, 184, 340, 392))
	_character_layer(self, "res://assets/art/characters/warrior/wear/helmet/black_iron_helmet_idle.png", Rect2(430, 184, 340, 392))
	_character_layer(self, "res://assets/art/characters/warrior/wear/weapon/weapon_042_idle.png", Rect2(430, 184, 340, 392))
	var name_plate := _panel(self, Rect2(436, 540, 328, 64), Color("0e0a09df"), Color("8a693e"), 3, 1)
	_label(name_plate, "北 辰", Rect2(0, 4, 328, 30), 24, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(name_plate, "战士 · 等级 26 · 战力 1847", Rect2(0, 31, 328, 24), 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_button(self, "进入玛法", Rect2(472, 620, 256, 58), true)

	var create := _panel(self, Rect2(884, 112, 358, 566), Color("100d0cef"), Color("6c5539"), 8, 2)
	_ornament_header(create, "创建人物", Rect2(24, 12, 310, 42), "人物选择与创建位于同一界面")
	_separator(create, Rect2(22, 76, 314, 1))
	_label(create, "角色名称", Rect2(24, 90, 116, 26), 14, MUTED)
	var input_panel := _panel(create, Rect2(24, 118, 310, 52), Color("090707ed"), Color("655744"), 4, 1)
	_label(input_panel, "请输入角色名称", Rect2(14, 0, 270, 52), 16, Color("756c61"))
	_label(create, "性别", Rect2(24, 180, 80, 26), 14, MUTED)
	_button(create, "男", Rect2(24, 210, 148, 48), true)
	_button(create, "女", Rect2(186, 210, 148, 48), false)
	_label(create, "选择职业", Rect2(24, 270, 100, 26), 14, MUTED)
	var class_names := ["战士", "法师", "道士"]
	var class_glyphs := ["战", "法", "道"]
	var class_notes := ["近战 · 爆发", "远程 · 群攻", "召唤 · 辅助"]
	for index in range(3):
		var x := 24 + index * 104
		var selected := index == 0
		var class_card := _panel(create, Rect2(x, 302, 94, 112), Color("351613eb") if selected else Color("171413e8"), RED if selected else Color("50483f"), 5, 2 if selected else 1)
		var class_medal := _panel(class_card, Rect2(24, 10, 46, 46), Color("27100f") if selected else Color("12100f"), RED_BRIGHT if selected else Color("665e52"), 23, 1)
		_label(class_medal, class_glyphs[index], Rect2(0, 0, 46, 46), 21, GOLD_BRIGHT if selected else BONE, HORIZONTAL_ALIGNMENT_CENTER)
		_label(class_card, class_names[index], Rect2(0, 58, 94, 25), 16, GOLD_BRIGHT if selected else BONE, HORIZONTAL_ALIGNMENT_CENTER)
		_label(class_card, class_notes[index], Rect2(0, 83, 94, 20), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label(create, "职业将在创建后决定初始技能与成长路线", Rect2(24, 424, 310, 30), 12, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_button(create, "创建角色", Rect2(24, 466, 310, 60), true)


func _build_exit_preview() -> void:
	_background(self, "res://assets/ui/gothic_preview/world_scene_reference.png", 0.58)
	var vignette := ColorRect.new()
	vignette.color = Color("05030370")
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vignette)
	var modal := _panel(self, Rect2(390, 76, 500, 578), Color("100c0bfd"), Color("8b6b42"), 10, 2)
	var crest := _panel(modal, Rect2(216, -28, 68, 68), Color("28100ffb"), RED, 34, 2)
	_label(crest, "◆", Rect2(0, 0, 68, 68), 28, RED_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_ornament_header(modal, "暂离玛法", Rect2(54, 50, 392, 48), "游戏已经暂停")
	_separator(modal, Rect2(54, 120, 392, 1))
	var status := _panel(modal, Rect2(72, 140, 356, 58), Color("111713e8"), Color("445b43"), 4, 1)
	_label(status, "✓  角色数据已自动保存", Rect2(0, 0, 356, 58), 15, Color("b8caa9"), HORIZONTAL_ALIGNMENT_CENTER)
	_button(modal, "继续游戏", Rect2(72, 220, 356, 60), true)
	_button(modal, "返回人物选择", Rect2(72, 294, 356, 60), false)
	_button(modal, "安全退出游戏", Rect2(72, 368, 356, 60), false, true)
	_separator(modal, Rect2(90, 452, 320, 1))
	_label(modal, "退出后角色将返回最近城镇安全区", Rect2(50, 468, 400, 28), 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_label(modal, "ESC / Android 返回键：关闭此菜单", Rect2(50, 504, 400, 26), 12, Color("71685e"), HORIZONTAL_ALIGNMENT_CENTER)
	_label(self, "退出界面视觉样板 · 游戏画面保持实时可见", Rect2(24, 674, 520, 28), 12, MUTED)


func _bar(parent: Node, rect: Rect2, ratio: float, fill: Color, caption: String) -> void:
	var frame := _panel(parent, rect, Color("080707e8"), Color("594a3d"), 3, 1)
	var inset := ColorRect.new()
	inset.color = fill
	inset.position = Vector2(3, 3)
	inset.size = Vector2((rect.size.x - 6) * clampf(ratio, 0.0, 1.0), rect.size.y - 6)
	frame.add_child(inset)
	_label(frame, caption, Rect2(0, 0, rect.size.x, rect.size.y), 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)


func _round_button(parent: Node, text: String, rect: Rect2, selected := false) -> void:
	var p := _panel(parent, rect, Color("401714ed") if selected else Color("171312e8"), RED_BRIGHT if selected else Color("6a5a49"), int(rect.size.x / 2.0), 2)
	_label(p, text, Rect2(0, 0, rect.size.x, rect.size.y), 17 if text.length() > 1 else 25, GOLD_BRIGHT if selected else BONE, HORIZONTAL_ALIGNMENT_CENTER)


func _apply_warrior_skill_toggle_style(button: Button, skill_name: String, enabled: bool) -> void:
	button.text = ""
	button.set_meta("state_caption", "自动：%s" % ("开" if enabled else "关"))
	button.add_theme_color_override("font_color", GOLD_BRIGHT if enabled else Color("b5aa9a"))
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	button.add_theme_stylebox_override("hover", _style(Color("681d1738"), Color.TRANSPARENT, 0, 0))
	button.add_theme_stylebox_override("pressed", _style(Color("8a201a50"), Color.TRANSPARENT, 0, 0))
	button.add_theme_stylebox_override("hover_pressed", _style(Color("8a201a62"), Color.TRANSPARENT, 0, 0))
	var frame := button.get_node_or_null("GothicSlotFrame") as NinePatchRect
	if frame != null:
		frame.modulate = Color("fff3d7") if enabled else Color("9f9a92")
	var name_label := button.get_node_or_null("SkillName") as Label
	if name_label != null:
		name_label.text = skill_name
		name_label.add_theme_color_override("font_color", GOLD_BRIGHT if enabled else Color("b5aa9a"))
	var state_label := button.get_node_or_null("SkillState") as Label
	if state_label != null:
		state_label.text = "自动：%s" % ("开" if enabled else "关")
		state_label.add_theme_color_override("font_color", RED_BRIGHT if enabled else MUTED)


func _on_warrior_skill_toggled(enabled: bool, button: Button, skill_name: String) -> void:
	_apply_warrior_skill_toggle_style(button, skill_name, enabled)


func _warrior_skill_toggle(parent: Node, skill_name: String, rect: Rect2, enabled: bool) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.toggle_mode = true
	button.button_pressed = enabled
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = true
	button.add_theme_font_size_override("font_size", 14)
	button.add_to_group("warrior_auto_skill_toggle")
	button.set_meta("skill_name", skill_name)
	button.set_meta("control_mode", "toggle_auto_use")
	button.set_meta("opaque_cell", true)
	button.set_meta("icon_frame_policy", "generated_frame_with_runtime_skill_texture")
	parent.add_child(button)
	_gothic_slot_frame_layer(button, Rect2(Vector2.ZERO, rect.size))
	var icon_frame_size := minf(rect.size.y, 58.0)
	var icon_frame_rect := Rect2(1, (rect.size.y - icon_frame_size) * 0.5, icon_frame_size, icon_frame_size)
	_round_action_frame_layer(button, icon_frame_rect, "SkillIconFrame")
	var icon_rect := _round_frame_content_rect(icon_frame_rect, 0.94)
	_button_icon_layer(button, _skill_icon_texture(skill_name), icon_rect)
	button.set_meta("icon_content_rect", icon_rect)
	var text_x := icon_frame_size + 1.0
	var name_label := _label(button, skill_name, Rect2(text_x, 5, rect.size.x - text_x - 4, 24), 12, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.name = "SkillName"
	var state_label := _label(button, "自动：%s" % ("开" if enabled else "关"), Rect2(text_x, 29, rect.size.x - text_x - 4, 20), 10, RED_BRIGHT if enabled else MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	state_label.name = "SkillState"
	_apply_warrior_skill_toggle_style(button, skill_name, enabled)
	button.toggled.connect(_on_warrior_skill_toggled.bind(button, skill_name))
	return button


func _apply_cast_selection_style(button: Button, skill_name: String, selected: bool) -> void:
	button.text = "%s\n%s" % [skill_name, "当前攻击" if selected else "点击选择"]
	button.add_theme_color_override("font_color", GOLD_BRIGHT if selected else BONE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(Color("321311f2") if selected else Color("12100fef"), RED if selected else Color("51483e"), 2 if selected else 1, 5))
	button.add_theme_stylebox_override("pressed", _style(Color("4b1713f8"), RED_BRIGHT, 2, 5))


func _on_cast_skill_selected(enabled: bool, button: Button, skill_name: String) -> void:
	if not enabled:
		return
	for peer: Button in button.button_group.get_buttons():
		if peer is Button:
			_apply_cast_selection_style(peer, str(peer.get_meta("skill_name", "普通攻击")), peer == button)
	button.set_meta("selected_attack_action", skill_name)


func _cast_selection_button(parent: Node, group: ButtonGroup, skill_name: String, rect: Rect2, selected: bool) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = selected
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	button.add_to_group("selected_attack_skill")
	button.set_meta("skill_name", skill_name)
	button.set_meta("control_mode", "select_attack_cast")
	_apply_cast_selection_style(button, skill_name, selected)
	button.toggled.connect(_on_cast_skill_selected.bind(button, skill_name))
	parent.add_child(button)
	return button


func _build_profession_skill_deck(parent: Node, profession: String) -> void:
	var entries: Array[Dictionary] = []
	if profession == "战士":
		# 被动技能不占HUD；野蛮冲撞在攻击键旁作为一次性动作。
		entries = [
			{"name": "刺杀剑术", "mode": "toggle", "enabled": true},
			{"name": "半月弯刀", "mode": "toggle", "enabled": true},
			{"name": "烈火剑法", "mode": "toggle", "enabled": false},
		]
	else:
		# 法师/道士共用相同布局，但使用互斥选择；攻击键施放当前选择，普通攻击也是一个技能项。
		var skills: Array[String] = ["普通攻击"]
		if profession == "法师":
			skills.append_array(["火球术", "雷电术", "大火球", "爆裂火焰", "火墙", "魔法盾"])
		else:
			skills.append_array(["治愈术", "施毒术", "灵魂火符", "召唤骷髅", "隐身术", "幽灵盾"])
		for index in range(skills.size()):
			entries.append({"name": skills[index], "mode": "select", "selected": index == 0})
	var selection_group := ButtonGroup.new()
	selection_group.allow_unpress = false
	var deck_control := parent as Control
	var compact := deck_control.size.y <= 84.0
	var button_width := 128.0 if compact else 138.0
	var button_height := 52.0 if compact else 58.0
	var column_stride := button_width + 8.0
	var first_row_y := 26.0 if compact else 30.0
	for index in range(entries.size()):
		var row := int(index / 4)
		var column := index % 4
		var remaining := entries.size() - row * 4
		var count_in_row := mini(4, remaining)
		var row_width := float(count_in_row) * button_width + float(maxi(0, count_in_row - 1)) * 8.0
		var start_x := (deck_control.size.x - row_width) * 0.5
		var rect := Rect2(start_x + float(column) * column_stride, first_row_y + float(row) * 60.0, button_width, button_height)
		var entry: Dictionary = entries[index]
		if str(entry.get("mode", "")) == "toggle":
			_warrior_skill_toggle(parent, str(entry.get("name", "")), rect, bool(entry.get("enabled", false)))
		else:
			_cast_selection_button(parent, selection_group, str(entry.get("name", "")), rect, bool(entry.get("selected", false)))


func _apply_auto_lock_style(button: Button, enabled: bool) -> void:
	button.text = "自动锁定：%s" % ("开" if enabled else "关")
	button.add_theme_color_override("font_color", GOLD_BRIGHT if enabled else MUTED)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(Color("321311f2") if enabled else Color("12100fef"), RED if enabled else Color("51483e"), 2 if enabled else 1, 4))
	button.add_theme_stylebox_override("pressed", _style(Color("4b1713f8"), RED_BRIGHT, 2, 4))


func _on_auto_lock_toggled(enabled: bool, button: Button) -> void:
	_apply_auto_lock_style(button, enabled)


func _auto_lock_button(parent: Node, rect: Rect2, enabled: bool) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.toggle_mode = true
	button.button_pressed = enabled
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	button.set_meta("control_mode", "toggle_auto_target_lock")
	_apply_auto_lock_style(button, enabled)
	_assign_button_icon(button, _function_icon_texture(7), 26)
	button.toggled.connect(_on_auto_lock_toggled.bind(button))
	parent.add_child(button)
	return button


func _combat_action_caption(profession: String) -> String:
	return "攻击" if profession == "战士" else "释放技能"


func _combat_action_button(parent: Node, profession: String, rect: Rect2) -> Button:
	var button := Button.new()
	var caption := _combat_action_caption(profession)
	button.text = ""
	button.position = rect.position
	button.size = rect.size
	button.clip_contents = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20 if profession == "战士" else 16)
	button.add_theme_color_override("font_color", GOLD_BRIGHT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	button.add_theme_stylebox_override("hover", _style(Color("7a1e1838"), Color.TRANSPARENT, 0, 0))
	button.add_theme_stylebox_override("pressed", _style(Color("a0261e58"), Color.TRANSPARENT, 0, 0))
	button.set_meta("combat_action", "basic_attack" if profession == "战士" else "cast_selected_skill")
	button.set_meta("caption", caption)
	parent.add_child(button)
	var frame_rect := Rect2(Vector2.ZERO, rect.size)
	_round_action_frame_layer(button, frame_rect)
	var icon_rect := _round_frame_content_rect(frame_rect, 0.88)
	_button_icon_layer(button, load("%s/function_attack.png" % HUD_RUNTIME_ICON_ROOT), icon_rect)
	button.set_meta("icon_frame_policy", "generated_frame_with_replaceable_runtime_icon")
	button.set_meta("icon_content_rect", icon_rect)
	var caption_label := _label(button, caption, Rect2(0, rect.size.y - 30, rect.size.x, 24), 18 if profession == "战士" else 14, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	caption_label.z_index = 10
	return button


func _interaction_button(parent: Node, rect: Rect2) -> Button:
	var button := _button(parent, "交互", rect, false)
	button.name = "InteractionButton"
	button.toggle_mode = false
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", GOLD_BRIGHT)
	button.add_theme_stylebox_override("normal", _style(Color("17120ff2"), Color("8b6b42"), 2, 8))
	button.add_theme_stylebox_override("hover", _style(Color("2d211af8"), GOLD_BRIGHT, 2, 8))
	button.add_theme_stylebox_override("pressed", _style(Color("32100df8"), RED_BRIGHT, 2, 8))
	button.set_meta("combat_control", "interact_only")
	button.set_meta("interaction_action", "interact_nearest")
	button.set_meta("occupies_skill_slot", false)
	_assign_button_icon(button, _function_icon_texture(5), 26)
	return button


func _instant_skill_button(parent: Node, skill_name: String, rect: Rect2) -> Button:
	var button := _button(parent, skill_name, rect, true)
	button.toggle_mode = false
	button.add_theme_font_size_override("font_size", 13)
	button.set_meta("combat_control", "instant_skill")
	button.set_meta("skill_name", skill_name)
	button.set_meta("activation", "press_once")
	return button


func _profession_uses_skill_toggles(profession: String) -> bool:
	return profession == "战士"


func _quick_skill_button(parent: Node, slot_index: int, skill_name: String, rect: Rect2, selected := false, profession := "战士") -> Button:
	var button := Button.new()
	button.text = ""
	button.position = rect.position
	button.size = rect.size
	button.clip_contents = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", GOLD_BRIGHT if selected else BONE)
	button.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	button.add_theme_stylebox_override("hover", _style(Color("641b1740"), Color.TRANSPARENT, 0, 0))
	button.add_theme_stylebox_override("pressed", _style(Color("7e1f195c"), Color.TRANSPARENT, 0, 0))
	button.add_to_group("combat_skill_slot")
	button.set_meta("slot_index", slot_index)
	button.set_meta("skill_name", skill_name)
	button.set_meta("tap_action", "instant_use_skill" if profession == "战士" else "select_cast_skill")
	button.set_meta("long_press_action", "open_skill_page")
	button.set_meta("long_press_seconds", 0.55)
	button.set_meta("opaque_cell", true)
	button.set_meta("icon_frame_policy", "generated_frame_with_replaceable_runtime_icon")
	parent.add_child(button)
	_round_action_frame_layer(button, Rect2(Vector2.ZERO, rect.size))
	_set_quick_skill_content(button, skill_name)
	var slot_label := _label(button, str(slot_index + 1), Rect2(5, 1, 15, 14), 8, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	slot_label.z_index = 10
	return button


func _set_quick_skill_content(button: Button, skill_name: String) -> void:
	button.set_meta("skill_name", skill_name)
	var old_icon := button.get_node_or_null("Icon")
	if old_icon != null:
		old_icon.free()
	var texture := _skill_icon_texture(skill_name) if not skill_name.is_empty() else load("%s/function_empty_skill.png" % HUD_RUNTIME_ICON_ROOT)
	var icon_rect := _round_frame_content_rect(Rect2(Vector2.ZERO, button.size), 0.94)
	_button_icon_layer(button, texture, icon_rect)
	button.set_meta("icon_content_rect", icon_rect)
	button.set_meta("dynamic_icon_updates_with_skill", true)


func _resource_orb(parent: Node, rect: Rect2, is_health: bool, current: int, maximum: int) -> Panel:
	var outer := _transparent_panel(parent, rect, Color.TRANSPARENT, int(rect.size.x / 2.0), 0)
	outer.name = "HealthOrb" if is_health else "ManaOrb"
	outer.add_to_group("player_resource_orb")
	outer.set_meta("resource_type", "health" if is_health else "mana")
	outer.set_meta("ornamental_frame_source", BOTTOM_HUD_CHASSIS)
	outer.set_meta("geometry_policy", "opencv_alpha_hole_center_radius")
	var liquid_color := Color("9e201c") if is_health else Color("194f86")
	var liquid_border := Color("e54c36") if is_health else Color("428bc4")
	var liquid := _panel(outer, Rect2(Vector2.ZERO, rect.size), liquid_color, liquid_border, int(rect.size.x / 2.0), 1)
	outer.set_meta("liquid_radius", rect.size.x * 0.5)
	var shine := _panel(liquid, Rect2(18, 13, 28, 18), Color(1, 0.78, 0.66, 0.18) if is_health else Color(0.65, 0.84, 1.0, 0.22), Color.TRANSPARENT, 12, 0)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label(liquid, str(current), Rect2(0, 25, liquid.size.x, 30), 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_label(outer, "生命" if is_health else "魔法", Rect2(0, rect.size.y - 26, rect.size.x, 20), 11, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(parent, "%d / %d" % [current, maximum], Rect2(rect.position.x - 8, rect.end.y + 1, rect.size.x + 16, 18), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	return outer


func _combat_item_slot(parent: Node, rect: Rect2, slot_index: int, item_name: String, item_path: String, amount: int) -> Button:
	var slot := Button.new()
	slot.position = rect.position
	slot.size = rect.size
	slot.clip_contents = true
	slot.focus_mode = Control.FOCUS_NONE
	slot.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	slot.add_theme_stylebox_override("hover", _style(Color("5d201a38"), Color.TRANSPARENT, 0, 0))
	slot.add_theme_stylebox_override("pressed", _style(Color("80251d58"), Color.TRANSPARENT, 0, 0))
	slot.add_to_group("combat_item_slot")
	slot.set_meta("slot_index", slot_index)
	slot.set_meta("item_name", item_name)
	slot.set_meta("tap_action", "use_item")
	slot.set_meta("long_press_action", "open_item_picker")
	slot.set_meta("long_press_seconds", 0.55)
	slot.set_meta("opaque_cell", true)
	slot.set_meta("slot_frame_source", GOTHIC_SLOT_FRAME)
	parent.add_child(slot)
	var frame_rect := Rect2(Vector2.ZERO, rect.size)
	_square_slot_frame_layer(slot, frame_rect)
	var content_rect := _square_frame_content_rect(frame_rect, 0.90)
	slot.set_meta("icon_content_rect", content_rect)
	var slot_index_label := _label(slot, str(slot_index + 1), Rect2(4, 1, 18, 18), 10, GOLD)
	slot_index_label.z_index = 10
	if ResourceLoader.exists(item_path):
		var icon := TextureRect.new()
		icon.name = "ItemIcon"
		icon.texture = load(item_path)
		icon.position = content_rect.position
		icon.size = content_rect.size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
	var amount_label := _label(slot, str(amount), Rect2(rect.size.x - 30, rect.size.y - 21, 25, 17), 10, BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	amount_label.z_index = 10
	var press_timer := Timer.new()
	press_timer.one_shot = true
	press_timer.wait_time = 0.55
	slot.add_child(press_timer)
	slot.button_down.connect(press_timer.start)
	slot.button_up.connect(_on_combat_item_slot_released.bind(slot, press_timer))
	press_timer.timeout.connect(_open_item_picker.bind(slot))
	return slot


func _on_combat_item_slot_released(slot: Button, press_timer: Timer) -> void:
	if press_timer.time_left <= 0.0:
		return
	press_timer.stop()
	_use_combat_item_slot(slot)


func _use_combat_item_slot(slot: Button) -> void:
	slot.set_meta("last_action", "use_item:%s" % str(slot.get_meta("item_name", "")))


func _open_item_picker(slot: Button) -> void:
	var previous := get_node_or_null("ItemPickerPreview")
	if previous != null:
		previous.queue_free()
	var picker := _panel(self, Rect2(382, 330, 516, 138), Color("100c0bfd"), Color("8b6b42"), 7, 2)
	picker.name = "ItemPickerPreview"
	picker.set_meta("target_slot", int(slot.get_meta("slot_index", 0)))
	_label(picker, "选择战斗物品", Rect2(16, 8, 484, 26), 16, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	var options := ["金创药", "魔法药", "回城卷", "随机传送卷"]
	for index in range(options.size()):
		var option := _button(picker, options[index], Rect2(14 + index * 123, 48, 112, 62), index == int(slot.get_meta("slot_index", 0)))
		option.add_theme_font_size_override("font_size", 13)
		option.set_meta("picker_item", options[index])
		option.pressed.connect(_choose_combat_item.bind(slot, options[index], picker))


func _choose_combat_item(slot: Button, item_name: String, picker: Panel) -> void:
	slot.set_meta("item_name", item_name)
	slot.set_meta("last_action", "select_item:%s" % item_name)
	picker.queue_free()


func _build_hud_preview() -> void:
	_background(self, "res://assets/ui/gothic_preview/world_scene_clean.png", 0.08)

	var target := _transparent_panel(self, Rect2(470, 14, 340, 58), Color("80633f"), 5, 1)
	target.set_meta("panel_role", "monster_target")
	_decorate_transparent_panel(target, Color("80633f"))
	_label(target, "半兽勇士", Rect2(16, 4, 160, 22), 15, BONE)
	_label(target, "Lv.18", Rect2(260, 4, 64, 22), 11, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_bar(target, Rect2(16, 31, 308, 14), 0.43, Color("8d2922"), "43%")

	var map := _transparent_panel(self, Rect2(1010, 14, 252, 92), Color("80633f"), 6, 2)
	map.set_meta("panel_role", "map_summary")
	_decorate_transparent_panel(map, GOLD)
	_label(map, "比奇城", Rect2(14, 8, 116, 24), 18, GOLD_BRIGHT)
	_label(map, "安全区域", Rect2(134, 8, 100, 22), 12, Color("9dc096"), HORIZONTAL_ALIGNMENT_RIGHT)
	_label(map, "坐标  332, 268", Rect2(14, 35, 150, 22), 12, MUTED)
	_label(map, "☼  19:42", Rect2(164, 35, 72, 22), 12, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var map_button := _button(map, "地图", Rect2(14, 62, 108, 24), false)
	map_button.add_theme_font_size_override("font_size", 13)
	_assign_button_icon(map_button, _function_icon_texture(13), 18)
	var menu_button := _button(map, "菜单", Rect2(130, 62, 108, 24), false)
	menu_button.add_theme_font_size_override("font_size", 13)
	_assign_button_icon(menu_button, _function_icon_texture(14), 18)

	_auto_lock_button(self, Rect2(1138, 132, 124, 50), true)

	var notice := _transparent_panel(self, Rect2(450, 470, 400, 26), Color("6d5336"), 4, 1)
	notice.set_meta("panel_role", "loot_notice")
	_gothic_line(notice, PackedVector2Array([Vector2(4, 13), Vector2(72, 13), Vector2(82, 6)]), Color("80633f"), 1.5)
	_gothic_line(notice, PackedVector2Array([Vector2(396, 13), Vector2(328, 13), Vector2(318, 6)]), Color("80633f"), 1.5)
	_label(notice, "◆  获得：强效金创药 × 1  ◆", Rect2(0, 0, 400, 26), 12, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)

	# Left mobile movement control.
	var joystick := _panel(self, Rect2(26, 592, 112, 112), Color("0b0908a8"), Color("6b5c4a"), 56, 2)
	var joystick_inner := _panel(joystick, Rect2(32, 32, 48, 48), Color("33251fdc"), GOLD, 24, 1)
	_label(joystick_inner, "◆", Rect2(0, 0, 48, 48), 14, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)

	var chassis_rect := Rect2(180, 520, 840, 180)
	_bottom_hud_chassis(self, chassis_rect)
	_resource_orb(self, _chassis_orb_rect(chassis_rect, "healthHole"), true, 936, 1200)
	_resource_orb(self, _chassis_orb_rect(chassis_rect, "manaHole"), false, 248, 400)
	if _profession_uses_skill_toggles("战士"):
		var skill_deck := _transparent_panel(self, Rect2(356, 510, 488, 90), Color.TRANSPARENT, 0, 0)
		skill_deck.set_meta("control_mode", "profession_skill_deck")
		skill_deck.set_meta("container_policy", "fully_transparent")
		_label(skill_deck, "◆  战士技能 · 自动开关  ◆", Rect2(12, 1, 464, 22), 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		_build_profession_skill_deck(skill_deck, "战士")
	var item_deck := _transparent_panel(self, Rect2(374, 608, 452, 94), Color.TRANSPARENT, 0, 0)
	item_deck.set_meta("control_mode", "combat_item_deck")
	item_deck.set_meta("container_policy", "fully_transparent")
	_label(item_deck, "◆  战斗物品  ◆", Rect2(12, 0, 428, 20), 10, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var item_names := ["金创药", "魔法药", "回城卷", "随机传送卷"]
	var item_paths := [
		"res://assets/art/items/service/inventory/client.classic_raw_complete/Items_00398.png",
		"res://assets/art/items/service/inventory/client.classic_raw_complete/Items_00394.png",
		"res://assets/art/items/service/inventory/client.classic_raw_complete/Items_00402.png",
		"res://assets/art/items/service/inventory/client.classic_raw_complete/Items_00404.png",
	]
	var item_amounts := [18, 16, 3, 5]
	var item_size := 74.0
	var item_gap := 8.0
	var items_width := item_size * 4.0 + item_gap * 3.0
	var item_start_x := (item_deck.size.x - items_width) * 0.5
	for index in range(4):
		_combat_item_slot(item_deck, Rect2(item_start_x + index * (item_size + item_gap), 20, item_size, item_size), index, item_names[index], item_paths[index], item_amounts[index])
	_quick_skill_button(self, 0, "野蛮", Rect2(1068, 492, 72, 72), true, "战士")
	_quick_skill_button(self, 1, "", Rect2(1014, 574, 72, 72), false, "战士")
	_quick_skill_button(self, 2, "", Rect2(1068, 648, 72, 72), false, "战士")
	var switch_target_button := _button(self, "切换敌人", Rect2(1162, 532, 98, 46), false)
	switch_target_button.add_theme_font_size_override("font_size", 12)
	switch_target_button.set_meta("combat_control", "switch_target")
	_assign_button_icon(switch_target_button, _function_icon_texture(6), 24)
	_combat_action_button(self, "战士", Rect2(1162, 594, 98, 98))
	_interaction_button(self, Rect2(1180, 466, 80, 54))


func _skill_catalog_button(parent: Node, skill_name: String, level: int, kind: String, rect: Rect2, selected := false) -> Button:
	var button := _button(parent, "%s\nLv.%d  ·  %s" % [skill_name, level, kind], rect, selected)
	button.add_theme_font_size_override("font_size", 14)
	button.set_meta("skill_name", skill_name)
	button.set_meta("skill_level", level)
	button.set_meta("skill_kind", kind)
	button.set_meta("long_press_action", "choose_quick_skill_slot")
	button.set_meta("long_press_seconds", 0.55)
	button.add_to_group("skill_catalog_entry")
	return button


func _build_skill_page_preview() -> void:
	_background(self, "res://assets/ui/gothic_preview/character_hall.png", 0.28)
	var shade := ColorRect.new()
	shade.color = Color("05030366")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_label(self, "技能典籍", Rect2(44, 18, 260, 42), 32, GOLD_BRIGHT)
	_label(self, "查看技能资料，长按技能放入右下三个技能按钮", Rect2(308, 26, 510, 30), 14, MUTED)
	_button(self, "关闭", Rect2(1132, 20, 104, 42), false)
	var main := _panel(self, Rect2(36, 76, 1208, 620), Color("0d0a09f7"), Color("806440"), 8, 2)
	var tabs := _panel(main, Rect2(18, 14, 1172, 52), Color("120e0ded"), Color("574a3d"), 4, 1)
	_button(tabs, "战士", Rect2(12, 6, 132, 40), true)
	_button(tabs, "法师", Rect2(154, 6, 132, 40), false)
	_button(tabs, "道士", Rect2(296, 6, 132, 40), false)
	_label(tabs, "已学习 6 / 6", Rect2(880, 6, 274, 40), 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)

	var list_panel := _panel(main, Rect2(18, 78, 320, 522), Color("100d0cef"), Color("5d4c38"), 5, 1)
	_label(list_panel, "人物技能", Rect2(14, 8, 292, 30), 18, GOLD_BRIGHT)
	_separator(list_panel, Rect2(14, 42, 292, 1))
	var skill_rows := [
		["基本剑术", 3, "被动"],
		["攻杀剑术", 3, "被动"],
		["刺杀剑术", 3, "自动开关"],
		["半月弯刀", 3, "自动开关"],
		["野蛮冲撞", 3, "瞬发技能"],
		["烈火剑法", 3, "自动开关"],
	]
	for index in range(skill_rows.size()):
		var row: Array = skill_rows[index]
		_skill_catalog_button(list_panel, str(row[0]), int(row[1]), str(row[2]), Rect2(14, 52 + index * 72, 292, 62), index == 4)

	var details := _panel(main, Rect2(352, 78, 510, 522), Color("100d0cef"), Color("6b553a"), 5, 1)
	var emblem := _panel(details, Rect2(22, 18, 82, 82), Color("321411f2"), RED, 41, 2)
	_label(emblem, "蛮", Rect2(0, 0, 82, 82), 30, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(details, "野蛮冲撞", Rect2(122, 18, 260, 38), 27, GOLD_BRIGHT)
	_label(details, "战士 · 瞬发位移技能", Rect2(122, 56, 260, 26), 14, MUTED)
	_label(details, "Lv.3 / 3", Rect2(396, 20, 92, 30), 15, BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	_label(details, "熟练度", Rect2(22, 118, 80, 22), 13, MUTED)
	_bar(details, Rect2(104, 121, 384, 16), 1.0, Color("9c6430"), "100%")
	_separator(details, Rect2(22, 158, 466, 1))
	_label(details, "技能参数", Rect2(22, 170, 150, 28), 17, GOLD_BRIGHT)
	var stats := [
		["使用方式", "快捷键单击"],
		["魔法消耗", "0 MP"],
		["冷却时间", "3.0 秒"],
		["冲撞距离", "115"],
		["目标方式", "当前方向"],
	]
	for index in range(stats.size()):
		var stat: Array = stats[index]
		_label(details, str(stat[0]), Rect2(22, 206 + index * 34, 130, 28), 13, MUTED)
		_label(details, str(stat[1]), Rect2(160, 206 + index * 34, 328, 28), 14, BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	_separator(details, Rect2(22, 382, 466, 1))
	_label(details, "向当前方向快速冲撞，对路径上的目标造成硬直。\n技能按钮轻触立即使用，不会替换普通攻击。", Rect2(22, 394, 466, 64), 14, BONE)
	_label(details, "数据依据：主服务端 Magic ID 27 · 当前等级记录 3", Rect2(22, 474, 466, 26), 11, MUTED)

	var equipped := _panel(main, Rect2(876, 78, 314, 522), Color("100d0cef"), Color("6b553a"), 5, 1)
	_label(equipped, "右下技能按钮", Rect2(16, 10, 282, 30), 18, GOLD_BRIGHT)
	_label(equipped, "轻触使用 · 长按技能重新配置", Rect2(16, 40, 282, 24), 12, MUTED)
	for index in range(3):
		var assigned_name := "野蛮冲撞" if index == 0 else "空技能位"
		var slot := _quick_skill_button(equipped, index, assigned_name, Rect2(24, 80 + index * 92, 266, 74), index == 0, "战士")
		slot.add_theme_font_size_override("font_size", 14)
	_separator(equipped, Rect2(18, 370, 278, 1))
	_label(equipped, "长按左侧任意技能，\n再选择要放入的按钮位置。", Rect2(20, 386, 274, 56), 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER)

	var assignment := _panel(self, Rect2(820, 432, 382, 204), Color("160d0cfd"), Color("a17943"), 8, 2)
	assignment.name = "SkillAssignmentPopup"
	assignment.set_meta("skill_name", "野蛮冲撞")
	_label(assignment, "将「野蛮冲撞」放入", Rect2(18, 14, 346, 30), 18, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	_label(assignment, "选择技能按钮位置", Rect2(18, 44, 346, 24), 12, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	for index in range(3):
		var target := _button(assignment, "技能按钮 %d" % (index + 1), Rect2(16 + index * 120, 82, 110, 66), index == 0)
		target.add_theme_font_size_override("font_size", 13)
		target.set_meta("assignment_slot", index)
		target.add_to_group("skill_assignment_target")
	_button(assignment, "取消", Rect2(126, 158, 130, 34), false)


func _capture() -> void:
	for _index in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output_dir := ProjectSettings.globalize_path("res://outputs/visual_acceptance/ui_gothic_preview")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var file_name := "character_select_create.png"
	if preview_mode == "exit":
		file_name = "in_game_exit_menu.png"
	elif preview_mode == "hud":
		file_name = "in_game_hud.png"
	elif preview_mode == "skill":
		file_name = "skill_assignment_page.png"
	var output := output_dir.path_join(file_name)
	var image := get_viewport().get_texture().get_image()
	assert(image.get_width() == 1280 and image.get_height() == 720, "UI preview capture must be 1280x720")
	assert(image.save_png(output) == OK, "Failed to save UI preview screenshot")
	print("UI_GOTHIC_PREVIEW_CAPTURE_PASS mode=%s output=%s" % [preview_mode, output])
	get_tree().quit(0)
