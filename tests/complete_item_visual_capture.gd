extends Node2D

const OUTPUT := "res://outputs/visual_acceptance/complete_item_system_20260715.png"
const ITEMS := [
	"金币", "金创药(小量)", "魔法药(小量)", "金创药(大量)", "超级金创药",
	"太阳水", "万年雪霜", "回城卷", "随机传送卷", "地牢逃脱卷",
	"祝福油", "修复油", "战神油", "黑铁矿", "基本剑术", "沃玛号角", "复活卷轴",
]


func _ready() -> void:
	build.call_deferred()


func build() -> void:
	var background := ColorRect.new()
	background.position = Vector2.ZERO
	background.size = Vector2(1280, 720)
	background.color = Color("171411")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = -10
	add_child(background)
	var title := Label.new()
	title.text = "完整物品系统验收 · 背包图标 / 实际地面掉落外观"
	title.position = Vector2(36, 20)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f1d28c"))
	add_child(title)
	var subtitle := Label.new()
	subtitle.text = "主客户端原图优先 · 主端缺帧才用辅1同索引 · 两端均缺失使用分类补图"
	subtitle.position = Vector2(38, 54)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("b9aa91"))
	add_child(subtitle)

	for index in range(ITEMS.size()):
		var item_name: String = ITEMS[index]
		var record := GameData.get_item_record(item_name)
		var column := index % 9
		var row := index / 9
		var origin := Vector2(75 + column * 136, 125 + row * 275)
		_add_icon(record, "inventoryIcon", origin)
		_add_icon(record, "groundIcon", origin + Vector2(0, 92))
		var name_label := Label.new()
		name_label.text = item_name
		name_label.position = origin + Vector2(-62, 128)
		name_label.size = Vector2(124, 25)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", Color("eee5d1"))
		add_child(name_label)
		var source := str(record.get("art", {}).get("groundIcon", {}).get("distribution", ""))
		var source_label := Label.new()
		source_label.text = {"client.classic_raw_complete": "主端原图", "client.mir2opensource_2013_complete": "辅1补帧", "project.category_fallback": "分类补图"}.get(source, source)
		source_label.position = origin + Vector2(-62, 151)
		source_label.size = Vector2(124, 22)
		source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		source_label.add_theme_font_size_override("font_size", 11)
		source_label.add_theme_color_override("font_color", Color("9b8e78"))
		add_child(source_label)

	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/visual_acceptance"))
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT))
	assert(error == OK, "物品验收截图保存失败")
	print("COMPLETE_ITEM_VISUAL_CAPTURE_PASS: %s" % OUTPUT)
	get_tree().quit(0)


func _add_icon(record: Dictionary, field: String, position_value: Vector2) -> void:
	var icon: Dictionary = record.get("art", {}).get(field, {})
	var texture := load(str(icon.get("path", ""))) as Texture2D
	assert(texture != null, "%s纹理加载失败" % field)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = position_value
	var maximum := 62.0 if field == "inventoryIcon" else 48.0
	var scale_factor := minf(maximum / maxf(1.0, texture.get_width()), maximum / maxf(1.0, texture.get_height()))
	sprite.scale = Vector2.ONE * minf(2.0, scale_factor)
	add_child(sprite)
	var role := Label.new()
	role.text = "背包" if field == "inventoryIcon" else "地面"
	role.position = position_value + Vector2(-25, 36 if field == "inventoryIcon" else 27)
	role.size = Vector2(50, 18)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role.add_theme_font_size_override("font_size", 10)
	role.add_theme_color_override("font_color", Color("756b5d"))
	add_child(role)
