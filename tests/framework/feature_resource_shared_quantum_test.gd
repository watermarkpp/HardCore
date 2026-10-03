extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Preparation := preload("res://scripts/features/runtime/feature_resource_preparation.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const REGISTRY := "res://assets/data/features/validation/resource_world_registry.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var boxes: Array = []
var previous_completed := 0
var maximum_completions_per_epoch := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	process_priority = 10000
	_run.call_deferred()

func _process(_delta: float) -> void:
	var completed := 0
	for box: Dictionary in boxes:
		if box.finished: completed += 1
	maximum_completions_per_epoch = maxi(maximum_completions_per_epoch, completed - previous_completed)
	previous_completed = completed

func _capture(service: Node, catalog: Dictionary, box: Dictionary) -> void:
	box.result = await service.prepare(catalog, ["hc.resource_world_probe"])
	box.finished = true

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog(REGISTRY), "load legitimate disabled resource definitions without fetching a texture")
	var configuration := ContentLayers.feature_configuration()
	var path: String = GameData.get_item_art_path("hc.item.910007", "inventoryIcon")
	check(not ResourceLoader.has_cached(path), "shared cold requests begin without a loaded primary texture")
	var service := Preparation.new()
	add_child(service)
	for index in range(32):
		var box := {"finished":false,"result":{}}
		boxes.append(box)
		_capture(service, configuration.catalog, box)
	check(service.metrics().jobs == 1 and previous_completed == 0, "thirty-two real callers initially share one pending engine job")
	for index in range(240):
		if previous_completed == 32: break
		await get_tree().process_frame
	await get_tree().process_frame
	check(previous_completed == 32, "every shared caller completes without dropping or limiting accepted requests")
	check(maximum_completions_per_epoch <= 1, "a ready shared job delivers at most one caller per ordinary budget quantum")
	check(service.metrics().request_calls == 1 and service.metrics().get_calls == 1, "shared cold work acquires and retrieves exactly one physical engine request")
	var texture: Resource = null
	var all_ready := true
	var all_shared := true
	var refs: Array = []
	for box: Dictionary in boxes:
		if not box.finished or not bool(box.result.get("success", false)):
			all_ready = false
			continue
		var lease: RefCounted = box.result.lease
		refs.append(weakref(lease))
		if texture == null: texture = lease.resource_at(path)
		else: all_shared = all_shared and is_same(texture, lease.resource_at(path))
	check(all_ready and refs.size() == 32 and texture is Texture2D, "all independent callers own actual usable readiness leases")
	check(all_shared and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "shared leases refer to one texture after all engine retrieval rights finish")
	check(Budget.snapshot().open_scopes == 0, "completion continuations execute after the preparation scope closes")
	boxes.clear()
	texture = null
	for index in range(240):
		if service.pending_count() == 0: break
		await get_tree().process_frame
	var all_retired := true
	for ref: WeakRef in refs: all_retired = all_retired and ref.get_ref() == null
	check(all_retired and service.pending_count() == 0, "every caller lease retires and the real release queue drains")
	check(not service.is_processing() and Budget.snapshot().open_scopes == 0, "an idle resource owner leaves no recurring frame work or scope")
	var samples: Array = []
	for round_index in range(4):
		refs.clear()
		previous_completed = 0
		for index in range(32):
			var box := {"finished":false,"result":{}}
			boxes.append(box)
			_capture(service, configuration.catalog, box)
		for index in range(240):
			if previous_completed == 32: break
			await get_tree().process_frame
		check(previous_completed == 32 and maximum_completions_per_epoch <= 1, "repeat round %d delivers all thirty-two callers through bounded quanta" % round_index)
		var successful := true
		for box: Dictionary in boxes:
			successful = successful and bool(box.result.get("success", false))
			if box.result.get("lease") != null: refs.append(weakref(box.result.lease))
		check(successful and refs.size() == 32, "repeat round %d gives each caller a real readiness lease" % round_index)
		boxes.clear()
		for index in range(240):
			if service.pending_count() == 0: break
			await get_tree().process_frame
		await get_tree().process_frame
		var retired := true
		for ref: WeakRef in refs: retired = retired and ref.get_ref() == null
		check(retired and service.pending_count() == 0 and not service.is_processing(), "repeat round %d retires every lease and all owned work" % round_index)
		samples.append({"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)), "resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))})
	var stable := true
	for sample: Dictionary in samples: stable = stable and sample == samples[0]
	check(stable, "four identical released rounds retain the same observed object and resource counts")
	print("FEATURE_RESOURCE_FINITE_ROUNDS " + JSON.stringify(samples))
	check(ContentLayers.reload_feature_catalog(), "ordinary empty configuration remains restorable")
	service.queue_free()
	await get_tree().process_frame
	if not proof.write_receipt("feature_resource_shared_quantum_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_SHARED_QUANTUM_%s checks=%d max_completions=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, maximum_completions_per_epoch, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
