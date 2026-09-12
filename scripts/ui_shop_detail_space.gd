class_name UIShopDetailSpace
extends RefCounted

## R3: space is measured AFTER calibration, in owner's local coordinates.
## Screen clearances are converted to local units. No text/price mutation.
const FRAME_CLEAR_PX := 32.0 # 30px requirement + 2px rounding reserve
const TITLE_CLEAR_PX := 26.0
const ACTION_CLEAR_PX := 36.0
const ACTION_FRAME_PX := 18.0
const ACTION_STACK_GAP_PX := 16.0
const Frame := preload("res://scripts/gothic_frame_factory.gd")
const VisualBounds := preload("res://scripts/ui_style_visual_bounds.gd")

static func transformed(t: Transform2D, r: Rect2) -> Rect2:
	var out := Rect2(t * r.position, Vector2.ZERO)
	for p: Vector2 in [Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		out = out.expand(t * p)
	return out

static func rect_in(owner: Control, target: Control, local_rect: Rect2 = Rect2()) -> Rect2:
	if not is_instance_valid(target):
		return Rect2()
	var ot := owner.get_global_transform_with_canvas()
	if absf(ot.determinant()) < 0.000001:
		return Rect2()
	var r := local_rect if local_rect.has_area() else Rect2(Vector2.ZERO, target.size)
	return transformed(ot.affine_inverse() * target.get_global_transform_with_canvas(), r)

static func screen_scale(owner: Control) -> Vector2:
	var t := owner.get_viewport().get_screen_transform() * owner.get_global_transform_with_canvas()
	# A headless test has no physical display; it verifies viewport-pixel layout
	# only. It MUST NOT report a physical-screen spacing PASS.
	if DisplayServer.get_name() == "headless":
		t = owner.get_global_transform_with_canvas()
	if absf(t.x.y) > 0.0001 or absf(t.y.x) > 0.0001:
		return Vector2.ZERO # project UI is axis-aligned; never guess under shear
	return Vector2(absf(t.x.x), absf(t.y.y))

static func inset(r: Rect2, amount: Vector2) -> Rect2:
	return Rect2(r.position + amount, Vector2(maxf(0.0, r.size.x - 2.0 * amount.x), maxf(0.0, r.size.y - 2.0 * amount.y)))

static func visual_rect(owner: Control, c: Control) -> Rect2:
	var bounds := VisualBounds.control_bounds(c)
	if not bool(bounds.get("ok", false)):
		return Rect2() # region() rejects unsupported actions before any reflow.
	return rect_in(owner, c, bounds.get("rect", Rect2()))

static func _shift_y(owner: Control, c: Control, delta: float) -> void:
	if absf(delta) < 0.05:
		return
	var parent := c.get_parent() as CanvasItem
	if parent == null:
		return
	var relative := parent.get_global_transform_with_canvas().affine_inverse() * owner.get_global_transform_with_canvas()
	c.position += (relative * Vector2(0.0, delta)) - (relative * Vector2.ZERO)

static func _shift_x(owner: Control, c: Control, delta: float) -> void:
	if absf(delta) < 0.05:
		return
	var parent := c.get_parent() as CanvasItem
	if parent == null:
		return
	var t := parent.get_global_transform_with_canvas().affine_inverse() * owner.get_global_transform_with_canvas()
	c.position += (t * Vector2(delta, 0.0)) - (t * Vector2.ZERO)

static func _set_size_in_owner(owner: Control, c: Control, extent: Vector2) -> void:
	var own := owner.get_global_transform_with_canvas()
	var ct := c.get_global_transform_with_canvas()
	var local_size := Vector2(extent.x * own.x.length() / maxf(ct.x.length(), 0.000001), extent.y * own.y.length() / maxf(ct.y.length(), 0.000001))
	if not c.size.is_equal_approx(local_size):
		c.size = local_size

static func _minimum_size_in_owner(owner: Control, c: Control) -> Vector2:
	var minimum := c.get_combined_minimum_size()
	var own := owner.get_global_transform_with_canvas()
	var ct := c.get_global_transform_with_canvas()
	return Vector2(minimum.x * ct.x.length() / maxf(own.x.length(), 0.000001), minimum.y * ct.y.length() / maxf(own.y.length(), 0.000001))

static func _visible_actions(owner: Control) -> Array[Control]:
	var out: Array[Control] = []
	for name_value: String in ["buy_button", "repair_button", "sell_quantity_row", "sell_quantity_button"]:
		var value: Variant = owner.get(name_value)
		if value is Control and (value as Control).is_visible_in_tree():
			out.append(value as Control)
	return out

static func region(owner: Control) -> Dictionary:
	var decoration := owner.get_node_or_null("DetailPanel/DetailPanelDecoration") as Control
	var title := owner.get_node_or_null("DetailPanel/DetailTitle") as Control
	var scale := screen_scale(owner)
	if decoration == null or title == null or scale.x <= 0.000001 or scale.y <= 0.000001:
		return {"region": Rect2(), "side": "center", "kind": "shop", "error": "GEOMETRY_NOT_READY"}
	var i: Vector4 = Frame.INSET_FRAME_V3_INNER_INSETS
	var opening := rect_in(owner, decoration, Rect2(Vector2(i.x, i.y), decoration.size - Vector2(i.x+i.z, i.y+i.w)))
	if not opening.has_area():
		return {"region": Rect2(), "side": "center", "kind": "shop", "error": "EMPTY_FRAME_OPENING"}
	var safe := inset(opening, Vector2(FRAME_CLEAR_PX / scale.x, FRAME_CLEAR_PX / scale.y))
	var top := maxf(safe.position.y, rect_in(owner, title).end.y + TITLE_CLEAR_PX / scale.y)
	var actions := _visible_actions(owner)
	# Validate before shifting/resizing anything. A future unknown custom style
	# must not silently use a hit box and violate the 30px visual clearance.
	for action: Control in actions:
		var bounds := VisualBounds.control_bounds(action)
		if not bool(bounds.get("ok", false)):
			var reason := str(bounds.get("reason", "UNKNOWN_STYLE"))
			if str(owner.get_meta("r31_bounds_error", "")) != reason:
				owner.set_meta("r31_bounds_error", reason)
				push_error("R31_ACTION_VISUAL_BOUNDS:" + reason)
			return {"region": Rect2(), "side": "center", "kind": "shop", "error": reason}
	if owner.has_meta("r31_bounds_error"):
		owner.remove_meta("r31_bounds_error")
	for c: Control in actions:
		if not c.has_meta("r3_original_size"):
			c.set_meta("r3_original_size", rect_in(owner, c).size)
	if actions.size() == 1 and actions[0] == owner.get("buy_button"):
		var original: Vector2 = actions[0].get_meta("r3_original_size")
		_set_size_in_owner(owner, actions[0], original)
		_shift_x(owner, actions[0], opening.get_center().x - visual_rect(owner, actions[0]).get_center().x)
	# Buy+repair may use one well-spaced row when their REAL text/style minima
	# fit. No smaller font, no ellipsis, no hidden repair function. Other modes
	# retain their vertical order. This also reserves enough reading height.
	var horizontal := false
	if actions.size() == 2 and actions[0] == owner.get("buy_button") and actions[1] == owner.get("repair_button"):
		var a := actions[0] as Button
		var b := actions[1] as Button
		var usable := opening.size.x - 2.0 * ACTION_FRAME_PX / scale.x
		var gap := ACTION_STACK_GAP_PX / scale.x
		var amin := _minimum_size_in_owner(owner, a)
		var bmin := _minimum_size_in_owner(owner, b)
		var aw := maxf(88.0, amin.x + 8.0)
		var bw := maxf(128.0, bmin.x + 8.0)
		if aw + bw + gap <= usable:
			var target_h := maxf(51.0, maxf(amin.y, bmin.y) + 4.0)
			# R3.2: reserve the DRAWN minima first. The old allocation filled the
			# complete hit-box budget, so any positive ornament expansion made a
			# feasible row fail its subsequent visual-width check.
			_set_size_in_owner(owner, a, Vector2(aw, target_h))
			_set_size_in_owner(owner, b, Vector2(bw, target_h))
			var actual_a := visual_rect(owner, a)
			var actual_b := visual_rect(owner, b)
			var drawn_minimum := actual_a.size.x + actual_b.size.x + gap
			if actual_a.has_area() and actual_b.has_area() and drawn_minimum <= usable + 0.05:
				var spare := maxf(0.0, usable - drawn_minimum - 0.5)
				if spare > 0.0:
					_set_size_in_owner(owner, b, Vector2(bw + spare, target_h))
					actual_b = visual_rect(owner, b)
					# A responsive style may change family at the wider size. Keep
					# the already verified minimal row rather than guessing bounds.
					if not actual_b.has_area() or actual_a.size.x + actual_b.size.x + gap > usable + 0.05:
						_set_size_in_owner(owner, b, Vector2(bw, target_h))
						actual_b = visual_rect(owner, b)
				var drawn_width := actual_a.size.x + actual_b.size.x + gap
				if actual_b.has_area() and drawn_width <= usable + 0.05:
					var left := opening.get_center().x - drawn_width * 0.5
					_shift_x(owner, a, left - actual_a.position.x)
					_shift_x(owner, b, left + actual_a.size.x + gap - actual_b.position.x)
					horizontal = true
	if not horizontal:
		for c: Control in actions:
			if c is BaseButton:
				_set_size_in_owner(owner, c, c.get_meta("r3_original_size"))
				_shift_x(owner, c, opening.get_center().x - visual_rect(owner, c).get_center().x)
	# Reclaim unused lower space. Styles and all action handlers are
	# preserved. This is stable per trade mode/viewport, NEVER per selected item.
	var bottom := opening.end.y - ACTION_FRAME_PX / scale.y
	for idx in range(actions.size() - 1, -1, -1):
		var c := actions[idx]
		var r := visual_rect(owner, c)
		_shift_y(owner, c, bottom - r.end.y)
		if not horizontal:
			bottom -= r.size.y + ACTION_STACK_GAP_PX / scale.y
	var action_top := safe.end.y + ACTION_CLEAR_PX / scale.y
	var protected: Array[Rect2] = []
	for c: Control in actions:
		var r := visual_rect(owner, c)
		protected.append(r)
		action_top = minf(action_top, r.position.y)
	var end_y := minf(safe.end.y, action_top - ACTION_CLEAR_PX / scale.y)
	var area := Rect2(Vector2(safe.position.x, top), Vector2(safe.size.x, maxf(0.0, end_y - top)))
	# Clip against the viewport without using an unrelated old detail label.
	var ot := owner.get_global_transform_with_canvas()
	var viewport_rect := transformed(ot.affine_inverse(), owner.get_viewport().get_visible_rect())
	area = area.intersection(viewport_rect)
	return {"region": area, "side": "center", "kind": "shop", "frame_opening": opening,
		"screen_scale": scale, "protected": protected, "title_rect": rect_in(owner, title),
		"action_layout": "row" if horizontal else "stack",
		"action_gap_px": ACTION_CLEAR_PX, "frame_gap_px": FRAME_CLEAR_PX,
		"pixel_scope": "viewport_only" if DisplayServer.get_name() == "headless" else "screen"}
