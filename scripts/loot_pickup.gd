class_name LootPickup
extends Node2D

signal collected(item_name: String)

var item_name := "金币"
var target: PlayerCharacter
var _bob_time := 0.0
var icon_sprite: Sprite2D


func setup(label_text: String, player_target: PlayerCharacter) -> void:
	item_name = label_text
	target = player_target


func _ready() -> void:
	var record := GameData.get_item_record(item_name)
	var art: Variant = record.get("art", {})
	var ground: Variant = art.get("groundIcon", {}) if art is Dictionary else {}
	var icon_path := str(ground.get("path", "")) if ground is Dictionary else str(ground)
	if icon_path.is_empty():
		var fallback_key: String = str({
			"skill_book": "book", "consumable": "potion", "scroll": "scroll",
			"quest_item": "quest", "currency": "material", "material": "material",
		}.get(GameData.get_item_kind(item_name), "material"))
		icon_path = str(GameData.service_item_catalog.get("runtimeFallbackArt", {}).get(fallback_key, {}).get("ground", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon_sprite = Sprite2D.new()
		icon_sprite.name = "ClientGroundIcon"
		icon_sprite.texture = load(icon_path) as Texture2D
		icon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_sprite.position = Vector2(0, -5)
		add_child(icon_sprite)
	var label := Label.new()
	label.text = item_name
	label.position = Vector2(-48, -36)
	label.size = Vector2(96, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var kind := GameData.get_item_kind(item_name)
	var item_color: Color = {
		"equipment": Color(0.55, 0.82, 1.0), "skill_book": Color(0.72, 0.55, 1.0),
		"currency": Color(1.0, 0.82, 0.28), "consumable": Color(0.45, 0.92, 0.52),
		"quest_item": Color(1.0, 0.48, 0.25),
	}.get(kind, Color(0.90, 0.82, 0.66))
	label.add_theme_color_override("font_color", item_color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	queue_redraw()


func _process(delta: float) -> void:
	_bob_time += delta
	if icon_sprite != null:
		icon_sprite.position.y = -5.0 + sin(_bob_time * 3.0) * 2.0
	queue_redraw()
	if is_instance_valid(target) and global_position.distance_to(target.global_position) < 34.0:
		collected.emit(item_name)
		queue_free()


func _draw() -> void:
	if icon_sprite != null:
		return
	var bob := sin(_bob_time * 3.0) * 3.0
	var kind := GameData.get_item_kind(item_name)
	var color: Color = {"equipment": Color(0.35, 0.65, 0.95), "skill_book": Color(0.60, 0.38, 0.90), "consumable": Color(0.25, 0.75, 0.35), "quest_item": Color(0.90, 0.28, 0.12)}.get(kind, Color(0.95, 0.67, 0.12))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -11 + bob), Vector2(10, bob), Vector2(0, 11 + bob), Vector2(-10, bob)]), color)
	draw_polyline(PackedVector2Array([Vector2(0, -11 + bob), Vector2(10, bob), Vector2(0, 11 + bob), Vector2(-10, bob), Vector2(0, -11 + bob)]), Color(1.0, 0.93, 0.55), 2.0)
