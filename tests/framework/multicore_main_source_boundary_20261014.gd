extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const WrongProvider := preload("res://scripts/gameplay/world/world_visual_viewport_port.gd")
var _proof := Proof.new()
var _checks := 0
var _failures := 0

func _check(value: bool, name: String) -> void:
	_checks += 1
	_failures += 0 if value else 1
	_proof.record(value, name)

func _ready() -> void:
	var deferred: RefCounted = ClassDB.instantiate("HardCoreMainSourceDeferred")
	_check(deferred != null, "actual native Main source boundary class registered")
	var caps: Dictionary = deferred.capabilities()
	_check(caps.actual_Main_only_queue_observation and not caps.checkpoint_producer_bound and not caps.queue_empty_proves_io_or_ui and not caps.production_Root_checkpoint_receiver_closure, "native queue evidence never claims missing IO/UI producer")
	var absent: Dictionary = deferred.observe_original_main_source_receivers({}, null, null, null)
	_check(absent.get("success") == false and "MISSING:actual_Root_Main_checkpoint_producer" in absent.get("errors", []), "no real producer means explicit MISSING receiver closure")
	var unverified: Dictionary = deferred.flush_original_main_source_checkpoint({}, null, null, null)
	_check(unverified.get("success") == false, "no unauthorised source checkpoint flush")
	var wrong := WrongProvider.new()
	var actual_script: Script = wrong.get_script()
	var actual_digest := actual_script.get_source_code().sha256_text()
	_check(not deferred.configure_original_checkpoint_producer(wrong, "res://scripts/gameplay/world/world_visual_viewport_port.gd", actual_digest), "actual unrelated script cannot manufacture legal checkpoint")
	var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
	_check(host.has_method("publish_original_source_admission_scope") and host.has_method("claim_original_source_admission_scope") and host.has_method("poll_original_source_admission_scope") and host.has_method("finish_original_source_admission_scope"), "actual nonblocking scope interface registered")
	_check(not host.bind_original_source_admission_producer(wrong, actual_digest), "source admission producer exact path is enforced")
	var rejected: Dictionary = host.publish_original_source_admission_scope({"state":"PREPARED"})
	_check(rejected.status == "INVALID", "plain PREPARED flag cannot authorize source handoff")
	var written := _proof.write_receipt("multicore_main_source_boundary_20261014", _checks, _failures)
	print("MULTICORE_MAIN_SOURCE_BOUNDARY_", "PASS" if written and _failures == 0 else "FAIL")
	get_tree().quit(0 if written and _failures == 0 else 1)
