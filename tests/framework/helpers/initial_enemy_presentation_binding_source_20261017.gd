extends "res://tests/framework/helpers/live_sprite_birth_order_source_20261017.gd"
## No fake Host, Native receipt, COMMITTED result or BindingFact. Owner
## doubles are inherited and explicitly limit this to a protocol component.
var initial_observations := 0
var observation_identity: Dictionary = {}
var cached_fact_pending_checked := false
var _initial_api := false
var _deadline_checked := false

func setup_case() -> void:
	super.setup_case()
	if case_index != 0: return
	_initial_api = coordinator.has_signal("original_initial_binding_observed") and coordinator.has_method("original_initial_binding_observation_pending")
	record(_initial_api, "RED: production coordinator exposes consumed initial-observation completion and exact retained-row predicate")
	if not _initial_api: return # Continue real accepted flow/cleanup on old source.
	observation_identity = registry.handle.identity().duplicate(true)
	record(coordinator.connect("original_initial_binding_observed", _on_initial_observation) == OK, "observe the existing production completion signal, never inject a completion")
	var id: int = registry.handle.get_instance_id()
	record(coordinator.call("original_initial_binding_observation_pending",id,observation_identity), "real initial row is retained before any Main BindingFact exists")
	record(not coordinator.call("original_initial_binding_observation_pending",id+1,observation_identity), "foreign service cannot borrow a retained initial observation")
	var foreign: Dictionary = observation_identity.duplicate(true)
	foreign.life_generation += 1
	record(not coordinator.call("original_initial_binding_observation_pending",id,foreign), "foreign life cannot borrow the initial row")
	foreign = observation_identity.duplicate(true); foreign.world.profile_id = "foreign_profile"
	record(not coordinator.call("original_initial_binding_observation_pending",id,foreign), "foreign Profile cannot borrow the initial row")

func _on_initial_observation(id: int, original_identity: Dictionary, consumed: Dictionary) -> void:
	initial_observations += 1
	record(initial_observations == 1 and id == registry.handle.get_instance_id() and original_identity == observation_identity, "one consumed initial observation returns its exact original service owner")
	record(consumed.get("status") == "COMMITTED" and consumed.get("reply",{}).get("executed") == true, "completion carries real executed COMMITTED result from existing Native/Session flow")
	var request: Dictionary = consumed.get("reply",{}).get("request",{})
	record(request.get("op") == &"observe_binding" and request.get("args") == [id], "an earlier visibility BindingFact cannot discharge the observation")
	record(primitives.has_binding_fact(id) and primitives.binding_fact(id) == consumed.get("result"), "sole production fact authority already installed the actual observation")
	record(not coordinator.call("original_initial_binding_observation_pending",id,observation_identity), "exact FIFO observation has been popped before presentation completion")
	record(not coordinator.get("_live_ops").has("binding"), "existing operation result consumed before callback, no second binding cursor")

func run_bindings(frame: Dictionary) -> void:
	if case_index == 0 and _initial_api:
		var id: int = registry.handle.get_instance_id()
		if primitives.has_binding_fact(id) and initial_observations == 0:
			cached_fact_pending_checked = true
			record(coordinator.call("original_initial_binding_observation_pending",id,observation_identity), "earlier actual visibility fact leaves initial observation pending until its own consumed result")
	var previous_case: int = case_index
	super.run_bindings(frame)
	if previous_case == 0 and case_index != 0:
		record(initial_observations == 1, "RED: actual initial observation releases its presentation obligation exactly once")
		record(cached_fact_pending_checked, "real earlier-fact versus consumed-observation boundary was exercised")
	if stage == "cleanup":
		record(initial_observations == 1, "later profile activation/release completions never repeat initial presentation admission")

func on_phase(name: String, frame: Dictionary) -> bool:
	if name != "PUBLISH": return super.on_phase(name, frame)
	var accepted: Dictionary = {}
	var pending: Dictionary = coordinator._live_ops.get("binding", {})
	if not pending.is_empty(): accepted = primitives.live_operation_identity(int(pending.id)).duplicate(true)
	return host.publish_snapshot({"valid":valid,"done":done,"stage":stage,"ticks":ticks,"polls":polls,
		"rows":proof_rows if done else [],"trace":trace if done else [],"case_index":case_index,
		"initial_binding_control":{"identity":accepted,"pending_operation":str(pending.get("op",""))}}, [])

func _check_fixture_pending_main() -> void:
	if boot.get("binding_test_mode", "ordinary") == "controlled_late":
		super._check_fixture_pending_main()
	else:
		# Ordinary Main service does not manufacture a pending interval. The
		# separate controlled-late scene must exercise the inherited assertion.
		print("INITIAL_BINDING_ORDINARY_PENDING_OBSERVED ", first_pending_checked)

func run_p(frame: Dictionary) -> void:
	super.run_p(frame)
	if done and not _deadline_checked:
		_deadline_checked = true
		var main_late := 0
		var read_late := 0
		var max_read_late_usec := 0
		var actual_raw: Array = primitives.deadline_failures
		for row: Dictionary in actual_raw:
			var due: int = int(row.site.deadline_usec)
			if int(row.finished_usec) > due: main_late += 1
			if int(row.received_usec) > due: read_late += 1
			max_read_late_usec = maxi(max_read_late_usec, int(row.received_usec) - due)
			record(row.status == &"FAIL" and (int(row.finished_usec) > due or int(row.received_usec) > due), "Native raw FAIL retains its actual execution or receipt lateness")
		print("INITIAL_BINDING_ACTUAL_DEADLINES ", JSON.stringify(actual_raw))
		print("INITIAL_BINDING_SPLIT_TIMING ", JSON.stringify({"mode":boot.get("binding_test_mode","ordinary"),
			"raw_native_FAILs":actual_raw.size(),"main_execution_late":main_late,"source_read_late":read_late,
			"max_source_read_late_usec":max_read_late_usec,"source_polls":polls,"source_h_ticks":ticks}))
		if boot.get("binding_test_mode", "ordinary") == "controlled_late":
			record(main_late > 0 and primitives.deadline_fail_count > 0, "deliberately withheld real Main execution produces a retained Native FAIL")
		else:
			record(main_late == 0, "ordinary real Main operations complete within their original deadlines; next-P reading measured separately")
