extends RefCounted

const POTION_PATHS := {
	"hc.item.920017": "res://assets/art/items/service/inventory/client.mir2opensource_2013_complete/Items_00315.png",
	"hc.item.920042": "res://assets/art/items/service/inventory/client.mir2opensource_2013_complete/Items_00316.png",
}
static var _textures: Dictionary = {}
static var _centers: Dictionary = {}

static func prepare_texture(source: Texture2D, item_id: String) -> Texture2D:
	if source == null or POTION_PATHS.get(item_id, "") != source.resource_path:
		return source
	var key := source.get_instance_id()
	if _textures.has(key):
		return _textures[key]
	# Existing lossless display sanitation removes only the isolated five-pixel
	# component. Source pixels and native dimensions remain unchanged.
	var cleaned := HUDAssetSanitizer.without_alpha_component(source, Vector2i(0, 16))
	var image := cleaned.get_image()
	var weight := 0.0
	var center := Vector2.ZERO
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var alpha := image.get_pixel(x, y).a
			weight += alpha
			center += Vector2(x + 0.5, y + 0.5) * alpha
	# The optical center accounts for the bottle's asymmetric ribbon; using
	# its bounding box alone still leaves most of the bottle visibly east.
	_centers[cleaned.get_instance_id()] = center / weight if weight > 0.0 else source.get_size() * 0.5
	_textures[key] = cleaned
	return cleaned

static func visible_center(texture: Texture2D) -> Vector2:
	return _centers.get(texture.get_instance_id(), texture.get_size() * 0.5)
