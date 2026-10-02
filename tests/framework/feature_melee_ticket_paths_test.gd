extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var proof := Proof.new()
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.set_profession_identity("hc.profession.warrior")
	PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.warrior.fire_sword":3,"hc.skill.warrior.half_moon":3,"hc.skill.warrior.thrusting":3}
	PlayerState.recalculate_stats(false)
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"formal melee world ready")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	var target := await Fixture.prepare_target(self,game,game.player,19,"feature_melee_ticket_paths")
	check(target != null,"actual mapped receiver exists")
	if target == null: game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	target.max_hp = 100000; target.current_hp = 100000; target.agility = 0
	game.player.attack_min = 100; game.player.attack_max = 100
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"real default-off ignite module enabled")
	var plan_lease: RefCounted = game._capture_melee_configuration()
	var actor: Dictionary = game._action_configuration_identity()
	check(plan_lease.accept(PlayerState.action_configuration_versions(),actor) and plan_lease.effect_reservation() != null,"internal planning fixture owns a real accepted melee reservation")
	var release_id := "player:%d:action:%d" % [game.player.get_instance_id(),game.player._combat_action_sequence+1]
	check(plan_lease.begin_release(actor,release_id),"outer owner claims the pending release once")
	check(not plan_lease.begin_plan(actor,"wrong:release",true) and not plan_lease._producer_closed,"wrong delegated identity cannot consume an open producer's plan")
	check(plan_lease.begin_plan(actor,release_id,true),"same open producer enters its delegated planner once")
	check(not plan_lease._producer_closed and not plan_lease.begin_plan(actor,release_id,true),"second internal plan is rejected while producer is still explicitly open")
	check(not plan_lease.begin_release(actor,release_id),"outer release remains one-shot before producer close")
	plan_lease.finish_producer()
	check(int(game._feature_effect_runtime.reservation_snapshot().actions) == 0,"unused open-plan fixture returns its real capacity at explicit producer end")
	await _swing(game,target,"armed_fire",true,false)
	await _swing(game,target,"half_moon",false,false)
	await _swing(game,target,"thrust",false,true)
	game.queue_free(); await get_tree().process_frame
	_finish()
func _swing(game: Node,target: EnemyActor,label: String,armed: bool,thrust: bool) -> void:
	# The before-image uses the existing charge owner, as the old compatibility
	# tests do. The next swing itself uses the real Player input and Root planner.
	game._set_canonical_fire_charge_expires_at(Time.get_ticks_msec()+10000 if armed else 0)
	game.player.fire_sword_enabled = false
	game.player.half_moon_enabled = not thrust
	game.player.thrusting_enabled = thrust
	game.player._skill_cooldown_remaining.clear(); game.player._attack_timer = 0.0; game.player._attack_action_timer = 0.0
	game.player.current_mp = 100; game.observed_releases = 0
	var lease: RefCounted = game._capture_melee_configuration()
	var hp: int = target.current_hp
	check(game.player.request_attack_toward(Vector2.RIGHT,true,target.get_instance_id(),lease),label+": actual input accepts")
	check(lease.effect_reservation() != null,label+": potential fire outcome owns a real nonempty reservation")
	var runtime: RefCounted = game._feature_effect_runtime
	var before: int = runtime.metrics().admitted_facts
	var deadline := Time.get_ticks_msec()+3000
	while game.observed_releases == 0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases == 1 and bool(game.observed_execution.get("accepted",false)),label+": same accepted lease reaches canonical planner exactly once")
	var expected_skill := "warrior.fire_sword" if armed else ("warrior.thrusting" if thrust else "warrior.half_moon")
	check(game.observed_execution.get("canonical_plan",{}).get("skill_id") == expected_skill,label+": hit-frame body choice remains authoritative")
	check(target.current_hp < hp,label+": actual base HP commit occurs")
	check(game.player.current_mp == (97 if not armed and not thrust else 100),label+": original resource contract is charged exactly once")
	if armed: check(game._canonical_fire_charge_expires_ms == 0,label+": old armed charge is consumed by this valid next swing")
	for index in 120:
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(int(runtime.metrics().admitted_facts)-before == (1 if armed else 0),label+": only the actual fire outcome creates the promised derived work")
	check(runtime.pending_count() == 0 and int(runtime.reservation_snapshot().actions) == 0 and runtime.errors.is_empty(),label+": spent or unused capacity returns after the real producer finishes")
	hp = target.current_hp
	var mp: int = game.player.current_mp
	var rng: int = game._rng.state
	var old: Dictionary = game._execute_canonical_skill(expected_skill,game.player.global_position,Vector2.RIGHT,100,
		{"release_id":"player:%d:action:%d" % [game.player.get_instance_id(),game.player._combat_action_sequence]},false,false,lease)
	check(not bool(old.get("accepted",false)) and target.current_hp == hp and game.player.current_mp == mp and game._rng.state == rng,
		label+": internal-plan route cannot reopen a completed release")
func _finish() -> void:
	if not proof.write_receipt("feature_melee_ticket_paths_test",proof.records.size(),failures.size()): failures.append("receipt")
	print("FEATURE_MELEE_TICKET_PATHS_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",proof.records.size(),str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
