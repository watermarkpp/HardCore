extends Node
const Presenter := preload("res://scripts/item_detail_docked_presenter.gd")
const Style := preload("res://scripts/ui_item_name_style.gd")
var failures: Array[String] = []
var checks := 0
class Scope:
	extends Control
	var region := Rect2(20, 20, 260, 520)
	func _ui_detail_region(_context: Dictionary) -> Dictionary:
		return {"region": region, "side": "center"}
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()
func settle() -> void:
	for i in range(3):
		await get_tree().process_frame
func _run() -> void:
	var owner := Scope.new()
	owner.size = Vector2(600, 650)
	add_child(owner)
	var view := Presenter.new()
	owner.add_child(view)
	await settle()
	for width: float in [170.0, 220.0, 260.0]:
		owner.region.size.x = width
		view.show_text("地狱火", "类别：技能书　重量 1\n使用技能书可以使对应技能等级+1，技能最高3级。\n这是一段需要自动换行且必须完整显示的说明。")
		await settle()
		var s: Dictionary = view.debug_layout_snapshot()
		expect(s["valid"], "normal content fits width=" + str(width))
		expect(not view.detail_label.scroll_active and not view.detail_label.get_v_scroll_bar().visible, "no scrollbar")
		expect(view.title_label.visible and view.title_label.text == "地狱火", "title actually visible")
		expect(view.title_label.modulate.a > 0.0 and view.modulate.a > 0.0, "title cannot be invisible through alpha")
		expect(view.size.y >= view.size.x * Presenter.PORTRAIT_RATIO - 1.0, "portrait rectangle")
		expect(float(view.detail_label.get_content_height()) <= view.detail_label.size.y, "all body lines fit")
		expect(owner.region.grow(1.0).encloses(Rect2(view.position, view.size)), "no overlap beyond region")
	var maps: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Style.DATA_PATH))["records"]
	var purple_id := -1
	for key: String in maps:
		if maps[key]["name_style"] == "ultra_rare":
			purple_id = int(key)
			break
	expect(purple_id > 0, "purple fixture is a real mapped item")
	view.show_text("极稀有物品", "说明", {"rarity_item": {"itemId": purple_id}})
	await settle()
	expect(view.title_label.get_theme_color("font_color") == Style.describe({"itemId": purple_id})["color"], "shop show_text uses rarity context")
	view.show_text("普通物品", "说明")
	await settle()
	expect(view.title_label.get_theme_color("font_color") == Style.DEFAULT_COLOR, "reuse clears previous purple")
	view.show_message("测试提示")
	await settle()
	expect(view.title_label.get_theme_color("font_color") == Style.MESSAGE_COLOR, "messages use message style")
	var before_layouts := int(view.debug_layout_snapshot()["layouts"])
	for i in range(30):
		await get_tree().process_frame
	expect(int(view.debug_layout_snapshot()["layouts"]) == before_layouts, "idle view does not poll layout per frame")
	# An 80-line payload cannot physically fit this fixed finite region. The new
	# contract must report failure while retaining source text, not pass via scroll.
	view._test_suppress_expected_layout_error = true
	view.show_text("极端边界", "保留的完整属性\n".repeat(80))
	await settle()
	expect(not view.debug_layout_valid(), "impossible geometry fails explicitly")
	expect(view.detail_label.text.count("保留的完整属性") == 80, "failure does not truncate source")
	expect(not view.detail_label.scroll_active, "overflow cannot restore scroll")
	view._test_suppress_expected_layout_error = false
	view.show_text("恢复正常", "说明")
	await settle()
	expect(view.debug_layout_valid() and view.modulate.a > 0.0, "recovery from overflow")
	owner.queue_free()
	await get_tree().process_frame
	for message: String in failures:
		push_error("R6_LAYOUT " + message)
	print("R6_1_DETAIL_LAYOUT_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
