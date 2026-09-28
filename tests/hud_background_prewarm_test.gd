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
	assert(is_instance_valid(hud.enhancement_panel), "forge panel remained cold until the first vendor tap")
	assert(not hud.enhancement_panel.visible, "prewarm exposed forge panel")
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
	assert(bool(diagnostic.get("shop_alternate_profile_warmed", false)), "initial Loading did not prepare both shop layouts")
	PlayerState.inventory = [{"name": "金创药(小量)", "count": 8}]
	PlayerState.inventory_changed.emit()
	var consumable_samples: Array[float] = []
	for _sample in 5:
		var item_started_usec := Time.get_ticks_usec()
		var use_result := PlayerState.use_inventory_index_result(0)
		assert(bool(use_result.get("success", false)), str(use_result))
		consumable_samples.append(float(Time.get_ticks_usec() - item_started_usec) / 1000.0)
	print("HUD_CONSUMABLE_SIGNAL_LATENCY ", JSON.stringify(consumable_samples))
	var forge_open_started_usec := Time.get_ticks_usec()
	hud.open_enhancement_vendor("")
	var forge_open_ms := float(Time.get_ticks_usec() - forge_open_started_usec) / 1000.0
	assert(hud.enhancement_panel.visible and is_instance_valid(hud.enhancement_panel), "first forge open failed after prewarm")
	print("HUD_BACKGROUND_PREWARM_PASS visible_phase_preserved=true resumed_after_close=true grids=100 script_failures=0 forge_first_open_ms=%.3f" % forge_open_ms)
	get_tree().quit(0)
