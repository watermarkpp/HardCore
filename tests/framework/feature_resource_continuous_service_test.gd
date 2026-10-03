extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var keep_running := true
var completed := 0
var producers_finished := 0
var producer_errors := 0

func check(value: bool, label: String) -> void:
	proof.record(value,label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _producer(service: Node, catalog: Dictionary) -> void:
	while keep_running:
		var result: Dictionary = await service.prepare(catalog,["hc.resource_world_probe"])
		if not bool(result.success): producer_errors += 1
		completed += 1
		# Clearing the result releases its real readiness lease and enqueues one
		# legitimate retirement. Two live producers keep total input bounded.
		result.clear()
	producers_finished += 1

func _capture(box: Dictionary) -> void:
	box.success = await ContentLayers.reload_feature_catalog_async("res://assets/data/features/validation/resource_ready_registry.json")
	box.finished = true

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/resource_world_registry.json"), "register the existing legitimate disabled resource module")
	var catalog: Dictionary = ContentLayers.feature_configuration().catalog
	var service: Node = ContentLayers._feature_resources()
	_producer(service,catalog)
	_producer(service,catalog)
	var box := {"finished":false,"success":false}
	_capture(box)
	var peak_retirements := 0
	var first_ready_epoch := -1
	var completion_epoch := -1
	for index in range(180):
		await get_tree().process_frame
		peak_retirements = maxi(peak_retirements,int(service.metrics().retirements))
		if service.metrics().applications > 0 and first_ready_epoch < 0: first_ready_epoch = Engine.get_process_frames()
		if box.finished and completion_epoch < 0: completion_epoch = Engine.get_process_frames()
	check(completed >= 20 and producer_errors == 0 and producers_finished == 0, "two bounded lawful callers continue real successful prepare-release work throughout observation")
	check(box.finished and box.success and first_ready_epoch >= 0 and completion_epoch - first_ready_epoch <= 6, "ready formal publication receives service within six epochs while input continues")
	check(peak_retirements <= 6 and service.metrics().retirements <= 6, "continuous bounded producers cannot grow an unserviced resource retirement backlog")
	check(service.metrics().request_calls == 1 and service.metrics().get_calls == 1, "continuous shared readiness retains exactly one physical engine request and get")
	check(Budget.snapshot().open_scopes == 0, "continuing input never leaves an outer scope open across its awaits")
	keep_running = false
	for index in range(240):
		if producers_finished == 2 and service.pending_count() == 0: break
		await get_tree().process_frame
	check(producers_finished == 2 and service.pending_count() == 0 and not service.is_processing(), "stopping both producers drains legitimate jobs applications and retirements")
	check(ContentLayers.reload_feature_catalog(), "continuous fixture restores its original empty baseline")
	print("FEATURE_RESOURCE_CONTINUOUS_OBSERVATION " + JSON.stringify({"completed":completed,"peak_retirements":peak_retirements,"first_ready_epoch":first_ready_epoch,"completion_epoch":completion_epoch}))
	if not proof.write_receipt("feature_resource_continuous_service_test",checks,failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_CONTINUOUS_SERVICE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
