class_name AdaptiveButtonStyleBox
extends StyleBox

var compact: StyleBoxTexture
var standard: StyleBoxTexture
var wide: StyleBoxTexture
var square_texture: Texture2D
var shortwide_texture: Texture2D
var widesmall_texture: Texture2D
var small_family := false
var square_threshold := 10.0 / 3.0
var fill_color := Color(0.055, 0.035, 0.018, 0.96)
var square_alpha_safe_inset := 12.0
var force_square := false
var force_widesmall := false

func configure(c: Texture2D, s: Texture2D, w: Texture2D, margins := Vector4(36, 0, 36, 0)) -> AdaptiveButtonStyleBox:
	compact = _make(c, margins)
	standard = _make(s, margins)
	wide = _make(w, margins)
	square_threshold = 10.0 / 3.0
	square_texture = null
	shortwide_texture = null
	widesmall_texture = null
	small_family = false
	force_widesmall = false
	force_square = false
	return self

func configure_widesmall(w: Texture2D, fill := Color(0.055, 0.035, 0.018, 0.96)) -> AdaptiveButtonStyleBox:
	compact = _make(w, Vector4.ZERO)
	standard = _make(w, Vector4.ZERO)
	wide = _make(w, Vector4.ZERO)
	widesmall_texture = w
	fill_color = fill
	force_widesmall = true
	force_square = false
	small_family = false
	return self

func configure_square(square: Texture2D, s: Texture2D, w: Texture2D, threshold := 2.0, fill := Color(0.055, 0.035, 0.018, 0.96)) -> AdaptiveButtonStyleBox:
	compact = _make(square, Vector4.ZERO)
	standard = _make(s, Vector4(36, 0, 36, 0))
	wide = _make(w, Vector4(36, 0, 36, 0))
	square_texture = square
	square_threshold = threshold
	fill_color = fill
	square_alpha_safe_inset = 12.0
	force_square = true
	small_family = false
	return self

func configure_small(square: Texture2D, shortwide: Texture2D, widesmall: Texture2D, fill := Color(0.055, 0.035, 0.018, 0.96)) -> AdaptiveButtonStyleBox:
	square_texture = square
	shortwide_texture = shortwide
	widesmall_texture = widesmall
	fill_color = fill
	force_square = false
	square_threshold = 1.35
	small_family = true
	return self

func selected_small_kind(rect: Rect2) -> StringName:
	var ratio := rect.size.x / maxf(rect.size.y, 1.0)
	return &"widesmall" if ratio > 2.2 else (&"shortwide" if ratio > 1.35 else &"square")

func selected_small_draw_rect(rect: Rect2) -> Rect2:
	return rect

func selected_small_fill_rect(rect: Rect2) -> Rect2:
	var inset := 12.0 if selected_small_kind(rect) == &"square" else 10.0
	return rect.grow(-inset)

func square_fill_rect(rect: Rect2) -> Rect2:
	var side := minf(rect.size.x, rect.size.y)
	var origin := rect.position + (rect.size - Vector2.ONE * side) * 0.5
	return Rect2(origin + Vector2.ONE * square_alpha_safe_inset, Vector2.ONE * maxf(0.0, side - square_alpha_safe_inset * 2.0))

func square_fill_style(rect: Rect2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	var radius := clampi(int(minf(rect.size.x, rect.size.y) * 0.12), 4, 18)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

func _make(texture: Texture2D, margins: Vector4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture
	sb.set_texture_margin(SIDE_LEFT, margins.x); sb.set_texture_margin(SIDE_TOP, margins.y)
	sb.set_texture_margin(SIDE_RIGHT, margins.z); sb.set_texture_margin(SIDE_BOTTOM, margins.w)
	sb.content_margin_left = margins.x; sb.content_margin_right = margins.z
	sb.draw_center = true
	return sb

func choose(rect: Rect2) -> StyleBoxTexture:
	var ratio := rect.size.x / maxf(rect.size.y, 1.0)
	return compact if ratio <= square_threshold else (standard if ratio <= 4.67 else wide)

func _draw(canvas_item: RID, rect: Rect2) -> void:
	if force_widesmall:
		var thin_texture := compact.texture
		square_fill_style(selected_small_fill_rect(rect)).draw(canvas_item, selected_small_fill_rect(rect))
		RenderingServer.canvas_item_add_texture_rect(canvas_item, rect, thin_texture.get_rid(), false, Color.WHITE)
		return
	if square_texture != null and (small_family or force_square):
		var ratio := rect.size.x / maxf(rect.size.y, 1.0)
		var texture := square_texture
		if not force_square and widesmall_texture != null and ratio > 2.2:
			texture = widesmall_texture
		elif not force_square and shortwide_texture != null and ratio > 1.35:
			texture = shortwide_texture
		square_fill_style(selected_small_fill_rect(rect)).draw(canvas_item, selected_small_fill_rect(rect))
		RenderingServer.canvas_item_add_texture_rect(canvas_item, selected_small_draw_rect(rect), texture.get_rid(), false, Color.WHITE)
		return
	choose(rect).draw(canvas_item, rect)
