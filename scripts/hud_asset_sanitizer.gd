class_name HUDAssetSanitizer
extends RefCounted

## Removes one isolated alpha-connected artifact without resampling any source
## pixels.  The seed must point inside the unwanted component.
const CHASSIS_LEGACY_SKILL_MASK_ID := "ui.hud.chassis.legacy_skill_alpha_mask.v2"
const _LEGACY_RING_TOP_BOUNDS := Rect2i(239, 0, 539, 133)
const _LEGACY_CONNECTOR_X_RANGE := Vector2i(204, 808)
const _LEGACY_CONNECTOR_Y_RANGE := Vector2i(125, 160)
const _LEGACY_RING_CENTERS: Array[int] = [309, 441, 574, 707]
static var _CENTER_CREST_PROTECT_POLYGON := PackedVector2Array([
	Vector2(505, 111),
	Vector2(520, 131),
	Vector2(546, 134),
	Vector2(553, 141),
	Vector2(568, 160),
	Vector2(442, 160),
	Vector2(458, 141),
	Vector2(466, 134),
	Vector2(490, 131),
])

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


## Removes only the baked legacy skill frames from the unified chassis. The mask
## is the union of the four upper ring silhouettes, their four red-gem diamonds,
## and the straight connector above the formal curved chassis rail. The central
## crest is a hard-protected polygon, including its upward spike at x≈505.
static func without_chassis_legacy_skill_art(source: Texture2D) -> Texture2D:
	if source == null:
		return null
	var cache_key := "legacy_skill_mask:%d" % source.get_instance_id()
	if _cache.has(cache_key):
		return _cache[cache_key]
	var image := source.get_image()
	if image == null or image.is_empty():
		return source
	image = image.duplicate()
	for y in range(0, mini(image.get_height(), _LEGACY_CONNECTOR_Y_RANGE.y)):
		for x in range(
			maxi(0, _LEGACY_CONNECTOR_X_RANGE.x),
			mini(image.get_width(), _LEGACY_CONNECTOR_X_RANGE.y),
		):
			if not is_chassis_legacy_skill_pixel(Vector2i(x, y)):
				continue
			var color := image.get_pixel(x, y)
			color.a = 0.0
			image.set_pixel(x, y, color)
	var cleaned := ImageTexture.create_from_image(image)
	_cache[cache_key] = cleaned
	return cleaned


static func is_chassis_legacy_skill_pixel(point: Vector2i) -> bool:
	var sample := Vector2(point) + Vector2(0.5, 0.5)
	if Geometry2D.is_point_in_polygon(sample, _CENTER_CREST_PROTECT_POLYGON):
		return false
	for center_x in _LEGACY_RING_CENTERS:
		var red_gem := PackedVector2Array([
			Vector2(center_x, 112),
			Vector2(center_x + 29, 137),
			Vector2(center_x, 161),
			Vector2(center_x - 29, 137),
		])
		if Geometry2D.is_point_in_polygon(sample, red_gem):
			return true
	if _LEGACY_RING_TOP_BOUNDS.has_point(point):
		return true
	if (
		point.x >= _LEGACY_CONNECTOR_X_RANGE.x
		and point.x < _LEGACY_CONNECTOR_X_RANGE.y
		and point.y >= _LEGACY_CONNECTOR_Y_RANGE.x
		and point.y < _LEGACY_CONNECTOR_Y_RANGE.y
	):
		# The obsolete connector is straight. The formal chassis rail below it
		# rises toward both demons, so the curved threshold preserves that rail.
		var formal_rail_top := 158.0 - 0.063 * absf(float(point.x) - 505.0)
		return float(point.y) < formal_rail_top
	return false


static func is_chassis_center_crest_protected(point: Vector2i) -> bool:
	return Geometry2D.is_point_in_polygon(
		Vector2(point) + Vector2(0.5, 0.5),
		_CENTER_CREST_PROTECT_POLYGON,
	)
