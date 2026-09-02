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

## Ordinary buttons use an inset code-drawn cue.  Character/transition frames
## opt into the layered path below so the source border stays byte-identical.
var feedback_style: StyleBoxFlat
var feedback_inset := 0.0
var feedback_layered := false
var feedback_background_styles: Dictionary = {}
var feedback_frame_styles: Dictionary = {}
var _feedback_clone_cache: Dictionary = {}


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
	_clear_feedback()
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
	_clear_feedback()
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
	_clear_feedback()
	return self


func configure_small(square: Texture2D, shortwide: Texture2D, widesmall: Texture2D, fill := Color(0.055, 0.035, 0.018, 0.96)) -> AdaptiveButtonStyleBox:
	square_texture = square
	shortwide_texture = shortwide
	widesmall_texture = widesmall
	fill_color = fill
	force_square = false
	square_threshold = 1.35
	small_family = true
	_clear_feedback()
	return self


func set_feedback(
	fill: Color,
	border: Color,
	shadow: Color,
	shadow_size := 0.0,
	inset := 10.0,
	border_width := 1,
	layered := false,
) -> AdaptiveButtonStyleBox:
	_feedback_clone_cache.clear()
	feedback_style = StyleBoxFlat.new()
	feedback_style.bg_color = fill
	feedback_style.border_color = border
	feedback_style.set_border_width_all(maxi(0, border_width))
	feedback_style.set_corner_radius_all(8)
	feedback_style.shadow_color = shadow
	feedback_style.shadow_size = maxf(0.0, shadow_size)
	feedback_style.shadow_offset = Vector2.ZERO
	feedback_inset = maxf(0.0, inset)
	feedback_layered = layered
	feedback_background_styles.clear()
	feedback_frame_styles.clear()
	if feedback_layered:
		_prepare_layered_feedback()
	return self


func set_precomputed_layered_feedback(
	fill: Color,
	source_texture: Texture2D,
	background_mask: Texture2D,
	frame_texture: Texture2D,
	shadow := Color.TRANSPARENT,
	shadow_size := 0.0,
	inset := 0.0,
	border_width := 0,
) -> AdaptiveButtonStyleBox:
	return set_precomputed_layered_feedback_family(
		fill,
		[source_texture],
		[background_mask],
		[frame_texture],
		[Vector4.ZERO],
		shadow,
		shadow_size,
		inset,
		border_width,
	)


func set_precomputed_layered_feedback_family(
	fill: Color,
	source_textures: Array,
	background_masks: Array,
	frame_textures: Array,
	margins: Array = [],
	shadow := Color.TRANSPARENT,
	shadow_size := 0.0,
	inset := 0.0,
	border_width := 0,
) -> AdaptiveButtonStyleBox:
	set_feedback(fill, Color.TRANSPARENT, shadow, shadow_size, inset, border_width, false)
	feedback_layered = true
	var count := mini(source_textures.size(), mini(background_masks.size(), frame_textures.size()))
	for index in range(count):
		var source_texture := source_textures[index] as Texture2D
		var background_mask := background_masks[index] as Texture2D
		var frame_texture := frame_textures[index] as Texture2D
		var key := _texture_key(source_texture)
		if key.is_empty() or background_mask == null or frame_texture == null:
			continue
		var layer_margins := margins[index] as Vector4 if index < margins.size() else Vector4.ZERO
		feedback_background_styles[key] = _texture_layer_style(background_mask, layer_margins, fill)
		feedback_frame_styles[key] = _texture_layer_style(frame_texture, layer_margins)
	return self


func has_feedback() -> bool:
	return feedback_style != null


func clone_with_feedback(fill: Color, border: Color, shadow: Color, shadow_size := 5.0, inset := 10.0, border_width := 1) -> AdaptiveButtonStyleBox:
	var cache_key := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		str(fill),
		str(border),
		str(shadow),
		shadow_size,
		inset,
		border_width,
		content_margin_left,
		content_margin_top,
		content_margin_right,
		content_margin_bottom,
	]
	if _feedback_clone_cache.has(cache_key):
		return _feedback_clone_cache[cache_key] as AdaptiveButtonStyleBox
	var copy := AdaptiveButtonStyleBox.new()
	copy.compact = compact
	copy.standard = standard
	copy.wide = wide
	copy.square_texture = square_texture
	copy.shortwide_texture = shortwide_texture
	copy.widesmall_texture = widesmall_texture
	copy.small_family = small_family
	copy.square_threshold = square_threshold
	copy.fill_color = fill_color
	copy.square_alpha_safe_inset = square_alpha_safe_inset
	copy.force_square = force_square
	copy.force_widesmall = force_widesmall
	# Button uses the active StyleBox content margins to place its text.  Every
	# feedback frame must retain the exact same content rectangle or the label
	# visibly jumps when normal/pressed/result states are exchanged.
	copy.content_margin_left = content_margin_left
	copy.content_margin_top = content_margin_top
	copy.content_margin_right = content_margin_right
	copy.content_margin_bottom = content_margin_bottom
	if feedback_layered and not feedback_background_styles.is_empty():
		copy.set_feedback(fill, Color.TRANSPARENT, shadow, shadow_size, inset, border_width, false)
		copy.feedback_layered = true
		for key: String in feedback_background_styles:
			var background := feedback_background_styles[key] as StyleBoxTexture
			var frame := feedback_frame_styles.get(key) as StyleBoxTexture
			if background == null or frame == null:
				continue
			var layer_margins := Vector4(
				background.get_texture_margin(SIDE_LEFT),
				background.get_texture_margin(SIDE_TOP),
				background.get_texture_margin(SIDE_RIGHT),
				background.get_texture_margin(SIDE_BOTTOM),
			)
			copy.feedback_background_styles[key] = copy._texture_layer_style(background.texture, layer_margins, fill)
			copy.feedback_frame_styles[key] = frame
	else:
		copy.set_feedback(fill, border, shadow, shadow_size, inset, border_width, feedback_layered)
	_feedback_clone_cache[cache_key] = copy
	return copy


func _clear_feedback() -> void:
	_feedback_clone_cache.clear()
	feedback_style = null
	feedback_inset = 0.0
	feedback_layered = false
	feedback_background_styles.clear()
	feedback_frame_styles.clear()


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
	sb.set_texture_margin(SIDE_LEFT, margins.x)
	sb.set_texture_margin(SIDE_TOP, margins.y)
	sb.set_texture_margin(SIDE_RIGHT, margins.z)
	sb.set_texture_margin(SIDE_BOTTOM, margins.w)
	sb.content_margin_left = margins.x
	sb.content_margin_right = margins.z
	sb.draw_center = true
	return sb


func choose(rect: Rect2) -> StyleBoxTexture:
	var ratio := rect.size.x / maxf(rect.size.y, 1.0)
	return compact if ratio <= square_threshold else (standard if ratio <= 4.67 else wide)


func _draw(canvas_item: RID, rect: Rect2) -> void:
	if force_widesmall:
		var thin_texture := compact.texture
		if feedback_layered:
			var layer_key := _texture_key(thin_texture)
			if feedback_background_styles.has(layer_key):
				feedback_background_styles[layer_key].draw(canvas_item, rect)
				feedback_frame_styles[layer_key].draw(canvas_item, rect)
			else:
				RenderingServer.canvas_item_add_texture_rect(canvas_item, rect, thin_texture.get_rid(), false, Color.WHITE)
		else:
			square_fill_style(selected_small_fill_rect(rect)).draw(canvas_item, selected_small_fill_rect(rect))
			RenderingServer.canvas_item_add_texture_rect(canvas_item, rect, thin_texture.get_rid(), false, Color.WHITE)
	elif square_texture != null and (small_family or force_square):
		var ratio := rect.size.x / maxf(rect.size.y, 1.0)
		var texture := square_texture
		if not force_square and widesmall_texture != null and ratio > 2.2:
			texture = widesmall_texture
		elif not force_square and shortwide_texture != null and ratio > 1.35:
			texture = shortwide_texture
		if feedback_layered:
			var layer_key := _texture_key(texture)
			if feedback_background_styles.has(layer_key):
				feedback_background_styles[layer_key].draw(canvas_item, rect)
				feedback_frame_styles[layer_key].draw(canvas_item, rect)
			else:
				RenderingServer.canvas_item_add_texture_rect(canvas_item, rect, texture.get_rid(), false, Color.WHITE)
		else:
			square_fill_style(selected_small_fill_rect(rect)).draw(canvas_item, selected_small_fill_rect(rect))
			RenderingServer.canvas_item_add_texture_rect(canvas_item, selected_small_draw_rect(rect), texture.get_rid(), false, Color.WHITE)
	else:
		var source := choose(rect)
		if feedback_layered:
			var layer_key := _texture_key(source.texture)
			if feedback_background_styles.has(layer_key):
				feedback_background_styles[layer_key].draw(canvas_item, rect)
				feedback_frame_styles[layer_key].draw(canvas_item, rect)
			else:
				source.draw(canvas_item, rect)
		else:
			source.draw(canvas_item, rect)
	_draw_feedback(canvas_item, rect)


func _draw_feedback(canvas_item: RID, rect: Rect2) -> void:
	if feedback_style == null or feedback_layered:
		return
	var inset := minf(feedback_inset, maxf(0.0, minf(rect.size.x, rect.size.y) * 0.35))
	var feedback_rect := rect.grow(-inset)
	if feedback_rect.size.x <= 0.0 or feedback_rect.size.y <= 0.0:
		return
	feedback_style.draw(canvas_item, feedback_rect)


func _texture_key(texture: Texture2D) -> String:
	if texture == null:
		return ""
	return texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())


func _prepare_layered_feedback() -> void:
	var candidates: Array[Dictionary] = []
	if small_family or force_square:
		for texture in [square_texture, shortwide_texture, widesmall_texture]:
			if texture != null:
				candidates.append({"texture": texture, "margins": Vector4.ZERO})
	else:
		for source in [compact, standard, wide]:
			if source != null and source.texture != null:
				candidates.append({"texture": source.texture, "margins": Vector4(source.get_texture_margin(SIDE_LEFT), source.get_texture_margin(SIDE_TOP), source.get_texture_margin(SIDE_RIGHT), source.get_texture_margin(SIDE_BOTTOM))})
	for candidate: Dictionary in candidates:
		var texture: Texture2D = candidate.texture
		var key := _texture_key(texture)
		if key.is_empty() or feedback_background_styles.has(key):
			continue
		var margins: Vector4 = candidate.margins
		var cache_token := _layer_cache_token(texture, margins)
		var cached: Variant = texture.get_meta(cache_token) if texture.has_meta(cache_token) else null
		if cached is Dictionary and cached.has("background") and cached.has("frame"):
			feedback_background_styles[key] = cached.background
			feedback_frame_styles[key] = cached.frame
			continue
		var geometry_token := _layer_geometry_token(texture)
		var geometry: Variant = texture.get_meta(geometry_token) if texture.has_meta(geometry_token) else null
		var layers: Dictionary
		if geometry is Dictionary and geometry.has("background") and geometry.has("frame"):
			layers = geometry
		else:
			layers = _build_layer_images(texture)
			if not layers.is_empty():
				texture.set_meta(geometry_token, layers)
		if layers.is_empty():
			continue
		var background_style := _layer_style(layers.background, margins, feedback_style.bg_color)
		var frame_style := _layer_style(layers.frame, margins)
		texture.set_meta(cache_token, {"background": background_style, "frame": frame_style})
		feedback_background_styles[key] = background_style
		feedback_frame_styles[key] = frame_style


func _layer_cache_token(texture: Texture2D, margins: Vector4) -> StringName:
	var fill := feedback_style.bg_color
	var digest := str(hash("%s|%s|%s" % [_texture_key(texture), str(fill), str(margins)])).replace("-", "n")
	return StringName("hardcore_feedback_layers_%s" % digest)


func _layer_geometry_token(texture: Texture2D) -> StringName:
	var digest := str(hash(_texture_key(texture))).replace("-", "n")
	return StringName("hardcore_feedback_geometry_%s" % digest)


func _layer_style(image: Image, margins: Vector4, modulate := Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	style.modulate_color = modulate
	_apply_layer_style_margins(style, margins)
	return style


func _texture_layer_style(texture: Texture2D, margins: Vector4, modulate := Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = modulate
	_apply_layer_style_margins(style, margins)
	return style


func _apply_layer_style_margins(style: StyleBoxTexture, margins: Vector4) -> void:
	style.set_texture_margin(SIDE_LEFT, margins.x)
	style.set_texture_margin(SIDE_TOP, margins.y)
	style.set_texture_margin(SIDE_RIGHT, margins.z)
	style.set_texture_margin(SIDE_BOTTOM, margins.w)
	style.content_margin_left = margins.x
	style.content_margin_right = margins.z
	style.draw_center = true


func _build_layer_images(texture: Texture2D) -> Dictionary:
	var source := texture.get_image()
	if source == null or source.is_empty():
		return {}
	var center := Vector2i(source.get_width() / 2, source.get_height() / 2)
	if source.get_pixel(center.x, center.y).a > 0.01:
		return _build_opaque_layer_images(source)
	return _build_transparent_layer_images(source)


func _build_transparent_layer_images(source: Image) -> Dictionary:
	var width := source.get_width()
	var height := source.get_height()
	var barrier := PackedByteArray()
	barrier.resize(width * height)
	var outside := PackedByteArray()
	outside.resize(width * height)
	var queue: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			barrier[y * width + x] = 1 if source.get_pixel(x, y).a > 0.01 else 0
	for x in range(width):
		_queue_outside(Vector2i(x, 0), barrier, outside, queue, width, height)
		_queue_outside(Vector2i(x, height - 1), barrier, outside, queue, width, height)
	for y in range(height):
		_queue_outside(Vector2i(0, y), barrier, outside, queue, width, height)
		_queue_outside(Vector2i(width - 1, y), barrier, outside, queue, width, height)
	var head := 0
	while head < queue.size():
		var point := queue[head]
		head += 1
		for next in [Vector2i(point.x - 1, point.y), Vector2i(point.x + 1, point.y), Vector2i(point.x, point.y - 1), Vector2i(point.x, point.y + 1)]:
			_queue_outside(next, barrier, outside, queue, width, height)
	var background := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var frame := source.duplicate()
	for index in range(width * height):
		if barrier[index] == 0 and outside[index] == 0:
			var x := index % width
			var y := index / width
			background.set_pixel(x, y, Color.WHITE)
			frame.set_pixel(x, y, Color.TRANSPARENT)
	return {"background": background, "frame": frame}


func _build_opaque_layer_images(source: Image) -> Dictionary:
	var width := source.get_width()
	var height := source.get_height()
	var candidate := PackedByteArray()
	candidate.resize(width * height)
	var seed := Vector2i(width / 2, height / 2)
	for y in range(clampi(int(height * 0.12), 0, height - 1), clampi(int(height * 0.88), 1, height)):
		if not _opaque_candidate(source, seed.x, y):
			continue
		var left := seed.x
		while left > 0 and _opaque_candidate(source, left - 1, y):
			left -= 1
		var right := seed.x
		while right < width - 1 and _opaque_candidate(source, right + 1, y):
			right += 1
		for x in range(left, right + 1):
			candidate[y * width + x] = 1
	var visited := PackedByteArray()
	visited.resize(width * height)
	var queue: Array[Vector2i] = [seed]
	visited[seed.y * width + seed.x] = 1
	var head := 0
	while head < queue.size():
		var point := queue[head]
		head += 1
		for next in [Vector2i(point.x - 1, point.y), Vector2i(point.x + 1, point.y), Vector2i(point.x, point.y - 1), Vector2i(point.x, point.y + 1)]:
			if next.x < 0 or next.x >= width or next.y < 0 or next.y >= height:
				continue
			var index: int = next.y * width + next.x
			if visited[index] == 1 or candidate[index] == 0:
				continue
			visited[index] = 1
			queue.append(next)
	var background := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var frame := source.duplicate()
	for index in range(width * height):
		if visited[index] == 1:
			var x := index % width
			var y := index / width
			background.set_pixel(x, y, Color.WHITE)
			frame.set_pixel(x, y, Color.TRANSPARENT)
	return {"background": background, "frame": frame}


func _opaque_candidate(image: Image, x: int, y: int) -> bool:
	var pixel := image.get_pixel(x, y)
	var maximum := maxf(pixel.r, maxf(pixel.g, pixel.b))
	var minimum := minf(pixel.r, minf(pixel.g, pixel.b))
	return pixel.a > 0.0 and maximum <= 0.47 and maximum - minimum <= 0.16


func _queue_outside(point: Vector2i, barrier: PackedByteArray, outside: PackedByteArray, queue: Array[Vector2i], width: int, height: int) -> void:
	if point.x < 0 or point.x >= width or point.y < 0 or point.y >= height:
		return
	var index := point.y * width + point.x
	if barrier[index] == 1 or outside[index] == 1:
		return
	outside[index] = 1
	queue.append(point)
