extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Scope := preload("res://scripts/features/contracts/loading_preparation_scope.gd")
const TARGET := "res://scripts/caster_skill_animation_player.gd"
const SCENE_ID := "code_preparation_brand_cover_surface_test"
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = false
	check(not PlayerState.test_mode, "BrandIntro guard uses the original runtime mode")
	check(OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/") and not OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID").is_empty(), "formal runner isolates user data and binds the run")
	check(not ResourceLoader.has_cached(TARGET), "guard fixture carries the target only as a String")
	for mode: String in ["valid", "hidden_background", "outside_tree", "queued_free", "reparented", "small", "translucent", "rotated", "clipped", "generation", "phase", "forged_boolean"]:
		var startup: Control = load("res://scenes/startup_loading.tscn").instantiate() as Control
		startup.auto_start = false
		add_child(startup)
		var intro: Control = startup.brand_intro
		var api: bool = intro.has_method("code_preparation_cover_receipt")
		check(api, "actual authored intro implements physical cover receipt: " + mode)
		var owner_api: bool = startup.has_method("is_code_preparation_generation_current") and startup.has_method("is_code_preparation_loading_phase_current")
		check(owner_api, "actual Startup owns generation and Loading phase qualification: " + mode)
		if not api or not owner_api:
			startup.queue_free()
			await get_tree().process_frame
			continue
		var background: ColorRect = intro.get_node("Background") as ColorRect
		if mode == "forged_boolean":
			intro.first_frame_presented = true
			check(intro.code_preparation_cover_receipt().is_empty() and Scope.issue(intro, startup, 1) == null, "a historical/forged first-frame boolean cannot replace presentation serial")
			startup.queue_free()
			await get_tree().process_frame
			continue
		var deadline := Time.get_ticks_msec() + 2000
		while not bool(intro.first_frame_presented) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var receipt: Dictionary = intro.code_preparation_cover_receipt()
		var permit: RefCounted = Scope.issue(intro, startup, 1)
		if mode == "valid":
			print("BRAND_COVER_OBSERVATION ", JSON.stringify({"receipt_empty": receipt.is_empty(), "permit_present": permit != null,
				"first_frame": intro.first_frame_presented, "serial": intro.get("_code_cover_serial"), "presented_serial": intro.get("_code_presented_serial"),
				"surface_current": intro._code_surface_covers_viewport(), "surface_rect": str(intro._code_surface_rect()), "viewport_rect": str(intro.get_viewport_rect()),
				"background_size": str(background.size), "intro_size": str(intro.size), "startup_size": str(startup.size),
				"background_transform": str(background.get_global_transform_with_canvas()), "auto_advance": intro.auto_advance,
				"visible": intro.is_visible_in_tree(), "generation_current": startup.is_code_preparation_generation_current(1),
				"phase_current": startup.is_code_preparation_loading_phase_current(1)}))
		check(not receipt.is_empty() and permit != null, "actual full-viewport authored Background admits a presented current scope: " + mode)
		if mode == "hidden_background":
			background.hide()
		elif mode == "outside_tree":
			intro.remove_child(background)
		elif mode == "queued_free":
			background.queue_free()
		elif mode == "reparented":
			background.reparent(startup)
		elif mode == "small":
			background.set_anchors_preset(Control.PRESET_TOP_LEFT)
			background.size = Vector2(1.0, 1.0)
		elif mode == "translucent":
			background.color.a = 0.5
		elif mode == "rotated":
			background.rotation = 0.25
		elif mode == "clipped":
			startup.clip_contents = true
		elif mode == "generation":
			startup._main_code_generation += 1
		elif mode == "phase":
			startup._startup_state = "exiting"
		if permit != null:
			check(bool(permit.valid_for(startup, 1)) == (mode == "valid"), "current physical/owner/Loading change is rejected by the original permit: " + mode)
		if mode not in ["valid", "generation", "phase"]:
			check(intro.code_preparation_cover_receipt().is_empty(), "changed physical surface invalidates receipt: " + mode)
		if mode == "outside_tree":
			background.free()
		startup.queue_free()
		await get_tree().process_frame
	check(not ResourceLoader.has_cached(TARGET) and ResourceLoader.load_threaded_get_status(TARGET) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "all cover counterexamples issue no target Script request or get")
	var written: bool = proof.write_receipt(SCENE_ID, proof.records.size(), failures.size())
	print("CODE_PREPARATION_BRAND_COVER_SURFACE_", "PASS" if written and failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
