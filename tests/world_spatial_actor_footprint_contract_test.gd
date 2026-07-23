extends Node


func _ready() -> void:
	var radius := 18.0
	var radii := WorldSpatialRules.actor_footprint_radii(radius)
	assert(radii == Vector2(18.0, 9.0), "actor footprint must preserve a 2:1 isometric ratio")
	var polygon := WorldSpatialRules.actor_footprint_polygon(radius)
	assert(polygon.size() == WorldSpatialRules.ACTOR_FOOTPRINT_SEGMENTS)
	var bounds := _bounds(polygon)
	assert(is_equal_approx(bounds.size.x, 36.0), "actor footprint width changed: %s" % bounds)
	assert(is_equal_approx(bounds.size.y, 18.0), "actor footprint height is not half its width: %s" % bounds)
	var shape := WorldSpatialRules.actor_footprint_shape(radius)
	assert(shape is ConvexPolygonShape2D and shape.points == polygon)
	var diamond_normal := Vector2(1.0, 2.0).normalized()
	var sampled_support := 0.0
	for point: Vector2 in polygon:
		sampled_support = maxf(sampled_support, point.dot(diamond_normal))
	var exact_support := sqrt(
		pow(radii.x * diamond_normal.x, 2.0)
		+ pow(radii.y * diamond_normal.y, 2.0)
	)
	assert(absf(sampled_support - exact_support) <= 0.2, "polygon does not approximate the isometric ellipse support: %s / %s" % [sampled_support, exact_support])
	assert(WorldSpatialRules.ACTOR_FOOTPRINT_CONTRACT_ID == "world.actor_footprint.iso_ellipse.v1")
	print("WORLD_SPATIAL_ACTOR_FOOTPRINT_CONTRACT_PASS 36x18 ellipse matches 64x32 isometric projection")
	get_tree().quit(0)


func _bounds(points: PackedVector2Array) -> Rect2:
	var minimum := points[0]
	var maximum := points[0]
	for point: Vector2 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)
