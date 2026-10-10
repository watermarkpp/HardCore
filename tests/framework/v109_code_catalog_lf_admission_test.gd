extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Catalogue := preload("res://scripts/features/generated/internal_code_preparation_catalog_data.gd")
const Overlay := preload("res://scripts/loading_transition_overlay.gd")
const Guard := preload("res://scripts/features/compilation/code_preparation_envelope_guard.gd")
const ENTRY := "framework.code.caster_animation.v1"
const LF_PATHS := [
	"res://assets/shaders/trial_magic_screen.gdshader",
	"res://assets/shaders/fire_wall_screen_blend_multiply.gdshader",
	"res://scripts/identity/entity_registry.gd",
	"res://scripts/features/contracts/plain_graph.gd",
]

class Consumer extends Control:
	var generation := 1
	func is_code_preparation_generation_current(value: int) -> bool:
		return generation == value
	func is_code_preparation_loading_phase_current(value: int) -> bool:
		return generation == value
	func _exit_tree() -> void:
		ContentLayers.cancel_internal_code_owner(self, generation)

var proof := Proof.new()
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	proof.record(ok, label)
	if not ok:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var bundle := Catalogue.read_bundle()
	var entry: Dictionary = bundle.get("entries", {}).get(ENTRY, {})
	check(not entry.is_empty(), "formal generated catalogue contains the registered entry")
	for path: String in LF_PATHS:
		var raw := FileAccess.get_file_as_bytes(path)
		check(not raw.get_string_from_utf8().contains("\r\n"), "actual input is repository LF: " + path)
		var record: Dictionary = entry.get("nodes", {}).get(path, {})
		check(not record.is_empty() and int(record.get("bytes", -1)) == raw.size() and str(record.get("sha256", "")) == FileAccess.get_sha256(path), "formal source fingerprint exactly matches actual LF bytes: " + path)
		check(Guard._checkout_bytes_match_fingerprint(raw.get_string_from_utf8().replace("\n", "\r\n").to_utf8_buffer(), record), "same canonical content admits CRLF checkout bytes: " + path)
	var consumer := Consumer.new()
	add_child(consumer)
	var overlay: Control = Overlay.new()
	consumer.add_child(overlay)
	overlay.begin_loading("v109.catalogue.lf")
	await overlay.transition_covered
	var prepared: Dictionary = await ContentLayers.prepare_internal_code_entry(ENTRY, overlay, consumer, consumer.generation)
	check(bool(prepared.get("success", false)), "actual ContentLayers publication and source envelope admit LF inputs")
	if bool(prepared.get("success", false)):
		var lease: RefCounted = prepared.get("lease")
		var plan: RefCounted = prepared.get("plan")
		var result: Dictionary = await ContentLayers.request_internal_prepared_script(prepared, consumer, consumer.generation)
		var script: Script = result.get("resource") as Script
		check(bool(result.get("success", false)) and script != null and bool(plan.valid_target(script)), "actual registered target Script is requested and admitted")
		for path: String in plan.paths():
			var shader: Shader = lease.resource_at(path) as Shader
			check(shader != null and bool(plan.valid_asset(path, shader)), "actual shader lease validates normalized source: " + path)
		ContentLayers.retire_internal_code_result(prepared)
	consumer.queue_free()
	await get_tree().process_frame
	check(ContentLayers._feature_resources().pending_code_count() == 0, "original preparation owner has no pending code job after retirement")
	var valid := proof.write_receipt("v109_code_catalog_lf_admission_test", proof.records.size(), failures.size())
	print("V109_CODE_CATALOG_LF_ADMISSION_", "PASS" if failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if valid and failures.is_empty() else 1)
