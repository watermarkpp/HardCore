class_name HUDAssetSanitizer
extends RefCounted

## Removes one isolated alpha-connected artifact without resampling any source
## pixels.  The seed must point inside the unwanted component.
static var _cache: Dictionary = {}


static func without_alpha_component(source: Texture2D, seed: Vector2i) -> Texture2D:
	if source == null:
		return null
	var cache_key := "component:%d@%d,%d" % [source.get_instance_id(), seed.x, seed.y]
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


## Clears a precisely bounded source-art rectangle without resampling anything
## outside that rectangle. This is used when obsolete artwork was baked into the
## same atlas as artwork that must be preserved.
static func without_alpha_rect(source: Texture2D, source_rect: Rect2i) -> Texture2D:
	if source == null:
		return null
	var cache_key := "rect:%d@%d,%d,%d,%d" % [
		source.get_instance_id(),
		source_rect.position.x,
		source_rect.position.y,
		source_rect.size.x,
		source_rect.size.y,
	]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var image := source.get_image()
	if image == null or image.is_empty():
		return source
	var image_rect := Rect2i(Vector2i.ZERO, image.get_size())
	var clipped := source_rect.intersection(image_rect)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return source
	image = image.duplicate()
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			var color := image.get_pixel(x, y)
			color.a = 0.0
			image.set_pixel(x, y, color)
	var cleaned := ImageTexture.create_from_image(image)
	_cache[cache_key] = cleaned
	return cleaned
