extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const REGISTRY := "res://assets/data/features/validation/publication_registry.json"
var proof := Proof.new()
var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	check(PlayerState.feature_errors.is_empty(), "existing production catalog starts valid")
	var initial := ContentLayers.feature_configuration()
	var old_bundle := PlayerState.feature_bundle()
	var base_accuracy := int(PlayerState.computed_stats.accuracy)
	var accepts_registry := false
	for method: Dictionary in ContentLayers.get_script().get_script_method_list():
		if method.name == "reload_feature_catalog" and method.args.size() == 1:
			accepts_registry = true
	# RED must produce a normal failed receipt, not an invalid-method engine error.
	check(accepts_registry, "formal authoring registry can introduce a new package without a core path edit")
	if accepts_registry:
		check(bool(ContentLayers.call("reload_feature_catalog", REGISTRY)), "real new JSON module publishes through ContentLayers")
		var loaded := ContentLayers.feature_configuration()
		check(loaded.catalog.modules.has("hc.publication_probe") and loaded.enabled_modules.is_empty(), "new package is registered but stays default off")
		check(PlayerState.feature_errors.is_empty() and int(PlayerState.computed_stats.accuracy) == base_accuracy,
			"loading an inactive package preserves actual player stats")
		check(ContentLayers.set_feature_module_enabled("hc.publication_probe", true), "activate registered package through the real service")
		check(PlayerState.feature_errors.is_empty() and int(PlayerState.computed_stats.accuracy) == base_accuracy + 3,
			"PlayerState applies the new declared contribution exactly once")
		check(PlayerState.feature_bundle().sources.size() == 1, "new contribution has one qualified source")
		var accepted := ContentLayers.feature_configuration()
		var accepted_bundle := PlayerState.feature_bundle()
		for path: String in ["user://publication_registry.json", "res://assets/data/features/../module_registry.json",
			"res://assets/data/features/validation/publication_registry.gd", "res://assets/data/features/validation/missing.json",
			"res://assets/data/features/validation/publication_invalid_path.json",
			"res://assets/data/features/validation/publication_invalid_identity.json",
			"res://assets/data/features/validation/publication_duplicate.json",
			"res://assets/data/features/validation/publication_missing_module.json"]:
			check(not bool(ContentLayers.call("reload_feature_catalog", path)), "reject non-authoring or absent registry: " + path)
			check(is_same(accepted.catalog, ContentLayers.feature_configuration().catalog)
				and is_same(accepted_bundle, PlayerState.feature_bundle()) and int(PlayerState.computed_stats.accuracy) == base_accuracy + 3,
				"failed registry leaves current catalog, source and actual player state intact: " + path)
		check(ContentLayers.set_feature_module_enabled("hc.publication_probe", false), "disable withdraws only the new grant")
		check(int(PlayerState.computed_stats.accuracy) == base_accuracy and PlayerState.feature_bundle().sources.is_empty(), "real player returns to the unchanged base")
		check(ContentLayers.reload_feature_catalog(), "original default registry remains valid")
		check(ContentLayers.feature_configuration().catalog.revision == initial.catalog.revision,
			"restoring default registry retains its exact original content identity")
	else:
		check(is_same(initial.catalog, ContentLayers.feature_configuration().catalog) and is_same(old_bundle, PlayerState.feature_bundle()),
			"unsupported publication attempt did not mutate the existing baseline")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("feature_registry_publication_test", checks, failures.size()):
		failures.append("receipt")
	print(("FRAMEWORK_FEATURE_REGISTRY_PUBLICATION_PASS" if failures.is_empty() else "FRAMEWORK_FEATURE_REGISTRY_PUBLICATION_FAIL")
		+ " checks=" + str(checks) + " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
