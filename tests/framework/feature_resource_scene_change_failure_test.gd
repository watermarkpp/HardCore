extends Node
## S3 scene-change immediate failure (fixed baseline 272430b36+).
## A scene change must fail every outstanding feature-resource preparation the
## moment the service observes it: the requesting world is gone, so no queued
## job may keep loading and no prepared candidate may promote into a different
## scene. Code-publication/handoff requests keep their own cross-scene
## retention contract and are NOT part of this proof.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const REGISTRY := "res://assets/data/features/validation/resource_ready_registry.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _capture_prepare(box: Dictionary, configuration: Dictionary) -> void:
	var result: Dictionary = await ContentLayers._feature_resource_service.prepare(configuration.catalog, configuration.enabled_modules)
	box.success = bool(result.success)
	box.errors = result.get("errors", [])
	box.finished = true

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	check(await ContentLayers.reload_feature_catalog_async(REGISTRY), "formal resource-backed catalog published")
	var configuration: Dictionary = ContentLayers.feature_configuration()
	var service: Node = ContentLayers._feature_resource_service
	var bundle: Dictionary = PlayerState.feature_bundle()
	var original_scene: Node = get_tree().current_scene
	# Park the real service (paused tree) so the preparation is registered but
	# cannot advance; then change the scene under it.
	get_tree().paused = true
	var pending := {"finished":false, "success":true, "errors":PackedStringArray()}
	_capture_prepare.call_deferred(pending, configuration)
	await get_tree().process_frame
	check(not pending.finished and service.pending_count() > 0,
		"real feature-resource preparation is pending before the scene change")
	var successor := Node.new(); successor.name = "SceneChangeSuccessor"
	get_tree().root.add_child(successor)
	get_tree().current_scene = successor
	get_tree().paused = false
	for index in range(240):
		if pending.finished and service.pending_count() == 0: break
		await get_tree().process_frame
	check(pending.finished and not pending.success and PackedStringArray(pending.errors) == PackedStringArray(["feature_resource_scene_changed"]),
		"the scene change fails the outstanding preparation immediately with an explicit reason")
	check(service.pending_count() == 0 and not ContentLayers._feature_publication_in_progress,
		"no job, retirement or application outlives the failed request")
	check(is_same(PlayerState.feature_bundle(), bundle) and is_same(ContentLayers.feature_configuration().catalog, configuration.catalog),
		"the failed candidate never publishes into the successor scene")
	check(ContentLayers.feature_load_errors.is_empty(), "an immediate scene-change failure is not a feature load error")
	# Restore the runner scene and prove the service still prepares normally
	# for the restored scene (the failure is an epoch check, not a poison state).
	get_tree().current_scene = original_scene
	successor.queue_free()
	var healthy: Dictionary = await service.prepare(configuration.catalog, configuration.enabled_modules)
	check(healthy.success and healthy.lease != null, "a fresh preparation in the restored scene still succeeds")
	healthy.lease = null
	for index in range(120):
		if service.pending_count() == 0: break
		await get_tree().process_frame
	check(service.pending_count() == 0, "the healthy request drains without residue")
	check(proof.write_receipt("feature_resource_scene_change_failure_test", checks, failures.size()), "receipt")
	print(("RESOURCE_SCENE_CHANGE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)]))
	get_tree().quit(0 if failures.is_empty() else 1)
