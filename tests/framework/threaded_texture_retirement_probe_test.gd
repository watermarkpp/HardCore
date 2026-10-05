extends Node

## Isolates the engine texture-loader lifetime from Root, UI and feature work.
## Both variants collect every real result. Exit warnings are checked externally.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
@export var use_sub_threads := false
@export var nested_atlas := false
@export var root_map_textures := false
var proof := Proof.new()
var failures: Array[String] = []
var rows: Array[Dictionary] = []

func check(value: bool, label: String) -> void:
	proof.record(value,label)
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	check(OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"engine loader probe owns isolated data")
	var paths: Array[String] = []
	var expected_count := 8
	if root_map_textures:
		expected_count = 40
		var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/framework/fixtures/root_startup_texture_paths.json"))
		if fixture is Dictionary:
			for path: Variant in fixture.get("paths", []):
				paths.append(str(path))
		check(paths.size() == 40, "declared real Root cohort has exactly forty paths")
	elif nested_atlas:
		for name: String in ["lucky_guardian_inventory","lucky_guardian_ground","dragon_heart_inventory","dragon_heart_ground",
			"dragon_eye_inventory","dragon_eye_ground","courage_badge_inventory","courage_badge_ground"]:
			paths.append("res://assets/art/items/custom/relics/"+name+".tres")
	else:
		for index in 8:
			paths.append("res://assets/art/characters/caster_skill_frames/ice_storm/direction_00/frame_%02d.png" % index)
	for index in paths.size():
		var path := paths[index]
		check(ResourceLoader.exists(path,"Texture2D") and not ResourceLoader.has_cached(path),"exact declared texture is cold: "+str(index))
		check(ResourceLoader.load_threaded_request(path,"Texture2D",use_sub_threads) == OK,"native request accepts exact texture: "+str(index))
	var pending := paths.duplicate()
	var deadline := Time.get_ticks_msec()+5000
	while not pending.is_empty() and Time.get_ticks_msec()<deadline:
		for path: String in pending.duplicate():
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				var texture := ResourceLoader.load_threaded_get(path) as Texture2D
				check(texture != null and texture.get_width()>0 and texture.get_height()>0,"real native completion has usable texture: "+path.get_file())
				rows.append({"path":path,"width":texture.get_width() if texture != null else 0,"height":texture.get_height() if texture != null else 0,
					"status_after_get":ResourceLoader.load_threaded_get_status(path),"process_frame":Engine.get_process_frames()})
				pending.erase(path)
			elif status in [ResourceLoader.THREAD_LOAD_FAILED,ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
				check(false,"native request fails: "+path.get_file()); pending.erase(path)
		if not pending.is_empty(): await get_tree().process_frame
	check(pending.is_empty() and rows.size()==expected_count,"every declared real native request completes within the same deadline")
	var retired := true
	for row: Dictionary in rows: retired = retired and int(row.status_after_get) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
	check(retired,"every collected path retires its user-facing request")
	for frame in 4: await get_tree().process_frame
	var scene_id := "threaded_texture_retirement_subthreads_test" if use_sub_threads else "threaded_texture_retirement_probe_test"
	if nested_atlas: scene_id = "threaded_atlas_retirement_subthreads_test" if use_sub_threads else "threaded_atlas_retirement_test"
	if root_map_textures: scene_id = "threaded_root_texture_retirement_subthreads_test" if use_sub_threads else "threaded_root_texture_retirement_test"
	var file := FileAccess.open("res://outputs/test_logs/framework/"+scene_id.trim_suffix("_test")+"_trace.json",FileAccess.WRITE)
	check(file != null,"owned native loader evidence opens")
	if file != null:
		file.store_string(JSON.stringify({"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
			"use_sub_threads":use_sub_threads,"nested_atlas":nested_atlas,"root_map_textures":root_map_textures,"expected_texture_count":expected_count,"rows":rows,
			"scope":"engine-only declared cold Texture2D requests; all status/get completions consumed; no Root, feature effect, UI or gameplay load"}))
		file.flush(); check(file.get_error() == OK,"owned native loader evidence completes"); file.close()
	var written := proof.write_receipt(scene_id,proof.records.size(),failures.size())
	print("THREADED_TEXTURE_RETIREMENT_",("PASS" if written and failures.is_empty() else "FAIL")," checks=",proof.records.size()," failures=",failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
