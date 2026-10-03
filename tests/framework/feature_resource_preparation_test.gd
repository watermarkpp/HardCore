extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const REGISTRY := "res://assets/data/features/validation/resource_ready_registry.json"
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
var proof := Proof.new()
var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	var old := ContentLayers.feature_configuration()
	var old_bundle := PlayerState.feature_bundle()
	var old_stats := PlayerState.computed_stats.duplicate(true)
	var path: String = GameData.get_item_art_path({"item_id":910007}, "inventoryIcon")
	check(ResourceLoader.exists(path) and not ResourceLoader.has_cached(path), "cold test begins with real primary icon uncached")
	check(ContentLayers.has_method("reload_feature_catalog_async"), "formal publication has a resource preparation entry")
	if ContentLayers.has_method("reload_feature_catalog_async"):
		check(not ContentLayers.reload_feature_catalog(REGISTRY), "synchronous publication refuses nonempty resources without preparing them")
		check(is_same(ContentLayers.feature_configuration().catalog, old.catalog) and is_same(PlayerState.feature_bundle(), old_bundle) and PlayerState.computed_stats == old_stats, "unprepared publication retains the entire old effective configuration")
		var application := {"open_scopes":0}
		var observe := func() -> void: application.open_scopes = Budget.snapshot().open_scopes
		ContentLayers.feature_catalog_changed.connect(observe)
		var result: bool = await ContentLayers.reload_feature_catalog_async(REGISTRY)
		ContentLayers.feature_catalog_changed.disconnect(observe)
		check(result, "formal asynchronous publication loads the real icon before promoting the candidate")
		check(int(application.open_scopes) > 0, "ready candidate validation application and synchronous observers are included in shared frame accounting")
		check(Budget.snapshot().open_scopes == 0, "publication completes with no scope held across await")
		var configuration := ContentLayers.feature_configuration()
		var lease: RefCounted = configuration.get("resource_lease")
		check(lease != null and lease.resource_at(path) is Texture2D and lease.resource_at(path).get_width() > 0 and lease.resource_at(path).get_height() > 0, "promoted configuration owns a usable real texture")
		check(int(PlayerState.computed_stats.accuracy) == int(old_stats.accuracy) + 1, "ready resource and real rule contribution publish in one configuration")
		check(lease != null and is_same(PlayerState._feature_loadout.resource_lease(), lease), "effective loadout owns the same readiness lease")
		var prepared: Dictionary = PlayerState._prepare_feature_configuration(configuration)
		check(prepared.get("success", false), "exact ready lease admits the actual player candidate")
		var invalid := configuration.duplicate(false)
		invalid.erase("resource_lease")
		check(not PlayerState._prepare_feature_configuration(invalid).get("success", false), "removing readiness ownership refuses an otherwise valid nonempty candidate")
		check(ContentLayers.reload_feature_catalog(), "empty baseline restores through the original synchronous path")
		check(lease.resource_at(path) is Texture2D, "retiring the published configuration does not invalidate another lawful holder")
		print("FEATURE_RESOURCE_PREPARED " + JSON.stringify(lease.diagnostics()))
	if not proof.write_receipt("feature_resource_preparation_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_PREPARATION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
