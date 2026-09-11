class_name UIItemSelectionVisual
extends RefCounted

## Only item/equipment/card surfaces use this. Action buttons and sliders
## retain their normal hover/focus/pressed affordances and feedback.
static func apply(button: Button, selected: bool, normal_type: StringName, selected_type: StringName) -> void:
	if not is_instance_valid(button):
		return
	for key: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
		button.remove_theme_stylebox_override(key)
	button.theme_type_variation = selected_type if selected else normal_type
	var semantic_style := button.get_theme_stylebox(&"normal")
	for key: StringName in [&"hover", &"pressed", &"hover_pressed"]:
		button.add_theme_stylebox_override(key, semantic_style)
	button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	button.set_meta("ui_selection_authoritative_pressed", selected)
	if button.toggle_mode:
		button.set_pressed_no_signal(selected)
	# Detached controls still need semantic/toggle cleanup, but have no viewport focus.
	if not selected and button.is_inside_tree() and button.has_focus():
		button.release_focus()
	button.queue_redraw()
