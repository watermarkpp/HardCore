extends Control


const TILE_HALF_W := 32.0
const TILE_HALF_H := 16.0

var review_asset: Dictionary = {}
var review_footprint := Vector2i.ONE
var review_anchor_px := Vector2.ZERO
var review_texture: Texture2D
var view_zoom := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(760, 620)


func set_review_asset(
	asset: Dictionary,
	footprint: Vector2i,
	anchor_px := Vector2(-1, -1)
) -> void:
	review_asset = asset.duplicate(true)
	review_footprint = Vector2i(
		maxi(1, footprint.x),
		maxi(1, footprint.y)
	)

	if anchor_px.x >= 0 and anchor_px.y >= 0:
		review_anchor_px = anchor_px
	else:
		review_anchor_px = Vector2.ZERO

	review_texture = null

	var image_path := str(
		review_asset.get("image", "")
	)

	if not image_path.is_empty():
		var resolved := image_path

		if resolved.begins_with("res://"):
			resolved = ProjectSettings.globalize_path(
				resolved
			)
		else:
			resolved = ProjectSettings.globalize_path(
				"res://" + resolved
			)

		var image := Image.load_from_file(
			resolved
		)

		if image != null and not image.is_empty():
			review_texture = (
				ImageTexture.create_from_image(
					image
				)
			)

	queue_redraw()


func set_view_zoom(value: float) -> void:
	view_zoom = clampf(
		value,
		0.25,
		2.5
	)
	queue_redraw()


func _canvas_center() -> Vector2:
	return Vector2(
		size.x * 0.5,
		size.y * 0.56
	)


func _grid_vertex(
	vertex: Vector2
) -> Vector2:
	var centered := (
		vertex
		- Vector2(
			review_footprint.x,
			review_footprint.y
		) * 0.5
	)

	return (
		_canvas_center()
		+ Vector2(
			(
				centered.x
				- centered.y
			) * TILE_HALF_W,
			(
				centered.x
				+ centered.y
			) * TILE_HALF_H
		) * view_zoom
	)


func _draw_cell(
	x: int,
	y: int,
	line_color: Color,
	line_width: float
) -> void:
	var points := PackedVector2Array([
		_grid_vertex(
			Vector2(x, y)
		),
		_grid_vertex(
			Vector2(x + 1, y)
		),
		_grid_vertex(
			Vector2(x + 1, y + 1)
		),
		_grid_vertex(
			Vector2(x, y + 1)
		),
		_grid_vertex(
			Vector2(x, y)
		),
	])

	draw_polyline(
		points,
		line_color,
		line_width,
		true
	)


func _pending_placement_anchor() -> Vector2:
	if review_texture == null:
		return Vector2.ZERO

	# Use review anchor override when set (non-zero).
	if review_anchor_px != Vector2.ZERO:
		return review_anchor_px

	var texture_size := review_texture.get_size()

	var source_raw: Array = review_asset.get(
		"anchor_px",
		[
			texture_size.x * 0.5,
			texture_size.y
		]
	)

	var source_anchor := Vector2(
		float(source_raw[0]),
		float(source_raw[1])
	)

	var approved_scale := maxf(
		0.0001,
		float(
			review_asset.get(
				"approved_scale",
				1.0
			)
		)
	)

	var foot_tile := (
		str(
			review_asset.get(
				"anchor_mode",
				""
			)
		) == "foot_tile"
		and str(
			review_asset.get(
				"asset_type",
				""
			)
		) != "wall_module"
		and str(
			review_asset.get(
				"object_class",
				""
			)
		) != "wall"
	)

	if foot_tile:
		var center_to_bottom := Vector2(
			(
				float(review_footprint.x)
				- float(review_footprint.y)
			) * TILE_HALF_W * 0.5,
			(
				float(review_footprint.x)
				+ float(review_footprint.y)
			) * TILE_HALF_H * 0.5
		)

		return (
			source_anchor
			- center_to_bottom
			/ approved_scale
		)

	var placement_raw: Array = (
		review_asset.get(
			"placement_anchor_px",
			source_raw
		)
	)

	return Vector2(
		float(placement_raw[0]),
		float(placement_raw[1])
	)


func _draw() -> void:
	draw_rect(
		Rect2(
			Vector2.ZERO,
			size
		),
		Color("15181d")
	)

	if review_asset.is_empty():
		return

	var context := 2

	for y in range(
		-context,
		review_footprint.y + context
	):
		for x in range(
			-context,
			review_footprint.x + context
		):
			_draw_cell(
				x,
				y,
				Color(
					0.30,
					0.34,
					0.39,
					0.55
				),
				1.0
			)

	if review_texture != null:
		var approved_scale := maxf(
			0.0001,
			float(
				review_asset.get(
					"approved_scale",
					1.0
				)
			)
		)

		var visual_scale := (
			approved_scale
			* view_zoom
		)

		var anchor := (
			_pending_placement_anchor()
		)

		var draw_size := (
			review_texture.get_size()
			* visual_scale
		)

		var top_left := (
			_canvas_center()
			- anchor
			* visual_scale
		)

		draw_texture_rect(
			review_texture,
			Rect2(
				top_left,
				draw_size
			),
			false
		)

	for y in range(
		review_footprint.y
	):
		for x in range(
			review_footprint.x
		):
			_draw_cell(
				x,
				y,
				Color(
					0.90,
					0.72,
					0.24,
					0.95
				),
				2.0
			)

	var bottom_vertex := _grid_vertex(
		Vector2(
			review_footprint.x,
			review_footprint.y
		)
	)

	draw_circle(
		bottom_vertex,
		6.0,
		Color(
			0.95,
			0.35,
			0.25,
			1.0
		)
	)

	# Draw pending anchor position crosshair
	if review_anchor_px != Vector2.ZERO:
		var approved_scale := maxf(
			0.0001,
			float(
				review_asset.get(
					"approved_scale",
					1.0
				)
			)
		)
		var anchor_screen := _canvas_center()
		var cross_color := Color(
			0.20,
			0.80,
			1.00,
			0.90
		)
		var cross_size := 12.0

		draw_line(
			anchor_screen + Vector2(-cross_size, 0),
			anchor_screen + Vector2(cross_size, 0),
			cross_color,
			2.0
		)
		draw_line(
			anchor_screen + Vector2(0, -cross_size),
			anchor_screen + Vector2(0, cross_size),
			cross_color,
			2.0
		)