extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var deaths := 0
var trace: Array[Dictionary] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var root := "user://periodic_credit_profile_switch_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("character_profiles.json")
	PlayerState.shared_warehouse_path = root.path_join("shared_warehouse.json")
	PlayerState.shared_warehouse_transaction_log_path = root.path_join("shared_warehouse.transaction.json")
	check(not PlayerState.test_mode, "actual production persistence, test_mode=false")
	# The autoload already initialized its default account before this scene.
	# Initialize the new isolated account with the same production writer.
	check(PlayerState._initialize_shared_warehouse(), "initialize actual isolated shared warehouse")
	check(PlayerState.create_character("归属边界A", "法师").is_empty(), "create A through real profile service")
	var profile_a: String = PlayerState.active_profile_id
	PlayerState.level = 50
	PlayerState.recalculate_stats(false)
	check(PlayerState.save_game(true, true, true), "A production profile/world checkpoint")
	var xp_a: int = PlayerState.experience
	check(PlayerState.create_character("归属边界B", "战士").is_empty(), "create B through real profile service")
	var profile_b: String = PlayerState.active_profile_id
	var xp_b: int = PlayerState.experience
	check(profile_a != profile_b and not profile_a.is_empty() and not profile_b.is_empty(), "two real distinct profile identities")
	check(PlayerState.select_character(profile_a), "official select A before world boot")
	if PlayerState.active_profile_id != profile_a: _finish(); return
	var game := Root.new()
	add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(game.gameplay_input_is_enabled(), "formal world ready")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	var target := await Fixture.prepare_target(self, game, game.player, 19, "periodic_credit_switch")
	check(target != null, "real mapped target and sole death signal connection")
	if target == null: game.queue_free(); _finish(); return
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"):
		actor.set_physics_process(false)
	game._enemy_death_flush_queued = true
	target.max_hp = 105
	target.current_hp = 105
	target.direct_spell_magic_defense_min = 0
	target.direct_spell_magic_defense_max = 0
	target.died.connect(func(_enemy: EnemyActor, _data: Dictionary) -> void: deaths += 1)
	check(ContentLayers.set_feature_module_enabled("hc.ignite", true), "formal source enabled")
	var batch: RefCounted = game._begin_feature_damage_batch("wizard.ice_storm", "credit:switch:lethal")
	check(batch != null, "qualified actual production damage batch")
	if batch == null: game.queue_free(); _finish(); return
	target.take_damage(100, game.player, {"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	game._finish_feature_damage_batch(batch)
	var runtime: RefCounted = game._feature_effect_runtime
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.pending_count() == 0 and runtime.active_count() == 1 and target.current_hp == 5, "A accepted effect has exactly one pending lethal tick")
	check(batch.facts()[0].historical_credit.profile_id == profile_a, "accepted historical credit is A")
	game._time_domains.advance_simulation(1.0)
	runtime.pump()
	check(target.current_hp == 0 and target._death_pending and deaths == 0 and game._pending_enemy_deaths.is_empty(), "real lethal HP commit precedes deferred death callback")
	var selected: bool = PlayerState.select_character(profile_b)
	trace.append({"operation":"official_select_after_lethal_before_callback", "selected":selected,
		"profile_before":profile_a,"requested_profile":profile_b,"active_profile":PlayerState.active_profile_id,
		"world_generation":game._zone_generation,"historical_credit":batch.facts()[0].historical_credit,
		"load_result":PlayerState.last_load_result.duplicate(true),"save_result":PlayerState.last_save_result.duplicate(true)})
	check(not selected or PlayerState.active_profile_id == profile_b, "official switch result agrees with active identity")
	check(not selected and PlayerState.active_profile_id == profile_a and PlayerState.last_load_result.get("reason") == "profile_gameplay_owner_active", "running world prevents profile replacement before its exit barrier")
	await get_tree().process_frame
	check(deaths == 1, "accepted lethal tick emits one actual death")
	game._flush_enemy_deaths(false)
	var expected_xp: int = game._build_enemy_death_runtime_snapshot(GameData.get_monster_by_id(19)).experience
	check(game._pending_enemy_deaths.is_empty(), "existing death queue completes at its real barrier")
	check(PlayerState.save_game(true, true, true), "active role production checkpoint after settlement")
	var document_b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PlayerState._profile_path(profile_b)))
	check(int(document_b.get("experience", -1)) == xp_b, "B receives no A kill experience " + str(document_b.get("experience")))
	check(PlayerState.experience == xp_a + expected_xp, "A retains exactly one accepted kill experience " + str(PlayerState.experience))
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0, "real profile/world receipts drained")
	trace.append({"operation":"final", "profile_a":profile_a,"profile_b":profile_b,
		"xp_a_before":xp_a,"xp_b_before":xp_b,"expected_gain":expected_xp,
		"xp_a_after":PlayerState.experience,"xp_b_after":document_b.get("experience"),
		"terminal_jobs":game._enemy_death_terminal_jobs.duplicate(true),"runtime_errors":runtime.errors.duplicate()})
	check(runtime.errors.is_empty(), "effect lifecycle has no hidden failure")
	check(ContentLayers.set_feature_module_enabled("hc.ignite", false), "source restored")
	game.queue_free()
	await get_tree().process_frame
	check(PlayerState.select_character(profile_a), "official reload A for owner receipt after world retirement")
	check(PlayerState.experience == xp_a + expected_xp, "A accepted kill remains durable after official reload")
	check(PlayerState.select_character(profile_b) and PlayerState.experience == xp_b, "official B selection succeeds after old world retirement with no foreign gain")
	print("PERIODIC_CREDIT_SWITCH_TRACE " + JSON.stringify(trace))
	_finish()

func _finish() -> void:
	if not proof.write_receipt("periodic_credit_profile_switch_test", checks, failures.size()): failures.append("receipt")
	print("PERIODIC_CREDIT_PROFILE_SWITCH_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
