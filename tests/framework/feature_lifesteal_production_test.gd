extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)
func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.profession = "法师"; PlayerState.level = 50
	PlayerState.learned_skills = {"hc.skill.wizard.ice_storm":3}; PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/lifesteal_registry.json"),"formal trusted registry publishes both heterogeneous definitions")
	check(ContentLayers.feature_configuration().enabled_modules.is_empty(),"both primitives are default-off until explicit test activation")
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"actual mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): game.queue_free(); await get_tree().process_frame; _finish(); return
	var target := await Fixture.prepare_target(self,game,game.player,19,"lifesteal_production")
	check(target != null,"formal geometry supplies an actual receiver")
	if target == null: game.queue_free(); await get_tree().process_frame; _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	target.max_hp = 10000; target.current_hp = 10000
	target.direct_spell_anti_magic_points = 0
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0; target.direct_spell_stats_valid = true
	PlayerState.computed_stats.magic_min = 100; PlayerState.computed_stats.magic_max = 100
	game.player.current_hp = 50; game.player.current_mp = 100
	game._skill_cast_target = target; game._set_magic_locked_target(target,true)
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true)
		and ContentLayers.set_feature_module_enabled("hc.validation.lifesteal",true),"formal live source activation compiles both handlers")
	game.player.current_hp = 50
	var lease: RefCounted = game._capture_action_configuration("hc.skill.wizard.ice_storm")
	check(lease != null and lease.event_bindings_for("hc.skill.wizard.ice_storm").size()==2,"accepted action freezes two different handler subscriptions")
	if lease == null: game.queue_free(); await get_tree().process_frame; _finish(); return
	check(game.player.request_skill("hc.skill.wizard.ice_storm",target.get_instance_id(),lease)
		and lease.is_accepted() and lease.effect_reservation()!=null,"real Player windup accepts a nonempty capacity ticket")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false)
		and ContentLayers.set_feature_module_enabled("hc.validation.lifesteal",false),"withdrawal during windup preserves accepted effects")
	deadline = Time.get_ticks_msec()+3000
	while game.observed_releases==0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases==1 and is_same(game.observed_configuration,lease),"one real release reaches the single planner")
	var loss: int = 10000-target.current_hp
	check(game.player.max_hp>=50+floori(float(loss)*0.25),"real profile maximum leaves space for the literal healing expectation")
	check(loss>0 and game.player.current_hp==50,"base HP commit finishes before either derived command")
	var runtime: RefCounted = game._feature_effect_runtime
	check(runtime!=null and runtime.pending_count()==1,"sole runtime owns the completed base fact")
	if runtime==null: game.queue_free(); await get_tree().process_frame; _finish(); return
	var root_rng: int = game._rng.state; var player_rng: int = game.player._rng.state
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count()==0: break
		await get_tree().process_frame
	check(game.player.current_hp==50+floori(float(loss)*0.25),"committed loss restores through the real player authority exactly once")
	check(runtime.active_count()==1 and runtime.heap_count()==1,"instant healing coexists with one persistent ignite state")
	check(runtime.metrics().healing_commands==1 and runtime.reservation_snapshot().actions==0,"instant receipt and completed producer retire without losing periodic state")
	for second in range(1,5):
		game._time_domains.advance_simulation(float(second*1000000-game._time_domains.simulation_usec())/1000000.0)
		for iteration in range(120):
			runtime.pump()
			if not runtime.has_due(): break
			await get_tree().process_frame
		check(target.current_hp==10000-loss-second*roundi(float(loss)*0.05),"old ignite damage is unchanged at tick "+str(second))
		check(game.player.current_hp==50+floori(float(loss)*0.25),"periodic damage cannot recursively heal at tick "+str(second))
	check(game._rng.state==root_rng and game.player._rng.state==player_rng,"both handlers preserve old combat random streams")
	check(runtime.errors.is_empty() and not runtime.has_work(),"mixed commands, states and producers drain without business failure")
	game.queue_free(); await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(),"retired world can restore the original default-off catalog")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_lifesteal_production_test",checks,errors.size()): errors.append("receipt")
	print(("FRAMEWORK_LIFESTEAL_PRODUCTION_PASS" if errors.is_empty() else "FRAMEWORK_LIFESTEAL_PRODUCTION_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
