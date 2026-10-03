extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const BASE := "res://assets/data/features/validation/"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var notifications := 0
var reenter := false
var nested_result := true
var nested_reload_result := true
var coherent_observer := true
var base_accuracy := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _observe_publication() -> void:
	notifications += 1
	if reenter:
		reenter = false
		coherent_observer = ContentLayers.feature_configuration().enabled_modules.has("hc.publication_probe") \
			and int(PlayerState.computed_stats.accuracy) == base_accuracy + 3 \
			and PlayerState.feature_bundle().sources.size() == 1
		nested_reload_result = ContentLayers.reload_feature_catalog()
		nested_result = ContentLayers.set_feature_module_enabled("hc.publication_probe", false)

func _unchanged(configuration: Dictionary, bundle: Dictionary, stats: Dictionary, count: int) -> bool:
	var current := ContentLayers.feature_configuration()
	return is_same(current.catalog, configuration.catalog) and current.enabled_modules == configuration.enabled_modules \
		and is_same(PlayerState.feature_bundle(), bundle) and PlayerState.computed_stats == stats \
		and PlayerState._feature_loadout.compile_count == count

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog(BASE + "publication_invalid_range_registry.json"), "inactive schema-valid package may register")
	var before := ContentLayers.feature_configuration()
	var bundle := PlayerState.feature_bundle()
	var stats := PlayerState.computed_stats.duplicate(true)
	var count: int = PlayerState._feature_loadout.compile_count
	ContentLayers.feature_catalog_changed.connect(_observe_publication)
	check(not ContentLayers.set_feature_module_enabled("hc.publication_invalid_range", true), "actual player inverted range is refused before enabling")
	check(_unchanged(before, bundle, stats, count), "failed enable preserves directory, enabled set, actual player and compile generation")
	check(notifications == 0 and PlayerState.feature_errors.is_empty(), "failed candidate emits no publication and does not poison the old player")
	check(ContentLayers.reload_feature_catalog(), "return to baseline after failed candidate")
	check(ContentLayers.reload_feature_catalog(BASE + "publication_invalid_skill_registry.json"), "inactive schema-valid skill contribution may register")
	before = ContentLayers.feature_configuration()
	bundle = PlayerState.feature_bundle()
	stats = PlayerState.computed_stats.duplicate(true)
	count = PlayerState._feature_loadout.compile_count
	check(not ContentLayers.set_feature_module_enabled("hc.publication_invalid_skill", true), "actual negative skill cost is rejected before enabling")
	check(_unchanged(before, bundle, stats, count) and PlayerState.feature_errors.is_empty(), "invalid effective skill preserves the old complete player publication")
	check(ContentLayers.reload_feature_catalog(), "return to baseline after invalid skill candidate")
	before = ContentLayers.feature_configuration()
	bundle = PlayerState.feature_bundle()
	stats = PlayerState.computed_stats.duplicate(true)
	count = PlayerState._feature_loadout.compile_count
	var old_notifications := notifications
	check(not ContentLayers.reload_feature_catalog(BASE + "publication_invalid_default_registry.json"), "default-on invalid actor range is refused before directory replacement")
	check(_unchanged(before, bundle, stats, count) and notifications == old_notifications, "failed reload preserves the complete old publication")
	check(ContentLayers.reload_feature_catalog(BASE + "publication_registry.json"), "valid new package remains available after failed reload")
	base_accuracy = int(PlayerState.computed_stats.accuracy)
	reenter = true
	check(ContentLayers.set_feature_module_enabled("hc.publication_probe", true), "valid actor candidate publishes")
	check(coherent_observer, "every observer sees matching directory and effective actor contribution")
	check(not nested_result, "observer cannot reenter an unfinished publication")
	check(not nested_reload_result, "observer cannot reload the directory during publication")
	check(ContentLayers.feature_configuration().enabled_modules == ["hc.publication_probe"] \
		and int(PlayerState.computed_stats.accuracy) == base_accuracy + 3, "reentrant attempt cannot replace the accepted candidate")
	check(ContentLayers.set_feature_module_enabled("hc.publication_probe", false), "subsequent independent disable remains legal")
	ContentLayers.feature_catalog_changed.disconnect(_observe_publication)
	check(ContentLayers.reload_feature_catalog() and PlayerState.feature_errors.is_empty(), "baseline restored without feature errors")
	if not proof.write_receipt("feature_publication_atomic_test", checks, failures.size()):
		failures.append("receipt")
	print(("FRAMEWORK_FEATURE_PUBLICATION_ATOMIC_PASS" if failures.is_empty() else "FRAMEWORK_FEATURE_PUBLICATION_ATOMIC_FAIL") \
		+ " checks=" + str(checks) + " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
