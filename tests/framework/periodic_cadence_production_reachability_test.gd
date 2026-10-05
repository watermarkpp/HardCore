extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const REGISTRY := "res://assets/data/features/validation/periodic_cadence_probe_registry.json"
const REPLACEMENT := "res://assets/data/features/validation/periodic_cadence_replacement_registry.json"
const MODULE := "hc.validation.periodic_cadence_probe"
const EVENT := "damage_committed:hc.skill.wizard.ice_storm"
var proof := Proof.new()
var failures: Array[String] = []
var game: Node
var target: EnemyActor
var release_observations: Array[Dictionary] = []
var exit_texture_jobs: Array[Dictionary] = []

func check(value: bool, label: String) -> void:
	proof.record(value,label)
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _observe_release(_skill: String, _origin: Vector2, _direction: Vector2, _damage: int) -> void:
	release_observations.append({"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),
		"simulation_usec":game._time_domains.simulation_usec(),"hp":target.current_hp,"metrics":game._feature_effect_runtime.metrics()})

func _observe_exit() -> void:
	for path: String in game._frame_texture_threaded:
		exit_texture_jobs.append({"path":path, "status":ResourceLoader.load_threaded_get_status(path)})

func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),
		"cadence reachability owns an isolated real profile")
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade() and PlayerState.create_character("周期可达边界","hc.profession.wizard").is_empty(),
		"real startup and production character creation")
	if not failures.is_empty(): _finish(); return
	PlayerState.level = 50; PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}
	check(PlayerState.recalculate_stats(false) and PlayerState.save_game(true,true,true),"one formal stat authority and writer prepare the profile")
	check(ContentLayers.reload_feature_catalog(REGISTRY),"trusted authoring registry accepts the existing compiler's one-microsecond four-tick definition")
	check(ContentLayers.feature_configuration().enabled_modules.is_empty(),"probe stays default-off until explicit READY activation")
	if not failures.is_empty(): _finish(); return
	game = Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"original Root reaches READY with its real mapped world and clock")
	if not game.gameplay_input_is_enabled(): _finish(); return
	target = await Fixture.prepare_target(self,game,game.player,19,"cadence_reachability")
	check(target != null,"single canonical receiver is produced by the mapped Root factory")
	if target == null: _finish(); return
	# Stationary geometry makes this a controlled production-API timing probe.
	# It is expressly not a natural movement or performance workload.
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	target.max_hp = 20000; target.current_hp = 20000
	target.direct_spell_anti_magic_points = 0; target.direct_spell_magic_defense_min = 0
	target.direct_spell_magic_defense_max = 0; target.direct_spell_stats_valid = true
	check(ContentLayers.set_feature_module_enabled(MODULE,true),"actual READY publisher enables the registered rule source")
	var bundle: Dictionary = PlayerState.feature_bundle()
	var bindings: Array = bundle.event_index.get(EVENT,[])
	check(bindings.size() == 1 and int(bindings[0].definition.config.period_usec) == 1
		and int(bindings[0].definition.config.duration_usec) == 4,"actual PlayerState consumer freezes the exact legal period and duration")
	if bindings.size() != 1: _finish(); return
	PlayerState.computed_stats.magic_min = 180; PlayerState.computed_stats.magic_max = 180
	game.player.skill_requested.connect(_observe_release)
	game._set_magic_locked_target(target,true)
	var outcome: StringName = game._try_release_skill("hc.skill.wizard.ice_storm",false)
	var action: Dictionary = game.player.combat_action_snapshot()
	var producer: Dictionary = game.player._accepted_release_producers.get(int(action.action_id),{})
	var configuration: RefCounted = producer.get("configuration")
	print("PERIODIC_CADENCE_ACCEPTANCE ",JSON.stringify({"outcome":str(outcome),"action":action,"producer_present":not producer.is_empty(),
		"configuration_present":configuration != null,"reservation_present":configuration != null and configuration.effect_reservation() != null}))
	check(outcome == &"accepted" and configuration != null and configuration.is_accepted() and configuration.effect_reservation() != null,
		"original Root input accepts a real nonempty reservation before delayed release")
	if outcome != &"accepted" or configuration == null: _finish(); return
	check(not ContentLayers.reload_feature_catalog(REPLACEMENT) and PlayerState.feature_bundle().revision == bundle.revision,
		"actual live-world definition replacement is rejected without changing the captured producer")
	deadline = Time.get_ticks_msec()+3000
	while release_observations.is_empty() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(release_observations.size() == 1,"actual Player timer releases once through Root's sole planner and HP port")
	if release_observations.is_empty(): _finish(); return
	var runtime: RefCounted = game._feature_effect_runtime
	var direct_loss := 20000-int(release_observations[0].hp)
	deadline = Time.get_ticks_msec()+3000
	while runtime.has_work() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	var metrics: Dictionary = runtime.metrics()
	check(direct_loss>0 and int(metrics.ticks) == 4 and int(metrics.tick_delivery_count) == 4
		and target.current_hp == 20000-direct_loss*5,"all four admitted ticks change actual receiver HP exactly once without manual clock advance or extra pump")
	var empty := true
	for count: int in runtime.reservation_snapshot().values(): empty = empty and count == 0
	check(empty and not runtime.has_work() and runtime.errors.is_empty(),"finite low-period accepted work and every reservation retire completely")
	check(int(metrics.maximum_tick_delivery_lateness_usec)>1,"legal sub-physics-step cadence cannot be reported as every tick serviced within its declared period")
	var path := "res://outputs/test_logs/framework/periodic_cadence_production_reachability_trace.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"bounded reachability evidence opens")
	if file != null:
		file.store_string(JSON.stringify({"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
			"module_id":MODULE,"mechanic_id":"hc.validation.periodic_cadence_probe.ignite","period_usec":1,"duration_usec":4,"authored_ticks":4,
			"physics_ticks_per_second":Engine.physics_ticks_per_second,"direct_loss":direct_loss,"target_hp":target.current_hp,"metrics":metrics,
			"release_observations":release_observations,"quantity_delivery":"PASS" if int(metrics.ticks)==4 else "FAIL",
			"strict_declared_period_lateness":"FAIL" if int(metrics.maximum_tick_delivery_lateness_usec)>=1 else "PASS",
			"scope":"controlled original Root input, actual Player timer, planner/HP and ordinary physics/process service; stationary target, no direct Batch/clock/pump; not natural P6/R3 or a 4-million refreshed horizon"}))
		file.flush(); check(file.get_error() == OK,"reachability evidence writes completely"); file.close()
	# Only the completed probe's local captured graph is released here. This
	# does not cancel accepted work or reset any production container.
	configuration = null; producer = {}; action = {}; bindings = []; bundle = {}; target = null
	game.tree_exiting.connect(_observe_exit)
	game.queue_free(); await get_tree().process_frame
	var completed_at_exit := 0
	for row: Dictionary in exit_texture_jobs:
		completed_at_exit += 1 if int(row.status) == ResourceLoader.THREAD_LOAD_LOADED else 0
	check(completed_at_exit == 0, "completed caster texture requests are collected before the retiring Root loses its last processing opportunity")
	var exit_file := FileAccess.open("res://outputs/test_logs/framework/periodic_cadence_exit_trace.json", FileAccess.WRITE)
	check(exit_file != null, "bounded caster exit trace opens")
	if exit_file != null:
		exit_file.store_string(JSON.stringify({"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"), "jobs":exit_texture_jobs,
			"scope":"read-only actual Root exit completion boundary; fixture does not collect loader results or add service pumps"}))
		exit_file.flush(); check(exit_file.get_error() == OK, "caster exit trace writes completely"); exit_file.close()
	check(ContentLayers.reload_feature_catalog(),"retired world restores the formal default registry")
	_finish()

func _finish() -> void:
	if is_instance_valid(game): game.queue_free()
	var written := proof.write_receipt("periodic_cadence_production_reachability_test",proof.records.size(),failures.size())
	print("PERIODIC_CADENCE_PRODUCTION_REACHABILITY_",("PASS" if written and failures.is_empty() else "FAIL")," checks=",proof.records.size()," failures=",failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
