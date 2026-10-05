extends Node

## Characterizes the real Root boundary before any added feature or cast.
## Only primitive job metadata and WeakRefs leave the live world.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const Visual := preload("res://scripts/monster_visual.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
@export var prepare_receiver := false
@export var release_skill := false
@export var wait_for_caster_warmup := false
var proof := Proof.new()
var failures: Array[String] = []
var game: Node
var jobs: Dictionary = {}
var overflowed := false
var startup_frames := 0
var teardown_rows: Array[Dictionary] = []
var skill_releases: Array[Dictionary] = []
var caster_jobs_before_wait: Array[Dictionary] = []
var closing_owner: WeakRef
var caster_exit_boundary: Dictionary = {}

func _scene_id() -> String:
	if release_skill:
		return "root_plain_skill_drained_retirement_test" if wait_for_caster_warmup else "root_plain_skill_retirement_test"
	return "root_receiver_retirement_test" if prepare_receiver else "root_startup_retirement_test"

func _observe_release(skill_id: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void:
	skill_releases.append({"skill_id":skill_id, "process_frame":Engine.get_process_frames(),
		"simulation_usec":game._time_domains.simulation_usec()})

func _observe_root_exit() -> void:
	var owner: Node = closing_owner.get_ref()
	var rows: Array[Dictionary] = []
	for path: String in owner._frame_texture_threaded:
		rows.append({"path":path, "status":ResourceLoader.load_threaded_get_status(path)})
	caster_exit_boundary = {"process_frame":Engine.get_process_frames(),
		"queued_for_deletion":owner.is_queued_for_deletion(), "jobs":rows,
		"unadmitted_registry_paths":CasterSkillVisualRegistry.pending_warm_path_count()}

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _observe_jobs() -> void:
	if not is_instance_valid(game) or game._streaming_coordinator == null:
		return
	var coordinator: RefCounted = game._streaming_coordinator
	for key: String in coordinator._threaded_profile_requests:
		var job: Dictionary = coordinator._threaded_profile_requests[key]
		var identity := key + ":" + str(job.get("request_sequence", 0))
		if not jobs.has(identity):
			if jobs.size() >= 128:
				overflowed = true
				continue
			jobs[identity] = {"resource_key":key, "request_sequence":int(job.get("request_sequence", 0)),
				"lane":str(job.get("lane", "")), "use_sub_threads":coordinator._job_use_sub_threads(job),
				"paths":job.get("paths", {}).duplicate(), "first_state":str(job.get("state", "")),
				"first_process_frame":Engine.get_process_frames()}
		jobs[identity]["last_state"] = str(job.get("state", ""))
		jobs[identity]["last_process_frame"] = Engine.get_process_frames()

func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"),
		"startup retirement owns an isolated production profile")
	PlayerState.begin_startup_save_upgrade()
	var profile_name: String = {"root_startup_retirement_test":"启动退休对照",
		"root_receiver_retirement_test":"怪物退休对照", "root_plain_skill_retirement_test":"施法退休对照",
		"root_plain_skill_drained_retirement_test":"施法完成对照"}[_scene_id()]
	check(PlayerState.finish_startup_save_upgrade() and PlayerState.create_character(profile_name, "hc.profession.wizard").is_empty(),
		"real startup and character writer prepare the baseline")
	if not failures.is_empty():
		_finish(); return
	PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}
	check(PlayerState.recalculate_stats(false) and PlayerState.save_game(true, true, true), "formal stats and save prepare the same learned-skill workset")
	check(ContentLayers.feature_configuration().enabled_modules.is_empty(), "no extension module is enabled")
	if not failures.is_empty():
		_finish(); return
	game = Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		_observe_jobs()
		startup_frames += 1
		await get_tree().process_frame
	_observe_jobs()
	check(game.gameplay_input_is_enabled(), "original mapped Root reaches READY without fixture pumps")
	if not game.gameplay_input_is_enabled():
		_finish(); return
	if prepare_receiver:
		var receiver: EnemyActor = await Fixture.prepare_target(self, game, game.player, 19, "retirement_control")
		check(receiver != null, "same canonical receiver factory and fixture run with all extensions disabled")
		if release_skill and receiver != null:
			for actor: Node in get_tree().get_nodes_in_group("enemies"):
				actor.set_physics_process(false)
			receiver.max_hp = 20000; receiver.current_hp = 20000
			receiver.direct_spell_anti_magic_points = 0
			receiver.direct_spell_magic_defense_min = 0; receiver.direct_spell_magic_defense_max = 0
			receiver.direct_spell_stats_valid = true
			PlayerState.computed_stats.magic_min = 180; PlayerState.computed_stats.magic_max = 180
			game.player.skill_requested.connect(_observe_release)
			game._set_magic_locked_target(receiver, true)
			check(game._try_release_skill("hc.skill.wizard.ice_storm", false) == &"accepted",
				"original input accepts the same skill without any extension module")
			deadline = Time.get_ticks_msec() + 3000
			while skill_releases.is_empty() and Time.get_ticks_msec() < deadline:
				await get_tree().process_frame
			check(skill_releases.size() == 1 and receiver.current_hp < 20000,
				"actual Player timer and sole HP port complete the plain-skill control")
		receiver = null
	for path: String in game._frame_texture_threaded:
		caster_jobs_before_wait.append({"path":path, "status":ResourceLoader.load_threaded_get_status(path)})
	if wait_for_caster_warmup:
		deadline = Time.get_ticks_msec() + 3000
		while (not game._frame_texture_threaded.is_empty() or CasterSkillVisualRegistry.pending_warm_path_count() > 0) \
			and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(game._frame_texture_threaded.is_empty() and CasterSkillVisualRegistry.pending_warm_path_count() == 0,
			"ordinary Root processing collects all accepted caster warmup requests before the control teardown")
	var caster_jobs_at_exit: Array[Dictionary] = []
	for path: String in game._frame_texture_threaded:
		caster_jobs_at_exit.append({"path":path, "status":ResourceLoader.load_threaded_get_status(path)})
	var coordinator: RefCounted = game._streaming_coordinator
	check(coordinator != null and not jobs.is_empty() and not overflowed, "bounded observation captures real loading jobs without truncation")
	check(game._feature_effect_runtime == null, "no feature runtime or added periodic work is created")
	var loader_before: Dictionary = coordinator.monster_streaming_diagnostics()
	var loader_calls := {"request":coordinator.threaded_texture_request_count(), "get":coordinator.threaded_texture_get_count()}
	check((int(loader_calls.request) >= 40 if prepare_receiver else int(loader_calls.request) == 40)
		and int(loader_calls.request) == int(loader_calls.get),
		"all real map-preload and optional receiver texture requests are collected before teardown")
	var watched: Dictionary = {"root":weakref(game), "world":weakref(game._world_context),
		"clock":weakref(game._time_domains), "streaming":weakref(coordinator)}
	coordinator = null
	closing_owner = weakref(game)
	game.tree_exiting.connect(_observe_root_exit)
	game.queue_free()
	game = null
	for frame in 4:
		await get_tree().process_frame
		var row := {"process_frame":Engine.get_process_frames()}
		for key: String in watched:
			row[key] = watched[key].get_ref() != null
		teardown_rows.append(row)
	var admitted_before_exit: Array[String] = []
	for row: Dictionary in caster_jobs_at_exit:
		admitted_before_exit.append(str(row.path))
	var newly_admitted_at_exit: Array[String] = []
	for row: Dictionary in caster_exit_boundary.get("jobs", []):
		if str(row.path) not in admitted_before_exit:
			newly_admitted_at_exit.append(str(row.path))
	check(newly_admitted_at_exit.is_empty(), "queued world starts no new caster texture request before actual tree exit")
	var retired := true
	for key: String in watched:
		retired = retired and watched[key].get_ref() == null
	check(retired, "Root world clock and coordinator owners retire without extra clear or reset")
	check(Visual.streaming_coordinator() == null, "world exit releases the static visual coordinator access path")
	var file := FileAccess.open("res://outputs/test_logs/framework/" + _scene_id().trim_suffix("_test") + "_trace.json", FileAccess.WRITE)
	check(file != null, "bounded startup retirement trace opens")
	if file != null:
		file.store_string(JSON.stringify({"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
			"startup_frames":startup_frames, "jobs":jobs.values(), "observation_overflowed":overflowed,
			"loader_before_teardown":loader_before, "loader_calls":loader_calls, "teardown":teardown_rows,
			"prepare_receiver":prepare_receiver,
			"release_skill":release_skill, "skill_releases":skill_releases,
			"wait_for_caster_warmup":wait_for_caster_warmup,
			"caster_jobs_before_wait":caster_jobs_before_wait, "caster_jobs_at_exit":caster_jobs_at_exit,
			"caster_exit_boundary":caster_exit_boundary,
			"scope":"real Root startup and teardown without an extension module; optional same canonical receiver and real plain-skill input/timer/HP path; observed job metadata may omit jobs completed between samples; native exit warning diagnosis is separate"}))
		file.flush()
		check(file.get_error() == OK, "startup retirement trace writes completely")
		file.close()
	_finish()

func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	var written := proof.write_receipt(_scene_id(), proof.records.size(), failures.size())
	print("ROOT_STARTUP_RETIREMENT_", "PASS" if written and failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
