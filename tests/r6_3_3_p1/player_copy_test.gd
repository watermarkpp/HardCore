extends Node
const Copy := preload("res://scripts/ui_item_player_copy.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures.append(why)
func _ready() -> void:
	var untouched: Array[String] = [
		"攻击 2-5　魔法 0-1", "HP +20 / MP +10", "使用后恢复生命（持续5秒）。",
		"来源：祖玛教主", "source: Woma Temple", "Cold resistance +5%",
		"[color=#ffaa00]出售提示：高价值[/color]", "[b]火球术[/b]：技能等级+1。",
		"穿戴要求：道术17", "第一段\n\n第二段", "\t保留原排版\r\n正文",
		"售价 11000 金币", "攻击（对不死生物有效）", "A/B类材料", "",
	]
	for text: String in untouched:
		check(Copy.description(text) == text, "unrelated prose changed: " + text)
	check(Copy.description(null) == "", "null description")
	check(Copy.description({"source": "audit", "notes": "x"}) == "", "dictionary leaked")
	check(Copy.description(["debug", 1]) == "", "array leaked")
	check(Copy.description(&"HP +20") == "HP +20", "StringName value")
	for source: String in Copy.AUDIT_SOURCES:
		check(Copy.description(source) == "", "bare known provenance leaked")
		check(Copy.description("来源：" + source) == "", "source row leaked")
		check(Copy.description("穿戴要求：道术17（" + source + "/A）") == "穿戴要求：道术17", "requirement suffix")
		check(Copy.description("[color=#999999]" + source + "[/color]") == "", "whole-line metadata wrapper")
	check(Copy.description("Internal note: renderer compatibility\n真实效果：生命+20") == "真实效果：生命+20", "internal note removal")
	check(Copy.description("第一行\nDebug note: migration only\n第二行") == "第一行\n第二行", "removed row retained height")
	check(Copy.description("[b]来源：project.hardcore.equipment_attribute_master.v2[/b]\nHP +20") == "HP +20", "balanced styling")
	check(Copy.description("[color=#eeeeee]\n真实效果\n[/color]") == "[color=#eeeeee]\n真实效果\n[/color]", "multiline bbcode damage")
	check(Copy.description("[color=#eeeeee]道术17（project.hardcore.equipment_attribute_master.v2/A）[/color]") == "[color=#eeeeee]道术17[/color]", "inline tag integrity")
	check(Copy.description("source: 未知英文资料名") == "source: 未知英文资料名", "unknown source auto-deleted")
	for text: String in untouched:
		check(Copy.description(Copy.description(text)) == Copy.description(text), "idempotence")
	for e: String in failures:
		push_error("R33_P1_COPY " + e)
	print("R33_P1_COPY_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)
