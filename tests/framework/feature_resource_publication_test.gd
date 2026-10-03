extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Authority := preload("res://scripts/features/adapters/feature_authority.gd")
const Catalog := preload("res://scripts/features/compilation/feature_catalog.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.recalculate_stats(false)
	var original := ContentLayers.feature_configuration()
	var original_bundle := PlayerState.feature_bundle()
	var path: String = GameData.get_item_art_path({"item_id":910007}, "inventoryIcon")
	check(not path.is_empty() and ResourceLoader.exists(path), "existing production healing icon is a real project resource")
	var module: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/features/validation/publication_probe.json"))
	module.module_id = "hc.resource_publication_probe"
	module.mechanics[0].mechanic_id = "hc.resource_publication_probe.accuracy"
	module.resource_dependencies = [path]
	module.tests = ["tests/framework/feature_resource_publication_test.tscn"]
	var result := Compiler.compile_catalog([module], Authority.build())
	print("FEATURE_RESOURCE_CANDIDATE " + JSON.stringify({"path":path, "success":result.success, "errors":result.errors}))
	check(bool(result.success), "real nonempty dependency can enter the formal feature resource closure")
	# Controlled data compiler authority isolates the second boundary. It does
	# not broaden ContentLayers trust, start a load, or publish this directory.
	var declared_authority := Authority.build().duplicate(true)
	declared_authority.resource_paths = [path]
	var candidate := Catalog.new()
	check(candidate.publish([module], [], declared_authority), "valid declared path can compile as a controlled data-only candidate")
	var prepared: Dictionary = PlayerState._prepare_feature_configuration({"catalog":candidate.catalog(), "authority":declared_authority, "bindings":[], "enabled_modules":[module.module_id]})
	print("FEATURE_RESOURCE_PREPARATION " + JSON.stringify({"path":path, "engine_cached":ResourceLoader.has_cached(path), "prepared":prepared.get("success"), "errors":prepared.get("errors", []), "has_preparation_lease":false}))
	check(not bool(prepared.success), "nonempty enabled resource dependency requires real readiness ownership before player publication")
	check(is_same(original.catalog, ContentLayers.feature_configuration().catalog) \
		and is_same(original_bundle, PlayerState.feature_bundle()), "resource compilation never partially publishes player state")
	if not proof.write_receipt("feature_resource_publication_test", checks, failures.size()):
		failures.append("receipt")
	print(("FRAMEWORK_FEATURE_RESOURCE_PUBLICATION_PASS" if failures.is_empty() else "FRAMEWORK_FEATURE_RESOURCE_PUBLICATION_FAIL") \
		+ " checks=" + str(checks) + " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
