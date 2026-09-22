class_name UIItemSelectionVisual
extends RefCounted

## Only item/equipment/card surfaces use this. Action buttons and sliders
## retain their normal hover/focus/pressed affordances and feedback.
static func apply(button: Button, selected: bool, normal_type: StringName, selected_type: StringName) -> void:
	if not is_instance_valid(button):
		return
	# Refreshes visit every slot. Replacing identical overrides broadcasts theme
	# changes through every icon/label descendant, even when nothing changed.
	# Compare the live theme resources so a real theme/calibration change still
	# invalidates the presentation; no stale per-button theme snapshot is needed.
	var desired_type := selected_type if selected else normal_type
	var semantic_style := button.get_theme_stylebox(&"normal")
	var changed := button.theme_type_variation != desired_type or button.has_theme_stylebox_override(&"normal")
	for key: StringName in [&"hover", &"pressed", &"hover_pressed"]:
		if not button.has_theme_stylebox_override(key) or button.get_theme_stylebox(key) != semantic_style:
			changed = true
	if not button.has_theme_stylebox_override(&"focus") or not button.get_theme_stylebox(&"focus") is StyleBoxEmpty:
		changed = true
	if changed:
		button.begin_bulk_theme_override()
		if button.has_theme_stylebox_override(&"normal"):
			button.remove_theme_stylebox_override(&"normal")
		button.theme_type_variation = desired_type
		semantic_style = button.get_theme_stylebox(&"normal")
		for key: StringName in [&"hover", &"pressed", &"hover_pressed"]:
			button.add_theme_stylebox_override(key, semantic_style)
		if not button.has_theme_stylebox_override(&"focus") or not button.get_theme_stylebox(&"focus") is StyleBoxEmpty:
			button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
		button.end_bulk_theme_override()
	if not button.has_meta("ui_selection_authoritative_pressed") or bool(button.get_meta("ui_selection_authoritative_pressed", false)) != selected:
		button.set_meta("ui_selection_authoritative_pressed", selected)
	if button.toggle_mode and button.button_pressed != selected:
		button.set_pressed_no_signal(selected)
	# Detached controls still need semantic/toggle cleanup, but have no viewport focus.
	if not selected and button.is_inside_tree() and button.has_focus():
		button.release_focus()
