extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(ProjectSettings.get_setting("application/config/name") == "HardCore")
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/brand_intro.tscn")
	assert(ProjectSettings.get_setting("application/config/icon") == "res://assets/branding/game_icon.png")
	assert(ProjectSettings.get_setting("application/boot_splash/image") == "res://assets/branding/boot_splash.png")
	assert(FileAccess.file_exists("res://assets/branding/brand_manifest.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/branding/brand_manifest.json"))
	assert(manifest.get("displayName", "") == "HardCore")
	var outputs: Array = manifest.get("outputs", [])
	var android_icon_registered := false
	for output: Dictionary in outputs:
		var output_size: Array = output.get("size", [])
		if output.get("path") == "assets/branding/android_icon_192.png" and output_size.size() == 2 and int(output_size[0]) == 192 and int(output_size[1]) == 192:
			android_icon_registered = true
	assert(android_icon_registered)
	var export_preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert(export_preset.contains("launcher_icons/main_192x192=\"res://assets/branding/android_icon_192.png\""))
	assert(export_preset.contains("package/name=\"HardCore\""))
	assert(export_preset.contains("package/unique_name=\"com.personal.mafaoffline\""))
	var intro: Control = load("res://scenes/brand_intro.tscn").instantiate()
	intro.auto_advance = false
	add_child(intro)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(intro.get_node("Slogan").text == "刷是一种状态，刷没有目的没有终点")
	var texture: Texture2D = intro.get_node("BrandLogo").texture
	assert(texture != null)
	assert(texture.get_width() == 1024 and texture.get_height() == 1024)
	assert(intro.NEXT_SCENE == "res://scenes/character_select.tscn")
	print("BRAND_INTRO_PASS: icon, boot splash, animation and exact slogan are connected")
	get_tree().quit(0)
