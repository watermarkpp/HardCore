extends Node

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")


func _ready() -> void:
	var theme := GothicUIThemeScript.build()
	for variation: StringName in [
		&"GothicInventoryActionGemButton",
		&"GothicShopBuyActionGemButton",
		&"GothicShopSellActionGemButton",
		&"GothicQuestActionGemButton",
		&"GothicQuestAbandonPlainButton",
		&"GothicDeathRevivalGemButton",
		&"GothicConfirmationGemButton",
	]:
		_assert_variation_alignment(theme, variation)
	var selected_tab := theme.get_stylebox("normal", &"GothicShopTradeTabSelectedGemButton") as AdaptiveButtonStyleBox
	assert(selected_tab.fill_color.is_equal_approx(GothicUIThemeScript.BUTTON_SELECTED_FILL), "active shop tab is not persistently dark red")
	print("BUTTON_FEEDBACK_ALIGNMENT_PASS: normal/pressed/success/failure content rects are invariant and result styles are reused")
	get_tree().quit(0)


func _assert_variation_alignment(theme: Theme, variation: StringName) -> void:
	var button := Button.new()
	add_child(button)
	button.theme = theme
	button.theme_type_variation = variation
	var reference := button.get_theme_stylebox("normal") as AdaptiveButtonStyleBox
	var disabled := button.get_theme_stylebox("disabled") as AdaptiveButtonStyleBox
	var pressed := button.get_theme_stylebox("pressed") as AdaptiveButtonStyleBox
	assert(reference.fill_color.is_equal_approx(GothicUIThemeScript.BUTTON_ACTION_IDLE_FILL), "%s idle background is not pale coffee" % variation)
	assert(disabled.fill_color.is_equal_approx(GothicUIThemeScript.BUTTON_ACTION_DISABLED_FILL), "%s unavailable background is not grey" % variation)
	assert(pressed.fill_color.is_equal_approx(GothicUIThemeScript.BUTTON_PRESS_FILL), "%s pressed background is not dark red" % variation)
	assert(button.get_theme_font_size("font_size") == GothicUIThemeScript.BUTTON_ACTION_FONT_SIZE, "%s action font size is inconsistent" % variation)
	for state: StringName in [&"hover", &"focus", &"pressed", &"disabled"]:
		_assert_same_content_rect(reference, button.get_theme_stylebox(state), "%s.%s" % [variation, state])
	GothicUIThemeScript.set_button_feedback(button, GothicUIThemeScript.BUTTON_FEEDBACK_BUSY, "alignment.test")
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_disabled_color"]:
		assert(button.get_theme_color(color_name).is_equal_approx(Color("ffe2ad")), "%s busy text did not change with the dark-red background" % variation)
	GothicUIThemeScript.set_button_feedback(button, GothicUIThemeScript.BUTTON_FEEDBACK_SUCCESS, "alignment.test")
	var first_success := button.get_theme_stylebox("normal")
	_assert_same_content_rect(reference, first_success, "%s.success" % variation)
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_disabled_color"]:
		assert(button.get_theme_color(color_name).is_equal_approx(GothicUIThemeScript.PARCHMENT), "%s result text did not return with the coffee background" % variation)
	button.disabled = true
	assert(button.get_theme_stylebox("disabled") == first_success, "%s feedback did not remain visible while disabled" % variation)
	button.disabled = false
	GothicUIThemeScript.clear_button_feedback(button)
	GothicUIThemeScript.set_button_feedback(button, GothicUIThemeScript.BUTTON_FEEDBACK_SUCCESS, "alignment.test")
	assert(button.get_theme_stylebox("normal") == first_success, "%s did not reuse its prewarmed success style" % variation)
	GothicUIThemeScript.clear_button_feedback(button)
	GothicUIThemeScript.set_button_feedback(button, GothicUIThemeScript.BUTTON_FEEDBACK_FAILURE, "alignment.test")
	_assert_same_content_rect(reference, button.get_theme_stylebox("normal"), "%s.failure" % variation)
	GothicUIThemeScript.clear_button_feedback(button)
	button.disabled = true
	assert(button.get_theme_stylebox("disabled") == disabled, "%s did not restore its grey unavailable state" % variation)
	button.free()


func _assert_same_content_rect(expected: StyleBox, actual: StyleBox, context: String) -> void:
	assert(actual != null, "%s style missing" % context)
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert(
			is_equal_approx(expected.get_content_margin(side), actual.get_content_margin(side)),
			"%s content margin changed on side %d" % [context, side],
		)
