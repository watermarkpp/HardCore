extends "res://tests/framework/periodic_refresh_horizon_test.gd"

const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
var observations: Array[Dictionary] = []

# Characterize accepted cumulative work without capping ticks or changing the
# user's keep-original-period decision. These are controlled API diagnostics;
# deliberately overdue service does not certify natural scheduling deadlines.
func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	PlayerState.active_profile_id="periodic-refresh-service-boundary"
	await _service_case(1000)
	await _service_case(1)
	var file:=FileAccess.open("res://outputs/test_logs/framework/periodic_refresh_service_boundary_test.trace.json",FileAccess.WRITE)
	check(file!=null,"bounded service observations have an owned evidence file")
	if file!=null:
		file.store_string(JSON.stringify({"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
			"scope":"controlled compiled configuration and real HP/Batch/budget characterization; not Root author reload or natural deadline acceptance",
			"rows":observations},"  "))
		file.flush(); check(file.get_error()==OK,"bounded trace writes without ignored I/O failure"); file.close()
	check(observations.size()==2,"both declared time scales produce complete scoped observations")
	var written:=proof.write_receipt("periodic_refresh_service_boundary_test",proof.records.size(),errors.size())
	print("PERIODIC_REFRESH_SERVICE_BOUNDARY_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)

func _service_case(original_period: int) -> void:
	_zone_generation+=1
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/periodic_chain_registry.json")
		and ContentLayers.set_feature_module_enabled("hc.validation.periodic_chain",true),"registered source and compiler authority load before the diagnostic")
	var configuration: Dictionary=ContentLayers.feature_configuration()
	var old: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/features/validation/periodic_chain.json"))
	old.mechanics[0].config.period_usec=original_period
	old.mechanics[0].config.duration_usec=original_period*4
	var changed: Dictionary=old.duplicate(true)
	changed.mechanics[0].config.period_usec=1000000; changed.mechanics[0].config.duration_usec=4000000
	var event: String="damage_committed:hc.skill.wizard.ice_storm"
	var contributions: Array=[]
	for binding: Dictionary in PlayerState.feature_bundle().event_index.get(event,[]):
		contributions.append({"source":binding.source,"mechanic_id":binding.definition.mechanic_id})
	var first:=Compiler.compile([old],contributions,configuration.authority)
	var second:=Compiler.compile([changed],contributions,configuration.authority)
	check(first.success and second.success,"both independently authored four-tick configurations pass the existing compiler")
	if not first.success or not second.success: return
	bindings=first.bundle.event_index.get(event,[])
	var later: Array=second.bundle.event_index.get(event,[])
	check(bindings.size()==2 and later.size()==2 and bindings[0].source==later[0].source,
		"same registered source identity reaches the existing refresh contract")
	world=World.new(); world.configure(self,PlayerState); clock=Clock.new(); clock.configure(self)
	var combat:=Combat.new(); add_child(combat)
	source_a=Player.new(); add_child(source_a); source_a.set_physics_process(false)
	source_b=Player.new(); add_child(source_b); source_b.set_physics_process(false)
	check(source_a.begin_combat_transition("service:A") and source_a.finish_combat_transition("service:A")
		and source_b.begin_combat_transition("service:B") and source_b.finish_combat_transition("service:B"),"source actor identities enter their actual transition service")
	target=ObservedEnemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false); target.configure_runtime_map_projection(current_map_id,_ground_to_screen,_screen_to_ground)
	target.set_combat_position(_ground_to_screen(Vector2(1,0)),&"service_boundary_position")
	target.max_hp=2000000; target.current_hp=2000000
	target.direct_spell_anti_magic_points=0; target.direct_spell_magic_defense_min=0
	target.direct_spell_magic_defense_max=0; target.direct_spell_stats_valid=true
	runtime=Runtime.new()
	check(runtime.configure(world,clock,combat) and runtime.configure_child_executor(_unexpected_child),"one actual runtime and Combat HP port own delivery")
	check(_submit("service:A",10,source_a,"A"),"old-period root reserves before direct HP")
	await _pump()
	var state: Dictionary=runtime._states.values()[0]
	bindings=later
	check(_submit("service:B",1,source_b,"B"),"changed-duration root reserves before direct HP")
	runtime._dispatch_one_fact()
	var expected_owed: int=4000 if original_period==1000 else 4000000
	check(runtime.active_count()==1 and state.period==original_period and state.next_due==original_period
		and state.expires==4000000 and state.raw_per_tick==10,
		"longer refresh duration retains original period, phase and strongest damage")
	check((int(state.expires)-int(state.next_due))/int(state.period)+1==expected_owed,
		"accepted cumulative horizon is exactly the independent 4000 or 4000000 tick count")
	var fully_drained: bool=original_period==1000
	var expected_sample: int=4000 if fully_drained else 1024
	check(clock.advance_simulation(4.0 if fully_drained else 0.001024),"explicit test-owned clock exposes the bounded due-work sample")
	var started: int=Time.get_ticks_usec()
	var maximum_quantum: int=0; var maximum_overrun: int=0; var service_epochs: int=0
	var pump_elapsed: int=0
	var closed_budget:=true
	var deadline: int=Time.get_ticks_msec()+20000
	while runtime.has_due() and Time.get_ticks_msec()<deadline:
		var pump_started: int=Time.get_ticks_usec()
		runtime.pump()
		pump_elapsed+=Time.get_ticks_usec()-pump_started
		var budget: Dictionary=Budget.snapshot()
		closed_budget=closed_budget and budget.open_scopes==0 and budget.limit_usec==1200
		for counters: Dictionary in budget.categories.values():
			maximum_quantum=maxi(maximum_quantum,int(counters.maximum_quantum_usec))
		maximum_overrun=maxi(maximum_overrun,int(budget.overrun_usec)); service_epochs+=1
		if budget.open_scopes!=0: break
		if runtime.has_due(): await get_tree().process_frame
	check(closed_budget,"real budget closes every pump scope without increasing its allowance")
	check(not runtime.has_due() and target.periodic_calls==expected_sample,
		"the actual consumer commits all 4000 deliveries or the expressly bounded 1024-tick sample")
	check(target.current_hp==2000000-11-expected_sample*10 and target.periodic_release_ids.size()==expected_sample,
		"every sampled unique tick changes real HP exactly once without a max_ticks truncation")
	check(runtime.metrics().peak_receipts<=4 and target.last_credit.get("marker")=="A" and runtime.errors.is_empty(),
		"cumulative work retains bounded dedup residency, original credit and valid promises")
	var actual_drained: bool=runtime.active_count()==0 and not runtime.has_work()
	var future_ticks: int=maxi(0,expected_owed-target.periodic_calls)
	if fully_drained:
		check(runtime.active_count()==0 and not runtime.has_work(),"the complete 4000-tick horizon retires both accepted roots")
	else:
		check(runtime.active_count()==1 and state.next_due==1025 and runtime.reservation_snapshot().actions==2,
			"remaining 3998976 future ticks stay explicitly owned, not declared delivered or silently dropped")
	observations.append({"original_period_usec":original_period,"original_authored_ticks":4,"refresh_authored_ticks":4,
		"accepted_horizon_ticks":expected_owed,"delivered_sample_ticks":target.periodic_calls,"future_ticks_not_run":future_ticks,
		"case_requests_full_drain":fully_drained,"fully_drained":actual_drained,"hp":target.current_hp,"elapsed_wall_usec":Time.get_ticks_usec()-started,
		"service_epochs":service_epochs,"maximum_quantum_usec":maximum_quantum,"maximum_epoch_overrun_usec":maximum_overrun,
		"pump_elapsed_usec":pump_elapsed,"pump_elapsed_scope":"sum of wall time inside actual pump calls, including possible OS scheduling; not CPU-only",
		"maximum_actual_lateness_usec":runtime.metrics().maximum_tick_delivery_lateness_usec,
		"deadline_acceptance":"NOT_RUN","reachability":"controlled compiled Runtime API; production author replacement while world active not established"})
	# Explicitly retire this test-owned world; this is cancellation, not delivery
	# of the extreme case's future work. No real profile or production save used.
	runtime.clear()
	var empty:=true
	for count: int in runtime.reservation_snapshot().values(): empty=empty and count==0
	check(empty and not runtime.has_work(),"explicit test owner retirement releases all pending promises")
	check(ContentLayers.reload_feature_catalog(),"retired diagnostic restores the formal default registry")
	target.queue_free(); source_a.queue_free(); source_b.queue_free(); combat.queue_free()
	await get_tree().process_frame
