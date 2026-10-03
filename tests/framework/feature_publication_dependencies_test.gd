extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const BASE := "res://assets/data/features/validation/"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var notifications := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _observe() -> void:
	notifications += 1

func unchanged(before: Dictionary, bundle: Dictionary, stats: Dictionary, count: int) -> bool:
	var current := ContentLayers.feature_configuration()
	return is_same(current.catalog, before.catalog) and current.enabled_modules == before.enabled_modules \
		and is_same(PlayerState.feature_bundle(), bundle) and PlayerState.computed_stats == stats \
		and PlayerState._feature_loadout.compile_count == count

func finish(scene_id: String) -> void:
	ContentLayers.feature_catalog_changed.disconnect(_observe)
	if not proof.write_receipt(scene_id, checks, failures.size()): failures.append("receipt")
	print(scene_id.to_upper() + ("_PASS" if failures.is_empty() else "_FAIL") + " checks=" + str(checks) + " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog(), "baseline prepared")
	var base_accuracy: int = PlayerState.computed_stats.accuracy
	var before := ContentLayers.feature_configuration()
	var bundle := PlayerState.feature_bundle()
	var stats := PlayerState.computed_stats.duplicate(true)
	var count: int = PlayerState._feature_loadout.compile_count
	ContentLayers.feature_catalog_changed.connect(_observe)
	check(not ContentLayers.reload_feature_catalog(BASE + "dependency_invalid_default_registry.json"), "default A cannot publish while required B is disabled")
	check(unchanged(before, bundle, stats, count) and notifications == 0 and PlayerState.feature_errors.is_empty(), "invalid default dependency preserves complete old publication")
	check(not ContentLayers.feature_load_errors.is_empty(), "invalid enabled dependency has explicit diagnostic")
	check(ContentLayers.reload_feature_catalog(BASE + "dependency_valid_default_registry.json"), "default A and B with closed dependencies publish legally")
	check(ContentLayers.feature_configuration().enabled_modules.has("hc.dependency_a") and ContentLayers.feature_configuration().enabled_modules.has("hc.dependency_b") and int(PlayerState.computed_stats.accuracy) == base_accuracy + 4, "valid two default grants contribute exactly four accuracy")
	check(ContentLayers.reload_feature_catalog(BASE + "dependency_manual_registry.json"), "same definitions can register with neither enabled")
	before = ContentLayers.feature_configuration()
	bundle = PlayerState.feature_bundle()
	stats = PlayerState.computed_stats.duplicate(true)
	count = PlayerState._feature_loadout.compile_count
	var previous_notifications := notifications
	check(not ContentLayers.set_feature_module_enabled("hc.dependency_a", true), "manual A obeys same dependency rule")
	check(unchanged(before, bundle, stats, count) and notifications == previous_notifications, "manual failed dependency preserves old publication")
	check(ContentLayers.set_feature_module_enabled("hc.dependency_b", true), "explicitly enabling B remains legal")
	check(ContentLayers.set_feature_module_enabled("hc.dependency_a", true), "explicitly enabling A after B remains legal")
	check(int(PlayerState.computed_stats.accuracy) == base_accuracy + 4, "manual closed dependency gives same effective result as defaults")
	before = ContentLayers.feature_configuration()
	bundle = PlayerState.feature_bundle()
	stats = PlayerState.computed_stats.duplicate(true)
	count = PlayerState._feature_loadout.compile_count
	previous_notifications = notifications
	check(not ContentLayers.set_feature_module_enabled("hc.dependency_b", false), "required B cannot be withdrawn under enabled A")
	check(unchanged(before, bundle, stats, count) and notifications == previous_notifications, "failed dependency withdrawal preserves accepted configuration")
	check(ContentLayers.set_feature_module_enabled("hc.dependency_a", false) and ContentLayers.set_feature_module_enabled("hc.dependency_b", false), "dependent then dependency can withdraw in legal order")
	check(ContentLayers.reload_feature_catalog() and int(PlayerState.computed_stats.accuracy) == base_accuracy, "baseline restores original attributes")
	finish("feature_publication_dependencies_test")
