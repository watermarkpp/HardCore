extends Node

## Real GDScript branches. No fake StyleBox/Control and no generated item data.
const Bounds := preload("res://scripts/ui_style_visual_bounds.gd")
var failures: Array[String] = []
var checks := 0
var finished := false
var started_usec := 0

func _ready() -> void:
	started_usec = Time.get_ticks_usec()
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not finished and Time.get_ticks_usec() - started_usec > 5000000:
		failures.append("TYPE_BRANCH_COROUTINE_ABORT_OR_TIMEOUT")
		_finish()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func near(a: Rect2, b: Rect2) -> bool:
	return a.position.is_equal_approx(b.position) and a.size.is_equal_approx(b.size)

func check_control(control: Control, expected: Rect2, label: String) -> void:
	# Variant is deliberate in a negative regression: an aborted old function
	# must be recorded as failure rather than causing a second .ok-on-null error.
	var result: Variant = Bounds.control_bounds(control)
	if not result is Dictionary:
		expect(false, label + ":NON_DICTIONARY_RESULT")
		return
	var data: Dictionary = result
	expect(bool(data.get("ok", false)), label + ":OK")
	var r: Variant = data.get("rect")
	if not r is Rect2:
		expect(false, label + ":RECT_MISSING")
		return
	expect(near(r, expected), label + ":GEOMETRY")

func _run() -> void:
	var cases: Array[Control] = []
	cases.append(Control.new())
	cases.append(Label.new())
	cases.append(ColorRect.new())
	cases.append(TextureRect.new())
	cases.append(Panel.new())
	cases.append(PanelContainer.new())
	cases.append(Button.new())
	cases.append(CheckButton.new())
	for control: Control in cases:
		if control is BaseButton:
			for state: StringName in Bounds.STATES:
				control.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		elif control is Panel or control is PanelContainer:
			control.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
		control.size = Vector2(180, 60)
		check_control(control, Rect2(Vector2.ZERO, control.size), control.get_class() + ":DETACHED")
		add_child(control)
		check_control(control, Rect2(Vector2.ZERO, control.size), control.get_class() + ":IN_TREE")
		remove_child(control)
		check_control(control, Rect2(Vector2.ZERO, control.size), control.get_class() + ":REMOVED")
		control.free()

	var root := Control.new()
	root.size = Vector2(100, 40)
	add_child(root)
	var panel := Panel.new()
	panel.position = Vector2(-10, 0)
	panel.size = Vector2(20, 20)
	panel.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	root.add_child(panel)
	var button := Button.new()
	button.position = Vector2(120, 5)
	button.size = Vector2(20, 20)
	for state: StringName in Bounds.STATES:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	root.add_child(button)
	check_control(root, Rect2(-10, 0, 150, 40), "NESTED_CONTROL_PANEL_BUTTON")
	panel.hide()
	check_control(root, Rect2(0, 0, 140, 40), "HIDDEN_ORNAMENT_EXCLUDED")
	panel.show()

	var expected_states: Array[StringName] = [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]
	for repeat: int in range(16):
		check_control(root, Rect2(-10, 0, 150, 40), "REPEAT_%d" % repeat)
	expect(Bounds.STATES == expected_states, "STATES_CONSTANT_NOT_ALIASED_OR_MUTATED")
	panel.add_theme_stylebox_override(&"panel", StyleBoxLine.new())
	var rejected: Variant = Bounds.control_bounds(root)
	if rejected is Dictionary:
		expect(not bool(rejected.get("ok", true)), "UNSUPPORTED_NESTED_STYLE_REJECTED")
		expect(str(rejected.get("reason", "")).contains("UNSUPPORTED_NATIVE_STYLE"), "REJECTION_REASON_PRESERVED")
	else:
		expect(false, "UNSUPPORTED_MUST_RETURN_DICTIONARY")
	remove_child(root)
	root.free()
	_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	expect(checks >= 80, "ALL_TYPE_BRANCH_CHECKS_REACHED")
	print("R311_TYPE_BRANCH_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
