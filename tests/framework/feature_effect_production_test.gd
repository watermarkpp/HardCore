extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
@export var melee := false
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.profession = "战士" if melee else "法师"
	PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.warrior.fire_sword":3} if melee else {"hc.skill.wizard.ice_storm":3}
	PlayerState.recalculate_stats(false)
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"real mapped world READY")
	if not game.gameplay_input_is_enabled(): _finish(); return
	var first := await Fixture.prepare_target(self,game,game.player,19,"feature_effect_production")
	check(first != null,"formal first receiver")
	if first == null: _finish(); return
	var targets: Array[EnemyActor] = [first]
	if not melee:
		var positions := [Vector2(41.2,13.5),Vector2(40.5,14.2)]
		var ids := [64,89]
		for index in range(2):
			var actor: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(ids[index]),
				game._canonical_ground_gu_to_screen_px(positions[index]),false,-1.0,{"respawn_enabled":false,"spawn_slot_id":"fixture:feature_effect:"+str(index)})
			check(actor != null and actor.projection_ready(),"exact mapped AOE actor "+str(index))
			if actor != null: targets.append(actor)
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	for actor: EnemyActor in targets:
		actor.max_hp = 10000; actor.current_hp = 10000
		actor.direct_spell_anti_magic_points = 0
		actor.direct_spell_magic_defense_min = 0; actor.direct_spell_magic_defense_max = 0
		actor.direct_spell_stats_valid = true
	PlayerState.computed_stats.magic_min = 100; PlayerState.computed_stats.magic_max = 100
	game.player.attack_min = 100; game.player.attack_max = 100
	game.player.current_mp = 100
	game.player.fire_sword_enabled = melee; game.player.half_moon_enabled = false; game.player.thrusting_enabled = false
	game._skill_cast_target = first; game._set_magic_locked_target(first,true)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"enable declared module through production catalog")
	var lease: RefCounted = game._capture_melee_configuration() if melee else game._capture_action_configuration("hc.skill.wizard.ice_storm")
	check(lease != null and not lease.event_bindings_for("hc.skill.warrior.fire_sword" if melee else "hc.skill.wizard.ice_storm").is_empty(),"accepted configuration freezes declared event bindings")
	if lease == null: _finish(); return
	var accepted := game.player.request_attack_toward(Vector2.RIGHT,true,first.get_instance_id(),lease) if melee \
		else game.player.request_skill("hc.skill.wizard.ice_storm",first.get_instance_id(),lease)
	check(accepted and lease.is_accepted(),"natural player input accepts the same action configuration")
	check(lease.effect_reservation() != null,"real ignite action owns a nonempty capacity reservation")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false),"remove source during accepted windup")
	deadline = Time.get_ticks_msec()+3000
	while game.observed_releases == 0 and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(game.observed_releases == 1 and is_same(game.observed_configuration,lease),"same configuration reaches the single real planner")
	var losses: Array[int] = []
	for actor: EnemyActor in targets:
		losses.append(10000-actor.current_hp)
		check(losses.back() > 0,"actual base HP commit on receiver "+str(actor.monster_id))
	var runtime: RefCounted = game._feature_effect_runtime
	check(runtime != null and runtime.active_count() == 0 and runtime.pending_count() == targets.size(),"base batch completes all receivers before any derived state is installed")
	if runtime == null: _finish(); return
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.active_count() == targets.size() and runtime.heap_count() == targets.size(),"one admitted state and one due node per confirmed receiver")
	var root_rng: int = game._rng.state
	var actor_rng: Array[int] = []
	for actor: EnemyActor in targets: actor_rng.append(actor._rng.state)
	game.set_physics_process(true)
	for iteration in range(3): await get_tree().physics_frame
	game.set_physics_process(false)
	check(game._time_domains.simulation_usec() > 0,"real Root physics advances simulation when effects are active")
	for second in range(1,5):
		game._time_domains.advance_simulation(float(second*1000000-game._time_domains.simulation_usec())/1000000.0)
		for iteration in range(120):
			runtime.pump()
			if not runtime.has_due(): break
			await get_tree().process_frame
		for index in range(targets.size()):
			check(targets[index].current_hp == 10000-losses[index]-second*roundi(float(losses[index])*0.05),"actual-loss-based periodic result at second "+str(second)+" target "+str(index))
	check(runtime.active_count() == 0 and runtime.heap_count() == 0 and runtime.pending_count() == 0,"real derived queues drain after final ticks")
	check(game._rng.state == root_rng,"periodic effects do not consume old Root RNG")
	for index in range(targets.size()): check(targets[index]._rng.state == actor_rng[index],"periodic effects do not consume old actor RNG "+str(index))
	check(runtime.errors.is_empty(),"production handler and command execution have no hidden failures")
	game.queue_free(); await get_tree().process_frame
	_finish()
func _finish() -> void:
	var name := "feature_fire_effect_production_test" if melee else "feature_effect_production_test"
	if not proof.write_receipt(name,checks,errors.size()): errors.append("receipt")
	print(("FRAMEWORK_FEATURE_EFFECT_PRODUCTION_PASS" if errors.is_empty() else "FRAMEWORK_FEATURE_EFFECT_PRODUCTION_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
