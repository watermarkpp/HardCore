extends Node

## Transaction/normal-feedback scope guard (R1). Freezes the non-error lanes
## against a mechanical mass-replacement of show_message -> show_error_message:
## success notices, transaction UI, LootFeedback and the show_message lane
## itself must keep their original routes.

const SCANNED_FILES := {
	"game_root": "res://scripts/game_root.gd",
	"hud": "res://scripts/hud.gd",
	"inventory_panel": "res://scripts/inventory_panel.gd",
	"shop_panel": "res://scripts/shop_panel.gd",
	"warehouse_panel": "res://scripts/warehouse_panel.gd",
	"loot_feedback_layer": "res://scripts/loot_feedback_layer.gd",
}


func _ready() -> void:
	_run.call_deferred()


func _source(key: String) -> String:
	var file := FileAccess.open(SCANNED_FILES[key], FileAccess.READ)
	assert(file != null, "cannot open %s" % SCANNED_FILES[key])
	return file.get_as_text()


func _count(source: String, needle: String) -> int:
	var total := 0
	var cursor := source.find(needle)
	while cursor >= 0:
		total += 1
		cursor = source.find(needle, cursor + needle.length())
	return total


func _run() -> void:
	var game_root := _source("game_root")
	var hud := _source("hud")
	var inventory_panel := _source("inventory_panel")
	var shop_panel := _source("shop_panel")
	var warehouse_panel := _source("warehouse_panel")
	var loot_layer := _source("loot_feedback_layer")

	# --- Ordinary/success notices keep the original show_message lane -------
	var protected_messages := [
		"hud.show_message(\"施放：%s\" % skill_name, 1.0)",
		"hud.show_message(\"进入%s\" % zone_name, 1.5)",
		"hud.show_message(\"你已在最近的城镇复活\", 2.0)",
		"hud.show_message(\"魔法盾自动补盾：开\", 1.5)",
		"hud.show_message(\"魔法盾自动补盾：关\", 1.5)",
		"hud.show_message(\"使用了%s\" % item_name)",
	]
	for needle: String in protected_messages:
		assert(game_root.contains(needle), "protected normal notice lost its original route: %s" % needle)
	assert(game_root.contains("快捷物品已绑定"), "quick-item binding success notice must stay")
	assert(game_root.contains("技能学习成功"), "skill learn success notice must stay")
	assert(_count(game_root, "使用了%s") >= 2, "item-use success notices must stay")

	# --- Both lanes coexist: no mechanical mass replacement ------------------
	var error_calls := _count(game_root, "show_error_message(")
	var message_calls := _count(game_root, "show_message(")
	assert(error_calls >= 40, "error channel must be actively used (got %d)" % error_calls)
	assert(message_calls >= 14, "normal channel must survive (got %d)" % message_calls)
	# show_error_message must never be routed through show_message or back.
	assert(not game_root.contains("show_message(show_error_message"), "lanes must not be chained")

	# --- R1.1 closure: the remaining failure entries are on the error lane ---
	assert(
		game_root.contains("func _on_loot_collection_rejected(")
		and game_root.contains("hud.show_error_message(message)"),
		"loot pickup rejection must surface on the error channel"
	)
	assert(
		game_root.contains("apply_weapon_repair_oil_result(")
		and game_root.contains("func _report_repair_oil_result(")
		and game_root.contains("hud.show_error_message("),
		"repair-oil failures must classify through the structured result"
	)
	assert(
		hud.contains("show_error_message(\"快捷物品 %d 为空：长按槽位可从背包选择\""),
		"empty quick-slot taps must surface on the error channel"
	)
	assert(
		_count(inventory_panel, "use_inventory_index(") == 0
		and _count(inventory_panel, "use_inventory_index_result(") >= 2,
		"item use must go through the structured result contract"
	)
	assert(
		_count(inventory_panel, "item_detail_presenter.show_message(\"[color=#e8c277]%s[/color]\" % str(use_result.get(\"message\", \"\")))") == 2,
		"item-use success keeps the presenter lane, failures go to the error channel"
	)
	assert(
		inventory_panel.contains("from_result(use_result,"),
		"use failures must pass the error boundary, never raw result text"
	)

	# --- HUD: show_message semantics unchanged, error lane independent ------
	assert(hud.contains("func show_message(message: String, seconds := 2.0) -> void:"), "show_message signature frozen")
	var show_message_start := hud.find("func show_message(message: String, seconds := 2.0) -> void:")
	var show_message_end := hud.find("\nfunc ", show_message_start + 10)
	var show_message_body := hud.substr(show_message_start, show_message_end - show_message_start)
	assert(show_message_body.contains("loot_label.text = message"), "show_message must keep writing the loot label")
	assert(not show_message_body.contains("error_label"), "show_message must never touch the error channel")
	var error_start := hud.find("func show_error_message(")
	assert(error_start > 0, "show_error_message must exist on the HUD")
	var error_end := hud.find("\nfunc ", error_start + 10)
	var error_body := hud.substr(error_start, error_end - error_start)
	assert(error_body.contains("error_label"), "error channel writes its own label")
	assert(error_body.contains("UIErrorFeedbackScript.user_message(message)"), "error channel guards machine reasons")
	assert(not error_body.contains("loot_label"), "error channel must never clear/write the loot lane")
	assert(hud.contains("var _error_message_timer := 0.0"), "independent error timer exists")
	assert(hud.contains("var error_label: Label"), "dedicated error label member exists")
	# Layering contract.
	assert(hud.contains("error_label.z_index = 4096"), "error label keeps the absolute top layer")

	# --- Inventory: success notices keep the presenter lane ------------------
	assert(inventory_panel.contains("自动整理完成"), "sort success stays in the original lane")
	assert(inventory_panel.contains("item_detail_presenter.show_message(\"[color=#e8c277]自动整理完成[/color]\")"), "sort success keeps the presenter route")
	assert(not inventory_panel.contains("_show_center_message"), "old center-message alias must be fully migrated")

	# --- Transaction UI frozen: no error-channel usage at all ----------------
	for frozen_source: String in [shop_panel, warehouse_panel, loot_layer]:
		assert(_count(frozen_source, "show_error_message") == 0, "transaction/loot UI must not use the error channel")
		assert(_count(frozen_source, "ui_error_feedback") == 0, "transaction/loot UI must not depend on the error boundary")

	print("UI_ERROR_FEEDBACK_SCOPE_GUARD_PASS: normal, transaction and loot lanes preserved")
	get_tree().quit(0)
