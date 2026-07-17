extends Node

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const MANIFEST_PATH := "res://assets/ui/gothic_theme/v1/sample/component_manifest.json"


func _ready() -> void:
	var theme := GothicUIThemeScript.build()
	for variation in ["GothicModalFrame", "GothicTitleBar", "GothicInsetFrame", "GothicTabFrame"]:
		assert(theme.has_stylebox("panel", variation), "%s 缺少公共Panel样式" % variation)
	for variation in ["GothicComponentButton", "GothicComponentSelectedButton", "GothicComponentTabButton", "GothicComponentSlotButton", "GothicComponentShopCard", "GothicComponentCloseButton"]:
		assert(theme.has_stylebox("normal", variation), "%s 缺少normal样式" % variation)
		assert(theme.has_stylebox("pressed", variation), "%s 缺少pressed样式" % variation)
		assert(theme.has_stylebox("disabled", variation), "%s 缺少disabled样式" % variation)
	assert(FileAccess.file_exists(MANIFEST_PATH))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert(manifest is Dictionary and manifest.get("status", "") == "awaiting_user_review")
	assert(manifest.get("components", []).size() == 10, "公共Theme样板必须包含10类组件")
	for entry: Variant in manifest.get("components", []):
		var image_path := "res://assets/ui/gothic_theme/v1/sample/%s" % entry.get("file", "")
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(not image.is_empty() and image.get_format() in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF, Image.FORMAT_RGBAH])
		assert(image.get_pixel(0, 0).a < 0.04, "%s 的透明角未清理干净" % entry.get("id", ""))
	print("GOTHIC_THEME_COMPONENT_TEST_PASS：10类公共组件、透明角与Theme状态样式均通过")
	get_tree().quit(0)
