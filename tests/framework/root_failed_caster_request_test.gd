extends Node

## A corrupt binary texture belongs only to this invocation's user:// root.
## Expected native errors remain in the raw wrapper FAIL; a separate exact
## error classifier may assess this negative without hiding any engine error.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
var proof := Proof.new()
var failures: Array[String] = []
var game: Node
var path := ""
var attempts: Array[Dictionary] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _observe_attempt() -> void:
	var admitted := false
	var states: Array[int] = []
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if game._frame_texture_threaded.has(path): admitted = true
		var status := ResourceLoader.load_threaded_get_status(path)
		if states.is_empty() or states[-1] != status: states.append(status)
		if admitted and not game._frame_texture_threaded.has(path): break
	attempts.append({"admitted":admitted, "statuses":states,
		"tracked_after":game._frame_texture_threaded.has(path),
		"native_status_after":ResourceLoader.load_threaded_get_status(path)})

func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"),
		"failed native request owns isolated production user data")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade() and PlayerState.create_character("失败加载对照", "hc.profession.wizard").is_empty(),
		"real startup and distinct profile create the mapped Root")
	if not failures.is_empty(): _finish(); return
	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "Root reaches READY through ordinary production processing")
	if not game.gameplay_input_is_enabled(): _finish(); return
	var nonce := OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	path = "user://caster_failure_%s.res" % nonce
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "exact test-owned malformed native resource opens")
	if file == null: _finish(); return
	file.store_buffer("OWNED_CASTER_FAILURE".to_utf8_buffer())
	file.flush()
	check(file.get_error() == OK, "malformed fixture writes completely without touching source art or imports")
	file.close()
	CasterSkillVisualRegistry.queue_sequence_warm([path])
	await _observe_attempt()
	check(attempts[0].admitted and not attempts[0].tracked_after,
		"ordinary Root accepts and terminates tracking for the actual failed native request")
	check(int(attempts[0].native_status_after) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"failed native request releases its retrieval token before leaving Root tracking")
	# Same exact path, valid bytes, same ordinary queue. No fixture get/clear
	# occurs between failed ownership and the new lawful attempt.
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	check(ResourceSaver.save(texture, path) == OK, "same test-owned path now contains a valid native Texture2D")
	texture = null
	image = null
	CasterSkillVisualRegistry.queue_sequence_warm([path])
	await _observe_attempt()
	check(attempts[1].admitted and not attempts[1].tracked_after,
		"fresh lawful attempt uses the unchanged ordinary Root loader")
	check(CasterSkillVisualRegistry.frame_texture_is_resident(path)
		and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"fresh valid texture becomes usable without reusing a failed native task")
	# Failed-source cleanup is after both business assertions. Consume exactly
	# the two possible tokens produced by these two actual Root requests.
	var cleanup_gets := 0
	for index in 2:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE: break
		ResourceLoader.load_threaded_get(path)
		cleanup_gets += 1
	check(ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"negative cleanup leaves no native retrieval right at process exit")
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
		"only this invocation's exact malformed/repaired fixture is removed")
	game.queue_free()
	game = null
	for index in 4: await get_tree().process_frame
	var trace := FileAccess.open("res://outputs/test_logs/framework/root_failed_caster_request_trace.json", FileAccess.WRITE)
	check(trace != null, "bounded failed-request trace opens")
	if trace != null:
		trace.store_string(JSON.stringify({"run_id":nonce,
			"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
			"fixture_path":path, "attempts":attempts, "negative_cleanup_gets":cleanup_gets,
			"scope":"actual Root ordinary warm channel with a test-owned corrupt binary resource and same-path lawful retry; expected native errors preserved; not a naturally corrupt game asset or normal UI reproduction"}))
		trace.flush()
		check(trace.get_error() == OK, "bounded failed-request trace writes completely")
		trace.close()
	_finish()

func _finish() -> void:
	if is_instance_valid(game): game.queue_free()
	var written := proof.write_receipt("root_failed_caster_request_test", proof.records.size(), failures.size())
	print("ROOT_FAILED_CASTER_REQUEST_", "PASS" if written and failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
