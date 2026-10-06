extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
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
	# Isolated runner only. Replay the real Android autoload dependency boundary
	# without writing assets/profiles or replacing the validator/HP/service.
	check(GameData.is_loaded(), "real GameData is ready before boundary replay")
	var loaded: bool = Registry._loaded
	var result: Dictionary = Registry._result
	var ready: bool = GameData._initial_load_complete
	var by_id: Dictionary = GameData._catalog_by_item_id
	var by_service: Dictionary = GameData._catalog_by_service_index
	var by_name: Dictionary = GameData._catalog_by_name
	Registry._loaded = false
	Registry._result = {}
	GameData._initial_load_complete = false
	GameData._catalog_by_item_id = {}
	GameData._catalog_by_service_index = {}
	GameData._catalog_by_name = {}
	var early: Dictionary = Registry.declarations()
	var latched: bool = Registry._loaded
	var early_cache: Dictionary = Registry._result
	# Restore the true authority before any notification, await or gameplay.
	GameData._catalog_by_item_id = by_id
	GameData._catalog_by_service_index = by_service
	GameData._catalog_by_name = by_name
	GameData._initial_load_complete = ready
	check(not early.success, "pre-ready query never publishes declarations")
	check(early.records.is_empty(), "pre-ready query exposes no partial resources")
	check(not latched and early_cache.is_empty(), "dependency NOT_READY is not cached as permanent origin corruption")
	var fresh := Registry.validate(JSON.parse_string(FileAccess.get_file_as_string(Registry.PATH)))
	check(fresh.success, "same shipped declarations pass real validator after original GameData becomes ready")
	var after: Dictionary = Registry.declarations()
	check(after.success, "normal post-ready query recovers without clearing a cached failure")
	check(Registry._loaded, "ready authority result is cached")
	check(GameData.get_item_art_path("hc.item.910007", "inventoryIcon") == "res://assets/art/items/service/inventory/client.classic_raw_complete/Items_00014.png", "healing primary identity and art source remain unchanged")
	Registry._loaded = true
	Registry._result = {"success":false, "records":{}, "errors":["feature_resource_registry_invalid"]}
	check(Registry.declarations().errors == ["feature_resource_registry_invalid"], "genuine ready-time rejection remains cached and is not silently repaired")
	Registry._loaded = loaded
	Registry._result = result
	check(GameData.is_loaded() == ready and is_same(GameData._catalog_by_item_id, by_id), "original authority restored exactly")
	if not proof.write_receipt("feature_resource_startup_order_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_RESOURCE_STARTUP_ORDER_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
