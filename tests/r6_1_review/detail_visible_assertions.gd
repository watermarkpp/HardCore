extends RefCounted

## Locked assertions for the executor's REAL-panel matrix fixtures.
## Coordinates of allowed/protected rectangles must be owner-local. Populate
## them from actual calibrated controls, never by increasing a dummy Scope.
## September 13 user contract permits clipped, touch-scrollable body overflow.
## Keep title, body source, geometry, identity and hidden-scrollbar checks.
static func _rect_in(owner_control: Control, control: Control) -> Rect2:
	var owner_transform := owner_control.get_global_transform_with_canvas()
	if absf(owner_transform.determinant()) < 0.000001:
		return Rect2()
	var transform := owner_transform.affine_inverse() * control.get_global_transform_with_canvas()
	var result := Rect2(transform * Vector2.ZERO, Vector2.ZERO)
	for point: Vector2 in [Vector2(control.size.x, 0), control.size, Vector2(0, control.size.y)]:
		result = result.expand(transform * point)
	return result

static func inspect(
	owner_control: Control,
	view: Control,
	allowed_rects: Array[Rect2],
	protected_rects: Array[Rect2],
	expected_title: String,
	expected_item_id: int,
	expected_color: Color,
	expected_body_bbcode: String
) -> Array[String]:
	var errors: Array[String] = []
	if not is_instance_valid(owner_control) or not is_instance_valid(view):
		return ["INVALID_REAL_PANEL_OR_PRESENTER"]
	var title: Label = view.get_node_or_null("Title") as Label
	var body: RichTextLabel = view.get_node_or_null("Body") as RichTextLabel
	if title == null or body == null:
		return ["MISSING_TITLE_OR_BODY"]
	if not view.has_method("debug_layout_snapshot"):
		return ["MISSING_LAYOUT_DIAGNOSTICS"]
	var snapshot: Dictionary = view.call("debug_layout_snapshot")
	if not bool(snapshot.get("valid", false)):
		errors.append("INVALID_LAYOUT:" + str(snapshot.get("error", "")))
	if not view.is_visible_in_tree() or not title.is_visible_in_tree() or not body.is_visible_in_tree():
		errors.append("NOT_VISIBLE_IN_TREE")
	var ancestor: Node = title
	while ancestor != null:
		if ancestor is CanvasItem and (ancestor as CanvasItem).modulate.a <= 0.0:
			errors.append("ZERO_ALPHA_ANCESTOR:" + str(ancestor.name))
		ancestor = ancestor.get_parent()
	if title.self_modulate.a <= 0.0 or body.self_modulate.a <= 0.0 or body.modulate.a <= 0.0:
		errors.append("ZERO_TEXT_ALPHA")
	if title.text.strip_edges().is_empty() or title.text != expected_title:
		errors.append("TITLE_MISMATCH_OR_EMPTY")
	if not title.get_theme_color("font_color").is_equal_approx(expected_color):
		errors.append("NAME_COLOR_MISMATCH")
	var name_style: Dictionary = snapshot.get("name_style", {})
	if expected_item_id > 0 and int(name_style.get("item_id", -1)) != expected_item_id:
		errors.append("DISPLAYED_ITEM_ID_MISMATCH")
	if body.text != expected_body_bbcode:
		errors.append("BODY_SOURCE_CHANGED_OR_TRUNCATED")
	if body.get_v_scroll_bar().visible:
		errors.append("BODY_VISIBLE_SCROLLBAR")
	if body.visible_characters != -1 or title.visible_characters != -1:
		errors.append("VISIBLE_CHARACTER_LIMIT")
	if (float(body.get_content_height()) > body.size.y and not body.scroll_active) or title.get_minimum_size().y > title.size.y:
		errors.append("TEXT_HEIGHT_OVERFLOW")
	var local := Rect2(Vector2.ZERO, view.size)
	if not local.grow(0.5).encloses(Rect2(title.position, title.size)) or not local.grow(0.5).encloses(Rect2(body.position, body.size)):
		errors.append("TEXT_OUTSIDE_DETAIL_PANEL")
	# R3.3 shop contract allows W <= 1.3 H; non-shop cards keep portrait.
	# See header_session_test and the current UIShopDetailSpace authority.
	if owner_control is ShopPanel:
		if view.size.x > view.size.y * 1.3 + 0.5:
			errors.append("SHOP_DETAIL_ASPECT_OVERFLOW")
	elif view.size.y < view.size.x * 1.12 - 1.0:
		errors.append("NON_PORTRAIT_DETAIL")
	var actual := _rect_in(owner_control, view)
	var inside_allowed := false
	for allowed: Rect2 in allowed_rects:
		if allowed.has_area() and allowed.grow(1.0).encloses(actual):
			inside_allowed = true
	if not inside_allowed:
		errors.append("OUTSIDE_ALLOWED_REGION")
	if protected_rects.is_empty():
		errors.append("NO_INDEPENDENT_PROTECTED_GEOMETRY")
	for protected: Rect2 in protected_rects:
		if protected.has_area() and protected.intersects(actual):
			errors.append("OVERLAPS_GRID_ACTION_TITLE_OR_FRAME_RING")
	# This check is independent of a production dock returning an over-large region.
	var visible_viewport: Rect2 = owner_control.get_viewport().get_visible_rect()
	var in_viewport := Rect2(view.get_global_transform_with_canvas() * Vector2.ZERO, Vector2.ZERO)
	for point: Vector2 in [Vector2(view.size.x, 0), view.size, Vector2(0, view.size.y)]:
		in_viewport = in_viewport.expand(view.get_global_transform_with_canvas() * point)
	if not visible_viewport.grow(1.0).encloses(in_viewport):
		errors.append("OUTSIDE_REAL_VIEWPORT")
	return errors
