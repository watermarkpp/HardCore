class_name UIItemDetailDock
extends RefCounted

## Every rectangle returned here is in the owning panel's LOCAL coordinates.
## This is deliberately independent of the selected row, scroll offset, and
## screenshot resolution. Authored/calibrated control geometry stays authoritative.
const EDGE := 18.0
const GAP := 12.0

static func transformed_rect(transform: Transform2D, rect: Rect2) -> Rect2:
	var result := Rect2(transform * rect.position, Vector2.ZERO)
	for point: Vector2 in [Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		result = result.expand(transform * point)
	return result

static func rect_in(owner_control: Control, target: Control) -> Rect2:
	if not is_instance_valid(owner_control) or not is_instance_valid(target):
		return Rect2()
	var owner_transform := owner_control.get_global_transform_with_canvas()
	if absf(owner_transform.determinant()) < 0.000001:
		return Rect2()
	var transform := owner_transform.affine_inverse() * target.get_global_transform_with_canvas()
	return transformed_rect(transform, Rect2(Vector2.ZERO, target.size))

static func viewport_in(owner_control: Control) -> Rect2:
	var transform := owner_control.get_global_transform_with_canvas()
	if absf(transform.determinant()) < 0.000001:
		return Rect2()
	return transformed_rect(transform.affine_inverse(), owner_control.get_viewport().get_visible_rect().grow(-EDGE))

static func side_region(owner_control: Control, scroll: Control, side: String) -> Dictionary:
	if not is_instance_valid(scroll):
		return {"region": Rect2(), "side": side}
	var safe := viewport_in(owner_control)
	var grid_view := rect_in(owner_control, scroll)
	# Protect the WHOLE six-column viewport, including its scroll indicator.
	# Do not place the detail inside empty cells or between grid and scrollbar.
	var top := maxf(safe.position.y, grid_view.position.y)
	var bottom := minf(safe.end.y, grid_view.end.y)
	var left := safe.position.x if side == "left" else grid_view.end.x + GAP
	var right := grid_view.position.x - GAP if side == "left" else safe.end.x
	return {"region": Rect2(left, top, maxf(0.0, right - left), maxf(0.0, bottom - top)), "expanded_region": Rect2(left, safe.position.y, maxf(0.0, right - left), safe.size.y), "side": side}

static func shop_region(owner: Control) -> Dictionary:
	var panel := owner.get_node_or_null("DetailPanel") as Control
	var decoration := owner.get_node_or_null("DetailPanel/DetailPanelDecoration") as Control
	var title := owner.get_node_or_null("DetailPanel/DetailTitle") as Control
	if panel == null or decoration == null or title == null:
		return {"region": Rect2(), "side": "center"}
	var transform := owner.get_global_transform_with_canvas()
	if absf(transform.determinant()) < 0.000001:
		return {"region": Rect2(), "side": "center"}
	# Use the ACTUAL calibrated second-level decoration and its measured opening,
	# not the uncalibrated logical DetailPanel rectangle. No manual JSON edits.
	var inset: Vector4 = preload("res://scripts/gothic_frame_factory.gd").INSET_FRAME_V3_INNER_INSETS
	var local_opening := Rect2(
		Vector2(inset.x, inset.y),
		decoration.size - Vector2(inset.x + inset.z, inset.y + inset.w)
	)
	if local_opening.size.x <= 0.0 or local_opening.size.y <= 0.0:
		return {"region": Rect2(), "side": "center"}
	var relative := transform.affine_inverse() * decoration.get_global_transform_with_canvas()
	var opening := transformed_rect(relative, local_opening).grow(-8.0)
	var region := opening.intersection(viewport_in(owner))
	var title_rect := rect_in(owner, title)
	var top := maxf(region.position.y, title_rect.end.y + GAP)
	var bottom := region.end.y
	for property_name: String in ["buy_button", "repair_button", "sell_quantity_row", "sell_quantity_button"]:
		var control: Variant = owner.get(property_name)
		if control is Control and (control as Control).is_visible_in_tree():
			bottom = minf(bottom, rect_in(owner, control).position.y - GAP)
	return {
		"region": Rect2(Vector2(region.position.x, top), Vector2(maxf(0.0, region.size.x), maxf(0.0, bottom - top))),
		"side": "center",
	}

static func equipment_region(owner_control: Control, buttons: Dictionary) -> Dictionary:
	# Equipped-item details stay in the central paper-doll column. BAG items
	# use side_region instead. None of the ten equipment slot buttons is covered.
	var panel := owner_control.get_node_or_null("EquipmentPanel") as Control
	if panel == null:
		return {"region": Rect2(), "side": "center"}
	var frame := rect_in(owner_control, panel).intersection(viewport_in(owner_control))
	var left := frame.position.x + 12.0
	var right := frame.end.x - 12.0
	for slot: String in ["圣物", "武器", "左手镯", "左戒指", "徽章"]:
		var button := buttons.get(slot) as Control
		if is_instance_valid(button):
			left = maxf(left, rect_in(owner_control, button).end.x + 8.0)
	for slot: String in ["项链", "衣服", "右手镯", "右戒指"]:
		var button := buttons.get(slot) as Control
		if is_instance_valid(button):
			right = minf(right, rect_in(owner_control, button).position.x - 8.0)
	var top := frame.position.y + 120.0
	var helmet := buttons.get("头盔") as Control
	if is_instance_valid(helmet):
		top = maxf(top, rect_in(owner_control, helmet).end.y + 20.0)
	var bottom := frame.end.y - 24.0
	return {"region": Rect2(left, top, maxf(0.0, right - left), maxf(0.0, bottom - top)), "side": "center"}

static func fit_rect(region: Rect2, desired: Vector2, side: String) -> Rect2:
	var extent := Vector2(clampf(desired.x, 0.0, region.size.x), clampf(desired.y, 0.0, region.size.y))
	var at := region.position + (region.size - extent) * 0.5
	if side == "left":
		at.x = region.end.x - extent.x
	elif side == "right":
		at.x = region.position.x
	return Rect2(at, extent)
