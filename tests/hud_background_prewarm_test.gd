extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: GameHUD = game.hud
	hud.start_budgeted_panel_prewarm(game._system_menu_panel)
	# Reproduce the race that matters on device: the player opens a page while
	# the invisible scheduler is still loading the remaining page scripts.
	hud._toggle_inventory()
	assert(hud.inventory_panel.visible, "immediate first interaction did not open inventory")
	# R2 contract migration: visible UI yields optional preparation. Keep the
	# original no-steal requirement BEFORE the user closes the panel; then
	# require bounded completion AFTER close, with the original 240-frame caps.
	for _visible_frame in range(16):
		await get_tree().process_frame
	assert(hud._ui_l1_background_blocked(), "visible business UI did not gate optional work")
	var visible_stage_count := (hud.panel_prewarm_diagnostic().get("construction_ms_by_panel", {}) as Dictionary).size()
	for _blocked_frame in range(16):
		await get_tree().process_frame
	assert((hud.panel_prewarm_diagnostic().get("construction_ms_by_panel", {}) as Dictionary).size() == visible_stage_count, "optional panel construction progressed behind visible UI")
	assert(hud.inventory_panel.visible, "background prewarm hid a page opened by the player")
	assert(hud.inventory_panel.item_grid.get_child_count() == 100, "visible inventory exposed a partial grid")
	hud.inventory_panel.hide() # explicit user close; not performed by scheduler
	for _frame in 240:
		if hud.all_panels_are_prewarmed():
			break
		await get_tree().process_frame
	assert(hud.all_panels_are_prewarmed(), "background panel prewarm did not resume after close")
	assert(not hud.inventory_panel.visible, "background prewarm reopened a page explicitly closed by the player")
	assert(hud.inventory_panel.item_grid.get_child_count() == 100, "visible inventory exposed a partial grid")
	assert(hud.warehouse_panel.bag_grid.get_child_count() == 100, "warehouse bag grid did not finish in background")
	assert(hud.warehouse_panel.stash_grid.get_child_count() == 100, "warehouse stash grid did not finish in background")
	for _frame in 240:
		if hud._catalog_icon_prewarm_complete:
			break
		await get_tree().process_frame
	assert(hud._catalog_icon_prewarm_complete, "catalog icon threaded prewarm did not settle")
	var diagnostic := hud.panel_prewarm_diagnostic()
	var script_prefetch: Dictionary = diagnostic.get("script_prefetch", {})
	assert((script_prefetch.get("failures", []) as Array).is_empty(), "panel script threaded prefetch failed")
	assert((script_prefetch.get("pending", []) as Array).is_empty(), "panel scripts remained pending")
	assert(not bool(diagnostic.get("shop_alternate_profile_warmed", true)), "user interaction did not protect shop profile state")
	print("HUD_BACKGROUND_PREWARM_PASS visible_phase_preserved=true resumed_after_close=true grids=100 script_failures=0")
	get_tree().quit(0)
