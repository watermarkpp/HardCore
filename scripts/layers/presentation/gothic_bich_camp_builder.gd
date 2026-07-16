class_name GothicBichCampBuilder
extends RefCounted

const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

const LAYOUT_PATH := "res://assets/presentation/skins/gothic_bich_camp/layout.json"
const SPRITE_ROOT := "res://assets/presentation/skins/gothic_bich_camp/sprites/"
const GROUND_ATLAS := "res://assets/presentation/skins/gothic_bich_camp/gothic_bich_ground_tiles.png"


static func load_layout() -> Dictionary:
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed if parsed is Dictionary else {}


static func build(parent: Node2D, home: Vector2) -> Dictionary:
	var layout := load_layout()
	var nodes: Array[Node] = []
	var collisions: Array[Dictionary] = []
	# The complete 700x700 Bich terrain is built once by WorldBackground.
	# City props sit on that shared tiled terrain so there is no visible patch edge.
	for record: Variant in layout.get("props", []):
		if not record is Dictionary:
			continue
		var position := home + _vector(record.get("position", [0, 0]))
		var sprite := _sprite(str(record.get("asset", "")), position)
		if sprite == null:
			continue
		if str(record.get("layer", "")) == "ground":
			sprite.z_index = -17
		else:
			sprite.z_index = -5
		parent.add_child(sprite)
		nodes.append(sprite)
		var collision: Variant = record.get("collision", {})
		if collision is Dictionary and not collision.is_empty():
			var body := _collision_body(position, collision)
			parent.add_child(body)
			nodes.append(body)
			collisions.append({"position": position, "definition": collision.duplicate(true)})
	for record: Variant in layout.get("lights", []):
		if record is Dictionary:
			_build_light(parent, home, record, nodes)
	return {"nodes": nodes, "collisions": collisions, "layout": layout}


static func _sprite(asset_id: String, foot_position: Vector2) -> Sprite2D:
	var path := SPRITE_ROOT + asset_id + ".png"
	if not ResourceLoader.exists(path):
		return null
	var sprite := Sprite2D.new()
	sprite.texture = load(path)
	sprite.centered = false
	sprite.position = foot_position - Vector2(sprite.texture.get_width() * 0.5, sprite.texture.get_height() - 4)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_as_relative = false
	return sprite


static func _collision_body(position: Vector2, definition: Dictionary) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = WorldSpatialRulesScript.WORLD_LAYER
	body.collision_mask = 0
	body.set_meta("gothic_bich_camp", true)
	var collision := CollisionShape2D.new()
	if str(definition.get("type", "")) == "circle":
		var shape := CircleShape2D.new()
		shape.radius = float(definition.get("radius", 16.0))
		collision.shape = shape
	else:
		var shape := RectangleShape2D.new()
		shape.size = _vector(definition.get("size", [32, 20]))
		collision.shape = shape
	body.add_child(collision)
	return body


static func _build_light(parent: Node2D, home: Vector2, record: Dictionary, nodes: Array[Node]) -> void:
	var path := SPRITE_ROOT + str(record.get("texture", "")) + ".png"
	if not ResourceLoader.exists(path):
		return
	var light := PointLight2D.new()
	light.texture = load(path)
	light.position = home + _vector(record.get("position", [0, 0]))
	light.texture_scale = float(record.get("scale", 1.0))
	light.energy = float(record.get("energy", 0.4))
	light.color = Color.from_string(str(record.get("color", "ffffff")), Color.WHITE)
	light.z_as_relative = false
	light.z_index = -3
	parent.add_child(light)
	nodes.append(light)


static func _vector(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1])) if value is Array and value.size() >= 2 else Vector2.ZERO
