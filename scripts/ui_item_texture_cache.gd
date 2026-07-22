class_name UIItemTextureCache
extends RefCounted

static var _textures: Dictionary = {}


static func texture_for(record: Dictionary, field := "inventoryIcon") -> Texture2D:
	var art: Variant = record.get("art", {})
	if not art is Dictionary:
		return null
	var source: Variant = art.get(field, {})
	var path := str(source.get("path", "")) if source is Dictionary else str(source)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _textures.has(path):
		return _textures[path] as Texture2D
	var texture := load(path) as Texture2D
	if texture != null:
		_textures[path] = texture
	return texture


static func clear_for_test() -> void:
	_textures.clear()
