extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const REGISTRY := "res://assets/data/features/validation/resource_ready_registry.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value,label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _capture(box: Dictionary) -> void:
	box.success = await ContentLayers.reload_feature_catalog_async(REGISTRY)
	box.resume_scopes = Budget.snapshot().open_scopes
	box.finished = true

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	var before := ContentLayers.feature_configuration()
	var stats := PlayerState.computed_stats.duplicate(true)
	var bundle := PlayerState.feature_bundle()
	var observer := {"calls":0}
	var observe := func() -> void: observer.calls += 1
	ContentLayers.feature_catalog_changed.connect(observe)
	for mode: String in ["formal", "service"]:
		var box := {"success":true,"finished":false,"resume_scopes":-1}
		_capture(box)
		var service: Node = ContentLayers._feature_resource_service
		for frame in range(180):
			if int(service.metrics().applications) > 0 or box.finished: break
			await get_tree().process_frame
		check(not box.finished and int(service.metrics().applications) == 1 and not service.is_applying(), mode + " real resources ready with application queued before callback starts")
		if mode == "formal": ContentLayers.cancel_feature_resource_preparation()
		else: service.cancel_all()
		check(box.finished and not box.success and int(box.resume_scopes) == 0, mode + " queued cancellation rejects once outside scope")
		check(not ContentLayers._feature_publication_in_progress, mode + " rejected application retires outer publication ownership")
		check(is_same(before.catalog,ContentLayers.feature_configuration().catalog) and is_same(bundle,PlayerState.feature_bundle()) and stats == PlayerState.computed_stats and observer.calls == 0, mode + " cancelled candidate never mutates directory actor or notification")
		check(ContentLayers.reload_feature_catalog(), mode + " next lawful publication is not permanently locked")
		# Restoration publishes a fresh equivalent catalog; capture its identity
		# before checking the next independent cancelled candidate.
		before = ContentLayers.feature_configuration()
		bundle = PlayerState.feature_bundle()
		observer.calls = 0
		for frame in range(180):
			if service.pending_count() == 0: break
			await get_tree().process_frame
		check(service.pending_count() == 0 and Budget.snapshot().open_scopes == 0, mode + " stale callback and resources reach terminal drain")
	ContentLayers.feature_catalog_changed.disconnect(observe)
	check(await ContentLayers.reload_feature_catalog_async(REGISTRY), "fresh asynchronous producer succeeds after both cancellation paths")
	check(ContentLayers.reload_feature_catalog(), "fixture restores original configuration")
	if not proof.write_receipt("feature_resource_queued_cancel_test",checks,failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_QUEUED_CANCEL_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
