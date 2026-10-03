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

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	ContentLayers.feature_catalog_changed.connect(_observe)
	for variant: String in ["unknown", "missing", "null", "number", "array", "mixed"]:
		check(ContentLayers.reload_feature_catalog(BASE + "publication_registry.json") and ContentLayers.set_feature_module_enabled("hc.publication_probe", true), variant + ": establish valid enabled source")
		var before := ContentLayers.feature_configuration()
		var bundle := PlayerState.feature_bundle()
		var stats := PlayerState.computed_stats.duplicate(true)
		var count: int = PlayerState._feature_loadout.compile_count
		var errors: Array = PlayerState.feature_errors.duplicate()
		var old_notifications := notifications
		check(not ContentLayers.reload_feature_catalog(BASE + "binding_" + variant + "_registry.json"), variant + ": malformed binding kind rejects complete registry")
		check(not ContentLayers.feature_load_errors.is_empty(), variant + ": explicit binding rejection reason")
		var after := ContentLayers.feature_configuration()
		check(is_same(after.catalog, before.catalog) and is_same(after.bindings, before.bindings) and after.enabled_modules == before.enabled_modules and is_same(after.authority, before.authority), variant + ": all published registry members remain unchanged")
		check(is_same(PlayerState.feature_bundle(), bundle) and PlayerState.computed_stats == stats and PlayerState._feature_loadout.compile_count == count and PlayerState.feature_errors == errors and notifications == old_notifications, variant + ": no partial contribution generation or observer notification")
	check(ContentLayers.reload_feature_catalog(), "baseline restored")
	ContentLayers.feature_catalog_changed.disconnect(_observe)
	if not proof.write_receipt("feature_binding_validation_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_BINDING_VALIDATION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
