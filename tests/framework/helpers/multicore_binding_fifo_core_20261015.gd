extends RefCounted

# Actual S/Native/Main resource protocol component, NOT application boot,
# canonical monster birth, physics performance, or full SourceSession admission.
const Session := preload("res://tests/framework/helpers/multicore_binding_session_component_20261015.gd")
const Coordinator := preload("res://scripts/gameplay/enemy/enemy_owner_streaming_coordinator.gd")
const Primitives := preload("res://scripts/gameplay/enemy/enemy_owner_resource_primitives.gd")
const Scope := preload("res://scripts/gameplay/world/world_temporal_scope.gd")

class Diagnostics extends RefCounted:
	var owner: int = OS.get_thread_caller_id()
	func owner_thread_id() -> int: return owner
	func timing_start() -> int: return Time.get_ticks_usec()
	func timing_elapsed_usec(started: int) -> int: return Time.get_ticks_usec() - started
	func record_performance_max(_name: StringName, _value: float) -> void: pass

class VisualModel extends RefCounted:
	var caller: WeakRef
	var completions := 0
	func owner_thread_id() -> int: return OS.get_thread_caller_id()
	func commit_live_resource_activation(_profile: Dictionary) -> void:
		completions += 1
		caller.get_ref().on_completion()
	func commit_live_resource_release() -> void:
		completions += 1
		caller.get_ref().on_completion()

class Handle extends Object:
	var view: RefCounted
	var world: Dictionary
	var life := 1
	var queued := false
	func model() -> RefCounted: return view
	func identity() -> Dictionary:
		return {"service_id":get_instance_id(),"life_generation":life,"world":world.duplicate(true)}
	func current_life() -> int: return life
	func runtime_object_is_present() -> bool: return true
	func is_queued_for_retirement() -> bool: return queued

class Registry extends RefCounted:
	var owner: int = OS.get_thread_caller_id()
	var handle: Object
	var world: Dictionary
	func owner_thread_id() -> int: return owner
	func capture_world() -> Dictionary: return world.duplicate(true)
	func resolve_service(id: int) -> Object:
		return handle if is_instance_valid(handle) and handle.get_instance_id() == id else null
	func service_qualification(id: int) -> Dictionary:
		return {"present":resolve_service(id) != null,"queued_for_retirement":handle.queued if resolve_service(id) != null else false}

var host: Object
var session: RefCounted
var primitives: RefCounted
var coordinator: RefCounted
var scope: RefCounted
var registry: RefCounted
var visual: RefCounted
var session_tag: Object
var random: Object
var world: Dictionary
var boot: Dictionary
var generation := 0
var stage := "prepare"
var prep_step := 0
var cleanup_step := 0
var profile: Dictionary = {}
var proof_rows: Array[Dictionary] = []
var trace: Array[Dictionary] = []
var ticks := 0
var polls := 0
var valid := true
var done := false
var released := false
var case_index := 0
var case_mode := "normal"
var case_modes: Array[String] = ["normal", "budget", "fairness", "life", "queue", "nested", "world", "closing"]
var completion_fired := false
var policy_checks := 0
var refill_sequence := 0
var first_pending_checked := false
var cleanup_receipts: Array = []
var nested_scopes := 0
var pressure_started := false
var pressure_done: Array[bool] = [false, false]

func record(ok: bool, label: String) -> void:
	proof_rows.append({"passed":ok,"label":label})
	if not ok: print("BINDING_FIFO_CHECK_FAIL ", label)

func _init(source_host: Object, input: Dictionary) -> void:
	host = source_host
	boot = input
	world = input.world_identity
	generation = int(host.capabilities().bridge_generation)
	random = ClassDB.instantiate("HardCoreGameplayGlobalRandom")
	valid = random.initialize_handoff(input.gameplay_random_handoff)
	session_tag = Object.new()
	session = Session.new()
	valid = valid and session.install_component(host, session_tag.get_instance_id(), generation, input.settings)
	primitives = Primitives.new()
	valid = valid and primitives.configure_owner(input.catalog, session.component_transport(), session.original_frame_budget(), session.component_clock(), session._resource_failure)
	scope = Scope.new()
	valid = valid and scope.configure_source({"runtime_present":true,"life_generation":1,"inside_world":true,"queued_for_retirement":false,
		"parent_scope_id":0,"can_process":true,"process_processing_enabled":true,"physics_processing_enabled":false,
		"ordinary_p_enabled":true,"raw_h_enabled":false,"physics_priority":0,"process_priority":0,"process_mode":1})
	registry = Registry.new()
	registry.world = world
	registry.handle = Handle.new()
	registry.handle.world = world
	visual = VisualModel.new()
	visual.caller = weakref(self)
	registry.handle.view = visual
	coordinator = Coordinator.new()
	valid = valid and coordinator.configure_owner({"FrameBudget":session.original_frame_budget(),"Time":session.component_clock(),
		"RuntimeDiagnostics":Diagnostics.new(),"services":registry,"primitives":primitives}, scope, session._resource_failure)
	var policy: Dictionary = {}
	for op in [&"status",&"load_threaded_request",&"load_threaded_get",&"replace_roots",&"close_get_escrow",&"bind_profile",&"bind_or_clear",&"observe_binding",&"retire_visual_binding",&"retire_threaded_resource_claims",&"forget_invalid_claim"]:
		policy[op] = 0
	valid = valid and coordinator.configure_live_session(session, policy)
	record(valid, "real S owns production coordinator, primitives, Session ticket methods and one ledger; fixture does not prove Loading admission")

func on_inputs(_domain: String, _packets: Array) -> bool: return true
func on_phase(name: String, frame: Dictionary) -> bool:
	if name == "H_GROUP": ticks += 1
	if name == "P_GROUP" and valid and not done: run_p(frame)
	if name == "PUBLISH":
		return host.publish_snapshot({"valid":valid,"done":done,"stage":stage,"ticks":ticks,"polls":polls,
			"rows":proof_rows if done else [],"trace":trace if done else [],"case_index":case_index}, [])
	return valid

func run_p(frame: Dictionary) -> void:
	# Match the original Source P prefix receipt pump before streaming; the
	# Native applied frontier must advance before the journal prunes its prefix.
	var prefix_receipt: Dictionary = host.completed_original_main_prefix_receipt()
	valid = session.original_event_journal().consume_normal_receipt(prefix_receipt)
	if not valid: return
	polls += 1
	var site: Dictionary = {"clock_epoch":int(frame.epoch),"domain":&"P","entry_id":"binding_fifo_native_component/P_GROUP",
		"entry_ordinal":1,"bootstrap":false,"observation_process_epoch":int(frame.source_process_frame),
		"world_context":world,"deadline_usec":int(frame.next_release_usec)}
	valid = primitives.begin_original_phase(site)
	if not valid: return
	valid = session.begin_resource_commit_phase(int(frame.source_process_frame))
	if not valid: return
	valid = primitives.commit_live_results()
	valid = session.finish_resource_commit_phase() and valid
	if not valid: return
	var budget: RefCounted = session.original_frame_budget()
	budget.mark_pending(coordinator._budget_category, true, true, false, scope)
	var token: int = budget.begin(coordinator._budget_category)
	if token != 0:
		if stage == "prepare": prepare_texture()
		elif stage == "binding": run_bindings(frame)
		elif stage == "cleanup": cleanup()
		if pressure_started: pump_pressure()
		budget.end(token)
	# No Native acceptance or waiting was added inside the scalar scope.
	valid = primitives.flush_live_submissions() and valid
	valid = primitives.finish_original_phase() and valid
	valid = host.finish_original_call_site(site) and valid
	if stage == "settle" and primitives.live_operations_drained():
		valid = coordinator.begin_live_close() and coordinator.retire_threaded_resource_claims() and coordinator.finish_owner() and session.component_tickets_empty() and valid
		record(valid, "all real Native tickets, original settlements and consumer responsibilities drained")
		record(session.fixture_sink.faults.is_empty(), "no Source protocol fault")
		done = true
		stage = "done"

func prepare_texture() -> void:
	var result: Dictionary
	if prep_step == 0:
		result = coordinator._live_operation("fixture_prepare", &"load_threaded_request", [boot.texture_path,"Texture2D",false], "fixture:loader")
	elif prep_step == 1:
		result = coordinator._live_operation("fixture_prepare", &"status", [boot.texture_path], "fixture:loader")
	else:
		result = coordinator._live_operation("fixture_prepare", &"load_threaded_get", [boot.texture_path], "fixture:loader")
	if result.get("status") != "COMMITTED": return
	if prep_step == 0:
		record(result.result == OK, "real fixture Texture2D threaded request accepted")
		prep_step = 1
	elif prep_step == 1:
		if result.result == 3: prep_step = 2
		elif result.result != 1:
			record(false, "real fixture texture must finish loading")
			valid = false
	else:
		var texture: int = int(result.texture)
		record(texture != 0, "real GET texture token preserves all ObjectID bits, not invented resource readiness")
		profile = {"idle":texture,"walk":texture,"attack":texture,"hit":texture,"death":texture,"frame_size":Vector2i(4,4),"foot_anchor":Vector2i.ZERO}
		valid = session.original_event_journal().append({"operation":&"fixture_renderer_create","arguments":[registry.handle.get_instance_id()]})
		setup_case()
		stage = "binding"

func setup_case() -> void:
	case_mode = case_modes[case_index]
	completion_fired = false
	var id: int = registry.handle.get_instance_id()
	if case_index == 0:
		coordinator.enqueue_live_binding_event(id, &"visual_visible", [false])
		coordinator.enqueue_live_binding_event(id, &"visual_create_body_sprite", [])
		coordinator._visual_subscriptions[id] = {"resource_key":"actual_fixture_profile","world_generation":1}
		record(coordinator.request_live_visual_activation(id, profile, true), "original cached activation retains its no-fact cursor behind two real initial mutations")
		record(coordinator._live_bindings.size() == 3 and coordinator._live_bindings[2].get("await_initial_binding") == true,
			"initial fact is not guessed and its cursor is not prematurely expanded")
	else:
		coordinator._enqueue_live_binding(id, &"bind_or_clear", [id,&"visual_visible",[true]], "release", {}, false)
		coordinator.enqueue_live_binding_event(id, &"visual_visible", [false])

func on_completion() -> void:
	completion_fired = true
	var budget: RefCounted = session.original_frame_budget()
	if case_mode == "budget": budget._limit_usec = 0
	elif case_mode == "fairness": budget.mark_pending("fixture_unserved_peer", true)
	elif case_mode == "life": registry.handle.life += 1
	elif case_mode == "world":
		registry.world = world.duplicate(true)
		registry.world.world_epoch += 1
	elif case_mode == "nested":
		var child: int = budget.begin("fixture_nested_completion", true)
		record(child > 0, "original callback opens its own real nested scope")
		if child > 0:
			nested_scopes += 1
			budget.end(child)
	elif case_mode == "closing":
		record(coordinator.begin_live_close(), "original callback enters actual coordinator close path")
	elif case_mode == "queue":
		var id: int = registry.handle.get_instance_id()
		var tail: Array[Dictionary] = coordinator._live_bindings.duplicate()
		coordinator._live_bindings.clear()
		coordinator.enqueue_live_binding_event(id, &"visual_visible", [true])
		coordinator._live_bindings.append_array(tail)

func run_bindings(frame: Dictionary) -> void:
	var before_count: int = coordinator._live_bindings.size()
	var before_sequence: int = primitives._live_intent_sequence
	var held: Dictionary = coordinator._live_ops.get("binding", {})
	var old_committed: bool = not held.is_empty() and primitives._live_intents.get(int(held.id), {}).get("committed") == true
	var old_completion: String = str(coordinator._live_bindings.front().completion) if before_count > 0 else ""
	var was_completion: bool = completion_fired
	var scopes: int = session.original_frame_budget()._next_token
	var nested_before: int = nested_scopes
	coordinator._live_poll_bindings()
	var after_sequence: int = primitives._live_intent_sequence
	trace.append({"p":int(frame.source_process_frame),"case":case_mode,"before":before_count,"after":coordinator._live_bindings.size(),
		"old_committed":old_committed,"new_intents":after_sequence-before_sequence,"completed":visual.completions})
	record(after_sequence - before_sequence <= 1, "at most one fresh intent per original polling scope")
	record(session.original_frame_budget()._next_token - scopes == nested_scopes - nested_before, "binding continuation creates no extra scope beyond the original callback")
	if old_committed and not coordinator._live_bindings.is_empty():
		var must_stop: bool = not was_completion and completion_fired and case_mode in ["budget","fairness","life","world"]
		if must_stop:
			record(after_sequence == before_sequence and not coordinator._live_ops.has("binding"), "completed callback stops fresh dispatch on " + case_mode)
			policy_checks += 1
		else:
			record(after_sequence == before_sequence + 1 and coordinator._live_ops.has("binding"), "completed old binding immediately attempts next actual FIFO head in " + case_mode)
			if case_mode == "queue" and old_completion != "":
				record(coordinator._live_ops.get("binding", {}).get("args", [0,0,[]])[2] == [true], "completion-created front is read instead of cached old tail")
	if not old_committed and not held.is_empty():
		record(after_sequence == before_sequence and coordinator._live_bindings.size() == before_count, "real pending Native operation never spins or pops the cursor")
		first_pending_checked = true
	if case_mode == "closing" and not was_completion and completion_fired:
		record(coordinator._live_closing and coordinator._live_bindings.is_empty() and after_sequence == before_sequence,
			"original close completes current callback and admits no new ordinary binding")
	if case_index == 0 and not pressure_started: pressure_started = true
	# Restore controlled test inputs only after checking the production decision.
	if case_mode == "world": registry.world = world
	if case_mode == "budget": session.original_frame_budget()._limit_usec = 2000000
	if case_mode == "fairness": session.original_frame_budget().mark_pending("fixture_unserved_peer", false)
	if coordinator._live_bindings.is_empty():
		if case_index == 0:
			var fact: Dictionary = primitives.binding_fact(registry.handle.get_instance_id())
			record(fact.sprite_exists and fact.actual_visible and fact.texture_nonnull and fact.actual_texture_token == profile.idle,
				"five real Main operations produced true Sprite/visibility/texture BindingFact")
		case_index += 1
		if case_index < case_modes.size(): setup_case()
		else:
			record(policy_checks == 4, "actual committed callbacks exercised budget, fairness, life and world boundaries")
			record(session.actual_native_backpressure > 0 and pressure_done == [true,true], "real two-slot Native capacity returned BACKPRESSURE and both accepted status operations settled")
			_check_fixture_pending_main()
			valid = session.original_event_journal().append({"operation":&"fixture_renderer_destroy","arguments":[registry.handle.get_instance_id()]})
			cleanup_receipts = primitives.live_collection_receipts()
			stage = "cleanup"

func pump_pressure() -> void:
	# Together with the one binding intent, these two real status operations
	# exceed the actual two-slot Native capacity. No false BUSY is injected.
	for index: int in range(2):
		if pressure_done[index]: continue
		var result: Dictionary = coordinator._live_operation("fixture_pressure:%d" % index, &"status", [boot.texture_path], "fixture:pressure:%d" % index)
		if result.get("status") == "COMMITTED":
			record(result.result == 0, "actual post-GET INVALID status consumed once")
			pressure_done[index] = true

func cleanup() -> void:
	var result: Dictionary
	if cleanup_step == 0:
		result = coordinator._live_operation("fixture_cleanup", &"retire_visual_binding", [registry.handle.get_instance_id()], "fixture:cleanup", true)
	else:
		result = coordinator._live_operation("fixture_cleanup", &"close_get_escrow", [cleanup_receipts], "fixture:cleanup", true)
	if result.get("status") != "COMMITTED": return
	record(result.result == true, "actual Main physical cleanup committed once")
	cleanup_step += 1
	if cleanup_step == 2: stage = "settle"

func close_session() -> bool:
	if not done or not primitives.live_operations_drained() or not session.component_tickets_empty(): return false
	host.completed_original_main_prefix_receipt()
	if not released:
		registry.handle.free()
		registry.handle = null
		session_tag.free()
		session_tag = null
		released = true
	return true

func _check_fixture_pending_main() -> void:
	record(first_pending_checked, "Main deliberately withheld a real result across Source P polls")
