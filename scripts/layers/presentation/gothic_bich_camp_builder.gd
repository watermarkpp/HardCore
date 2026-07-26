class_name GothicBichCampBuilder
extends RefCounted

const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const RuntimeVisualGeometryScript := preload(
	"res://scripts/map_editor/map_editor_runtime_visual_geometry_service.gd"
)

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
			parent.add_child(sprite)
			nodes.append(sprite)
		else:
			_add_actor_sorted_prop(
				parent, sprite, position, str(record.get("asset", "")), nodes
			)
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


static func _add_actor_sorted_prop(
	background: Node2D,
	sprite: Sprite2D,
	foot_position: Vector2,
	asset_id: String,
	nodes: Array[Node]
) -> void:
	var actor_parent := background.get_parent() as Node2D
	var prop := {"position": foot_position, "occlusion": true}
	if (
		actor_parent == null
		or RuntimeVisualGeometryScript.legacy_profile_prop_render_domain(prop)
		!= RuntimeVisualGeometryScript.RENDER_DOMAIN_ACTOR_Y_SORT
	):
		sprite.z_index = -5
		background.add_child(sprite)
		nodes.append(sprite)
		return
	var actor_sort_root := Node2D.new()
	actor_sort_root.name = "GothicBichOccluder_%s" % asset_id
	actor_sort_root.position = RuntimeVisualGeometryScript.legacy_profile_prop_actor_sort_world(
		prop
	)
	actor_sort_root.z_as_relative = false
	actor_sort_root.z_index = 0
	actor_sort_root.set_meta("gothic_bich_camp_actor_occluder", true)
	actor_sort_root.set_meta(
		"map_occlusion_sort_contract_id",
		RuntimeVisualGeometryScript.OCCLUSION_SORT_CONTRACT_ID
	)
	sprite.position -= actor_sort_root.position
	sprite.z_as_relative = true
	sprite.z_index = 0
	actor_parent.add_child(actor_sort_root)
	actor_sort_root.add_child(sprite)
	nodes.append(actor_sort_root)


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
