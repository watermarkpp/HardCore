extends Node

## Notice-lane scope guard (R2). Freezes the unified-notice contracts: the
## central overlay is the single global lane, item-use notices follow the
## structured contract (instant potions silent), transaction UI stays local,
## and the R1/R1.1 error-lane closures remain intact.

const SCANNED_FILES := {
	"game_root": "res://scripts/game_root.gd",
	"hud": "res://scripts/hud.gd",
	"inventory_panel": "res://scripts/inventory_panel.gd",
	"shop_panel": "res://scripts/shop_panel.gd",
	"warehouse_panel": "res://scripts/warehouse_panel.gd",
	"loot_feedback_layer": "res://scripts/loot_feedback_layer.gd",
	"notice_contract": "res://scripts/ui_player_notice.gd",
	"notice_presenter": "res://scripts/player_notice_presenter.gd",
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
	var notice_contract := _source("notice_contract")
	var notice_presenter := _source("notice_presenter")

	# --- Unified central lane is the only global notice layer ----------------
	assert(hud.contains("func show_notice(notice: Dictionary) -> void:"), "HUD owns the unified show_notice entry")
	for wrapper: String in [
		"func show_success_message(message: String, seconds := 2.0) -> void:",
		"func show_error_message(message: String, seconds := 2.0) -> void:",
		"func show_warning_message(message: String, seconds := 2.0) -> void:",
		"func show_message(message: String, seconds := 2.0) -> void:",
	]:
		assert(hud.contains(wrapper), "legacy wrapper kept and routed through the overlay: %s" % wrapper)
	assert(hud.contains("func show_item_notice("), "item notice entry exists")
	assert(hud.contains("func present_action_result(result: Dictionary) -> void:"), "ActionResult entry exists")
	# Every wrapper routes into show_notice: no wrapper may write a label.
	assert(_count(hud, "show_notice(") >= 5, "all notice entries funnel into show_notice")
	assert(not hud.contains("loot_label.text = message"), "show_message must not write the retired loot lane")
	assert(hud.contains("var notice_presenter: PlayerNoticePresenter"), "presenter member exists")
	assert(hud.contains("var error_label: Label"), "error alias member kept for the error lane")
	assert(not hud.contains("var _error_message_timer"), "HUD no longer owns notice timers")
	assert(hud.contains("PlayerNoticePresenterScript.new()"), "HUD builds the unified overlay")
	assert(notice_presenter.contains("z_index = 4096"), "overlay keeps the absolute top layer")
	assert(notice_presenter.contains("NOTICE_FONT_SIZE := 22"), "notice font size pinned at 22px")
	assert(notice_presenter.contains("offset_left = 360"), "notice geometry pinned (legacy error geometry)")
	# Priority + dedupe live in the presenter/contract, not in business code.
	assert(notice_presenter.contains("MAX_QUEUE") or notice_contract.contains("MAX_QUEUE"), "queue bound defined")
	assert(notice_contract.contains("PRIORITY_ERROR := 100"), "priority table owned by the contract")
	assert(notice_contract.contains("should_report_item_use"), "item-use notice gate owned by the contract")
	# Item names always resolve through the authoritative style system.
	assert(notice_presenter.contains("ui_item_name_style.gd"), "presenter reuses UIItemNameStyle")
	assert(notice_contract.contains("UIItemNameStyle.canonical_id") or notice_contract.contains("display_name"), "contract reuses UIItemNameStyle display names")

	# --- Item-use notice contract (R2 user decision) -------------------------
	assert(notice_contract.contains("\"temporary_stat_buff\",") and notice_contract.contains("\"blessing_oil\",") and notice_contract.contains("\"repair_oil\",") and notice_contract.contains("\"war_god_oil\",") and notice_contract.contains("\"temporary_buff\",") and notice_contract.contains("== \"skill_book\""), "reported uses: skill books, oils, timed buffs")
	# Quick-slot and bag entries share the same structured gate and central lane.
	assert(game_root.contains("UIPlayerNoticeScript.should_report_item_use(used_item)"), "quick-slot use gate uses the shared contract")
	assert(_count(inventory_panel, "UIPlayerNoticeScript.should_report_item_use(") >= 2, "bag use gates use the shared contract")
	assert(game_root.contains("hud.show_success_message(str(result.get(\"message\", \"\")))"), "quick-slot success reports the structured message once")
	# The legacy generic use texts are retired: instant potions stay silent.
	assert(not game_root.contains("hud.show_message(\"使用了%s\" % item_name)"), "legacy 使用了X texts retired from the signal chains")
	# Timed 神水 expiry + level-up join the central lane.
	assert(game_root.contains("PlayerState.temporary_item_buff_expired.connect(_on_temporary_item_buff_expired)"), "timed buff expiry connected")
	assert(game_root.contains("%s效果结束"), "buff expiry notice text present")
	assert(game_root.contains("hud.show_success_message(\"等级提升至 %d\" % new_level)"), "level-up notice present")
	# Skill learn texts stay on the authority wording, shared by both entries.
	assert(
		game_root.contains("hud.show_success_message(str(result.get(\"message\", \"\")))"),
		"quick-slot learn reports the same structured success text"
	)
	assert(
		inventory_panel.contains("已装备 ")
		and _count(inventory_panel, "已装备 ") >= 3
		and inventory_panel.contains("已卸下 "),
		"equip/unequip central notices cover all production entries"
	)
	assert(inventory_panel.contains("\"equipment.equip\"") and inventory_panel.contains("\"equipment.unequip\""), "equip notices carry dedupe keys")

	# --- Ordinary status notices keep their show_message lane ----------------
	var protected_messages := [
		"hud.show_message(\"施放：%s\" % skill_name, 1.0)",
		"hud.show_message(\"进入%s\" % zone_name, 1.5)",
		"hud.show_message(\"你已在最近的城镇复活\", 2.0)",
		"hud.show_message(\"魔法盾自动补盾：开\", 1.5)",
		"hud.show_message(\"魔法盾自动补盾：关\", 1.5)",
	]
	for needle: String in protected_messages:
		assert(game_root.contains(needle), "protected normal notice lost its original route: %s" % needle)
	assert(game_root.contains("快捷物品已绑定"), "quick-item binding success notice must stay")
	var error_calls := _count(game_root, "show_error_message(")
	var message_calls := _count(game_root, "show_message(")
	assert(error_calls >= 40, "error channel must be actively used (got %d)" % error_calls)
	assert(message_calls >= 8, "normal channel must survive (got %d)" % message_calls)
	assert(not game_root.contains("show_message(show_error_message"), "lanes must not be chained")

	# --- R1.1 closures stay on the error lane --------------------------------
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
		_count(inventory_panel, "item_detail_presenter.show_message(\"[color=#e8c277]%s[/color]\" % str(use_result.get(\"message\", \"\")))") == 0,
		"item-use success must not use the detail presenter lane anymore"
	)
	assert(
		inventory_panel.contains("from_result(use_result,"),
		"use failures must pass the error boundary, never raw result text"
	)

	# --- Error lane boundary guard --------------------------------------------
	var error_start := hud.find("func show_error_message(")
	assert(error_start > 0, "show_error_message must exist on the HUD")
	var error_end := hud.find("\nfunc ", error_start + 10)
	var error_body := hud.substr(error_start, error_end - error_start)
	assert(error_body.contains("UIErrorFeedbackScript.user_message(message)"), "error channel guards machine reasons")
	assert(error_body.contains("show_notice("), "error channel routes into the unified overlay")
	assert(not error_body.contains("loot_label"), "error channel must never write the loot lane")

	# --- Inventory local lane: only detail text, no global notices -----------
	assert(inventory_panel.contains("自动整理完成"), "sort success notice stays")
	assert(inventory_panel.contains("_show_success_message(\"自动整理完成\")"), "sort success moved into the central overlay (R2)")
	assert(not inventory_panel.contains("_show_center_message"), "old center-message alias must be fully migrated")

	# --- Transaction UI frozen: no error-channel usage at all ----------------
	for frozen_source: String in [shop_panel, warehouse_panel, loot_layer]:
		assert(_count(frozen_source, "show_error_message") == 0, "transaction/loot UI must not use the error channel")
		assert(_count(frozen_source, "ui_error_feedback") == 0, "transaction/loot UI must not depend on the error boundary")

	print("UI_ERROR_FEEDBACK_SCOPE_GUARD_PASS: unified overlay, use-notice contract, transaction freeze preserved")
	get_tree().quit(0)
