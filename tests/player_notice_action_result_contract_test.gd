extends Node

## ActionResult contract acceptance (R2). Future services (forge, synth,
## reinforce...) return structured results; HUD.present_action_result maps
## them into the unified notice layer without any service-side UI knowledge.
## `reason` is diagnostics-only and must never render.

const NoticeScript := preload("res://scripts/ui_player_notice.gd")
const NameStyleScript := preload("res://scripts/ui_item_name_style.gd")

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
	var hud := GameHUD.new()
	add_child(hud)
	await settle()
	var presenter := hud.notice_presenter
	expect(presenter != null, "notice presenter exists")
	if presenter == null:
		get_tree().quit(1)
		return
	presenter.set_process(false)

	# --- Success with an item_ref renders the authoritative item name --------
	var forged_item := GameData.get_item("屠龙")
	expect(not forged_item.is_empty(), "屠龙 catalog record exists")
	presenter.clear_for_test()
	hud.present_action_result({
		"success": true,
		"reason": "",
		"message": "锻造成功",
		"notice_code": "forge.success",
		"notice_kind": "success",
		"item_ref": forged_item,
	})
	await settle()
	# R2.1 contract spacing: the gap between message and item name is explicit
	# text owned by the contract, never container padding.
	expect(hud.error_label.text == "锻造成功 ", "forge success message renders with explicit trailing gap")
	expect(presenter.full_text() == "锻造成功 屠龙", "full line reads '锻造成功 屠龙' with explicit spacing")
	expect(presenter.item_label.text == "屠龙", "item_ref name renders through UIItemNameStyle")
	expect(presenter.item_label.get_theme_color("font_color") == NameStyleScript.describe(forged_item, {}).get("color"), "item_ref color is authoritative")
	var notice := presenter.current_notice()
	expect(str(notice.get("code", "")) == "forge.success", "notice_code carried for diagnostics/dedupe")

	# --- Failure maps to the error lane; reason never renders ----------------
	presenter.clear_for_test()
	hud.present_action_result({
		"success": false,
		"reason": "materials_insufficient",
		"message": "锻造材料不足",
		"notice_code": "forge.materials_insufficient",
		"notice_kind": "error",
	})
	expect(hud.error_label.text == "锻造材料不足", "failure message renders on the error lane")
	expect(presenter.current_notice().get("priority", 0) == NoticeScript.PRIORITY_ERROR, "failure notice takes error priority")
	expect(not hud.error_label.text.contains("materials_insufficient"), "machine reason never renders")
	# An omitted notice_kind falls back from success to error automatically.
	var fallback := NoticeScript.from_action_result({"success": false, "message": "合成失败"})
	expect(str(fallback["kind"]) == "error", "missing notice_kind falls back to error for failures")
	var success_fallback := NoticeScript.from_action_result({"success": true, "message": "合成成功"})
	expect(str(success_fallback["kind"]) == "success", "missing notice_kind falls back to success for wins")

	# --- item_ref as a committed instance resolves its catalog style ---------
	var instance_ref := {
		"name": "屠龙",
		"item_id": NameStyleScript.canonical_id(forged_item) if not forged_item.is_empty() else 0,
		"instance_id": "committed-1",
	}
	var resolved := NoticeScript.resolve_item_ref(instance_ref)
	expect(not (resolved["instance"] as Dictionary).is_empty(), "instance-shaped item_ref keeps the instance")
	expect(resolved["item"] is Dictionary, "instance-shaped item_ref resolves a catalog record")
	# The explicit pair shape passes straight through.
	var pair := NoticeScript.resolve_item_ref({"item": forged_item, "instance": instance_ref})
	expect((pair["item"] as Dictionary) == forged_item, "explicit item/instance pair passes through")

	# --- Success preemption still applies to action results ------------------
	presenter.clear_for_test()
	hud.present_action_result({"success": true, "message": "强化成功", "notice_code": "reinforce.success"})
	hud.present_action_result({"success": false, "message": "强化材料不足", "notice_code": "reinforce.materials_insufficient", "notice_kind": "error"})
	expect(hud.error_label.text == "强化材料不足", "later failure preempts earlier success")

	# --- R2.1 machine-message boundary on failed action results --------------
	# A future service that stuffs the raw reason into `message` must still
	# never leak it: the failure path runs through UIErrorFeedback.from_result.
	presenter.clear_for_test()
	hud.present_action_result({
		"success": false,
		"reason": "materials_insufficient",
		"message": "materials_insufficient",
		"notice_code": "forge.leak_probe",
		"notice_kind": "error",
	})
	await settle()
	expect(hud.error_label.text == "操作失败，请稍后重试。", "machine-token failure message falls back to Chinese prose (got [%s])" % hud.error_label.text)
	expect(not presenter.full_text().contains("materials_insufficient"), "machine token in message never reaches the overlay")
	presenter.clear_for_test()
	hud.present_action_result({
		"success": false,
		"reason": "",
		"message": "",
		"notice_kind": "error",
	})
	await settle()
	expect(hud.error_label.text == "操作失败，请稍后重试。", "empty failure message falls back to Chinese prose")
	# Spacing never applies to a text-only failure (no item segment).
	expect(hud.error_label.text.ends_with("。"), "fallback prose stays intact without item spacing")

	hud.queue_free()
	await settle()
	if failures.is_empty():
		print("PLAYER_NOTICE_ACTION_RESULT_CONTRACT_PASS: item_ref, kind fallback, reason hidden, preemption, machine-message guard, contract spacing")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("PLAYER_NOTICE_ACTION_RESULT_CONTRACT_FAIL: " + failure)
		get_tree().quit(1)
