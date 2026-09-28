extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var hud := GameHUD.new()
	add_child(hud)
	await get_tree().process_frame
	var target_panel := hud.get_node("MobileSafeRoot/TargetPanel") as Control
	assert(target_panel != null and target_panel.visible)
	hud.open_enhancement_vendor()
	assert(hud.enhancement_panel != null and hud.enhancement_panel.visible)
	assert(not target_panel.visible, "target status leaked through forge header")
	hud.update_target("钉耙猫", 1, 2)
	hud._close_modal_panels()
	assert(target_panel.visible, "closing forge did not restore combat target bar")
	assert("钉耙猫" in hud.target_label.text, "hidden target bar did not keep its current target")
	print("FORGE_HUD_TARGET_OCCLUSION_PASS")
	get_tree().quit(0)
