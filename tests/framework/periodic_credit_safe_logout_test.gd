extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const EXPECTED_PATH := "res://outputs/test_logs/framework/periodic_credit_safe_logout_expected.json"
const QUEST_ID := "bich_beginner_gear"
const MONSTER_ID := 21
const Ledger := preload("res://scripts/world_monster_clock_ledger.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var deaths := 0
var trace: Array[Dictionary] = []

class TransitionProbe extends Root:
	var transition_count := 0
	func _perform_character_select_transition() -> void:
		# Observe only the final visual scene port. The real logout, pending
		# actor scan, reward writer, drop/loot drain and save all execute first.
		transition_count += 1

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	# The runner isolates APPDATA before the autoload initializes. Retain its
	# actual production paths so no cached warehouse owner is redirected later.
	check(not PlayerState.test_mode,"real production persistence without test_mode bypass")
	var account_directory := PlayerState.profile_directory.get_base_dir()
	print("PERIODIC_CREDIT_PATH_TRACE "+JSON.stringify({"profile_directory":PlayerState.profile_directory,
		"account_directory":account_directory,"backup_trimmed_root":account_directory.trim_suffix("/")}))
	PlayerState.begin_startup_save_upgrade()
	var startup_ready: bool = PlayerState.finish_startup_save_upgrade()
	check(startup_ready,"official startup upgrade gate completes in isolated production user data "+str(PlayerState.startup_save_upgrade_result))
	if not startup_ready: _finish(); return
	check(PlayerState.create_character("周期边界A","hc.profession.wizard").is_empty(),"A created through official profile service")
	var profile_a: String = PlayerState.active_profile_id
	PlayerState.level = 50; PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}; PlayerState.recalculate_stats(false)
	PlayerState.accept_quest(QUEST_ID)
	check(PlayerState.quest_states.get(QUEST_ID,{}).get("status") == "active","A accepts registered prerequisite-free kill quest through its sole owner")
	check(PlayerState.save_game(true,true,true),"real durable A baseline")
	var xp_a: int = PlayerState.experience
	var generation_a: String = PlayerState._world_clock_generation
	check(PlayerState.create_character("周期边界B","hc.profession.warrior").is_empty(),"B created through official profile service")
	var profile_b: String = PlayerState.active_profile_id
	PlayerState.accept_quest(QUEST_ID)
	check(PlayerState.save_game(true,true,true),"real durable B baseline")
	var xp_b: int = PlayerState.experience
	# JSON persistence restores numeric values as floats. Compare the complete
	# durable representation, rather than Variant type identity (int vs float).
	var quests_b: Dictionary = JSON.parse_string(JSON.stringify(PlayerState.quest_states))
	var generation_b: String = PlayerState._world_clock_generation
	var b_hash := FileAccess.get_sha256(PlayerState._profile_path(profile_b))
	check(profile_a != profile_b and Ledger.valid_generation(generation_a) and Ledger.valid_generation(generation_b),"A/B have distinct profile identities and contract-valid clock generations, including legacy empty namespaces")
	var selected_a: bool = PlayerState.select_character(profile_a)
	check(selected_a,"A officially selected before world creation "+str(PlayerState.last_load_result))
	if not selected_a:
		print("PERIODIC_CREDIT_SETUP_TRACE "+JSON.stringify({"load_result":PlayerState.last_load_result,"save_result":PlayerState.last_save_result,
			"startup_pending":PlayerState._startup_save_upgrade_pending,"warehouse_initialized":PlayerState._shared_warehouse_initialized,
			"profile_directory":PlayerState.profile_directory,"shared_warehouse_path":PlayerState.shared_warehouse_path}))
		_finish(); return
	var game := TransitionProbe.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"actual authored world ready")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	var target := await Fixture.prepare_target(self,game,game.player,MONSTER_ID,"credit_safe_logout")
	check(target != null,"registered quest receiver uses real mapped spawn and death signal")
	if target == null: game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	check(not game._enemy_death_flush_queued and game._pending_enemy_deaths.is_empty(),"initial queue uses its real idle flags without forced suppression")
	target.max_hp = 105; target.current_hp = 105
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	target.died.connect(func(_enemy: EnemyActor,_data: Dictionary) -> void: deaths += 1)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"default-off module explicitly enabled only for this test")
	var batch: RefCounted = game._begin_feature_damage_batch("wizard.ice_storm","credit:safe_logout:lethal")
	check(batch != null,"qualified batch is owned by actual Root")
	if batch == null: game.queue_free(); _finish(); return
	target.take_damage(100,game.player,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	game._finish_feature_damage_batch(batch)
	var runtime: RefCounted = game._feature_effect_runtime
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.pending_count() == 0 and runtime.active_count() == 1 and target.current_hp == 5,"actual committed fact admits exactly one pending lethal periodic state")
	check(batch.facts()[0].historical_credit.profile_id == profile_a,"accepted state retains exact A credit")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false),"withdrawal leaves the accepted state alive and restores default-off qualification")
	game._time_domains.advance_simulation(1.0)
	runtime.pump()
	check(target.current_hp == 0 and target._death_pending and not target._dying and deaths == 0 and game._pending_enemy_deaths.is_empty(),"narrow boundary is real lethal HP before deferred actor callback")
	trace.append({"operation":"lethal_before_callback","profile_id":PlayerState.active_profile_id,
		"world_generation":game._zone_generation,"world_clock_generation":PlayerState._world_clock_generation,
		"death_origin":target.get_meta("death_origin",{}),"historical_credit":batch.facts()[0].historical_credit,
		"pending_actor":target._death_pending,"root_deaths":game._pending_enemy_deaths.size()})
	# This is the real system-menu handler, before yielding to any deferred
	# callback. No direct select B or private queue-flag override occurs here.
	game._return_to_character_select()
	check(game.transition_count == 1,"real return handler reaches visual transition only after guard success")
	check(deaths == 1 and not target._death_pending and target._dying,"logout guard synchronously closes the deferred actor death exactly once")
	check(game._pending_enemy_deaths.is_empty() and game._prepared_enemy_death_settlement.is_empty(),"actual death settlement and prepared writer drain before transition")
	var expected_xp: int = game._build_enemy_death_runtime_snapshot(GameData.get_monster_by_id(MONSTER_ID)).experience
	check(PlayerState.active_profile_id == profile_a and PlayerState.experience == xp_a+expected_xp,"A is still active when its sole reward owner applies exactly one kill")
	check(int(PlayerState.quest_states.get(QUEST_ID,{}).get("progress",{}).get("稻草人",-1)) == 1,"A quest objective increments exactly once in the real reward plan")
	check(bool(PlayerState.last_save_result.get("success",false)),"logout has an actual durable save success")
	check(FileAccess.get_sha256(PlayerState._profile_path(profile_b)) == b_hash,"A death and logout leave B profile bytes unchanged")
	check(runtime.active_count() == 0 and runtime.heap_count() == 0 and runtime.pending_count() == 0 and runtime.errors.is_empty(),"accepted effect terminates without leftover mutation handles or hidden failure")
	var terminal_jobs: Array = game._enemy_death_terminal_jobs.duplicate(true)
	check(terminal_jobs.size() == 1 and terminal_jobs[0].state == "COMMITTED","real death/drop pipeline has exactly one committed terminal job")
	var rng_after: int = game._rng.state
	await get_tree().process_frame
	check(deaths == 1 and PlayerState.experience == xp_a+expected_xp and game._rng.state == rng_after,"original queued callback neither repeats rewards nor consumes old drop RNG")
	trace.append({"operation":"guard_finished","profile_id":PlayerState.active_profile_id,
		"save_result":PlayerState.last_save_result.duplicate(true),"terminal_jobs":terminal_jobs,
		"xp_a":PlayerState.experience,"quest_a":PlayerState.quest_states.duplicate(true),
		"a_profile_sha256":FileAccess.get_sha256(PlayerState._profile_path(profile_a)),"b_profile_sha256":b_hash})
	# Recreate the character-select lifecycle: retire the old world, then use
	# the same official selection service used by CharacterSelect.
	game.queue_free(); await get_tree().process_frame
	check(PlayerState.select_character(profile_b),"B officially selected after guarded old-world retirement")
	trace.append({"operation":"B_after_official_reload","xp_actual":PlayerState.experience,"xp_expected":xp_b,
		"quests_actual":PlayerState.quest_states.duplicate(true),"quests_expected":quests_b,
		"generation_actual":PlayerState._world_clock_generation,"generation_expected":generation_b,
		"load_result":PlayerState.last_load_result.duplicate(true)})
	check(PlayerState.experience == xp_b,"B XP is not contaminated by A")
	check(PlayerState.quest_states == quests_b,"B quests are not contaminated by A")
	check(PlayerState._world_clock_generation == generation_b,"B world identity is not contaminated by A")
	check(PlayerState.select_character(profile_a),"A reloads through the real saved profile/world ledger")
	check(PlayerState.experience == xp_a+expected_xp and PlayerState._world_clock_generation == generation_a,"A owner and persisted kill gain survive role reload")
	check(int(PlayerState.quest_states.get(QUEST_ID,{}).get("progress",{}).get("稻草人",-1)) == 1,"A persisted quest gain remains exactly one")
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,"real profile/world receipts are fully consumed")
	var expected := {"profile_directory":PlayerState.profile_directory,"profile_index_path":PlayerState.profile_index_path,
		"shared_warehouse_path":PlayerState.shared_warehouse_path,"transaction_path":PlayerState.shared_warehouse_transaction_log_path,
		"profile_a":profile_a,"profile_b":profile_b,"xp_a":xp_a+expected_xp,"xp_b":xp_b,
		"quests_b":quests_b,"generation_a":generation_a,"generation_b":generation_b,
		"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256")}
	if failures.is_empty():
		var output := FileAccess.open(EXPECTED_PATH,FileAccess.WRITE)
		check(output != null,"write cold-process expectation from this successful producer only")
		if output != null: output.store_string(JSON.stringify(expected)); output.close()
	print("PERIODIC_CREDIT_SAFE_LOGOUT_TRACE "+JSON.stringify(trace))
	_finish()

func _finish() -> void:
	if not proof.write_receipt("periodic_credit_safe_logout_test",checks,failures.size()): failures.append("receipt")
	print("PERIODIC_CREDIT_SAFE_LOGOUT_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
