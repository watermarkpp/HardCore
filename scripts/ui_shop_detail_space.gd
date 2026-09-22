class_name UIShopDetailSpace
extends RefCounted

## R3: space is measured AFTER calibration, in owner's local coordinates.
## Screen clearances are converted to local units. No text/price mutation.
const FRAME_CLEAR_PX := 32.0 # preferred visual breathing room
const FRAME_CLEAR_MIN_PX := 30.0 # hard acceptance floor; never go below
const TITLE_CLEAR_PX := 26.0
const ACTION_CLEAR_PX := 36.0 # preferred visual breathing room
const ACTION_CLEAR_MIN_PX := 32.0 # hard acceptance floor; never go below
const ACTION_FRAME_PX := 18.0
const ACTION_STACK_GAP_PX := 16.0
const Frame := preload("res://scripts/gothic_frame_factory.gd")
const VisualBounds := preload("res://scripts/ui_style_visual_bounds.gd")

## The shop section heading remains visible above the independent item card.
static func sync_section_caption(owner: Control, _card_active: bool) -> void:
	if not is_instance_valid(owner):
		return
	var caption := owner.get_node_or_null("DetailPanel/DetailTitle") as Label
	var decoration := owner.get_node_or_null("DetailPanel/DetailPanelDecoration") as Control
	if caption == null or decoration == null:
		return # Non-shop presenters retain their existing layout and headings.
	if not caption.visible:
		caption.show()

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
	var minimum_safe := inset(opening, Vector2(FRAME_CLEAR_MIN_PX / scale.x, FRAME_CLEAR_MIN_PX / scale.y))
	# Reserve the persistent section caption independently of the item title.
	var top := safe.position.y
	var minimum_top := minimum_safe.position.y
	if title.visible:
		var title_floor := rect_in(owner, title).end.y + TITLE_CLEAR_PX / scale.y
		top = maxf(top, title_floor)
		minimum_top = maxf(minimum_top, title_floor)
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
	# Calibration owns action positions and dimensions (reference v72 APK).
	# Measuring an item card must never rearrange buy/repair/quantity controls.
	var action_top := safe.end.y + ACTION_CLEAR_PX / scale.y
	var minimum_action_top := minimum_safe.end.y + ACTION_CLEAR_MIN_PX / scale.y
	var protected: Array[Rect2] = []
	for c: Control in actions:
		var r := visual_rect(owner, c)
		protected.append(r)
		action_top = minf(action_top, r.position.y)
		minimum_action_top = minf(minimum_action_top, r.position.y)
	var end_y := minf(safe.end.y, action_top - ACTION_CLEAR_PX / scale.y)
	var minimum_end_y := minf(
		minimum_safe.end.y,
		minimum_action_top - ACTION_CLEAR_MIN_PX / scale.y
	)
	var area := Rect2(Vector2(safe.position.x, top), Vector2(safe.size.x, maxf(0.0, end_y - top)))
	var expanded_area := Rect2(
		Vector2(minimum_safe.position.x, minimum_top),
		Vector2(minimum_safe.size.x, maxf(0.0, minimum_end_y - minimum_top))
	)
	# Clip against the viewport without using an unrelated old detail label.
	var ot := owner.get_global_transform_with_canvas()
	var viewport_rect := transformed(ot.affine_inverse(), owner.get_viewport().get_visible_rect())
	area = area.intersection(viewport_rect)
	expanded_area = expanded_area.intersection(viewport_rect)
	# Transform chains accumulate ~1e-5 px drift, which can shrink the legal
	# floor rect below its exact value (e.g. 263.999969 instead of 264.0) and
	# create a phantom sub-pixel deficit. Quantize the expanded candidate to a
	# 1/1000 px grid: this restores the TRUE legal geometry (worst case +0.0005
	# px, far inside the 0.05 px acceptance tolerance) without changing any
	# real clearance. The preferred region is intentionally left untouched.
	expanded_area = Rect2(
		Vector2(snappedf(expanded_area.position.x, 0.001), snappedf(expanded_area.position.y, 0.001)),
		Vector2(snappedf(expanded_area.size.x, 0.001), snappedf(expanded_area.size.y, 0.001)))
	return {"region": area, "expanded_region": expanded_area,
		"side": "center", "kind": "shop", "frame_opening": opening,
		"screen_scale": scale, "protected": protected, "title_rect": rect_in(owner, title),
		"action_layout": "calibrated",
		"caption_reserved": title.visible, "frame_safe_rect": safe,
		"minimum_frame_safe_rect": minimum_safe,
		"caption_reserved_height": maxf(0.0, top - safe.position.y),
		"heading_mode": "section_caption",
		"action_gap_px": ACTION_CLEAR_PX, "frame_gap_px": FRAME_CLEAR_PX,
		"minimum_action_gap_px": ACTION_CLEAR_MIN_PX,
		"minimum_frame_gap_px": FRAME_CLEAR_MIN_PX,
		"layout_policy": "preferred_then_legal_minimum",
		"pixel_scope": "viewport_only" if DisplayServer.get_name() == "headless" else "screen"}
