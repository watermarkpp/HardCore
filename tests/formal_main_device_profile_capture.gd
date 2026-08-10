extends Node

const PROFILE_PHYSICAL := Vector2(2664, 1200)
const PROFILE_SAFE_LEFT_PX := 121.0
const PROFILE_SAFE_RIGHT_PX := 129.0

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var ratio_text := OS.get_environment("HARDCORE_DEVICE_PROFILE_EXP_RATIO")
	var exp_ratio := clampf(float(ratio_text) if not ratio_text.is_empty() else 0.0, 0.0, 1.0)
	var exp_required := maxi(1, PlayerState.experience_to_next_level())
	var actual_experience := clampi(int(floor(float(exp_required) * exp_ratio)), 0, exp_required - 1)
	PlayerState.experience = actual_experience
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport := get_viewport()
	var logical := viewport.get_visible_rect().size
	assert(logical.x > 0.0 and logical.y > 0.0, "formal main scene has no viewport")
	var safe_left := PROFILE_SAFE_LEFT_PX / PROFILE_PHYSICAL.x * logical.x
	var safe_right := PROFILE_SAFE_RIGHT_PX / PROFILE_PHYSICAL.x * logical.x
	var hud: Node = game.get_node_or_null("HUD")
	if hud == null and game.get("hud") is Node:
		hud = game.get("hud") as Node
	assert(hud != null, "formal main scene did not create GameHUD")
	var safe_root := hud.get_node_or_null("MobileSafeRoot") as Control
	assert(safe_root != null, "formal main scene HUD is missing MobileSafeRoot")
	# Desktop has no Android cutout API. Inject the measured device safe rect into
	# the real HUD tree, preserving the production main scene and all resources.
	safe_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	safe_root.position = Vector2(safe_left, 0.0)
	safe_root.size = logical - Vector2(safe_left + safe_right, 0.0)
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path("res://outputs/android_device")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var image := viewport.get_texture().get_image()
	var capture_name := OS.get_environment("HARDCORE_DEVICE_PROFILE_CAPTURE_NAME")
	if capture_name.is_empty():
		capture_name = "local_main_device_profile"
	var output_path := output_dir.path_join("%s.png" % capture_name)
	assert(image.save_png(output_path) == OK, "unable to save formal main scene capture")
	var geometry := {
		"profile": "HardCore.android.device_ui.v1",
		"source": "res://scenes/main.tscn",
		"head": OS.get_environment("DEVICE_PROFILE_HEAD"),
		"experience_ratio": exp_ratio,
		"experience_required": exp_required,
		"experience": actual_experience,
		"physical_size": [int(PROFILE_PHYSICAL.x), int(PROFILE_PHYSICAL.y)],
		"logical_viewport": [logical.x, logical.y],
		"safe_pixels": {"left": PROFILE_SAFE_LEFT_PX, "right": PROFILE_SAFE_RIGHT_PX, "top": 0.0, "bottom": 0.0},
		"safe_logical": {"left": safe_left, "right": safe_right},
		"safe_root_rect": [safe_root.position.x, safe_root.position.y, safe_root.size.x, safe_root.size.y],
		"capture": output_path,
	}
	var geometry_path := output_dir.path_join("%s.json" % capture_name)
	FileAccess.open(geometry_path, FileAccess.WRITE).store_string(JSON.stringify(geometry, "  "))
	print("FORMAL_MAIN_DEVICE_PROFILE_PASS capture=%s geometry=%s logical=%s" % [output_path, geometry_path, logical])
	get_tree().quit(0)
