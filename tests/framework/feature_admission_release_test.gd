extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	check(PlayerState.set_profession_identity("hc.profession.wizard"),"registered wizard identity")
	PlayerState.level = 50; PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}; PlayerState.recalculate_stats(false)
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"actual formal world is ready")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	var selected := await Fixture.prepare_target(self,game,game.player,19,"feature_admission_release")
	check(selected != null,"real selected receiver exists")
	if selected == null: game.queue_free(); _finish(); return
	var moving: EnemyActor = _spawn(game,64,Vector2(47,13.5),"fixture:admission:moving")
	var replaced: EnemyActor = _spawn(game,89,Vector2(40.5,14.2),"fixture:admission:respawn")
	var summoner: EnemyActor = _spawn(game,126,Vector2(44,13.5),"fixture:admission:summoner")
	check(moving != null and replaced != null and summoner != null,"declared base slots use exact production monster factories")
	if moving == null or replaced == null or summoner == null: game.queue_free(); _finish(); return
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	for actor: EnemyActor in [selected,moving,replaced,summoner]: _durable_target(actor)
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	PlayerState.computed_stats.magic_min = 100; PlayerState.computed_stats.magic_max = 100
	game.player.current_mp = 100; game._skill_cast_target = selected; game._set_magic_locked_target(selected,true)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"actual default-off module enabled only for this test")
	var bound: Dictionary = game.feature_world_capacity_bound()
	var lease: RefCounted = game._capture_action_configuration("hc.skill.wizard.ice_storm")
	check(game.player.request_skill("hc.skill.wizard.ice_storm",selected.get_instance_id(),lease),"real Player request accepts after acquiring capacity")
	var runtime: RefCounted = game._feature_effect_runtime
	check(runtime != null and int(runtime.reservation_snapshot().actions) == 1,"windup owns a real outstanding promise")
	check(game.observed_releases == 0 and selected.current_hp == 10000,"acceptance has not prematurely committed damage")
	# These changes occur after acceptance. Use the existing position transaction,
	# delayed respawn path, and summon queue; never edit the planner's target list.
	moving.set_combat_position(game._canonical_ground_gu_to_screen_px(Vector2(41.2,13.5)),&"test_move_during_windup")
	var prior_instance := replaced.get_instance_id()
	replaced.queue_free()
	game._respawn_later(GameData.get_monster_by_id(89),game._canonical_ground_gu_to_screen_px(Vector2(40.5,14.2)),false,0.01,
		game._zone_generation,{"respawn_enabled":false,"spawn_slot_id":"fixture:admission:respawn"})
	summoner.control_time = 0; summoner.target = game.player
	summoner.set_meta("m30_summon_release_serial",1)
	game._on_boss_summon_requested(summoner,[127],1,5)
	var child: EnemyActor
	var replacement: EnemyActor
	while game.observed_releases == 0 and (child == null or replacement == null):
		for actor: EnemyActor in game._active_enemy_cache.values():
			if not is_instance_valid(actor) or actor.is_queued_for_deletion(): continue
			if actor.get_instance_id() != prior_instance and str(actor.get_meta("spawn_slot_id","")) == "fixture:admission:respawn":
				replacement = actor; _durable_target(replacement)
			if str(actor.get_meta("summoner_spawn_slot","")) == "fixture:admission:summoner":
				child = actor; _durable_target(child)
				child.set_combat_position(game._canonical_ground_gu_to_screen_px(Vector2(40.8,13.2)),&"test_summon_enters_release")
		await get_tree().process_frame
	check(child != null and replacement != null and game.observed_releases == 0,"formal summon and replacement life materialize during the accepted windup")
	check(game.feature_world_capacity_bound() == bound,"birth, movement and replacement fit the previously declared count without freezing identities")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false),"source withdrawn after acceptance through its formal module service")
	deadline = Time.get_ticks_msec()+3000
	while game.observed_releases == 0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases == 1 and bool(game.observed_execution.get("accepted",false)),"same accepted configuration reaches the real single planner exactly once")
	var receivers: Array[EnemyActor] = [selected,moving]
	if replacement != null: receivers.append(replacement)
	if child != null: receivers.append(child)
	for actor: EnemyActor in receivers: check(actor.current_hp < 10000,"release-time receiver receives actual base HP commit: "+str(actor.monster_id))
	for index in 120:
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.active_count() == 4 and runtime.pending_count() == 0 and runtime.errors.is_empty(),"all four promised derived effects survive motion, rebirth, new birth and source withdrawal")
	check(int(runtime.reservation_snapshot().actions) == 0 and int(runtime.reservation_snapshot().receipts) == 0,"consumer completion retires the spent producer while its four effects remain alive")
	var hp := selected.current_hp
	var replay: Dictionary = game._execute_canonical_skill("冰咆哮",game.player.global_position,Vector2.RIGHT,0,{},true,false,lease)
	check(not bool(replay.get("accepted",false)) and selected.current_hp == hp,"retained accepted configuration cannot replay HP after receipt retirement")
	# Let the actual player timers recover before another actual request.
	game.player.set_physics_process(true)
	await get_tree().create_timer(1.7).timeout
	game.player.set_physics_process(false)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"module restored for the independent cancellation case")
	var mp_before: int = game.player.current_mp
	var rng_before: int = game._rng.state
	var unaccepted: Dictionary = game._execute_canonical_skill("冰咆哮",game.player.global_position,Vector2.RIGHT,0)
	check(not bool(unaccepted.get("accepted",false)) and unaccepted.get("reason") == "missing_accepted_feature_configuration",
		"direct feature execution cannot bypass the action acceptance owner")
	check(game.player.current_mp == mp_before and selected.current_hp == hp and game._rng.state == rng_before,
		"unaccepted direct call is rejected before resources, HP and planner RNG")
	var cancelled: RefCounted = game._capture_action_configuration("hc.skill.wizard.ice_storm")
	game._skill_cast_target = selected; game._set_magic_locked_target(selected,true)
	check(game.player.request_skill("hc.skill.wizard.ice_storm",selected.get_instance_id(),cancelled),"next request accepts after real cooldown recovery")
	var releases_before: int = game.observed_releases
	check(game.player.begin_combat_transition("feature_capacity_cancel"),"existing lifecycle owner cancels delayed release")
	await get_tree().create_timer(0.7).timeout
	check(game.observed_releases == releases_before and selected.current_hp == hp,"lifecycle cancellation prevents delayed HP submission")
	check(int(runtime.reservation_snapshot().actions) == 0,"cancelled delayed callback returns its outstanding reservation")
	check(game.player.finish_combat_transition("feature_capacity_cancel"),"existing lifecycle transition closes normally")
	print("FEATURE_ADMISSION_RELEASE_TRACE "+JSON.stringify({"bound":bound,"metrics":runtime.metrics(),"reservation":runtime.reservation_snapshot()}))
	game.queue_free(); await get_tree().process_frame
	_finish()

func _spawn(game: Node, id: int, ground: Vector2, slot: String) -> EnemyActor:
	return game._spawn_enemy(GameData.get_monster_by_id(id),game._canonical_ground_gu_to_screen_px(ground),false,-1.0,
		{"respawn_enabled":false,"spawn_slot_id":slot})

func _durable_target(actor: EnemyActor) -> void:
	actor.set_physics_process(false); actor.max_hp = 10000; actor.current_hp = 10000
	actor.direct_spell_anti_magic_points = 0; actor.direct_spell_magic_defense_min = 0; actor.direct_spell_magic_defense_max = 0
	actor.direct_spell_stats_valid = true

func _finish() -> void:
	if not proof.write_receipt("feature_admission_release_test",checks,failures.size()): failures.append("receipt")
	print("FEATURE_ADMISSION_RELEASE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
