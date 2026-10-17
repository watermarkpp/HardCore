extends Node

const Original := preload("res://tests/framework/helpers/multicore_original_game_data_oracle_20261014.gd")
const Queries := preload("res://scripts/gameplay/content/content_query_core.gd")
const Catalogs := preload("res://scripts/gameplay/content/published_static_catalogs.gd")
const Combat := preload("res://scripts/combat_resolution_rules.gd")
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

static func _probe(snapshot: Dictionary, cases: Array) -> Dictionary:
	var token: Dictionary = snapshot.catalog_lease
	if not Catalogs.enter_reader(token): return {"entered":false}
	var port: RefCounted = Queries.create_content_port(snapshot)
	var results: Array = []
	var available: bool = port != null and port.has_method("potion_recovery_profile")
	if available:
		for parameters: Array in cases:
			results.append(port.callv("potion_recovery_profile", parameters))
	var result := {"entered":true, "available":available, "results":results,
		"combat_hash":Graph.fingerprint(Combat._contract_cache),
		"combat_readonly":Combat._contract_cache.is_read_only()}
	port = null
	result["reader_released"] = Catalogs.leave_reader(token)
	return result

func _run() -> void:
	check(GameData.ensure_loaded(), "production content loads")
	var core: RefCounted = GameData.content_query_core()
	check(core.has_method("potion_recovery_profile"), "original potion algorithm is available from sole content core")
	if not core.has_method("potion_recovery_profile"):
		_finish()
		return
	var oracle: Node = Original.new()
	var cases: Array = []
	var expected: Array = []
	var actual: Array = []
	for level: int in [-10, 0, 1, 9, 10, 19, 20, 39, 40, 60, 100]:
		for health: int in [-5, 0, 1, 4, 5, 6, 37, 301]:
			for mana: int in [-7, 0, 1, 17, 200]:
				for effect: String in ["", "instant_restore", "delayed_restore", "unknown"]:
					var parameters := [level, health, mana, effect]
					cases.append(parameters)
					expected.append(oracle.callv("potion_recovery_profile", parameters))
					actual.append(GameData.callv("potion_recovery_profile", parameters))
	check(actual == expected, "1760 potion projections preserve exact original timing and totals on Main")
	oracle.free()
	check(not Combat.contract().is_empty(), "original Combat contract is warmed on Main")
	var original_cache: Dictionary = Combat._contract_cache
	var token := Catalogs.acquire()
	check(not token.is_empty(), "catalog publisher acquires original complete DAG")
	if token.is_empty():
		_finish()
		return
	var contract_hash := Graph.fingerprint(Combat._contract_cache)
	check(Combat._contract_cache.is_read_only(), "Combat cache belongs to recursively immutable published DAG")
	Combat._contract_cache = {"attempted_replacement":true}
	check(Graph.fingerprint(Combat._contract_cache) == contract_hash, "Main cannot replace Combat cache while S publication is active")
	var snapshot := GameData.publish_content_snapshot(token)
	var worker := Thread.new()
	check(worker.start(_probe.bind(snapshot, cases)) == OK, "actual worker starts using published content")
	var result: Dictionary = worker.wait_to_finish()
	check(result.get("entered", false) and result.get("available", false), "S constructs original owner-local content port")
	check(result.get("results", []) == expected, "same 1760 potion projections match original on S")
	check(result.get("combat_readonly", false) and result.get("combat_hash", "") == contract_hash, "S observes exact published Combat contract")
	check(result.get("reader_released", false), "reader retires before publication release")
	check(Catalogs.release_after_host_quiescence(token), "quiescent isolated reader permits publication release")
	Combat._contract_cache = original_cache
	_finish()

func _finish() -> void:
	if not proof.write_receipt("multicore_potion_catalog_20261014", checks, failures.size()):
		failures.append("receipt")
	print("MULTICORE_POTION_CATALOG_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
