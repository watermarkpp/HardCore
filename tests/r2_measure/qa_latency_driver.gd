extends Node
## QA ONLY. Requires an identical, previously validated seed copied to each
## isolated measure tree. Not a seed generator, not a production autoload.
## Signal/GUI route -> real transaction -> disk delta -> post_draw proxy.
var spec: Dictionary = {}
var game: Node
var hud: GameHUD
var rows: Array = []
var failures: Array[String] = []
var started_usec := 0
var finished := false
var profile_path := ""
var expected := {"buy": 0, "equip": 0}
var completed := {"buy": 0, "equip": 0}
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	started_usec = Time.get_ticks_usec()
	_run.call_deferred()
func _process(_delta: float) -> void:
	# Wall-clock watchdog survives an aborted coroutine / missing API / long wait.
	if not finished and Time.get_ticks_usec() - started_usec > 180000000:
		failures.append("WALL_CLOCK_TIMEOUT_INCOMPLETE_ACTIONS")
		finish(false)
func require(ok: bool, why: String) -> bool:
	if not ok:
		failures.append(why)
		push_error("R2_QA " + why)
	return ok
func read_json(path: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if raw is Dictionary else {}
func wait_for(predicate: Callable, seconds := 10.0) -> bool:
	var until := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while not bool(predicate.call()) and Time.get_ticks_usec() < until and not finished:
		await get_tree().process_frame
	return bool(predicate.call()) and not finished
func tap(button: BaseButton) -> bool:
	if not require(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "GUI_TARGET_NOT_AVAILABLE"):
		return false
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	if not require(button.get_viewport().get_visible_rect().has_point(point), "GUI_TARGET_OUTSIDE_VIEWPORT"):
		return false
	for down: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = point
		event.pressed = down
		button.get_viewport().push_input(event, true) # already viewport-local
	return true
func next_draw() -> void:
	await RenderingServer.frame_post_draw
func disk_matches() -> bool:
	var saved := read_json(profile_path)
	return require(bool(PlayerState.last_save_result.get("success", false)) and
		str(saved.get("profile_id", "")) == PlayerState.active_profile_id and
		int(saved.get("gold", -1)) == PlayerState.gold and
		JSON.stringify(saved.get("inventory", [])) == JSON.stringify(JSON.parse_string(JSON.stringify(PlayerState.inventory))) and
		JSON.stringify(saved.get("equipment", {})) == JSON.stringify(JSON.parse_string(JSON.stringify(PlayerState.equipment))),
		"COMMITTED_MEMORY_AND_DISK_DIFFER")
func bag_index_for(name_text: String) -> int:
	for i in range(PlayerState.inventory.size()):
		var r: Variant = PlayerState.inventory[i]
		if r is Dictionary and str(r.get("name", "")) == name_text:
			return i
	return -1
func _run() -> void:
	# Manifests are executor-prepared fixture data, not permission to edit core.
	var path := OS.get_environment("HC_R2_QA_MANIFEST")
	if not require(not path.is_empty(), "MANIFEST_REQUIRED"):
		finish(false); return
	spec = read_json(path)
	if not require(str(spec.get("schema", "")) == "hc.r2.qa.seed.v1", "MANIFEST_SCHEMA"):
		finish(false); return
	if not require(DisplayServer.get_name() != "headless", "RENDERED_ROUTE_REQUIRES_WINDOWED_BACKEND"):
		finish(false); return
	var root_path := str(spec.get("storage_root", ""))
	if not require(root_path.begins_with("user://r2_fixture/") and not root_path.contains("..") and root_path.ends_with("/"), "ISOLATED_STORAGE_ROOT_REQUIRED"):
		finish(false); return
	var profile_id := str(spec.get("profile_id", ""))
	if not require(not profile_id.is_empty() and not profile_id.contains("/") and not profile_id.contains("\\") and not profile_id.contains(".."), "PROFILE_ID_REQUIRED"):
		finish(false); return
	var seed_files: Dictionary = spec.get("seed_files", {})
	if not require(not seed_files.is_empty(), "SEED_HASHES_REQUIRED"):
		finish(false); return
	for rel: String in seed_files:
		if not require(not rel.begins_with("/") and not rel.contains("..") and not rel.contains(":"), "INVALID_SEED_PATH"):
			finish(false); return
		if not require(FileAccess.file_exists(root_path + rel) and FileAccess.get_sha256(root_path + rel) == str(seed_files[rel]), "SEED_HASH_MISMATCH:" + rel):
			finish(false); return
	PlayerState.test_mode = false
	PlayerState.profile_directory = root_path + "characters"
	PlayerState.profile_index_path = root_path + "character_profiles.json"
	PlayerState.shared_warehouse_path = root_path + "shared_warehouse.json"
	PlayerState.shared_warehouse_transaction_log_path = root_path + "shared_warehouse.transaction.json"
	profile_path = PlayerState.profile_directory + "/" + profile_id + ".json"
	if not require(seed_files.has("characters/" + profile_id + ".json") and seed_files.has("shared_warehouse.json") and seed_files.has("character_profiles.json"), "CRITICAL_SEED_FILES_MISSING"):
		finish(false); return
	if not require(GameData.ensure_loaded(), "DATA_NOT_READY"):
		finish(false); return
	PlayerState._shared_warehouse_initialized = false
	PlayerState.active_profile_id = profile_id
	PlayerState.load_save()
	if not require(bool(PlayerState.last_load_result.get("success", false)), "VALIDATED_PROFILE_LOAD_FAILED"):
		finish(false); return
	var repetitions := int(spec.get("repetitions", 10))
	var equipment_cases: Array = spec.get("equipment_cases", [])
	if not require(repetitions >= 5 and repetitions <= 30 and not equipment_cases.is_empty(), "INSUFFICIENT_ACTION_PLAN"):
		finish(false); return
	expected = {"buy": repetitions, "equip": repetitions * equipment_cases.size()}
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	if not require(await wait_for(func() -> bool: return game.get("hud") != null and bool(game.call("gameplay_input_is_enabled")), 45.0), "WORLD_READINESS_TIMEOUT"):
		finish(false); return
	hud = game.get("hud") as GameHUD
	var stock_key := str(spec.get("merchant_stock_key", "medicine"))
	var context: Dictionary = GameData.merchant_context(stock_key)
	var stock: Array = GameData.merchant_stock(stock_key)
	if not require(not str(context.get("merchant_id", "")).is_empty() and not stock.is_empty(), "REAL_MERCHANT_STOCK_REQUIRED"):
		finish(false); return
	var already_constructed := is_instance_valid(hud.shop_panel)
	var t0 := Time.get_ticks_usec()
	hud.open_shop("R2实际商人服务入口", stock, context)
	var cpu_done := Time.get_ticks_usec()
	await next_draw()
	rows.append({"operation": "service_open", "cpu_us": cpu_done - t0,
		"post_draw_proxy_us": Time.get_ticks_usec() - t0, "constructor_cold": not already_constructed,
		"scope": "HUD_service_entry_NOT_NPC_proximity_or_voice"})
	var shop = hud.shop_panel
	if not require(shop.buy_requested.get_connections().size() > 0, "BUY_AUTHORITY_NOT_CONNECTED"):
		finish(false); return
	var buy_index := int(spec.get("stock_index", 0))
	if not require(buy_index >= 0 and buy_index < shop.goods_buttons.size(), "STOCK_INDEX_INVALID"):
		finish(false); return
	for i in range(repetitions):
		if not require(await wait_for(func() -> bool: return not shop._buy_request_locked), "BUY_LOCK_TIMEOUT"):
			finish(false); return
		if not tap(shop.goods_buttons[buy_index]):
			finish(false); return
		await next_draw()
		var quote: Dictionary = shop._buy_quote_for_index(buy_index).duplicate(true)
		if not require(bool(quote.get("valid", false)) and not str(quote.get("quote_id", "")).is_empty() and not shop.buy_button.disabled, "REAL_BUY_QUOTE_NOT_READY"):
			finish(false); return
		var name_text := str(quote.get("item_name", ""))
		var count0 := PlayerState.item_count(name_text)
		var gold0 := PlayerState.gold
		t0 = Time.get_ticks_usec()
		if not tap(shop.buy_button):
			finish(false); return
		cpu_done = Time.get_ticks_usec()
		await next_draw()
		var draw_done := Time.get_ticks_usec()
		if not require(PlayerState.item_count(name_text) == count0 + int(quote.get("pack_count", 1)) and PlayerState.gold == gold0 - int(quote.get("total_price", 0)), "BUY_DID_NOT_COMMIT_EXACT_DELTA") or not disk_matches():
			finish(false); return
		completed["buy"] += 1
		rows.append({"operation": "buy", "index": i, "cpu_us": cpu_done - t0, "post_draw_proxy_us": draw_done - t0, "success": true, "disk_verified": true, "save": PlayerState._last_runtime_commit_profile.duplicate(true)})
	hud._close_modal_panels()
	hud._toggle_inventory()
	var inv = hud.inventory_panel
	await next_draw()
	for c: Dictionary in equipment_cases:
		var slot := str(c.get("slot", ""))
		var names: Array = c.get("names", [])
		if not require(inv.equipment_buttons.has(slot) and names.size() == 2 and names[0] != names[1], "EXPLICIT_EQUIPMENT_PAIR_REQUIRED"):
			finish(false); return
		for i in range(repetitions):
			inv._ui_dismiss_selection()
			var name_text := str(names[i % 2])
			var index := bag_index_for(name_text)
			if not require(index >= 0 and index < inv._bag_cells.size(), "SEEDED_EQUIPMENT_NOT_IN_BAG:" + name_text):
				finish(false); return
			var instance_id := str(PlayerState.inventory[index].get("instance_id", ""))
			if not require(not instance_id.is_empty(), "OPAQUE_EQUIPMENT_ID_REQUIRED"):
				finish(false); return
			if not tap(inv._bag_cells[index].get_child(0) as BaseButton):
				finish(false); return
			await next_draw()
			if not require(inv.selected_inventory_index == index and inv.selected_inventory_refs.size() == 1, "BAG_GUI_SELECTION_DID_NOT_ROUTE"):
				finish(false); return
			var rev := PlayerState.equipment_transaction_revision
			t0 = Time.get_ticks_usec()
			if not tap(inv.equipment_buttons[slot]):
				finish(false); return
			cpu_done = Time.get_ticks_usec()
			await next_draw()
			var draw_done := Time.get_ticks_usec()
			if not require(PlayerState.equipment_transaction_revision == rev + 1 and str(PlayerState.equipment[slot].get("instance_id", "")) == instance_id, "EQUIP_GUI_DID_NOT_COMMIT_EXACT_INSTANCE") or not disk_matches():
				finish(false); return
			completed["equip"] += 1
			rows.append({"operation": "equip", "slot": slot, "index": i, "cpu_us": cpu_done - t0, "post_draw_proxy_us": draw_done - t0, "success": true, "disk_verified": true, "save": PlayerState._last_runtime_commit_profile.duplicate(true)})
	finish(true)
func finish(ok: bool) -> void:
	if finished:
		return
	finished = true
	ok = ok and failures.is_empty() and completed == expected and int(expected.get("buy", 0)) > 0
	var dir := "user://r2_results"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var out := dir + "/actions_%d.json" % Time.get_ticks_usec()
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		ok = false
	else:
		f.store_string(JSON.stringify({"schema": "hc.r2.actions.v1", "complete": ok, "spec": spec,
			"test_mode": PlayerState.test_mode, "expected": expected, "completed": completed,
			"rows": rows, "failures": failures, "scope": "synthetic_GUI_release_to_post_draw_PROXY_not_android_presentation"}, "  "))
		f.close()
	print("R2_QA_DRIVER_%s path=%s" % ["PASS" if ok else "FAIL", out])
	get_tree().quit(0 if ok else 1)
