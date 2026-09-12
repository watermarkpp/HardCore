extends Node
## Synthetic geometry regression. Not a real merchant or a device test.
const Space := preload("res://scripts/ui_shop_detail_space.gd")
class Fixture:
	extends Control
	var buy_button: Button
	var repair_button: Button
	var sell_quantity_row: Control
	var sell_quantity_button: Button
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var owner := Fixture.new()
	owner.size = Vector2(1080, 620)
	var section := Control.new()
	section.name = "DetailPanel"
	section.position = Vector2(674, 76)
	owner.add_child(section)
	var decoration := Control.new()
	decoration.name = "DetailPanelDecoration"
	decoration.position = Vector2(-4.1989136, -26.4)
	decoration.size = Vector2(365.90863, 510)
	section.add_child(decoration)
	var caption := Label.new()
	caption.name = "DetailTitle"
	caption.text = "商品详情"
	caption.position = Vector2(24, 12)
	caption.size = Vector2(316, 34)
	section.add_child(caption)
	owner.buy_button = Button.new()
	owner.buy_button.text = "购买"
	owner.buy_button.size = Vector2(270, 51)
	section.add_child(owner.buy_button)
	add_child(owner)
	await get_tree().process_frame
	var initial_caption := Rect2(caption.position, caption.size)
	var before: Dictionary = Space.region(owner)
	var original_button := Rect2(owner.buy_button.position, owner.buy_button.size)
	check(bool(before.get("caption_reserved", false)), "idle caption band missing")
	Space.sync_section_caption(owner, true)
	var after: Dictionary = Space.region(owner)
	var old_area: Rect2 = before["region"]
	var new_area: Rect2 = after["region"]
	var safe: Rect2 = after["frame_safe_rect"]
	check(not caption.visible, "redundant caption remained visible")
	check(new_area.position.y == safe.position.y, "hidden caption still consumes height")
	check(absf((new_area.size.y - old_area.size.y) - (old_area.position.y - safe.position.y)) < 0.05, "height not reclaimed exactly")
	check(new_area.end.is_equal_approx(old_area.end), "button boundary or right edge moved")
	check(absf(new_area.size.x - old_area.size.x) < 0.05, "reading width changed")
	check(Rect2(owner.buy_button.position, owner.buy_button.size).is_equal_approx(original_button), "heading switch moved the button")
	check(Rect2(caption.position, caption.size).is_equal_approx(initial_caption), "authored caption geometry modified")
	check(caption.text == "商品详情", "generic caption text modified")
	for i in range(6):
		Space.sync_section_caption(owner, true)
		check((Space.region(owner)["region"] as Rect2).is_equal_approx(new_area), "accumulating drift")
	Space.sync_section_caption(owner, false)
	check(caption.visible, "idle caption not restored")
	check((Space.region(owner)["region"] as Rect2).is_equal_approx(old_area), "idle area not restored")
	caption.hide()
	Space.sync_section_caption(owner, true)
	Space.sync_section_caption(owner, false)
	check(not caption.visible, "authored hidden caption was incorrectly forced visible")
	var ordinary := Control.new()
	Space.sync_section_caption(ordinary, true)
	Space.sync_section_caption(ordinary, false)
	check(ordinary.get_child_count() == 0, "non-shop UI changed")
	ordinary.free()
	owner.queue_free()
	await get_tree().process_frame
	for item: String in failures:
		push_error("R33_HEADER_GEOMETRY " + item)
	print("R33_HEADER_GEOMETRY_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)
