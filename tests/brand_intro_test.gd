extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(ProjectSettings.get_setting("application/config/name") == "HardCore")
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/startup_loading.tscn")
	assert(ProjectSettings.get_setting("application/config/icon") == "res://assets/branding/game_icon.png")
	assert(ProjectSettings.get_setting("application/boot_splash/image", "") == "res://assets/branding/hardcore_demonic_startup_1598x720_v1.png")
	assert(ProjectSettings.get_setting("application/boot_splash/bg_color", Color.WHITE) == Color.BLACK, "Godot boot splash surround must remain black")
	assert(bool(ProjectSettings.get_setting("application/boot_splash/show_image", false)))
	assert(int(ProjectSettings.get_setting("application/boot_splash/minimum_display_time", -1)) == 0)
	var project_source := FileAccess.get_file_as_string("res://project.godot")
	assert(project_source.contains("boot_splash/fullsize=false"), "startup plate must preserve authored 1598x720 pixels")
	assert(project_source.contains("boot_splash/use_filter=false"), "startup plate must avoid filtered startup scaling")
	assert(FileAccess.file_exists("res://scenes/startup_loading.tscn"))
	var startup_source := FileAccess.get_file_as_string("res://scripts/startup_loading.gd")
	assert(startup_source.contains("brand_intro"), "startup runtime must host the authored game-entry animation")
	assert(startup_source.contains("load_threaded_request"), "startup must request character select asynchronously")
	assert(startup_source.contains("intro_animation_finished"), "startup must await the authored game-entry animation")
	assert(startup_source.contains("await get_tree().process_frame"), "startup animation must present one real frame before waiting")
	assert(startup_source.contains("intro_first_frame_presented"), "authoritative data must wait for a rendered authored CG frame")
	assert(startup_source.contains("ContentLayers.ensure_loaded()"), "startup must explicitly open the content-layer gate")
	assert(startup_source.contains("WorldContent.ensure_loaded()"), "startup must explicitly open the world-content gate")
	assert(startup_source.contains("GameData.ensure_loaded()"), "startup must explicitly open the GameData gate")
	assert(startup_source.find("_run_finite_loading_phase.call_deferred()") < startup_source.find("load_threaded_request"), "finite loading phase must start before request result is known")
	assert(startup_source.contains("if not _load_requested or _resource_ready"), "failed request must not transition")
	var intro_source := FileAccess.get_file_as_string("res://scripts/brand_intro.gd")
	assert(not intro_source.contains("brand_logo, \"modulate:a\""), "BrandIntro must not fade the approved logo in from transparency")
	assert(not intro_source.contains("create_timer(0.12)"), "BrandIntro must not add an empty black lead-in before its first frame")
	assert(not intro_source.contains("create_timer(0.92)"), "BrandIntro must not hold on a dim logo before the authored text motion")
	assert(not intro_source.contains("brand_logo, \"scale\""), "BrandIntro must begin at the approved full logo size instead of replaying a dark scale-up lead-in")
	var startup: Node = load("res://scenes/startup_loading.tscn").instantiate()
	startup.auto_start = false
	add_child(startup)
	await get_tree().process_frame
	assert(startup.brand_intro != null and not startup.brand_intro.auto_advance, "startup must own intro scene transitions")
	startup.queue_free()
	await get_tree().process_frame
	# Exercise the prepared handoff twice.  The next scene must settle invisibly
	# while the intro remains alive, then become visible without clearing the
	# viewport between scenes.  Repeating this covers cached/restarted launches.
	for launch_index in range(2):
		var handoff: Control = load("res://scenes/startup_loading.tscn").instantiate()
		handoff.auto_start = false
		handoff.suppress_scene_handoff_for_test = true
		add_child(handoff)
		await get_tree().process_frame
		var packed_target := PackedScene.new()
		var target_control := Control.new()
		target_control.name = "PreparedCharacterSelect%d" % launch_index
		assert(packed_target.pack(target_control) == OK)
		target_control.free()
		handoff._target_scene = packed_target
		handoff._resource_ready = true
		handoff._animation_finished = false
		handoff._check_transition()
		assert(not handoff._target_prepare_started, "target preparation escaped before authoritative data readiness on launch %d" % launch_index)
		handoff._authoritative_data_ready = true
		handoff._check_transition()
		await get_tree().process_frame
		assert(not handoff._target_prepare_started, "target preparation froze the authored CG before completion on launch %d" % launch_index)
		handoff._animation_finished = true
		handoff._check_transition()
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		assert(is_instance_valid(handoff._target_scene_instance), "prepared handoff did not instantiate on launch %d" % launch_index)
		assert(handoff._target_scene_ready, "target did not settle behind the CG on launch %d" % launch_index)
		assert((handoff._target_scene_instance as CanvasItem).visible, "prepared handoff did not reveal a settled target on launch %d" % launch_index)
		assert(handoff.is_inside_tree(), "startup intro was removed before target readiness on launch %d" % launch_index)
		handoff._target_scene_instance.queue_free()
		handoff.queue_free()
		await get_tree().process_frame
	assert(FileAccess.file_exists("res://assets/branding/brand_manifest.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/branding/brand_manifest.json"))
	assert(manifest.get("displayName", "") == "HardCore")
	var outputs: Array = manifest.get("outputs", [])
	var android_icon_registered := false
	var adaptive_foreground_registered := false
	var adaptive_background_registered := false
	var intro_first_frame_registered := false
	var demonic_startup_registered := false
	for output: Dictionary in outputs:
		var output_size: Array = output.get("size", [])
		if output.get("path") == "assets/branding/android_icon_192.png" and output_size.size() == 2 and int(output_size[0]) == 192 and int(output_size[1]) == 192:
			android_icon_registered = true
		if output.get("path") == "assets/branding/android_adaptive_foreground_432.png" and output_size.size() == 2 and int(output_size[0]) == 432 and int(output_size[1]) == 432:
			adaptive_foreground_registered = true
		if output.get("path") == "assets/branding/android_adaptive_background_432.png" and output_size.size() == 2 and int(output_size[0]) == 432 and int(output_size[1]) == 432:
			adaptive_background_registered = true
		if output.get("path") == "assets/branding/brand_intro_first_frame_1598x720.png" and output_size.size() == 2 and int(output_size[0]) == 1598 and int(output_size[1]) == 720:
			intro_first_frame_registered = true
		if output.get("path") == "assets/branding/hardcore_demonic_startup_1598x720_v1.png" and output_size.size() == 2 and int(output_size[0]) == 1598 and int(output_size[1]) == 720:
			demonic_startup_registered = true
	assert(android_icon_registered)
	assert(adaptive_foreground_registered)
	assert(adaptive_background_registered)
	assert(intro_first_frame_registered, "deterministic opaque BrandIntro first-frame surface is not registered")
	assert(demonic_startup_registered, "HardCore demonic startup plate is not registered")
	var legacy_icon := Image.load_from_file("res://assets/branding/android_icon_192.png")
	var adaptive_foreground := Image.load_from_file("res://assets/branding/android_adaptive_foreground_432.png")
	var adaptive_background := Image.load_from_file("res://assets/branding/android_adaptive_background_432.png")
	assert(legacy_icon.get_size() == Vector2i(192, 192))
	assert(adaptive_foreground.get_size() == Vector2i(432, 432))
	assert(adaptive_background.get_size() == Vector2i(432, 432))
	assert(adaptive_foreground.get_pixel(0, 0).a == 0.0, "adaptive foreground must leave a transparent Android mask-safe margin")
	assert(adaptive_foreground.get_pixel(84, 84).a > 0.99, "complete approved logo must begin inside the 264px adaptive safe zone")
	assert(adaptive_background.get_pixel(0, 0).is_equal_approx(Color.BLACK), "adaptive launcher background must be black")
	var intro_first_frame := Image.load_from_file("res://assets/branding/brand_intro_first_frame_1598x720.png")
	assert(intro_first_frame.get_size() == Vector2i(1598, 720))
	assert(intro_first_frame.get_pixel(0, 0).is_equal_approx(Color.BLACK), "first-frame surface must retain the native black surround")
	assert(intro_first_frame.get_pixel(799, 317).get_luminance() > 0.02, "first-frame surface center must contain the approved opaque CG artwork")
	assert(FileAccess.get_sha256("res://assets/branding/brand_intro_first_frame_1598x720.png") == "0eea4e0440a4f565c4f2e8241acf04a0e3b8380eae48a5b5557a6054baaa0b52")
	var demonic_startup := Image.load_from_file("res://assets/branding/hardcore_demonic_startup_1598x720_v1.png")
	assert(demonic_startup.get_size() == Vector2i(1598, 720))
	assert(demonic_startup.get_pixel(0, 0).get_luminance() < 0.01, "startup plate must retain a near-black screen-safe surround")
	assert(demonic_startup.get_pixel(799, 360).get_luminance() > 0.02, "startup plate center must contain the HardCore title artwork")
	assert(FileAccess.get_sha256("res://assets/branding/hardcore_demonic_startup_1598x720_v1.png") == "f21e6abb6e57242b162e871d333f8c63adc43f16ffea45923b449f8476da04f4")
	var export_preset := FileAccess.get_file_as_string("res://export_presets.cfg")
	assert(export_preset.contains("launcher_icons/main_192x192=\"res://assets/branding/android_icon_192.png\""))
	assert(export_preset.contains("launcher_icons/adaptive_foreground_432x432=\"res://assets/branding/android_adaptive_foreground_432.png\""))
	assert(export_preset.contains("launcher_icons/adaptive_background_432x432=\"res://assets/branding/android_adaptive_background_432.png\""))
	assert(export_preset.contains("gradle_build/use_gradle_build=true"), "Android export must use Gradle for splash theme overrides")
	assert(export_preset.contains("gradle_build/custom_theme_attributes={"), "Android export must define theme attributes as a Dictionary")
	assert(export_preset.contains("\"[splash]windowSplashScreenAnimatedIcon\": \"@android:color/transparent\""), "Android 12 splash icon must be transparent instead of falling back to the launcher icon")
	assert(export_preset.contains("\"[splash]android:windowSplashScreenBrandingImage\": \"@null\""), "Android splash branding image must be disabled")
	assert(export_preset.contains("\"[splash]android:windowSplashScreenBackground\": \"#000000\""), "Android splash background must match BrandIntro's first black frame")
	assert(export_preset.contains("\"[splash]windowSplashScreenBackground\": \"#000000\""), "AndroidX splash background must match BrandIntro's first black frame")
	assert(export_preset.contains("package/name=\"HardCore\""))
	assert(export_preset.contains("package/unique_name=\"com.personal.mafaoffline\""))
	var intro: Control = load("res://scenes/brand_intro.tscn").instantiate()
	intro.auto_advance = false
	add_child(intro)
	assert(is_equal_approx((intro.get_node("BrandLogo") as TextureRect).modulate.a, 1.0), "first authored logo frame must be fully opaque before the first draw")
	assert((intro.get_node("GlowLogo") as TextureRect).modulate.a >= 0.28, "first authored frame must begin at the approved bright glow instead of looking translucent")
	assert((intro.get_node("BrandLogo") as TextureRect).scale.is_equal_approx(Vector2.ONE), "first authored frame must use the final approved logo scale")
	await get_tree().process_frame
	await get_tree().process_frame
	assert(is_equal_approx((intro.get_node("BrandLogo") as TextureRect).modulate.a, 1.0), "logo became translucent after the first rendered frame")
	assert(intro.get_node("Slogan").text == "刷是一种状态，刷没有目的没有终点")
	var texture: Texture2D = intro.get_node("BrandLogo").texture
	assert(texture != null)
	assert(texture.get_width() == 1024 and texture.get_height() == 1024)
	assert(intro.NEXT_SCENE == "res://scenes/character_select.tscn")
	assert(intro.FINAL_PRESENTATION_SECONDS == 0.0, "startup must not add an arbitrary final-frame delay")
	# Fresh Android-mode autoload instances must remain cold until StartupLoading
	# invokes their explicit ensure_loaded() boundary.
	for lazy_script_path: String in [
		"res://scripts/layers/runtime/content_layer_registry.gd",
		"res://scripts/layers/runtime/world_content_service.gd",
		"res://scripts/game_data.gd",
	]:
		var lazy_node: Node = load(lazy_script_path).new()
		lazy_node.initial_load_deferred = true
		add_child(lazy_node)
		await get_tree().process_frame
		assert(not lazy_node.is_loaded(), "%s performed eager Android startup work" % lazy_script_path)
		assert(lazy_node.ensure_loaded(), "%s explicit startup load failed" % lazy_script_path)
		assert(lazy_node.is_loaded(), "%s did not publish a ready state atomically" % lazy_script_path)
		lazy_node.queue_free()
		await get_tree().process_frame
	print("BRAND_INTRO_PASS: icon, boot splash, animation and exact slogan are connected")
	get_tree().quit(0)
