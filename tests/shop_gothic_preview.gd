extends Control

const BUY_OUTPUT_PATH := "res://outputs/visual_acceptance/shop/shop_gothic_sample_v1.png"
const SELL_OUTPUT_PATH := "res://outputs/visual_acceptance/shop/shop_gothic_sell_v1.png"
const SELL_CONFIRM_OUTPUT_PATH := "res://outputs/visual_acceptance/shop/shop_sell_confirmation_v1.png"
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
	PlayerState.add_item("太阳水", 5)
	PlayerState.add_item("匕首")
	PlayerState.add_item("古铜戒指")
	PlayerState.add_item("裁决之杖")
	var panel := ShopPanel.new()
	panel.name = "ShopPanel"
	add_child(panel)
	await get_tree().process_frame
	panel.open_for("比奇武器店", SAMPLE_STOCK)
	panel._select_shop_item(0)
	await get_tree().process_frame
	await get_tree().process_frame
	_capture(BUY_OUTPUT_PATH)
	panel._set_trade_mode("sell")
	var quotes := {}
	for inventory_index in range(PlayerState.inventory.size()):
		var record: Dictionary = PlayerState.inventory[inventory_index]
		var quote_key := panel.sell_quote_key(inventory_index, record)
		var risky := str(record.get("name", "")) == "裁决之杖"
		quotes[quote_key] = {
			"quote_id": "preview-%d" % inventory_index,
			"sellable": true,
			"unit_price": [80, 120, 180, 12000][inventory_index],
			"max_quantity": int(record.get("count", 1)),
			"requires_confirmation": risky,
			"risk_flags": ["high_value", "special"] if risky else [],
			"warning": "高价值特殊装备，出售后无法恢复。" if risky else "",
		}
	panel.set_sell_quotes(quotes)
	panel._select_sell_item(PlayerState.inventory.size() - 1)
	if PlayerState.inventory.size() > 1:
		panel._select_sell_item(0)
		panel._change_sell_quantity(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_capture(SELL_OUTPUT_PATH)
	panel._request_sell(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_capture(SELL_CONFIRM_OUTPUT_PATH)
	print("SHOP_GOTHIC_PREVIEW_CAPTURE_PASS buy=%s sell=%s confirmation=%s" % [BUY_OUTPUT_PATH, SELL_OUTPUT_PATH, SELL_CONFIRM_OUTPUT_PATH])
	get_tree().quit(0)


func _capture(output_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(output_path))
	assert(error == OK, "无法保存哥特商店样板")


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
