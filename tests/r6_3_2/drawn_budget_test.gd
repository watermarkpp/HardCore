extends Node
## Synthetic known drawing margins; independent geometry assertions, not a
## replacement for the real ShopPanel catalog matrix or visual inspection.
const Space := preload("res://scripts/ui_shop_detail_space.gd")
const Bounds := preload("res://scripts/ui_style_visual_bounds.gd")
class Fixture:
	extends Control
	var buy_button: Button
	var repair_button: Button
	var sell_quantity_row: Control
	var sell_quantity_button: Button
var checks := 0
var errors: Array[String] = []
func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok: errors.append(label)
func _ready() -> void:
	_run.call_deferred()
func make_button(text_value: String, parent: Control) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", 16)
	button.size = Vector2(270, 51)
	for state: StringName in Bounds.STATES:
		var style := StyleBoxFlat.new()
		style.set_expand_margin_all(4.0)
		style.anti_aliasing = true
		style.anti_aliasing_size = 1.0
		button.add_theme_stylebox_override(state, style)
	parent.add_child(button)
	return button
func _run() -> void:
	var owner := Fixture.new()
	owner.size = Vector2(1000, 650)
	var section := Control.new()
	section.name = "DetailPanel"
	owner.add_child(section)
	var decoration := Control.new()
	decoration.name = "DetailPanelDecoration"
	decoration.position = Vector2(500, 30)
	decoration.size = Vector2(366, 510)
	section.add_child(decoration)
	var title := Label.new()
	title.name = "DetailTitle"
	title.text = "商品详情"
	title.position = Vector2(530, 60)
	title.size = Vector2(304, 30)
	section.add_child(title)
	owner.buy_button = make_button("购买", section)
	owner.repair_button = make_button("维修", section)
	add_child(owner)
	await get_tree().process_frame
	var spec: Dictionary = Space.region(owner)
	var a: Rect2 = Space.visual_rect(owner, owner.buy_button)
	var b: Rect2 = Space.visual_rect(owner, owner.repair_button)
	# The old full-hit-budget algorithm fails this with any positive margins.
	verify(absf(a.end.y - b.end.y) < 0.1, "feasible drawn button row wrongly stacked")
	verify(not a.intersects(b), "buttons overlap")
	var scale: Vector2 = Space.screen_scale(owner)
	verify((b.position.x - a.end.x) * scale.x >= 16.0 - 0.1, "drawn action gap lost")
	var opening: Rect2 = spec.get("frame_opening", Rect2())
	verify(a.position.x >= opening.position.x + 18.0 / scale.x - 0.1, "left drawn boundary escaped")
	verify(b.end.x <= opening.end.x - 18.0 / scale.x + 0.1, "right drawn boundary escaped")
	var area: Rect2 = spec.get("region", Rect2())
	verify((minf(a.position.y, b.position.y) - area.end.y) * scale.y >= 36.0 - 0.1, "reading gap lost")
	for i in range(12):
		Space.region(owner)
		verify(Space.visual_rect(owner, owner.buy_button).is_equal_approx(a), "buy position accumulated drift")
		verify(Space.visual_rect(owner, owner.repair_button).is_equal_approx(b), "repair position accumulated drift")
	verify(owner.buy_button.text == "购买" and owner.repair_button.text == "维修", "labels modified")
	verify(owner.buy_button.get_theme_font_size("font_size") == 16, "font modified")
	owner.queue_free()
	await get_tree().process_frame
	for error: String in errors: push_error("R32_BUDGET " + error)
	print("R32_DRAWN_BUDGET_%s checks=%d" % ["PASS" if errors.is_empty() else "FAIL", checks])
	get_tree().quit(0 if errors.is_empty() else 1)
