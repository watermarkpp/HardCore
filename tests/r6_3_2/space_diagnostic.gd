extends Node
## DIAGNOSTIC ONLY. Does not certify rendering, transaction latency or Android.
const Shop := preload("res://scripts/shop_panel.gd")
const Names := preload("res://scripts/ui_item_name_style.gd")
const Bounds := preload("res://scripts/ui_style_visual_bounds.gd")
const Space := preload("res://scripts/ui_shop_detail_space.gd")
const SOURCE_PATHS := [
	"scripts/item_detail_docked_presenter.gd", "scripts/ui_shop_detail_space.gd",
	"scripts/ui_style_visual_bounds.gd", "scripts/gothic_ui_theme.gd",
	"scripts/shop_panel.gd", "scripts/ui_runtime_layout_overrides.gd",
	"assets/data/ui/manual_layout_overrides.json", "project.godot",
]
var panel: Control
var merchant: Dictionary = {}
var active_stock_key := ""
var rows: Array = []
var problems: Array[String] = []
var output_path := "res://outputs/test_logs/r32_geometry.json"
var completed := false
var started := 0

func _ready() -> void:
	started = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerState.test_mode = true
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not completed and Time.get_ticks_msec() - started > 45000:
		problems.append("DIAGNOSTIC_WATCHDOG_TIMEOUT")
		finish(false)

func json_value(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x, value.y]
	if value is Rect2: return [value.position.x, value.position.y, value.size.x, value.size.y]
	if value is Color: return [value.r, value.g, value.b, value.a]
	if value is Vector4: return [value.x, value.y, value.z, value.w]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = json_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for element: Variant in value: result.append(json_value(element))
		return result
	return value

func frames(count: int) -> void:
	for i in range(count): await get_tree().process_frame

func on_buy(stock: Array) -> void:
	panel.call("set_buy_quotes", PlayerState.shop_buy_quotes(stock, merchant))

func on_sell(requests: Array) -> void:
	panel.call("set_sell_quotes", PlayerState.shop_sell_quotes(requests))

func state_row(name_text: String, domain: String, stage: String) -> Dictionary:
	var view: Control = panel.get("item_detail_presenter") as Control
	var result: Dictionary = {"name": name_text, "domain": domain, "stage": stage,
		"merchant_context": merchant.duplicate(true), "stock_key": active_stock_key, "panel_rect": Rect2(panel.position, panel.size),
		"viewport": get_viewport().get_visible_rect(), "window": get_window().size,
		"owner_canvas_transform": str(panel.get_global_transform_with_canvas()),
		"screen_transform": str(get_viewport().get_screen_transform()),
		"snapshot": view.call("debug_layout_snapshot"), "actions": []}
	for property: String in ["buy_button", "repair_button", "sell_quantity_row", "sell_quantity_button"]:
		var control: Control = panel.get(property) as Control
		if control == null: continue
		var bounds: Dictionary = Bounds.control_bounds(control)
		var action: Dictionary = {"property": property, "name": str(control.name),
			"visible": control.is_visible_in_tree(), "position": control.position, "size": control.size,
			"minimum": control.get_minimum_size(), "combined_minimum": control.get_combined_minimum_size(),
			"custom_minimum": control.custom_minimum_size, "scale": control.scale,
			"theme_variation": str(control.theme_type_variation), "bounds": bounds,
			"owner_hit_rect": Space.rect_in(panel, control)}
		if bool(bounds.get("ok", false)):
			action["owner_visual_rect"] = Space.rect_in(panel, control, bounds.get("rect", Rect2()))
		if control is Button:
			action["text"] = (control as Button).text
			action["font_size"] = control.get_theme_font_size("font_size")
			var style_data: Array = []
			for state: StringName in Bounds.STATES:
				var style: StyleBox = control.get_theme_stylebox(state)
				style_data.append({"state": str(state), "bounds": Bounds.style_bounds(style, Rect2(Vector2.ZERO, control.size)),
					"class": style.get_class() if style != null else "null"})
			action["styles"] = style_data
		(result["actions"] as Array).append(action)
	var title: Label = view.get("title_label") as Label
	var body: RichTextLabel = view.get("detail_label") as RichTextLabel
	result["title_font"] = title.get_theme_font("font").resource_path
	result["body_font"] = body.get_theme_font("normal_font").resource_path
	return result

func record(name_text: String, domain: String, stage: String) -> void:
	rows.append(state_row(name_text, domain, stage))
	write_capture(false) # Persist every sample BEFORE any terminal failure.

func take_shot(name_text: String, domain: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("HC_R32_CAPTURE_SHOTS") != "1": return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		problems.append("SCREENSHOT_UNAVAILABLE"); return
	var path := "res://outputs/test_logs/r32_shots/" + (active_stock_key + "|" + str(merchant.get("merchant_id", "")) + "|" + name_text + "|" + domain).sha256_text().substr(0, 16) + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if image.save_png(ProjectSettings.globalize_path(path)) != OK:
		problems.append("SCREENSHOT_WRITE_FAILED")
		return
	var sidecar := FileAccess.open(path + ".json", FileAccess.WRITE)
	if sidecar == null:
		problems.append("SCREENSHOT_SIDECAR_WRITE_FAILED")
		return
	sidecar.store_string(JSON.stringify(json_value({"stock_key": active_stock_key, "name": name_text,
		"domain": domain, "image_size": image.get_size(), "row": rows.back(),
		"scope": "raw_rendered_runtime_not_phone_not_acceptance"}), "  "))
	sidecar.close()

func _run() -> void:
	if not GameData.ensure_loaded():
		problems.append("DATA_UNAVAILABLE"); finish(false); return
	PlayerState.reset_progress(false)
	PlayerState.level = 60
	PlayerState.recalculate_stats(false)
	for stock_key: String in ["medicine", "general"]:
		active_stock_key = stock_key
		merchant = GameData.merchant_context(stock_key)
		if str(merchant.get("merchant_id", "")).is_empty():
			problems.append("MERCHANT_UNAVAILABLE:" + stock_key); continue
		panel = Shop.new()
		panel.connect("buy_quotes_requested", on_buy)
		panel.connect("sell_quotes_requested", on_sell)
		add_child(panel)
		var view: Control = panel.get("item_detail_presenter") as Control
		if view == null:
			problems.append("PRESENTER_MISSING"); finish(false); return
		# Suppression is permitted ONLY for collecting the failing baseline.
		# The production/formal matrix never enables these flags.
		view.set("_test_suppress_expected_layout_error", true)
		view.set("_r32_capture_candidates", true)
		await frames(6)
		for name_text: String in ["木剑", "匕首", "超级金创药", "超级魔法药"]:
			var item: Dictionary = GameData.get_item_record(name_text)
			if item.is_empty():
				problems.append("ITEM_UNAVAILABLE:" + name_text); continue
			var entry: Dictionary = {"name": name_text, "pack_count": 1,
				"merchant_context": merchant.duplicate(true), "merchant_id": merchant.get("merchant_id", "")}
			var canonical := int(Names.canonical_id(item))
			if canonical > 0: entry["item_id"] = canonical
			panel.call("open_for", "R3.2空间诊断", [entry], merchant)
			await frames(6)
			panel.get("item_list").select(0)
			panel.call("_on_item_selected", 0)
			record(name_text, "buy", "synchronous")
			await frames(1); record(name_text, "buy", "next_frame")
			await frames(5); record(name_text, "buy", "settled")
			await take_shot(name_text, "buy")
			panel.call("_ui_dismiss_selection")
			PlayerState.inventory = []
			var received: Dictionary = PlayerState.add_item(name_text, 1)
			if not bool(received.get("success", false)):
				problems.append("RECEIVE_FAILED:" + name_text); continue
			panel.call("_set_trade_mode", "sell")
			await frames(6)
			panel.call("_request_sell_quotes")
			panel.call("_select_sell_item", 0)
			record(name_text, "sell", "synchronous")
			await frames(1); record(name_text, "sell", "next_frame")
			await frames(5); record(name_text, "sell", "settled")
			await take_shot(name_text, "sell")
			panel.call("_ui_dismiss_selection")
		panel.queue_free()
		await frames(2)
	finish(problems.is_empty() and rows.size() == 48)

func write_capture(complete: bool) -> void:
	var hashes: Dictionary = {}
	for path: String in SOURCE_PATHS:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	var data: Dictionary = {"schema": "hc.r32.geometry.v1", "capture_complete": complete,
		"layout_acceptance": "NOT_EVALUATED_DIAGNOSTIC_ONLY", "test_mode": PlayerState.test_mode,
		"engine": Engine.get_version_info(), "source_hashes": hashes,
		"loaded_project_root": ProjectSettings.globalize_path("res://"),
		"rows": rows, "problems": problems, "expected_rows": 48}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		problems.append("CAPTURE_WRITE_FAILED"); return
	file.store_string(JSON.stringify(json_value(data), "  "))
	file.close()

func finish(ok: bool) -> void:
	if completed: return
	completed = true
	write_capture(ok)
	print("R32_CAPTURE_PASS layout_acceptance=NOT_EVALUATED" if ok else "R32_CAPTURE_INCOMPLETE")
	get_tree().quit(0 if ok and problems.is_empty() else 1)
