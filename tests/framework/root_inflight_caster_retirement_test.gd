extends Node

## Controlled native ownership probe. Two test-owned Texture2D resources enter
## the real registry queue and ordinary Root process; no fixture pumps/joins
## run before the actual owner's destruction and the failed assertions.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const Visual := preload("res://scripts/monster_visual.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
var proof := Proof.new()
var failures: Array[String] = []
var game: Node
var paths: Array[String] = []
var observing := false
var observed := false
var before_exit: Array[Dictionary] = []
var after_exit: Array[Dictionary] = []
var destroyed_owner: WeakRef
var exit_usec := 0
var exit_budget: Dictionary = {}

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	process_priority = 10000
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not observing or not is_instance_valid(game): return
	if game._frame_texture_threaded.size() != paths.size(): return
	for path: String in paths:
		if not game._frame_texture_threaded.has(path): return
	observing = false
	for path: String in paths:
		before_exit.append({"path":path, "status":ResourceLoader.load_threaded_get_status(path)})
	destroyed_owner = weakref(game)
	var started := Time.get_ticks_usec()
	# Direct deletion is an actual Node lifecycle boundary, before any next
	# Root processing opportunity. It is not a normal-menu reproduction.
	game.free()
	game = null
	exit_usec = Time.get_ticks_usec() - started
	exit_budget = Budget.snapshot()
	for path: String in paths:
		after_exit.append({"path":path, "status":ResourceLoader.load_threaded_get_status(path)})
	observed = true

func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"),
		"native retirement owns isolated production user data")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade() and PlayerState.create_character("加载退休对照", "hc.profession.wizard").is_empty(),
		"production startup and distinct profile prepare the real world")
	if not failures.is_empty(): _finish(); return
	check(ContentLayers.feature_configuration().enabled_modules.is_empty(), "all extension modules remain disabled")
	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "mapped Root reaches READY through ordinary processing")
	if not game.gameplay_input_is_enabled(): _finish(); return
	# No source art, import data, real save or broad directory is modified.
	# Native binary textures belong exclusively to this runner's user:// root.
	var nonce := OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	for index in 2:
		var path := "user://caster_retirement_%s_%d.res" % [nonce, index]
		var image := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.2 + index * 0.2, 0.4, 0.6, 1.0))
		var texture := ImageTexture.create_from_image(image)
		check(ResourceSaver.save(texture, path) == OK, "test-owned binary texture %d saves completely" % index)
		texture = null
		image = null
		check(not ResourceLoader.has_cached(path), "test-owned texture %d starts outside the native cache" % index)
		paths.append(path)
	if not failures.is_empty(): _finish(); return
	CasterSkillVisualRegistry.queue_sequence_warm(paths)
	observing = true
	deadline = Time.get_ticks_msec() + 3000
	while not observed and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(observed and before_exit.size() == 2 and after_exit.size() == 2,
		"ordinary Root admits both cold native requests before this observer destroys it")
	var live_rights := 0
	var in_progress := 0
	for row: Dictionary in before_exit:
		live_rights += 1 if int(row.status) in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED] else 0
		in_progress += 1 if int(row.status) == ResourceLoader.THREAD_LOAD_IN_PROGRESS else 0
	check(live_rights == 2, "both admitted requests still have their original native retrieval right at destruction")
	check(in_progress > 0, "at least one actual native request is still IN_PROGRESS before owner destruction")
	var abandoned := 0
	for row: Dictionary in after_exit:
		abandoned += 1 if int(row.status) in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED] else 0
	check(abandoned == 0, "actual Root destruction consumes every previously admitted native retrieval right")
	check(destroyed_owner != null and destroyed_owner.get_ref() == null and Visual.streaming_coordinator() == null
		and int(exit_budget.open_scopes) == 0,
		"the destroyed Root and its static world access do not survive retirement; budget scopes are closed")
	# RED cleanup occurs after observation and assertions, never in place of
	# production cleanup. It prevents abandoned workers from outliving the test.
	for path: String in paths:
		var status := ResourceLoader.load_threaded_get_status(path)
		var texture: Texture2D
		if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED]:
			texture = ResourceLoader.load_threaded_get(path) as Texture2D
			CasterSkillVisualRegistry.retain_loaded_texture(path, texture)
		else:
			texture = CasterSkillVisualRegistry.request_animation_frame_texture(path)
		check(texture != null and texture.get_size() == Vector2(1024, 1024), "each admitted native texture remains usable from its collecting owner")
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "only this invocation's exact texture fixture is removed")
	var trace_path := "res://outputs/test_logs/framework/root_inflight_caster_retirement_trace.json"
	var trace := FileAccess.open(trace_path, FileAccess.WRITE)
	check(trace != null, "bounded native ownership trace opens")
	if trace != null:
		trace.store_string(JSON.stringify({"run_id":nonce,
			"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
			"before_exit":before_exit, "after_exit":after_exit, "exit_usec":exit_usec, "exit_budget":exit_budget,
			"in_progress_before_exit":in_progress, "abandoned_after_exit":abandoned,
			"scope":"controlled direct Node destruction; real cold native Texture2D requests admitted by ordinary Root; test-owned user data only; not natural combat, normal menu, APK or device evidence"}))
		trace.flush()
		check(trace.get_error() == OK, "native ownership trace writes completely")
		trace.close()
	_finish()

func _finish() -> void:
	observing = false
	if is_instance_valid(game): game.queue_free()
	var written := proof.write_receipt("root_inflight_caster_retirement_test", proof.records.size(), failures.size())
	print("ROOT_INFLIGHT_CASTER_RETIREMENT_", "PASS" if written and failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
