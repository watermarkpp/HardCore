extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Closing := preload("res://scripts/gameplay/source/main_close_process_frame_producer.gd")
const Fatal := preload("res://scripts/gameplay/source/main_source_failure.gd")
var proof := Proof.new()
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value,label)
	if not value: failures += 1
func _ready() -> void: start.call_deferred()
func start() -> void:
	var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
	check(host.has_method("prepare_original_main_channels") and host.has_method("abort_prepared_original_main_channels"), "actual Native prestart allocation and retained-owner abort ABI exist")
	if failures > 0:
		finish(); return
	var config := {"bridge_generation":1151610,"primitive_request_capacity":65536,"primitive_result_capacity":65536,"event_capacity":8,"input_capacity":8,"live_primitive_capacity":2}
	var before: Dictionary = host.status()
	check(before.started == false and before.owner_thread == 0, "blank Host has never started Source")
	var first: Dictionary = host.prepare_original_main_channels(config)
	check(first.get("status") == "PREPARED" and first.get("host_object_id") == host.get_instance_id(), "actual channels prepare on this exact Host")
	check(host.prepare_original_main_channels(config) == first, "same layout reuses the original channel incarnation")
	var mismatch := config.duplicate(true)
	mismatch.input_capacity += 1
	check(host.prepare_original_main_channels(mismatch).get("status") == "INVALID", "capacity drift is rejected before Source or physics handoff")
	var state: Dictionary = host.status()
	check(state.started == false and state.owner_thread == 0 and state.physics_handoff_prepared == false and state.original_operation_sequence == 0, "channel preparation does not allocate a Source owner, clock execution or physics lease")
	check(host.capabilities().bridge_generation == config.bridge_generation, "Main may read protocol facts from the actual prepared channels")
	check(not host.close_and_join(), "prepared bindings cannot bypass their explicit prestart abort")
	var fatal: RefCounted = Fatal.new()
	check(fatal.configure_main(host), "actual fixed Main failure owner binds without Source")
	var closing: RefCounted = Closing.new()
	check(closing.configure_main(host,get_tree(),config.bridge_generation,1,4,fatal).get("success") == true, "actual listener and closing producer bind before Source start")
	check(get_tree().root.get_node_or_null("HardCoreOriginalCloseProcessFrame") != null, "the actual closing listener is physically retained")
	var owners := {"admission":null,"claim_feature":null,"claim_origin":null,"live_feature":null,"streaming":null,"caster":null,"closing":closing}
	var wrong := owners.duplicate(false)
	wrong.closing = null
	check(host.abort_prepared_original_main_channels(wrong).get("status") == "INVALID", "prestart abort cannot lose the last actual Main owner")
	check(host.abort_prepared_original_main_channels(owners).get("status") == "ABORTED_BEFORE_START", "unstarted exact-owner channels detach without a fake STOP")
	check(get_tree().root.get_node_or_null("HardCoreOriginalCloseProcessFrame") != null, "Native detach preserves the actual Main listener until its real owner releases it")
	check(closing.finish_after_actual_prestart_abort(), "the same actual producer disconnects and frees its never-used listener")
	check(get_tree().root.get_node_or_null("HardCoreOriginalCloseProcessFrame") == null, "actual listener was released without a runtime-loss fault")
	state = host.status()
	check(state.main_channels_aborted and not state.started and not state.physics_handoff_prepared and state.fault.is_empty() and state.original_main_source_fault.is_empty(), "abort neither starts Source nor manufactures successful gameplay or clears a fault")
	check(host.prepare_original_main_channels(config).get("status") == "INVALID", "an aborted Host cannot silently allocate a replacement incarnation")
	check(host.close_and_join(), "the aborted unstarted Host has no thread to join")
	host = null
	finish()
func finish() -> void:
	var written: bool = proof.write_receipt("main_prestart_channels_20261016",checks,failures)
	print("MAIN_PRESTART_CHANNELS_20261016_"+("PASS" if written and failures == 0 else "FAIL")+" checks="+str(checks)+" failures="+str(failures))
	get_tree().quit(0 if written and failures == 0 else 1)
