class_name GothicModalLayout
extends RefCounted

## The frame source is 932x685. Its deepest inner ornaments end at y=85
## and begin again at y=579. These insets add an 8 px breathing gap so
## runtime content never touches either visible ring.
const FRAME_SAFE_INSET := Vector4(54, 94, 54, 114)
const HEADER_HEIGHT := 48.0
const HEADER_BODY_GAP := 10.0
const CLOSE_TOUCH_SIZE := Vector2(56, 56)
const VIEWPORT_MARGIN := Vector2(24, 24)
const STANDARD_TOUCH_HEIGHT := 56.0
const COMPACT_TOUCH_HEIGHT := 46.0
const CONTROL_GAP := 8.0
const SECTION_PADDING := Vector4(18, 18, 18, 18)
const SHOP_ICON_FRACTION := 0.26
const SHOP_TEXT_GAP := 12.0


static func safe_rect(panel_size: Vector2) -> Rect2:
	return Rect2(
		Vector2(FRAME_SAFE_INSET.x, FRAME_SAFE_INSET.y),
		panel_size - Vector2(
			FRAME_SAFE_INSET.x + FRAME_SAFE_INSET.z,
			FRAME_SAFE_INSET.y + FRAME_SAFE_INSET.w
		)
	)


static func header_rect(panel_size: Vector2, title_width: float) -> Rect2:
	var safe := safe_rect(panel_size)
	return Rect2(
		Vector2(safe.position.x + (safe.size.x - title_width) * 0.5, safe.position.y),
		Vector2(title_width, HEADER_HEIGHT)
	)


static func close_rect(panel_size: Vector2) -> Rect2:
	var safe := safe_rect(panel_size)
	return Rect2(
		Vector2(safe.end.x - CLOSE_TOUCH_SIZE.x, safe.position.y),
		CLOSE_TOUCH_SIZE
	)


static func body_rect(panel_size: Vector2) -> Rect2:
	var safe := safe_rect(panel_size)
	var body_top := safe.position.y + HEADER_HEIGHT + HEADER_BODY_GAP
	return Rect2(
		Vector2(safe.position.x, body_top),
		Vector2(safe.size.x, safe.end.y - body_top)
	)


static func split_columns(rect: Rect2, weights: Array[float], gap: float) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if weights.is_empty():
		return result
	var total_weight := 0.0
	for weight in weights:
		total_weight += maxf(weight, 0.0)
	assert(total_weight > 0.0)
	var available_width := rect.size.x - gap * float(weights.size() - 1)
	var cursor_x := rect.position.x
	for index in range(weights.size()):
		var width := available_width * maxf(weights[index], 0.0) / total_weight
		if index == weights.size() - 1:
			width = rect.end.x - cursor_x
		result.append(Rect2(cursor_x, rect.position.y, width, rect.size.y))
		cursor_x += width + gap
	return result


static func split_rows(rect: Rect2, weights: Array[float], gap: float) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if weights.is_empty():
		return result
	var total_weight := 0.0
	for weight in weights:
		total_weight += maxf(weight, 0.0)
	assert(total_weight > 0.0)
	var available_height := rect.size.y - gap * float(weights.size() - 1)
	var cursor_y := rect.position.y
	for index in range(weights.size()):
		var height := available_height * maxf(weights[index], 0.0) / total_weight
		if index == weights.size() - 1:
			height = rect.end.y - cursor_y
		result.append(Rect2(rect.position.x, cursor_y, rect.size.x, height))
		cursor_y += height + gap
	return result


static func inset_rect(rect: Rect2, margins: Vector4) -> Rect2:
	return Rect2(
		rect.position + Vector2(margins.x, margins.y),
		rect.size - Vector2(margins.x + margins.z, margins.y + margins.w)
	)


static func vertical_button_stack(rect: Rect2, count: int, gap := CONTROL_GAP, preferred_height := STANDARD_TOUCH_HEIGHT) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if count <= 0:
		return result
	var total_preferred := preferred_height * count + gap * (count - 1)
	var button_height := preferred_height if total_preferred <= rect.size.y else (rect.size.y - gap * (count - 1)) / count
	var stack_height := button_height * count + gap * (count - 1)
	var cursor_y := rect.position.y + (rect.size.y - stack_height) * 0.5
	for _index in range(count):
		result.append(Rect2(rect.position.x, cursor_y, rect.size.x, button_height))
		cursor_y += button_height + gap
	return result


static func horizontal_button_row(rect: Rect2, count: int, gap := CONTROL_GAP, height := STANDARD_TOUCH_HEIGHT) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if count <= 0:
		return result
	var button_width := (rect.size.x - gap * (count - 1)) / count
	var row_height := minf(height, rect.size.y)
	var cursor_x := rect.position.x
	var y := rect.position.y + (rect.size.y - row_height) * 0.5
	for index in range(count):
		var width := button_width if index < count - 1 else rect.end.x - cursor_x
		result.append(Rect2(cursor_x, y, width, row_height))
		cursor_x += width + gap
	return result


static func apply_button_rect(button: Button, rect: Rect2) -> void:
	apply_rect(button, rect)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


static func apply_centered_label(label: Label, rect: Rect2, alignment := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	apply_rect(label, rect)
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


static func shop_card_regions(card_size: Vector2) -> Dictionary:
	var outer := Rect2(Vector2.ZERO, card_size)
	var content := inset_rect(outer, SECTION_PADDING)
	var icon_width := content.size.x * SHOP_ICON_FRACTION
	var icon_rect := Rect2(content.position, Vector2(icon_width, content.size.y))
	var text_rect := Rect2(
		Vector2(icon_rect.end.x + SHOP_TEXT_GAP, content.position.y),
		Vector2(content.end.x - icon_rect.end.x - SHOP_TEXT_GAP, content.size.y)
	)
	return {"icon": icon_rect, "text": text_rect}


static func apply_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size


static func apply_responsive_scale(control: Control, design_size: Vector2, viewport_size: Vector2) -> void:
	var available := Vector2(
		maxf(viewport_size.x - VIEWPORT_MARGIN.x * 2.0, 1.0),
		maxf(viewport_size.y - VIEWPORT_MARGIN.y * 2.0, 1.0)
	)
	var uniform_scale := minf(1.0, minf(available.x / design_size.x, available.y / design_size.y))
	control.pivot_offset = design_size * 0.5
	control.scale = Vector2.ONE * uniform_scale


static func contains(outer: Rect2, inner: Rect2, epsilon := 0.5) -> bool:
	return (
		inner.position.x >= outer.position.x - epsilon
		and inner.position.y >= outer.position.y - epsilon
		and inner.end.x <= outer.end.x + epsilon
		and inner.end.y <= outer.end.y + epsilon
	)
