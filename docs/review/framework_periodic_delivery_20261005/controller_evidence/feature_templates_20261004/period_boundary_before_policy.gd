extends "res://tests/framework/periodic_refresh_horizon_test.gd"

const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")

# A bounded observation of a legal compiled refresh. It deliberately services
# only 1025 due ticks, then performs explicit owner teardown; it does not claim
# that the remaining three-million-tick horizon has completed or met deadlines.
func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	PlayerState.active_profile_id="periodic-refresh-period-boundary"
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/periodic_chain_registry.json")
		and ContentLayers.set_feature_module_enabled("hc.validation.periodic_chain",true),
		"registered default-off module supplies the original source identities and authority")
	var configuration: Dictionary=ContentLayers.feature_configuration()
	var old_module: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/features/validation/periodic_chain.json"))
	var changed_module: Dictionary=old_module.duplicate(true)
	changed_module.mechanics[0].config.period_usec=1
	changed_module.mechanics[0].config.duration_usec=4
	var event: String="damage_committed:hc.skill.wizard.ice_storm"
	var contributions: Array=[]
	for binding: Dictionary in PlayerState.feature_bundle().event_index.get(event,[]):
		contributions.append({"source":binding.source,"mechanic_id":binding.definition.mechanic_id})
	var first:=Compiler.compile([old_module],contributions,configuration.authority)
	var second:=Compiler.compile([changed_module],contributions,configuration.authority)
	check(first.success and second.success,"formal compiler accepts both one-second and one-microsecond four-tick configurations")
	if not first.success or not second.success: _finish(); return
	bindings=first.bundle.event_index.get(event,[])
	var later: Array=second.bundle.event_index.get(event,[])
	check(bindings.size()==2 and later.size()==2 and bindings[0].source==later[0].source
		and bindings[1].source==later[1].source,"configuration changes retain the exact same stable sources rather than creating another status")
	if bindings.size()!=2 or later.size()!=2: _finish(); return
	world=World.new(); world.configure(self,PlayerState)
	clock=Clock.new(); clock.configure(self)
	var combat:=Combat.new(); add_child(combat)
	source_a=Player.new(); add_child(source_a); source_a.set_physics_process(false)
	source_b=Player.new(); add_child(source_b); source_b.set_physics_process(false)
	check(source_a.begin_combat_transition("period-boundary:A") and source_a.finish_combat_transition("period-boundary:A")
		and source_b.begin_combat_transition("period-boundary:B") and source_b.finish_combat_transition("period-boundary:B"),
		"sources use the real actor transition service")
	target=ObservedEnemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false)
	target.configure_runtime_map_projection(current_map_id,_ground_to_screen,_screen_to_ground)
	target.set_combat_position(_ground_to_screen(Vector2(1,0)),&"period_boundary_unit_position")
	target.max_hp=20000; target.current_hp=20000
	target.direct_spell_anti_magic_points=0
	target.direct_spell_magic_defense_min=0; target.direct_spell_magic_defense_max=0
	target.direct_spell_stats_valid=true
	runtime=Runtime.new()
	check(runtime.configure(world,clock,combat) and runtime.configure_child_executor(_unexpected_child),
		"one runtime and original Combat port own the controlled observation")
	check(_submit("period-boundary:A",10,source_a,"A"),"original root is accepted before direct HP")
	await _pump()
	var state: Dictionary=runtime._states.values()[0]
	check(state.next_due==1000000 and state.expires==4000000 and target.current_hp==19990,
		"original compiled period and four-second horizon are active")
	check(clock.advance_simulation(1.0),"simulation reaches the first owed tick")
	bindings=later
	check(_submit("period-boundary:B",1,source_b,"B"),"changed compiled configuration is accepted through the real HP and Batch chain")
	# Observe refresh before serving old due work, as in the existing horizon unit.
	runtime._dispatch_one_fact()
	check(runtime.active_count()==1 and runtime.heap_count()==1 and state.period==1
		and state.next_due==1000000 and state.expires==4000000 and state.raw_per_tick==10,
		"strongest_keep_phase retains old due and longer expiry while applying the new legal period")
	var promised_ticks: int=(int(state.expires)-int(state.next_due))/int(state.period)+1
	check(promised_ticks==3000001 and promised_ticks>8,
		"two authored four-tick applications produce a finite 3000001-tick shared horizon")
	await _pump()
	check(target.periodic_calls==1 and state.next_due==1000001,"the old first due tick commits exactly once")
	check(clock.advance_simulation(0.001024) and clock.simulation_usec()==1001024,
		"a bounded 1024-microsecond simulation observation introduces exactly 1024 more due ticks")
	await _pump()
	check(target.periodic_calls==1025 and target.current_hp==9739 and runtime.metrics().ticks==1025,
		"real HP port executes all 1025 observed ticks without an eight-tick truncation")
	check(target.periodic_release_ids.size()==1025 and target.last_credit.get("marker")=="A"
		and state.next_due==1001025 and state.expires==4000000,
		"distinct tick identities preserve initial credit and the uncompleted old horizon")
	check(runtime.active_count()==1 and not runtime.has_due() and runtime.metrics().peak_receipts<=4
		and runtime.errors.is_empty(),"future accepted work remains owned with bounded receipt residency")
	check(runtime.metrics().maximum_tick_delivery_lateness_usec==1023,
		"controlled accumulated lateness exceeds the one-microsecond period and is retained as diagnostic evidence")
	print("PERIODIC_REFRESH_PERIOD_BOUNDARY_OBSERVATION ",JSON.stringify({
		"applications":2,"authored_ticks_per_application":4,"shared_horizon_tick_count":promised_ticks,
		"observed_ticks":target.periodic_calls,"remaining_future_ticks":promised_ticks-target.periodic_calls,
		"simulation_usec":clock.simulation_usec(),"maximum_actual_lateness_usec":runtime.metrics().maximum_tick_delivery_lateness_usec,
		"scope":"controlled legal configuration boundary; partial service then explicit owner teardown; no deadline acceptance"}))
	runtime.clear()
	var empty:=true
	for count: int in runtime.reservation_snapshot().values(): empty=empty and count==0
	check(empty and not runtime.has_work(),"explicit world-owner teardown retires future promises without claiming their completion")
	check(ContentLayers.reload_feature_catalog(),"test restores the formal default publication")
	target.queue_free(); source_a.queue_free(); source_b.queue_free(); combat.queue_free()
	await get_tree().process_frame
	_finish()

func _pump() -> void:
	# The inherited unit observes 104 ticks in at most 200 process epochs.
	# This distinct boundary intentionally owes 1025 ticks; allow its existing
	# budgeted consumer enough epochs, without changing the production budget,
	# clock, period, damage count or the ordinary runner's 30-second deadline.
	for iteration in range(4096):
		runtime.pump()
		if runtime.pending_count()==0 and runtime.child_count()==0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"bounded real consumer completes the 1025-tick diagnostic")

func _finish() -> void:
	var written:=proof.write_receipt("periodic_refresh_period_boundary_test",proof.records.size(),errors.size())
	print("PERIODIC_REFRESH_PERIOD_BOUNDARY_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
