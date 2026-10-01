extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Catalog := preload("res://scripts/features/compilation/feature_catalog.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
var checks := 0
var errors: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	_proof.record(value, label)
	checks += 1
	if not value:
		errors.append(label)

func numeric_module() -> Dictionary:
	return {"schema_version":1,"module_id":"fixture.numeric","module_version":1,"core_api_version":1,
		"requires":[],"conflicts":[],"capabilities":["stats.contribute"],"handlers":[],
		"resource_dependencies":[],"cost":{"commands_per_event":0,"states_per_target":0},
		"mechanics":[{"mechanic_id":"fixture.accuracy","kind":"stat","tags":["fixture.grant"],
			"operations":[{"stat":"accuracy","op":"add","value":2.5}]}],
		"tests":["tests/framework/feature_compiler_test.tscn"]}

func grant(slot: String, instance_id: String) -> Dictionary:
	return {"source":{"slot":slot,"instance_id":instance_id,"mechanic_id":"fixture.accuracy"},
		"mechanic_id":"fixture.accuracy"}

func authority() -> Dictionary:
	return {"core_api_version":1,"stat_keys":["accuracy"],"skill_ids":[],
		"capabilities":["stats.contribute"],"handler_ids":[],"resource_paths":[],
		"max_commands_per_event":16,"max_states_per_target":16,"max_sources":64}

func _run() -> void:
	var module := numeric_module()
	var sources := [grant("ring_1","fixture:ring:1"),grant("rune_1","fixture:rune:1")]
	var compiled: Dictionary = Compiler.compile([module],sources,authority())
	check(bool(compiled.success),"valid numeric module compiles")
	if not bool(compiled.success):
		print("FEATURE_COMPILER_DIAGNOSTIC=" + JSON.stringify(compiled.errors))
		_finish()
		return
	var bundle: Dictionary = compiled.bundle
	check(bundle.stat_operations.size()==2,"both exact sources contribute")
	check(int(bundle.tags.get("fixture.grant",0))==2,"tag references count by source")
	check(bundle.is_read_only() and bundle.stat_operations.is_read_only()
		and bundle.stat_operations[0].is_read_only() and bundle.stat_operations[0].source.is_read_only(),
		"nested bundle and source handles are frozen")
	module.mechanics[0].operations[0].value = 999
	sources[0].source.instance_id = "mutated_after_compile"
	check(float(bundle.stat_operations[0].value)==2.5
		and str(bundle.stat_operations[0].source.instance_id)=="fixture:ring:1",
		"caller mutations cannot alter an accepted bundle")
	var one_source: Dictionary = Compiler.compile([numeric_module()],[grant("rune_1","fixture:rune:1")],authority())
	check(bool(one_source.success) and one_source.bundle.stat_operations.size()==1
		and int(one_source.bundle.tags.get("fixture.grant",0))==1,"revoke one source preserves the other")
	var duplicate: Dictionary = Compiler.compile([numeric_module()],
		[grant("ring_1","fixture:ring:1"),grant("ring_1","fixture:ring:1")],authority())
	check(not bool(duplicate.success),"duplicate stable source handle fails explicitly")
	var unknown_stat := numeric_module()
	unknown_stat.mechanics[0].operations[0].stat = "unknown_stat"
	check(not bool(Compiler.compile([unknown_stat],[grant("ring_1","fixture:ring:1")],authority()).success),
		"unknown canonical stat is rejected")
	var unknown_op := numeric_module()
	unknown_op.mechanics[0].operations[0].op = "fallback"
	check(not bool(Compiler.compile([unknown_op],[grant("ring_1","fixture:ring:1")],authority()).success),
		"unknown operation is rejected")
	var unknown_field := numeric_module()
	unknown_field.arbitrary_script = "res://untrusted.gd"
	check(not bool(Compiler.compile([unknown_field],[],authority()).success),"unknown manifest field is rejected")
	var missing_dependency := numeric_module()
	missing_dependency.requires = ["missing.module"]
	check(not bool(Compiler.compile([missing_dependency],[grant("ring_1","fixture:ring:1")],authority()).success),
		"missing dependency is rejected")
	var cyclic := numeric_module()
	cyclic.requires = ["fixture.numeric"]
	check(not bool(Compiler.compile([cyclic],[grant("ring_1","fixture:ring:1")],authority()).success),
		"dependency cycle is rejected")
	var forbidden := numeric_module()
	forbidden.capabilities.append("database.write")
	check(not bool(Compiler.compile([forbidden],[],authority()).success),"ungranted capability is rejected")
	var excessive := numeric_module()
	excessive.cost.commands_per_event = 17
	check(not bool(Compiler.compile([excessive],[grant("ring_1","fixture:ring:1")],authority()).success),
		"declared active-combination capacity is bounded")
	var bad_mechanic := numeric_module()
	bad_mechanic.mechanics = [null]
	check(not bool(Compiler.compile([bad_mechanic],[],authority()).success), "null mechanic fails rather than disappearing")
	var bad_cost := numeric_module()
	bad_cost.cost = []
	check(not bool(Compiler.compile([bad_cost],[],authority()).success), "non-dictionary cost fails closed")
	check(not bool(Compiler.compile([numeric_module()],[null],authority()).success), "null contribution fails closed")
	var extra_operation := numeric_module()
	extra_operation.mechanics[0].operations[0].execute = "arbitrary"
	check(not bool(Compiler.compile([extra_operation],[],authority()).success), "unknown operation field fails")
	var conflict_a := numeric_module()
	var conflict_b := numeric_module()
	conflict_b.module_id = "fixture.other"
	conflict_b.mechanics = []
	conflict_a.conflicts = ["fixture.other"]
	check(not bool(Compiler.compile([conflict_a,conflict_b],[],authority()).success), "declared conflicting catalog is rejected")
	var strict_tags := authority()
	strict_tags.tag_keys = []
	check(not bool(Compiler.compile([numeric_module()],[],strict_tags).success), "unknown authoritative tag fails")
	var malformed_hash := numeric_module()
	malformed_hash["content_hash"] = "z".repeat(64)
	check(not bool(Compiler.compile([malformed_hash],[],authority()).success), "non-hex declared content hash fails")
	var wrong_hash := numeric_module()
	wrong_hash["content_hash"] = "0".repeat(64)
	check(not bool(Compiler.compile([wrong_hash],[],authority()).success), "wrong declared content hash fails")
	var correct_hash := numeric_module()
	correct_hash["content_hash"] = JSON.stringify(correct_hash).sha256_text()
	check(bool(Compiler.compile([correct_hash],[],authority()).success), "canonical declared content hash verifies")
	var malformed_authority := authority()
	malformed_authority["tag_keys"] = null
	check(not bool(Compiler.compile([],[],malformed_authority).success), "optional authority must be a string allowlist")
	var unknown_authority := authority()
	unknown_authority["arbitrary_permission"] = true
	check(not bool(Compiler.compile([],[],unknown_authority).success), "unknown authority fields fail")
	var compiled_catalog: Dictionary = Compiler.compile_catalog([numeric_module()],authority()).catalog
	var forged := compiled_catalog.duplicate(true)
	forged.mechanics["fixture.accuracy"].definition.operations[0].stat = "unknown_stat"
	check(not bool(Compiler.compile_loadout(forged,[grant("ring_1","fixture:ring:1")],authority()).success),
		"public loadout rejects a forged selected definition")
	forged = compiled_catalog.duplicate(true)
	forged.mechanics["fixture.accuracy"].definition.mechanic_id = "fixture.other"
	check(not bool(Compiler.compile_loadout(forged,[grant("ring_1","fixture:ring:1")],authority()).success),
		"selected entry identity must equal the contribution ID")
	forged = compiled_catalog.duplicate(true)
	forged.mechanics["fixture.accuracy"].cost.commands_per_event = -1
	check(not bool(Compiler.compile_loadout(forged,[grant("ring_1","fixture:ring:1")],authority()).success),
		"selected entry cannot inject a negative cost")
	var non_plain := Node.new()
	check(not bool(Graph.capture({"node":non_plain}).success), "Node cannot enter immutable definition graph")
	non_plain.free()
	var cyclic_graph: Array = []
	cyclic_graph.append(cyclic_graph)
	check(not bool(Graph.capture(cyclic_graph).success), "cyclic graph is rejected before duplication")
	cyclic_graph.clear()
	var catalog := Catalog.new()
	check(catalog.publish([numeric_module()],sources,authority()), "atomic catalog publishes valid candidate")
	var valid_catalog: Dictionary = catalog.catalog()
	var valid_bundle: Dictionary = catalog.bundle()
	check(not catalog.publish([unknown_op],[],authority())
		and is_same(valid_catalog,catalog.catalog()) and is_same(valid_bundle,catalog.bundle()),
		"failed catalog candidate leaves exact previous catalog and bundle active")
	var missing_source := grant("ring_1","unknown:instance")
	missing_source.mechanic_id = "fixture.missing"
	missing_source.source.mechanic_id = "fixture.missing"
	var compile_count_before: int = catalog.loadout_compile_count
	check(not catalog.recompile_sources([missing_source]) and is_same(valid_bundle,catalog.bundle())
		and catalog.loadout_compile_count == compile_count_before,
		"failed source compile keeps prior immutable bundle and published revision")
	var large_module := numeric_module()
	for index: int in range(10000):
		large_module.mechanics.append({"mechanic_id":"fixture.unused_%d" % index,"kind":"stat","tags":[],
			"operations":[{"stat":"accuracy","op":"add","value":float(index)}]})
	var large := Catalog.new()
	check(large.publish([large_module],[grant("ring_1","fixture:ring:1")],authority()), "10000 inactive definitions compile")
	if not large.catalog().is_empty():
		check(large.catalog().mechanics.size() == 10001 and large.bundle().stat_operations.size() == 1,
			"active bundle contains exact source contributions rather than whole catalog")
		check(large.bindings_for("damage_committed","warrior.fire_sword").is_empty(),
			"inactive definitions have no event subscriptions")
	_finish()

func _finish() -> void:
	if not _proof.write_receipt("feature_compiler_test", checks, errors.size()):
		errors.append("framework assertion receipt failed")
	print(("FRAMEWORK_FEATURE_COMPILER_PASS" if errors.is_empty() else "FRAMEWORK_FEATURE_COMPILER_FAIL")
		+ " checks=" + str(checks) + " errors=" + str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
