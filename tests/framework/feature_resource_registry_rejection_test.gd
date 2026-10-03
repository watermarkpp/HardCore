extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
const PACKAGE := "res://assets/data/features/validation/publication_registry.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

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
	var original: Dictionary = Registry.declarations()
	check(original.success, "production resource registry starts valid")
	check(ContentLayers.reload_feature_catalog(PACKAGE) and ContentLayers.set_feature_module_enabled("hc.publication_probe", true), "real resource-free package supplies an active old configuration")
	var old := ContentLayers.feature_configuration()
	var bundle := PlayerState.feature_bundle()
	var stats := PlayerState.computed_stats.duplicate(true)
	var compile_count: int = PlayerState._feature_loadout.compile_count
	var notices := {"count":0}
	var observe := func() -> void: notices.count += 1
	ContentLayers.feature_catalog_changed.connect(observe)
	# Inject the exact cached result of a failed declaration reader. This is a
	# controlled service-boundary counterexample, not a corrupted shipped file.
	Registry._result = {"success":false,"records":{},"errors":["feature_resource_registry_invalid"]}
	check(not ContentLayers.reload_feature_catalog(PACKAGE), "synchronous resource-free candidate rejects a failed resource authority")
	check(ContentLayers.feature_load_errors == ["feature_resource_registry_invalid"], "publication propagates the original declaration failure")
	check(is_same(ContentLayers.feature_configuration().catalog, old.catalog) and is_same(PlayerState.feature_bundle(), bundle)
		and PlayerState.computed_stats == stats and PlayerState._feature_loadout.compile_count == compile_count and notices.count == 0,
		"declaration failure preserves effective catalog bundle stats compilation and notifications")
	check(not await ContentLayers.reload_feature_catalog_async(PACKAGE), "asynchronous resource-free publication also rejects failed declarations")
	check(is_same(ContentLayers.feature_configuration().catalog, old.catalog) and is_same(PlayerState.feature_bundle(), bundle) and notices.count == 0,
		"failed asynchronous reader never replaces the old configuration")
	Registry._result = original
	ContentLayers.feature_catalog_changed.disconnect(observe)
	check(ContentLayers.reload_feature_catalog(), "restored legitimate reader retains the original empty-resource publication")
	if not proof.write_receipt("feature_resource_registry_rejection_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_REGISTRY_REJECTION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
