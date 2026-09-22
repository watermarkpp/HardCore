extends Node

## Unified item-name styling acceptance (R2). The central notice must reuse
## the authoritative UIItemNameStyle system: default/wooma/zuma/redmoon/
## ultra_rare groups keep their official colors, the ultra-rare outline is
## preserved, affixed ★ instances keep the star prefix, and the prefix text
## never inherits the item color.

const NameStyleScript := preload("res://scripts/ui_item_name_style.gd")
const NoticeScript := preload("res://scripts/ui_player_notice.gd")

const EXPECTED_GROUPS := {
	"木剑": "default",
	"龙之戒指": "wooma",
	"力量戒指": "zuma",
	"圣战戒指": "redmoon",
	"麻痹戒指": "ultra_rare",
}

var failures: Array[String] = []


func expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func settle() -> void:
	for _index in range(4):
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	expect(NameStyleScript.ensure_loaded(), "item name style data loads")
	var hud := GameHUD.new()
	add_child(hud)
	await settle()
	var presenter := hud.notice_presenter
	expect(presenter != null, "notice presenter exists")
	if presenter == null or not NameStyleScript.ensure_loaded():
		get_tree().quit(1)
		return
	presenter.set_process(false)

	# --- One notice per rarity: only the item name carries its own style ----
	for item_name: String in EXPECTED_GROUPS:
		var item := GameData.get_item(item_name)
		expect(not item.is_empty(), "catalog record exists: " + item_name)
		if item.is_empty():
			continue
		presenter.clear_for_test()
		hud.show_item_notice("已装备 ", item, {}, "", "success", 2.0, "equipment.equip")
		await settle()
		var style := NameStyleScript.describe(item, {})
		expect(str(style.get("group", "")) == EXPECTED_GROUPS[item_name], "%s resolves to group %s" % [item_name, EXPECTED_GROUPS[item_name]])
		expect(presenter.item_label.text == item_name, "%s renders the authoritative name" % item_name)
		expect(presenter.prefix_label.text == "已装备 ", "%s prefix text" % item_name)
		# Prefix color stays the plain notice color; the item label carries
		# the official group color.
		expect(presenter.prefix_label.get_theme_color("font_color") == presenter.NOTICE_TEXT_COLOR, "%s prefix keeps plain color" % item_name)
		expect(presenter.item_label.get_theme_color("font_color") == style.get("color"), "%s item color matches UIItemNameStyle" % item_name)
		# The whole row reads as one line: prefix + item + empty suffix.
		expect(presenter.suffix_label.visible == false or presenter.suffix_label.text.is_empty(), "%s suffix empty" % item_name)

	# --- Ultra-rare outline must survive in the central notice --------------
	var ultra := GameData.get_item("麻痹戒指")
	var ultra_style := NameStyleScript.describe(ultra, {})
	var outline: Dictionary = ultra_style.get("outline", {})
	expect(not outline.is_empty(), "ultra rare has an outline style")
	presenter.clear_for_test()
	hud.show_item_notice("已装备 ", ultra, {}, "", "success", 2.0, "equipment.equip")
	await settle()
	if outline.is_empty():
		expect(presenter.item_label.get_theme_constant("outline_size") == 0, "no outline style means no outline override")
	else:
		expect(presenter.item_label.get_theme_color("font_outline_color") == Color(str(outline["color"])), "ultra rare outline color applied")
		expect(presenter.item_label.get_theme_constant("outline_size") == int(outline["size"]), "ultra rare outline size applied")

	# --- Affixed ★ instance keeps the star via display_name -----------------
	var affixed_item := GameData.get_item("裁决之杖")
	expect(not affixed_item.is_empty(), "裁决之杖 catalog record exists")
	if not affixed_item.is_empty():
		var star_instance := {"name": "★裁决之杖", "item_id": NameStyleScript.canonical_id(affixed_item), "instance_id": "test-instance"}
		presenter.clear_for_test()
		hud.show_item_notice("已装备 ", affixed_item, star_instance, "", "success", 2.0, "equipment.equip")
		await settle()
		expect(presenter.item_label.text == "★裁决之杖", "affixed instance keeps the ★ prefix (display_name path)")
		# The non-affixed path must not invent a star.
		expect(NameStyleScript.display_name(affixed_item, {}) == "裁决之杖", "plain instance shows the plain name")

	# --- Item segment normalization drops invalid payloads ------------------
	var notice := NoticeScript.normalize({
		"kind": "success",
		"segments": [
			NoticeScript.text_segment("已装备 "),
			{"type": "item", "item": {}},
			{"type": "item", "item": affixed_item},
		],
	})
	expect((notice["segments"] as Array).size() == 2, "empty item segments are dropped, valid ones kept")
	expect(str((notice["segments"] as Array)[1].get("type", "")) == "item", "the valid item segment survives normalization")

	hud.queue_free()
	await settle()
	if failures.is_empty():
		print("PLAYER_NOTICE_ITEM_STYLE_PASS: five rarities, ultra outline, affixed star, normalization")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("PLAYER_NOTICE_ITEM_STYLE_FAIL: " + failure)
		get_tree().quit(1)
