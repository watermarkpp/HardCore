extends Node
const Controller := preload("res://scripts/map_editor/polygon/poly_editor_controller.gd")
const CanvasScript := preload("res://scripts/map_editor/map_editor_canvas_preview.gd")
const Stack := preload("res://scripts/map_editor/map_editor_command_stack.gd")
const Geo := preload("res://scripts/map_editor/polygon/poly_geometry.gd")
const Coord := preload("res://scripts/map_editor/map_editor_coordinate.gd")
# The original canvas input implementation is exercised. Only raster rendering
# and document-side texture/workspace I/O are disabled in this fixture.
class InputCanvas extends MapEditorCanvasPreview:
	func _draw() -> void:
		pass
	func set_document(value: Dictionary) -> void:
		document = value
		if is_instance_valid(_hc_polygon_controller):
			_hc_polygon_controller.invalidate_document()
class EditorShell extends Control:
	var preview: Variant
	var sidebar: VBoxContainer
	var status_label: Label
	var command_stack := MapEditorCommandStack.new()
	var current_document: Dictionary
	var _last_build_candidate: Dictionary = {}
var errors: Array[String] = []
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		errors.append(message)
		push_error("HC_POLYGON_EDITOR_INPUT: " + message)
func _ready() -> void:
	call_deferred("run")
func key(code: Key, ctrl := false, echo := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.echo = echo
	return e
func mouse(point: Vector2, pressed: bool, double_click := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = point
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.double_click = double_click
	return e
func run() -> void:
	var shell := EditorShell.new()
	add_child(shell)
	shell.sidebar = VBoxContainer.new()
	shell.add_child(shell.sidebar)
	shell.status_label = Label.new()
	shell.add_child(shell.status_label)
	shell.preview = InputCanvas.new()
	shell.preview.size = Vector2(1000,700)
	shell.add_child(shell.preview)
	shell.current_document = {"map_id":"precision_input_fixture", "design":{"design_size":[80,80]}, "editor_meta":{"collision_authority":Geo.AUTHORITY,"revision":1},
		"layers":{"collision":[],"object_base":[{"instance_id":"inst_fixture", "asset_id":"precision_fixture_missing_catalog", "tile":[20,21], "footprint_tiles":[2,3], "anchor_px":[32,64], "scale":[1.2,1.2], "offset_px":[0,0], "collision_policy":"none"}]}}
	shell.preview.set_document(shell.current_document)
	var controller := Controller.new()
	shell.add_child(controller)
	controller.setup(shell)
	shell.preview.grab_focus()
	await get_tree().process_frame
	shell.preview.selected_selectable_id = "inst_fixture"
	var grid_events := {"count":0,"delta":Vector2i.ZERO}
	shell.preview.selectable_move_requested.connect(func(_id: String, delta: Vector2i) -> void: grid_events.count += 1; grid_events.delta = delta)
	shell.preview._gui_input(key(KEY_RIGHT))
	check(grid_events.count == 1 and grid_events.delta == Vector2i(1,0), "normal arrows retain original grid signal")
	shell.preview._gui_input(key(KEY_UP,true))
	check(grid_events.count == 1, "Ctrl key must not also emit grid movement")
	check(shell.current_document.layers.object_base[0].offset_px == [0.0,-1.0], "Ctrl up moves exactly one unzoomed pixel north")
	check(shell.current_document.layers.object_base[0].tile == [20,21], "pixel move never rounds/replaces tile")
	shell.preview._gui_input(key(KEY_RIGHT,true,true))
	check(shell.current_document.layers.object_base[0].offset_px == [1.0,-1.0], "key repeat remains one pixel per event")
	check(shell.command_stack.undo(), "pixel undo exists")
	check(shell.current_document.layers.object_base[0].offset_px == [0.0,-1.0], "pixel undo restores exact offset")
	check(shell.command_stack.redo(), "pixel redo exists")
	check(shell.current_document.layers.object_base[0].offset_px == [1.0,-1.0], "pixel redo exact")
	controller.open_polygon_tool("polygon")
	shell.preview._draw_offset = Vector2(100.3,77.6)
	shell.preview._draw_scale = .731
	var points := PackedVector2Array([Vector2(3.137,4.421), Vector2(7.253,4.873), Vector2(5.113,8.167)])
	for i: int in range(points.size()):
		var screen := controller._gu_to_screen(points[i])
		shell.preview._gui_input(mouse(screen,true))
		if i == 0:
			shell.preview._gui_input(mouse(screen,true))
			check(controller.draft.size() == 1, "duplicate pressed event cannot duplicate vertex")
		shell.preview._gui_input(mouse(screen,false))
	check(controller.draft.size() == 3, "three free arbitrary vertices")
	check(controller.draft[0].distance_to(points[0]) < .0001, "first point not snapped to intersection")
	shell.preview._gui_input(key(KEY_ENTER))
	check(shell.current_document.layers.collision.size() == 1, "Enter commits exact polygon into document")
	if shell.current_document.layers.collision.size() == 1:
		var written := Geo.decode(shell.current_document.layers.collision[0].data.points)
		check(written.size() == 3, "no grid rasterization in saved polygon")
		for point: Vector2 in points:
			var nearest := INF
			for saved: Vector2 in written: nearest = minf(nearest,saved.distance_to(point))
			check(nearest < .0001, "stored vertex equals authored free point")
	check(shell.command_stack.undo(), "polygon undo uses original stack")
	check(shell.current_document.layers.collision.is_empty(), "undo removes exact polygon")
	check(shell.command_stack.redo(), "polygon redo uses original stack")
	check(shell.current_document.layers.collision.size() == 1, "redo restores polygon")
	shell.queue_free()
	await get_tree().process_frame
	if errors.is_empty(): print("HC_POLYGON_EDITOR_INPUT_TEST_PASS checks=",checks)
	get_tree().quit(0 if errors.is_empty() else 1)
