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
	ContentLayers.feature_catalog_changed.connect(_observe)
	for variant: String in ["null", "number", "string", "array", "boolean", "mixed"]:
		check(ContentLayers.reload_feature_catalog(BASE + "publication_registry.json"), variant + ": establish known valid directory")
		var before := ContentLayers.feature_configuration()
		var bundle := PlayerState.feature_bundle()
		var stats := PlayerState.computed_stats.duplicate(true)
		var count: int = PlayerState._feature_loadout.compile_count
		var previous_notifications := notifications
		check(not ContentLayers.reload_feature_catalog(BASE + "structure_" + variant + "_registry.json"), variant + ": malformed module entry rejects whole registry")
		check(not ContentLayers.feature_load_errors.is_empty(), variant + ": rejection has explicit business error")
		check(unchanged(before, bundle, stats, count) and notifications == previous_notifications, variant + ": malformed entry cannot publish empty or partial directory")
	check(ContentLayers.reload_feature_catalog(), "baseline restored")
	finish("feature_registry_structure_test")
