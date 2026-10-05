extends Node

# Candidate only: three independent scenes set this serialized mode. No CLI mode.
@export_enum("inputs_wrong_scope", "inputs_null_publisher", "catalogue_wrong_scope") var case_mode: String = "inputs_wrong_scope"
@export var receipt_scene_id: String = ""

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const OverlayScript := preload("res://scripts/loading_transition_overlay.gd")
const Scope := preload("res://scripts/features/contracts/loading_preparation_scope.gd")
const Data := preload("res://scripts/features/generated/internal_code_preparation_catalog_data.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const ENTRY_ID := "framework.code.caster_animation.v1"
const TARGET_SCRIPT := "res://scripts/caster_skill_animation_player.gd"
const DIAGNOSTIC_PROCESS_FRAMES := 4
const SCENE_IDS := {
	"inputs_wrong_scope": "code_preparation_wrong_scope_test",
	"inputs_null_publisher": "code_preparation_null_publisher_test",
	"catalogue_wrong_scope": "code_catalogue_wrong_scope_test",
}

var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var observation: Dictionary = {"phase": "setup"}

class Consumer extends Control:
	var generation := 1
	var loading_phase := true
	func is_code_preparation_generation_current(value: int) -> bool:
		return value == generation
	func is_code_preparation_loading_phase_current(value: int) -> bool:
		return loading_phase and value == generation

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _owner_snapshot(service: Node) -> Dictionary:
	# Read the actual owner's existing scalars/maps. No cache query, job pump,
	# reset, second loader, or Budget.snapshot() (which calls _sync_epoch()).
	return {
		"process_frame": Engine.get_process_frames(),
		"next_request": int(service.get("_next_request")),
		"requests": (service.get("_requests") as Dictionary).size(),
		"jobs": (service.get("_jobs") as Dictionary).size(),
		"applications": (service.get("_applications") as Dictionary).size(),
		"work": (service.get("_work") as Dictionary).size(),
		"retirements": (service.get("_retirements") as Dictionary).size(),
		"apply_tail": int(service.get("_apply_tail")),
		"request_calls": int(service.get("_request_calls")),
		"get_calls": int(service.get("_get_calls")),
		"applying_request": int(service.get("_applying_request")),
		"quantum_active": bool(service.get("_quantum_active")),
		"open_budget_scopes": Budget._stack.size(),
		"publication_pending": bool(ContentLayers.get("_internal_code_publication_pending")),
		"publication_sequence": int(ContentLayers.get("_feature_preparation_sequence")),
		"published_entries": (ContentLayers.get("_internal_code_entries") as Dictionary).size(),
	}

func _unchanged_owner(before: Dictionary, after: Dictionary) -> bool:
	for field: String in ["next_request", "requests", "jobs", "applications", "work", "retirements", "apply_tail", "request_calls", "get_calls", "applying_request", "quantum_active", "publication_pending", "publication_sequence", "published_entries"]:
		if before[field] != after[field]:
			return false
	return true

func _invoke_once(service: Node, payload: Dictionary, supplied_scope: RefCounted, publisher: Node, consumer: Node, generation: int, holder: Dictionary) -> void:
	holder["started"] = true
	holder["call_process_frame"] = Engine.get_process_frames()
	# A faulty await is confined to this helper. The outer observer never awaits
	# this helper or its completion. Godot errors remain in the native raw log.
	if case_mode == "catalogue_wrong_scope":
		holder["result"] = await ContentLayers.ensure_internal_code_catalogue_async(supplied_scope, consumer, generation)
	else:
		holder["result"] = await service.prepare_code_inputs(payload, ENTRY_ID, publisher, supplied_scope, consumer, generation)
	holder["done"] = true
	holder["return_process_frame"] = Engine.get_process_frames()

func _run() -> void:
	PlayerState.test_mode = false
	check(not PlayerState.test_mode, "fixture retains non-test production runtime setting")
	var appdata := OS.get_environment("APPDATA").replace("\\", "/")
	check(appdata.contains("/.godot/runtime_appdata/") and not OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID").is_empty(), "formal runner isolates APPDATA and binds run identity")
	check(not OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID").is_empty() and not OS.get_environment("HARDCORE_R3_CONTENT_SHA256").is_empty(), "receipt binds invocation and exact tested source content")
	check(SCENE_IDS.has(case_mode), "serialized scene selects one explicit API shape counterexample")
	check(receipt_scene_id == scene_file_path.get_file().get_basename() and SCENE_IDS.get(case_mode, "") == receipt_scene_id, "each standalone scene binds its exact basename, receipt scene ID and serialized mode")
	check(not ResourceLoader.has_cached(TARGET_SCRIPT), "fixture stores the registered target only as its cold String path")
	var ready := ContentLayers.has_method("_feature_resources") and ContentLayers.has_method("ensure_internal_code_catalogue_async")
	check(ready, "existing ContentLayers owns the only preparation service and catalogue API")
	if not ready or not SCENE_IDS.has(case_mode):
		_finish()
		return
	var consumer := Consumer.new()
	add_child(consumer)
	var overlay: Control = OverlayScript.new()
	consumer.add_child(overlay)
	overlay.begin_loading("api.shape." + case_mode)
	await overlay.transition_covered
	var cover: Dictionary = overlay.code_preparation_cover_receipt()
	check(not cover.is_empty() and overlay.code_preparation_cover_current(cover), "formal Overlay covered handshake provides its actual current presentation witness")
	var valid_scope: RefCounted = Scope.issue(overlay, consumer, consumer.generation)
	var scope_valid := valid_scope != null and is_same(valid_scope.get_script(), Scope) and bool(valid_scope.valid_for(consumer, consumer.generation))
	check(scope_valid, "Scope.issue supplies the exact contract for this live covered consumer generation")
	var bundle := Data.read_bundle()
	var entry_value: Variant = bundle.get("entries", {}).get(ENTRY_ID)
	check(entry_value is Dictionary, "entry payload comes directly from the existing generated Data entry")
	if not scope_valid or not entry_value is Dictionary:
		_finish()
		return
	var payload: Dictionary = entry_value
	check(Data.REGISTERED_TARGETS.get(ENTRY_ID) == TARGET_SCRIPT and payload.get("target_path") == TARGET_SCRIPT and payload.get("status") == "PASS" and payload.get("errors") == [], "unmodified generated payload binds the supported registered target and passing producer")
	check(payload.get("producer_id") == "hc.code_preparation.lexical_subset.candidate.v1" and payload.get("scope") == "supported_gdscript_compile_inputs" and payload.get("nodes") is Dictionary and payload.get("edges") is Array and payload.get("prepared_inputs") is Array, "correct generated envelope retains its producer, scope and graph shape")
	check(is_same(get_tree().root.get_node_or_null("ContentLayers"), ContentLayers) and ContentLayers.is_inside_tree() and not ContentLayers.is_queued_for_deletion() and ContentLayers.get_script().resource_path == "res://scripts/layers/runtime/content_layer_registry.gd", "legitimate publisher is the actual live formal ContentLayers autoload")
	# Obtains the existing ContentLayers-owned instance once; never .new() a
	# service, rewrite publication, or perform a positive target resource load.
	var service: Node = ContentLayers._feature_resources()
	check(is_instance_valid(service) and is_same(ContentLayers.get("_feature_resource_service"), service) and service.has_method("prepare_code_inputs"), "one existing production service owns the counterexample")
	if not failures.is_empty() or not is_instance_valid(service):
		_finish()
		return
	var before := _owner_snapshot(service)
	check(before.requests == 0 and before.jobs == 0 and before.applications == 0 and before.work == 0 and before.retirements == 0 and not before.quantum_active and before.applying_request == 0 and not before.publication_pending, "isolated call starts with no pre-existing service or publication work")
	check(before.open_budget_scopes == 0, "no budget scope is open before the public entry")
	if not failures.is_empty():
		observation["before"] = before
		_finish()
		return
	var wrong_scope := RefCounted.new()
	var supplied_scope: RefCounted = valid_scope if case_mode == "inputs_null_publisher" else wrong_scope
	var publisher: Node = null if case_mode == "inputs_null_publisher" else ContentLayers
	check(not is_same(wrong_scope.get_script(), Scope) and not wrong_scope.has_method("valid_for"), "wrong scope is an ordinary RefCounted with no forged contract method")
	check(is_instance_valid(consumer) and consumer.is_inside_tree() and not consumer.is_queued_for_deletion() and bool(valid_scope.valid_for(consumer, consumer.generation)), "call-time consumer and genuine issued scope remain live and covered")
	check((case_mode == "inputs_null_publisher" and publisher == null and is_same(supplied_scope, valid_scope)) or (case_mode != "inputs_null_publisher" and is_same(publisher, ContentLayers) and is_same(supplied_scope, wrong_scope)), "only the selected API shape field differs from the covered input setup")
	var holder: Dictionary = {"started": false, "done": false, "result": null, "call_process_frame": -1, "return_process_frame": -1}
	observation = {
		"phase": "counterexample", "mode": case_mode, "diagnostic_process_frames": DIAGNOSTIC_PROCESS_FRAMES,
		"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
		"invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"native_process_id": OS.get_process_id(), "entry_id": ENTRY_ID,
		"payload_plan_sha256": JSON.stringify(payload, "", true).sha256_text(),
		"consumer_id": consumer.get_instance_id(), "service_id": service.get_instance_id(),
		"before": before, "samples": [], "positive_resource_load": "NOT_RUN",
	}
	_invoke_once(service, payload, supplied_scope, publisher, consumer, consumer.generation, holder)
	observation.samples.append(_owner_snapshot(service))
	# Exactly four real process-frame signals, with a snapshot after each.
	# This is a bounded shape diagnostic, not a service completion deadline.
	for _frame in range(DIAGNOSTIC_PROCESS_FRAMES):
		await get_tree().process_frame
		observation.samples.append(_owner_snapshot(service))
	var after: Dictionary = observation.samples[-1]
	observation["holder"] = holder.duplicate(true)
	observation["catalogue_errors"] = ContentLayers.internal_code_errors.duplicate()
	observation["actual_frame_advance"] = int(after.process_frame) - int(before.process_frame)
	check(holder.started and holder.done, "public entry returns a terminal business result within the bounded observer")
	if case_mode == "catalogue_wrong_scope":
		check(holder.done and holder.result is bool and holder.result == false and ContentLayers.internal_code_errors == ["internal_code_publication_loading_scope_unavailable"], "wrong catalogue scope produces explicit business refusal rather than an error default return")
	else:
		var result: Dictionary = holder.result if holder.result is Dictionary else {}
		check(holder.done and result.get("success") is bool and result.get("success") == false and result.get("errors") == ["code_preparation_owner_or_capacity"] and result.has("lease") and result.lease == null, "bad input shape returns the explicit existing refusal envelope with no lease")
	var unchanged := true
	var closed := true
	for sample: Dictionary in observation.samples:
		unchanged = unchanged and _unchanged_owner(before, sample)
		closed = closed and sample.open_budget_scopes == 0
	check(unchanged, "rejection allocates no request ID, queue item, job, publication or native request/get token at any captured boundary")
	check(closed, "business rejection leaves the actual budget stack closed at every captured boundary")
	check(int(after.process_frame) - int(before.process_frame) == DIAGNOSTIC_PROCESS_FRAMES and observation.samples.size() == DIAGNOSTIC_PROCESS_FRAMES + 1, "diagnostic samples cover exactly four actual process frames plus immediate admission")
	check(bool(valid_scope.valid_for(consumer, consumer.generation)), "legitimate issued scope remains current; observer never retires the consumer to force refusal")
	check(not ResourceLoader.has_cached(TARGET_SCRIPT), "shape refusal leaves the real target Script cold")
	# Preserve faulty requests/scopes in the observation. Do not cancel, drain,
	# reset budget state, or suppress the native error before writing the FAIL.
	_finish()

func _finish() -> void:
	var scene_id := scene_file_path.get_file().get_basename()
	print("CODE_PREPARATION_API_SHAPE_OBSERVATION ", JSON.stringify(observation))
	var valid := proof.write_receipt(scene_id, checks, failures.size())
	var passed := valid and failures.is_empty()
	print("CODE_PREPARATION_API_SHAPE_%s scene=%s mode=%s checks=%d failures=%s" % ["PASS" if passed else "FAIL", scene_id, case_mode, checks, str(failures)])
	get_tree().quit(0 if passed else 1)
