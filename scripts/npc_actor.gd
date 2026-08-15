class_name NPCActor
extends Node2D

const NPCVisualScript := preload("res://scripts/npc_visual.gd")
const FACING_DIRECTIONS: Array[Vector2] = [
	Vector2.DOWN, Vector2(-0.70710678, 0.70710678), Vector2.LEFT, Vector2(-0.70710678, -0.70710678),
	Vector2.UP, Vector2(0.70710678, -0.70710678), Vector2.RIGHT, Vector2(0.70710678, 0.70710678),
]

var npc_name := "NPC"
var npc_kind := "shop"
var shop_stock: Array = []
var stock_key := ""
var appearance := -1
var facing := Vector2.DOWN
var default_facing := Vector2.DOWN
var map_center := Vector2.ZERO
var visual: NPCVisual
var name_label: Label


func setup(display_name: String, kind: String, stock: Array = [], dynamic_stock_key := "", npc_appearance := -1, center := Vector2.ZERO) -> void:
	npc_name = display_name
	npc_kind = kind
	shop_stock = stock
	stock_key = dynamic_stock_key
	appearance = npc_appearance if npc_appearance >= 0 else _fallback_appearance(display_name, kind, dynamic_stock_key)
	map_center = center


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("zone_content")
	face_toward(map_center, true)
	visual = NPCVisualScript.new()
	visual.name = "NPCVisual"
	visual.setup(self)
	add_child(visual)
	name_label = Label.new()
	name_label.text = npc_name
	name_label.position = Vector2(-75.0, -76.0)
	name_label.size = Vector2(150, 25)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.98, 0.78, 0.42))
	add_child(name_label)
	_refresh_name_label_anchor()
	queue_redraw()


func face_toward(target_position: Vector2, as_default := false) -> void:
	var direction := global_position.direction_to(target_position)
	if direction.length_squared() < 0.0001:
		direction = Vector2.DOWN
	facing = FACING_DIRECTIONS[ArtSpec.direction_index(direction)]
	if as_default:
		default_facing = facing
	_refresh_name_label_anchor()


func reset_to_default_facing() -> void:
	facing = default_facing
	_refresh_name_label_anchor()


func _refresh_name_label_anchor() -> void:
	if name_label == null or visual == null:
		return
	var visual_center_offset := visual.stable_frame_center_offset()
	name_label.position.x = -75.0 + visual_center_offset.x


func interact(game: Node) -> void:
	if game != null and is_instance_valid(game.player):
		face_toward(game.player.global_position)
	if npc_kind == "shop":
		var active_stock := shop_stock
		if stock_key == "books":
			active_stock = game._build_skill_book_stock(PlayerState.profession)
		# Keep the merchant identity explicit even when the stock is empty or
		# filtered. ShopPanel must not infer authority from stock[0].
		var merchant_context := GameData.merchant_context(stock_key)
		game.hud.open_shop(npc_name, active_stock, merchant_context)
	elif npc_kind == "trainer":
		game.hud.open_skill_trainer(npc_name)
	elif npc_kind == "quest":
		game.hud.open_quest(npc_name)
	elif npc_kind == "guide":
		game.hud.show_message("暗殿真假难辨，沿通道深入后原路返回。", 2.5)
	elif npc_kind == "warehouse":
		game.hud.open_warehouse()


func interaction_text() -> String:
	return "与%s交谈" % npc_name


func uses_final_art() -> bool:
	return visual != null and visual.uses_final_art()


func _fallback_appearance(display_name: String, kind: String, dynamic_stock_key: String) -> int:
	# Exact server Image wins when available. These are stable presentation fallbacks.
	if "武器" in display_name or "铁匠" in display_name or dynamic_stock_key in ["starter_gear", "mid_gear"]:
		return 11
	if "书" in display_name or dynamic_stock_key == "books":
		return 8
	if "武馆" in display_name or kind == "trainer":
		return 15
	if "仓库" in display_name or kind == "warehouse":
		return 14
	if "老兵" in display_name or kind == "quest":
		return 0
	if "杂货" in display_name or dynamic_stock_key == "general":
		return 10
	return posmod(display_name.hash(), 23)


func _draw() -> void:
	if visual != null and visual.uses_final_art():
		return
	draw_set_transform(Vector2(0, 16), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 22.0, Color(0, 0, 0, 0.4))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([Vector2(-18, -8), Vector2(18, -8), Vector2(15, 31), Vector2(-15, 31)]), Color(0.39, 0.24, 0.14) if npc_kind == "shop" else Color(0.20, 0.32, 0.48))
	draw_circle(Vector2(0, -17), 15.0, Color(0.80, 0.65, 0.46))
