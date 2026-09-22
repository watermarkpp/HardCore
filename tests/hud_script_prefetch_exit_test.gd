extends Node

const HUD := preload("res://scripts/hud.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var hud := HUD.new()
	add_child(hud)
	# Begin real asynchronous script compilation, then immediately leave the
	# tree while it owns the requests. The engine must never outlive their
	# owner with unresolved script dependencies during shutdown.
	hud._prefetch_panel_scripts()
	remove_child(hud)
	for path: String in [HUD.INVENTORY_PANEL_SCRIPT_PATH, HUD.MAP_PANEL_SCRIPT_PATH,
		HUD.SKILL_PANEL_SCRIPT_PATH, HUD.QUEST_PANEL_SCRIPT_PATH,
		HUD.WAREHOUSE_PANEL_SCRIPT_PATH, HUD.SHOP_PANEL_SCRIPT_PATH]:
		assert(ResourceLoader.has_cached(path), "HUD exited before its script finished: %s" % path)
	assert(hud._panel_script_pending.is_empty())
	hud.free()
	await get_tree().process_frame
	print("HUD_SCRIPT_PREFETCH_EXIT_PASS")
	get_tree().quit()
