extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Catalog := preload("res://scripts/features/compilation/feature_catalog.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const REGISTRY := "res://assets/data/features/validation/resource_ready_registry.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _capture_reload(box: Dictionary) -> void:
	box.success = await ContentLayers.reload_feature_catalog_async(REGISTRY)
	box.finished = true

func _drain(service: Node) -> void:
	for index in range(120):
		if service.pending_count() == 0: return
		await get_tree().process_frame

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	check(await ContentLayers.reload_feature_catalog_async(REGISTRY), "initial formal producer readies primary resource")
	var configuration := ContentLayers.feature_configuration()
	var path: String = GameData.get_item_art_path("hc.item.910007", "inventoryIcon")
	var first: RefCounted = configuration.resource_lease
	var service: Node = ContentLayers._feature_resource_service
	var shared: Dictionary = await service.prepare(configuration.catalog, configuration.enabled_modules)
	check(shared.success and shared.lease.diagnostics().cache_hits == 1 and shared.lease.diagnostics().requested == 0, "warm preparation records real engine cache hit without another request")
	check(is_same(first.resource_at(path), shared.lease.resource_at(path)), "separate lawful leases share the same actual engine resource")
	var parent: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/features/validation/resource_ready_probe.json"))
	var child: Dictionary = parent.duplicate(true)
	child.module_id = "hc.resource_dependency_probe"
	child.mechanics[0].mechanic_id = "hc.resource_dependency_probe.accuracy"
	parent.requires = [child.module_id]
	var dependency_catalog := Catalog.new()
	check(dependency_catalog.publish([parent, child], [], configuration.authority), "two real compiled modules declare one shared required resource")
	var closed: Dictionary = await service.prepare(dependency_catalog.catalog(), [parent.module_id, child.module_id])
	check(closed.success and closed.lease.diagnostics().cache_hits == 1 and is_same(closed.lease.resource_at(path), first.resource_at(path)), "dependency closure deduplicates the actual shared path before resource acquisition")
	var incomplete: Dictionary = await service.prepare(dependency_catalog.catalog(), [parent.module_id])
	check(not incomplete.success and incomplete.errors == ["feature_disabled_dependency:hc.resource_ready_probe:hc.resource_dependency_probe"], "missing enabled dependency refuses preparation without implicit activation")
	closed = {}
	var module: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/features/validation/resource_ready_probe.json"))
	module.module_version = 2
	var newer := Catalog.new()
	check(newer.publish([module], [], configuration.authority), "second compiled candidate has a distinct valid revision")
	var wrong := configuration.duplicate(false)
	wrong.catalog = newer.catalog()
	check(not PlayerState._prepare_feature_configuration(wrong).success, "old readiness lease cannot authorize a new catalog revision")
	wrong = {}
	check(ContentLayers.reload_feature_catalog(), "old loadout is retired through ordinary empty publication")
	configuration = {}
	first = null
	await _drain(service)
	check(shared.lease.resource_at(path) is Texture2D and shared.lease.resource_at(path).get_width() > 0, "retiring one lease leaves the shared live holder usable")
	shared = {}
	await _drain(service)
	check(service.pending_count() == 0, "last shared owner drains budgeted retirements")
	var before := ContentLayers.feature_configuration()
	var bundle := PlayerState.feature_bundle()
	var stats := PlayerState.computed_stats.duplicate(true)
	# Pause the real tree so the asynchronous request is registered but its
	# ordinary process owner cannot advance. No engine mock or fake clock.
	get_tree().paused = true
	var cancelled := {"finished":false, "success":true}
	_capture_reload.call_deferred(cancelled)
	await get_tree().process_frame
	check(ContentLayers._feature_publication_in_progress and not cancelled.finished and service.pending_count() > 0, "paused preparation has a real pending request and no early success")
	check(is_same(ContentLayers.feature_configuration().catalog, before.catalog) and is_same(PlayerState.feature_bundle(), bundle) and PlayerState.computed_stats == stats, "old published state remains authoritative throughout pending preparation")
	ContentLayers.cancel_feature_resource_preparation()
	check(cancelled.finished and not cancelled.success, "explicit cancellation terminates the awaiting producer as failure")
	get_tree().paused = false
	await _drain(service)
	check(service.pending_count() == 0 and not ContentLayers._feature_publication_in_progress, "cancelled job and resource ownership fully drain after resume")
	check(is_same(ContentLayers.feature_configuration().catalog, before.catalog) and is_same(PlayerState.feature_bundle(), bundle), "cancelled candidate never replaces old configuration")
	get_tree().paused = true
	var stale := {"finished":false, "success":true}
	_capture_reload.call_deferred(stale)
	await get_tree().process_frame
	var profile: String = PlayerState.active_profile_id
	PlayerState.active_profile_id = "resource_scope_probe"
	get_tree().paused = false
	for index in range(120):
		if stale.finished: break
		await get_tree().process_frame
	check(stale.finished and not stale.success and ContentLayers.feature_load_errors == ["feature_resource_preparation_stale"], "changed profile identity prevents prepared candidate promotion")
	PlayerState.active_profile_id = profile
	await _drain(service)
	check(is_same(ContentLayers.feature_configuration().catalog, before.catalog) and is_same(PlayerState.feature_bundle(), bundle) and service.pending_count() == 0, "stale completion retires all resources and preserves old publication")
	check(Budget.snapshot().open_scopes == 0, "all lifecycle awaits occur outside frame budget scopes")
	var wrong_type := Resource.new()
	wrong_type.take_over_path(path)
	check(not await ContentLayers.reload_feature_catalog_async(REGISTRY) and ContentLayers.feature_load_errors == ["feature_resource_type_or_shape:" + path], "actual wrong cached resource type explicitly rejects preparation")
	check(is_same(ContentLayers.feature_configuration().catalog, before.catalog) and is_same(PlayerState.feature_bundle(), bundle), "resource validation failure never partially publishes")
	wrong_type = null
	await _drain(service)
	check(service.pending_count() == 0, "failed resource candidate retires its owned references")
	check(ContentLayers.reload_feature_catalog(), "fixture restores baseline")
	if not proof.write_receipt("feature_resource_lifecycle_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_LIFECYCLE_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
