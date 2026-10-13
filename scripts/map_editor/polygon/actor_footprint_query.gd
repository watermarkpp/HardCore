extends RefCounted

## Private formal-provider preparation. No actor, map or collision result is
## retained. Arbitrary public offsets continue through PolyRuntime.actor_world.
const Spatial := preload("res://scripts/world_spatial_rules.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
const CAPACITY := 4 # two authored monster radii, player radius, zero radius

class Template:
	extends RefCounted
	var radius_px: float
	var _offsets := PackedVector2Array()
	var _max_offset := 0.0
	var _valid := true
	func _init(radius: float) -> void:
		radius_px = radius
		_offsets = Spatial.actor_footprint_polygon_px(radius)
		_valid = not _offsets.is_empty()
		for offset: Vector2 in _offsets:
			if not offset.is_finite():
				_valid = false
				break
			_max_offset = maxf(_max_offset,offset.length_squared())

var _templates: Array[Template] = []
var _last: Template

func blocked(snapshot: Dictionary, center_px: Vector2, radius_px: float) -> bool:
	if not is_finite(radius_px) or radius_px < 0.0:
		return true
	if not snapshot.has("poly_index") or not center_px.is_finite():
		return true
	# Preserve the original generator's nonnegative-zero normalization. Positive
	# float64 radii compare exactly; neighboring radii are never quantized.
	var radius := maxf(0.0,radius_px)
	var template := _last
	if template == null or template.radius_px != radius:
		template = null
		for entry: Template in _templates:
			if entry.radius_px == radius:
				template = entry
				break
		if template == null:
			template = Template.new(radius)
			if _templates.size() == CAPACITY:
				_templates.pop_front()
			_templates.append(template)
		_last = template
	if not template._valid:
		return true
	var footprint := PackedVector2Array()
	var map_center := (Vector2(snapshot.design_size) - Vector2.ONE) * 0.5
	for offset: Vector2 in template._offsets:
		footprint.append(map_center + Coord.screen_delta_px_to_ground_delta_gu(center_px + offset))
	var index: Index = snapshot.poly_index
	if template._max_offset <= Geo.EPS * Geo.EPS:
		return index.point_blocked(footprint[0])
	return index.footprint_blocked(footprint)
