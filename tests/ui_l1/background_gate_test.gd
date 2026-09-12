extends Node
const HUDScript := preload("res://scripts/hud.gd")
var failures: Array[String] = []
func expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()
func _run() -> void:
	assert(GameData.ensure_loaded(), "real catalog required")
	var hud: Node = HUDScript.new()
	add_child(hud)
	if not hud.has_method("_ui_l1_background_blocked"):
		push_error("UI_L1_BACKGROUND_RED: no interactive priority gate")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	hud._ensure_inventory_panel()
	await hud.inventory_panel.wait_until_runtime_ready()
	for i in 5:
		await get_tree().process_frame
	hud.inventory_panel.show()
	expect(hud._ui_l1_background_blocked(), "open real inventory defers optional background work")
	var explicit_allowed: bool = await hud._ui_l1_wait_for_background_slot(false)
	expect(explicit_allowed, "explicit prewarm mode is not gated or deadlocked")
	hud.inventory_panel.hide()
	Input.action_press("ui_accept")
	expect(hud._ui_l1_background_blocked(), "held input defers optional background work")
	Input.action_release("ui_accept")
	expect(not hud._ui_l1_background_blocked(), "idle hidden panels permit background work")
	hud.queue_free()
	await get_tree().process_frame
	for failure: String in failures:
		push_error("UI_L1_BACKGROUND " + failure)
	print("UI_L1_BACKGROUND_%s failures=%d" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
