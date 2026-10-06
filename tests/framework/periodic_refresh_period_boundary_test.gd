extends "res://tests/framework/periodic_refresh_horizon_test.gd"

const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")

# 2026-10-05 user ruling: same-species replacement is atomic — the fresh
# incarnation owns its own accepted period, phase and full duration from the
# actual application time. The old strongest_keep_phase observations remain in
# owned historical evidence.
func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	PlayerState.active_profile_id="periodic-refresh-period-policy"
	await _period_case(false)
	await _period_case(true)
	_finish()

func _period_case(longer: bool) -> void:
	_zone_generation+=1
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/periodic_chain_registry.json")
		and ContentLayers.set_feature_module_enabled("hc.validation.periodic_chain",true),
		"registered default-off module supplies real source identities and authority")
	var configuration: Dictionary=ContentLayers.feature_configuration()
	var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/features/validation/periodic_chain.json"))
	var changed: Dictionary=original.duplicate(true)
	changed.mechanics[0].config.period_usec=2000000 if longer else 1
	changed.mechanics[0].config.duration_usec=8000000 if longer else 4
	var event: String="damage_committed:hc.skill.wizard.ice_storm"
	var contributions: Array=[]
	for binding: Dictionary in PlayerState.feature_bundle().event_index.get(event,[]):
		contributions.append({"source":binding.source,"mechanic_id":binding.definition.mechanic_id})
	var first:=Compiler.compile([original],contributions,configuration.authority)
	var second:=Compiler.compile([changed],contributions,configuration.authority)
	check(first.success and second.success,"both four-tick author configurations pass the original compiler")
	if not first.success or not second.success: return
	bindings=first.bundle.event_index.get(event,[])
	var later: Array=second.bundle.event_index.get(event,[])
	check(bindings.size()==2 and later.size()==2 and bindings[0].source==later[0].source
		and bindings[1].source==later[1].source,"refresh retains exact stable sources and status identity")
	if bindings.size()!=2 or later.size()!=2: return
	world=World.new(); world.configure(self,PlayerState)
	clock=Clock.new(); clock.configure(self)
	var combat:=Combat.new(); add_child(combat)
	source_a=Player.new(); add_child(source_a); source_a.set_physics_process(false)
	source_b=Player.new(); add_child(source_b); source_b.set_physics_process(false)
	check(source_a.begin_combat_transition("period-policy:A") and source_a.finish_combat_transition("period-policy:A")
		and source_b.begin_combat_transition("period-policy:B") and source_b.finish_combat_transition("period-policy:B"),
		"sources enter the original actor transition service")
	target=ObservedEnemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false)
	target.configure_runtime_map_projection(current_map_id,_ground_to_screen,_screen_to_ground)
	target.set_combat_position(_ground_to_screen(Vector2(1,0)),&"period_policy_unit_position")
	target.max_hp=20000; target.current_hp=20000
	target.direct_spell_anti_magic_points=0
	target.direct_spell_magic_defense_min=0; target.direct_spell_magic_defense_max=0
	target.direct_spell_stats_valid=true
	runtime=Runtime.new()
	check(runtime.configure(world,clock,combat) and runtime.configure_child_executor(_unexpected_child),
		"one existing runtime and the real Combat HP port own the test")
	check(_submit("period-policy:A",10,source_a,"A"),"original root accepts before direct HP")
	await _pump()
	var state: Dictionary=runtime._states.values()[0]
	check(state.period==1000000 and state.next_due==1000000 and state.expires==4000000,
		"the existing effect starts with its original period and phase")
	check(clock.advance_simulation(1.0),"simulation reaches the first owed tick")
	bindings=later
	var refresh_loss: int=20 if longer else 1
	# 2026-10-05 user ruling: same-species replacement is atomic — the fresh
	# incarnation owns its own accepted period, phase and full duration from the
	# actual application time, and the owed original tick is cancelled with the
	# old incarnation instead of being committed on the original phase.
	var expected_raw: int=20 if longer else 1
	var expected_period: int=2000000 if longer else 1
	var expected_expiry: int=9000000 if longer else 1000004
	var expected_ticks: int=4
	check(_submit("period-policy:B",refresh_loss,source_b,"B"),"changed configuration accepts through the original HP and Batch chain")
	runtime._dispatch_one_fact()
	var replacement: Dictionary={}
	for live: Dictionary in runtime._states.values():
		if live.target.resolve()==target: replacement=live
	check(runtime.active_count()==1 and runtime.heap_count()==1 and replacement.period==expected_period,
		"replacement installs its accepted period when the new period is "+("longer" if longer else "shorter"))
	check(replacement.next_due==clock.simulation_usec()+expected_period
		and replacement.expires==clock.simulation_usec()+int(changed.mechanics[0].config.duration_usec)
		and replacement.raw_per_tick==expected_raw,
		"replacement restarts phase and the full accepted duration from the actual application time")
	if replacement.period==expected_period:
		var owed: int=(int(replacement.expires)-int(replacement.next_due))/expected_period+1
		check(owed==expected_ticks,"the accepted period gives the exact finite replacement horizon")
		check(clock.advance_simulation(float(expected_expiry-clock.simulation_usec())/1000000.0),
			"simulation reaches the replacement's final expiry")
		await _pump()
		check(target.periodic_calls==expected_ticks and target.current_hp==20000-10-refresh_loss-expected_ticks*expected_raw,
			"the real HP port delivers every replacement tick through expiry without truncation")
		check(target.periodic_release_ids.size()==expected_ticks and target.last_credit.get("marker")=="B",
			"every tick has a unique release identity owned by the replacement's own credit")
		check(runtime.active_count()==0 and runtime.heap_count()==0 and not runtime.has_work() and runtime.errors.is_empty(),
			"the accepted replacement horizon completes and retires all runtime work")
		print("PERIODIC_REFRESH_PERIOD_POLICY_OBSERVATION ",JSON.stringify({"new_period_usec":changed.mechanics[0].config.period_usec,
			"replacement_period_usec":replacement.period,"expiry_usec":expected_expiry,"completed_ticks":target.periodic_calls,
			"hp":target.current_hp,"scope":"controlled real HP and Batch chain; replacement owns its own period; not natural deadline proof"}))
		var hp_before_new: int=target.current_hp
		check(_submit("period-policy:C",refresh_loss,source_b,"C"),"after expiry a new accepted root can create a separate state")
		await _pump()
		var fresh: Dictionary=runtime._states.values()[0]
		check(fresh.period==changed.mechanics[0].config.period_usec
			and fresh.next_due==clock.simulation_usec()+int(fresh.period)
			and fresh.expires==clock.simulation_usec()+int(changed.mechanics[0].config.duration_usec),
			"new state uses its own accepted period and expiry after the old state fully retires")
		check(clock.advance_simulation(float(changed.mechanics[0].config.duration_usec)/1000000.0),
			"simulation reaches the independent new state's final tick")
		await _pump()
		check(target.periodic_calls==expected_ticks+4 and target.current_hp==hp_before_new-5*refresh_loss,
			"all four ticks of the new configuration commit through the original HP port")
		check(target.periodic_release_ids.size()==expected_ticks+4 and target.last_credit.get("marker")=="C"
			and runtime.active_count()==0 and not runtime.has_work() and runtime.errors.is_empty(),
			"new state has independent tick identities and credit and completes without stale old ownership")
	runtime.clear()
	var empty:=true
	for count: int in runtime.reservation_snapshot().values(): empty=empty and count==0
	check(empty and not runtime.has_work(),"owner teardown leaves no promise or receipt slot")
	check(ContentLayers.reload_feature_catalog(),"test restores the formal default publication")
	target.queue_free(); source_a.queue_free(); source_b.queue_free(); combat.queue_free()
	await get_tree().process_frame

func _finish() -> void:
	var written:=proof.write_receipt("periodic_refresh_period_boundary_test",proof.records.size(),errors.size())
	print("PERIODIC_REFRESH_PERIOD_BOUNDARY_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
