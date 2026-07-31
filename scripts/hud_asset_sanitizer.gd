class_name HUDAssetSanitizer
extends RefCounted

## Removes one isolated alpha-connected artifact without resampling any source
## pixels.  The seed must point inside the unwanted component.
static var _cache: Dictionary = {}


static func without_alpha_component(source: Texture2D, seed: Vector2i) -> Texture2D:
	if source == null:
		return null
	var cache_key := "%s@%d,%d" % [source.resource_path, seed.x, seed.y]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var image := source.get_image()
	if image == null or image.is_empty():
		return source
	image = image.duplicate()
	if seed.x < 0 or seed.y < 0 or seed.x >= image.get_width() or seed.y >= image.get_height():
		return source
	if image.get_pixelv(seed).a <= 0.01:
		return source
	var pending: Array[Vector2i] = [seed]
	var visited := {}
	while not pending.is_empty():
		var point: Vector2i = pending.pop_back()
		if visited.has(point):
			continue
		visited[point] = true
		if point.x < 0 or point.y < 0 or point.x >= image.get_width() or point.y >= image.get_height():
			continue
		var color := image.get_pixelv(point)
		if color.a <= 0.01:
			continue
		color.a = 0.0
		image.set_pixelv(point, color)
		for offset: Vector2i in [
			Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
			Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
		]:
			pending.append(point + offset)
	var cleaned := ImageTexture.create_from_image(image)
	_cache[cache_key] = cleaned
	return cleaned
