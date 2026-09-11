extends RefCounted

## R3.1: conservative visual envelope using PUBLIC script APIs only.
## Does not draw, load textures, mutate a style, or call a native-only method.
## Bounds are local to the caller. Unknown custom styles fail the preflight;
## they are never silently treated as the smaller button hit rectangle.
const Adaptive := preload("res://scripts/adaptive_button_style_box.gd")
const STATES: Array[StringName] = [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]
const MAX_DEPTH := 8

static func _ok(rect: Rect2) -> Dictionary:
	return {"ok": true, "rect": rect, "reason": ""}

static func _bad(reason: String) -> Dictionary:
	return {"ok": false, "rect": Rect2(), "reason": reason}

static func _finite_rect(rect: Rect2) -> bool:
	return rect.position.is_finite() and rect.size.is_finite() and rect.size.x >= 0.0 and rect.size.y >= 0.0

static func _expand(rect: Rect2, margins: Vector4) -> Rect2:
	# Negative expand values can only move drawing inward. Retaining the
	# original rectangle is deliberately conservative (no clearance shrink).
	var left := maxf(0.0, margins.x)
	var top := maxf(0.0, margins.y)
	var right := maxf(0.0, margins.z)
	var bottom := maxf(0.0, margins.w)
	return Rect2(rect.position - Vector2(left, top), rect.size + Vector2(left + right, top + bottom))

static func _texture_bounds(style: StyleBoxTexture, rect: Rect2) -> Dictionary:
	var margins := Vector4(style.get_expand_margin(SIDE_LEFT), style.get_expand_margin(SIDE_TOP), style.get_expand_margin(SIDE_RIGHT), style.get_expand_margin(SIDE_BOTTOM))
	if not margins.is_finite():
		return _bad("NONFINITE_TEXTURE_EXPANSION")
	return _ok(_expand(rect, margins))

static func _flat_bounds(style: StyleBoxFlat, rect: Rect2) -> Dictionary:
	var margins := Vector4(style.get_expand_margin(SIDE_LEFT), style.get_expand_margin(SIDE_TOP), style.get_expand_margin(SIDE_RIGHT), style.get_expand_margin(SIDE_BOTTOM))
	if not margins.is_finite() or not style.shadow_offset.is_finite() or not style.skew.is_finite() or not is_finite(style.shadow_size) or not is_finite(style.anti_aliasing_size):
		return _bad("NONFINITE_FLAT_GEOMETRY")
	var shape := _expand(rect, margins)
	# Skew is center-relative in native drawing. This full-extent allowance
	# intentionally overbounds it instead of understating an ornamental edge.
	var skew_pad := Vector2(absf(style.skew.x) * shape.size.y, absf(style.skew.y) * shape.size.x)
	shape = Rect2(shape.position - skew_pad, shape.size + 2.0 * skew_pad)
	var result := shape
	if style.shadow_size > 0:
		var shadow := shape.grow(float(style.shadow_size))
		shadow.position += style.shadow_offset
		result = result.merge(shadow)
	if style.anti_aliasing:
		result = result.grow(maxf(0.0, style.anti_aliasing_size))
	return _ok(result.merge(rect))

static func _adaptive_bounds(style: StyleBox, rect: Rect2, depth: int) -> Dictionary:
	# This is an adapter for the LOCKED AdaptiveButtonStyleBox source, not a
	# generic guess about all custom StyleBoxes. Its native 9-slice candidates,
	# bitmap family and all prepared feedback layers may draw at this rect.
	# Unioning the existing family conservatively covers ratio switches too.
	var result := rect
	for property_name: String in ["compact", "standard", "wide"]:
		var source: Variant = style.get(property_name)
		if source != null:
			if not source is StyleBox:
				return _bad("ADAPTIVE_SOURCE_TYPE:" + property_name)
			var bounds := style_bounds(source as StyleBox, rect, depth + 1)
			if not bool(bounds.ok):
				return bounds
			result = result.merge(bounds.rect)
	if bool(style.get("feedback_layered")):
		for property_name: String in ["feedback_background_styles", "feedback_frame_styles"]:
			var layers: Variant = style.get(property_name)
			if not layers is Dictionary:
				return _bad("ADAPTIVE_LAYER_TYPE:" + property_name)
			for value: Variant in (layers as Dictionary).values():
				if not value is StyleBox:
					return _bad("ADAPTIVE_LAYER_NOT_STYLE")
				var bounds := style_bounds(value as StyleBox, rect, depth + 1)
				if not bool(bounds.ok):
					return bounds
				result = result.merge(bounds.rect)
	else:
		var feedback: Variant = style.get("feedback_style")
		if feedback != null:
			if not feedback is StyleBox:
				return _bad("ADAPTIVE_FEEDBACK_TYPE")
			var inset_value := float(style.get("feedback_inset"))
			if not is_finite(inset_value):
				return _bad("NONFINITE_FEEDBACK_INSET")
			var amount := minf(maxf(0.0, inset_value), maxf(0.0, minf(rect.size.x, rect.size.y) * 0.35))
			var inner := rect.grow(-amount)
			if inner.has_area():
				var bounds := style_bounds(feedback as StyleBox, inner, depth + 1)
				if not bool(bounds.ok):
					return bounds
				result = result.merge(bounds.rect)
	return _ok(result)

static func style_bounds(style: StyleBox, rect: Rect2, depth: int = 0) -> Dictionary:
	if not _finite_rect(rect) or depth > MAX_DEPTH:
		return _bad("INVALID_RECT_OR_RECURSION")
	if style == null:
		return _ok(rect)
	var script: Script = style.get_script() as Script
	if script != null:
		if script == Adaptive:
			return _adaptive_bounds(style, rect, depth)
		return _bad("UNSUPPORTED_CUSTOM_STYLE:" + script.resource_path)
	if style is StyleBoxTexture:
		return _texture_bounds(style as StyleBoxTexture, rect)
	if style is StyleBoxFlat:
		return _flat_bounds(style as StyleBoxFlat, rect)
	if style is StyleBoxEmpty:
		return _ok(rect)
	# The current action theme uses the three native types above and Adaptive.
	# A future new renderer needs an explicit adapter before layout acceptance.
	return _bad("UNSUPPORTED_NATIVE_STYLE:" + style.get_class())

static func transform_rect(transform: Transform2D, rect: Rect2) -> Rect2:
	var out := Rect2(transform * rect.position, Vector2.ZERO)
	for point: Vector2 in [Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		out = out.expand(transform * point)
	return out

static func control_bounds(control: Control, depth: int = 0) -> Dictionary:
	if not is_instance_valid(control) or depth > MAX_DEPTH:
		return _bad("INVALID_CONTROL_OR_RECURSION")
	var base := Rect2(Vector2.ZERO, control.size)
	if not _finite_rect(base):
		return _bad("NONFINITE_CONTROL_SIZE")
	var result := base
	var states: Array[StringName] = STATES if control is BaseButton else []
	if control is Panel or control is PanelContainer:
		states = [&"panel"]
	for state: StringName in states:
		var bounds := style_bounds(control.get_theme_stylebox(state), base)
		if not bool(bounds.ok):
			bounds["reason"] = str(control.name) + "/" + str(state) + ":" + str(bounds.reason)
			return bounds
		result = result.merge(bounds.rect)
	# Quantity rows are plain Controls containing real minus/plus buttons.
	# Include their ornaments too, including nested decorative controls. Not
	# clipping the envelope to a parent is conservative for clearance testing.
	for child: Node in control.get_children():
		if child is Control and (child as Control).visible:
			var bounds := control_bounds(child as Control, depth + 1)
			if not bool(bounds.ok):
				return bounds
			result = result.merge(transform_rect((child as Control).get_transform(), bounds.rect))
	return _ok(result)
