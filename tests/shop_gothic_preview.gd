extends Control

const OUTPUT_PATH := "res://outputs/visual_acceptance/shop/shop_gothic_sample_v1.png"
const WORLD_TEXTURE := preload("res://assets/ui/gothic_preview/world_scene_clean.png")

const SAMPLE_STOCK := [
	{"name": "太阳水", "price": 300, "description": "恢复生命与魔法。"},
	{"name": "匕首", "price": 500, "description": "轻便的入门武器。"},
	{"name": "布衣(男)", "price": 650, "description": "基础防护衣物。"},
	{"name": "古铜戒指", "price": 800, "description": "常见的低级戒指。"},
	{"name": "木剑", "price": 1000, "description": "适合新手使用。"},
	{"name": "黑铁头盔", "price": 6800, "description": "坚固的重型头盔。"},
	{"name": "绿色项链", "price": 7200, "description": "祖玛级项链。"},
	{"name": "骑士手镯", "price": 7500, "description": "提升战士攻击能力。"},
	{"name": "力量戒指", "price": 8200, "description": "战士的高级戒指。"},
	{"name": "裁决之杖", "price": 32000, "description": "沉重而强力的战士武器。"},
]


func _ready() -> void:
	_build_background()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.gold = 100000
	var panel := ShopPanel.new()
	panel.name = "ShopPanel"
	add_child(panel)
	await get_tree().process_frame
	panel.open_for("比奇武器店", SAMPLE_STOCK)
	panel._select_shop_item(0)
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	assert(error == OK, "无法保存哥特商店样板")
	print("SHOP_GOTHIC_PREVIEW_CAPTURE_PASS output=%s" % OUTPUT_PATH)
	get_tree().quit(0)


func _build_background() -> void:
	var world := TextureRect.new()
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.texture = WORLD_TEXTURE
	world.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world.stretch_mode = TextureRect.STRETCH_SCALE
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.008, 0.006, 0.005, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
