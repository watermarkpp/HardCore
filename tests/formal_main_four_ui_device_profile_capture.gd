extends Node

const PROFILE_PHYSICAL := Vector2(2664, 1200)
const PROFILE_SAFE_LEFT_PX := 121.0
const PROFILE_SAFE_RIGHT_PX := 129.0

var _output_dir := ""
var _logical := Vector2.ZERO
var _safe_left := 0.0
var _safe_right := 0.0
var _head := ""
var _hud: Node
var _safe_root: Control
var _viewport: Viewport

func _ready() -> void:
	_head = OS.get_environment("DEVICE_PROFILE_HEAD")
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.inventory = []
	PlayerState.add_item("强效太阳水", 82)
	PlayerState.add_item("魔法药(中量)", 94)
	PlayerState.add_item("金创药(小量)", 25)
	PlayerState.warehouse_inventory = [{"name": "魔法药(小量)", "count": 23}]
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_viewport = get_viewport()
	_logical = _viewport.get_visible_rect().size
	_safe_left = PROFILE_SAFE_LEFT_PX / PROFILE_PHYSICAL.x * _logical.x
	_safe_right = PROFILE_SAFE_RIGHT_PX / PROFILE_PHYSICAL.x * _logical.x
	_hud = game.get("hud") as Node
	assert(_hud != null, "formal main scene did not create GameHUD")
	_safe_root = _hud.get_node_or_null("MobileSafeRoot") as Control
	assert(_safe_root != null, "formal main scene HUD is missing MobileSafeRoot")
	_safe_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_safe_root.position = Vector2(_safe_left, 0.0)
	_safe_root.size = _logical - Vector2(_safe_left + _safe_right, 0.0)
	_output_dir = ProjectSettings.globalize_path("res://outputs/android_device")
	DirAccess.make_dir_recursive_absolute(_output_dir)
	await _capture("skill", "skill_panel", func() -> void: _hud.call("_toggle_skill_book"))
	await _capture("inventory", "inventory_panel", func() -> void: _hud.call("_toggle_inventory"))
	await _capture("map", "map_panel", func() -> void: _hud.call("_toggle_map_panel"))
	await _capture("warehouse", "warehouse_panel", func() -> void: _hud.call("open_warehouse"))
	print("FORMAL_MAIN_FOUR_UI_DEVICE_PROFILE_PASS head=%s logical=%s" % [_head, _logical])
	get_tree().quit(0)

func _capture(mode: String, panel_property: String, opener: Callable) -> void:
	_hud.call("_close_modal_panels")
	await get_tree().process_frame
	opener.call()
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Node = _hud.get(panel_property) as Node
	assert(panel != null and panel.visible, "%s panel did not open through GameHUD" % mode)
	var png_path := _output_dir.path_join("local_main_%s_device_profile.png" % mode)
	assert(_viewport.get_texture().get_image().save_png(png_path) == OK, "unable to save %s capture" % mode)
	var modal_rects: Dictionary = {}
	_collect_rects(panel, modal_rects)
	var payload := {
		"head": _head,
		"source": "res://scenes/main.tscn",
		"mode": mode,
		"physical_size": [int(PROFILE_PHYSICAL.x), int(PROFILE_PHYSICAL.y)],
		"logical_viewport": [_logical.x, _logical.y],
		"safe_pixels": {"left": PROFILE_SAFE_LEFT_PX, "right": PROFILE_SAFE_RIGHT_PX, "top": 0.0, "bottom": 0.0},
		"safe_logical": {"left": _safe_left, "right": _safe_right},
		"safe_root_rect": [_safe_root.position.x, _safe_root.position.y, _safe_root.size.x, _safe_root.size.y],
		"panel_rect": _rect_array(panel.get_global_rect()),
		"modal_and_section_rects": modal_rects,
		"bottom_gaps": _bottom_gaps(panel, modal_rects),
		"capture": png_path,
	}
	var json_path := _output_dir.path_join("local_main_%s_device_profile.json" % mode)
	FileAccess.open(json_path, FileAccess.WRITE).store_string(JSON.stringify(payload, "  "))
	print("FORMAL_MAIN_UI_CAPTURE_PASS mode=%s capture=%s geometry=%s" % [mode, png_path, json_path])

func _collect_rects(node: Node, output: Dictionary) -> void:
	if node is Control:
		var control := node as Control
		var node_name := str(node.name)
		if node_name == "ModalSurface" or node_name.contains("Frame") or node_name.contains("Surface"):
			output[node_name] = _rect_array(control.get_global_rect())
		for child in node.get_children():
			_collect_rects(child, output)

func _rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _bottom_gaps(panel: Node, rects: Dictionary) -> Dictionary:
	var gaps := {"panel": _logical.y - (panel as Control).get_global_rect().end.y}
	for key: String in rects.keys():
		var rect_values: Array = rects[key]
		gaps[key] = _logical.y - (float(rect_values[1]) + float(rect_values[3]))
	return gaps
