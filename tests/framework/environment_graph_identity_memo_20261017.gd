extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Original := preload("res://tests/framework/helpers/world_environment_value_graph_original_20261017.gd")
const Current := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
var _proof := Proof.new()
var _failed := 0
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1; print("ENVIRONMENT_MEMO_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func compare(value: Variant,label: String) -> void:
	var before: Dictionary = Original.copy_and_seal(value)
	var after: Dictionary = Current.copy_and_seal(value)
	check(before.ok == after.ok and before.errors == after.errors,label+": same acceptance and exact diagnostics")
	if before.ok: check(var_to_bytes(before.value) == var_to_bytes(after.value),label+": identical serialized mathematical values")
func _run() -> void:
	var native: Object = ClassDB.instantiate("HardCoreContentValueGraph")
	check(native.has_method("container_identity_for_local_copy"),"actual matching Native container identity primitive exists")
	var shared: Dictionary = {"shape":PackedVector2Array([Vector2(1,2),Vector2(3,4)]),"empty":[]}
	var distinct_a: Dictionary = {}; var distinct_b: Dictionary = {}
	var typed: Array[int] = [3,5,7]
	var empty_objects: Array[Resource] = []
	var typed_dict: Dictionary[int,String] = {1:"one",2:"two"}
	var mixed: Dictionary = {"a":shared,"b":shared,"distinct_a":distinct_a,"distinct_b":distinct_b,"typed":typed,"empty_objects":empty_objects,"typed_dict":typed_dict}
	compare(mixed,"aliases, distinct-equal and typed containers")
	var owned: Dictionary = Current.copy_and_seal(mixed)
	check(owned.ok and is_same(owned.value.a,owned.value.b) and not is_same(owned.value.a,shared),"same alias is preserved in an independent output graph")
	check(not is_same(owned.value.distinct_a,owned.value.distinct_b),"equal distinct containers remain distinct")
	check(owned.value.is_read_only() and owned.value.a.is_read_only() and owned.value.typed.is_read_only(),"all owned containers remain readonly")
	check(owned.value.typed.get_typed_builtin() == TYPE_INT and owned.value.empty_objects.get_typed_builtin() == TYPE_OBJECT and owned.value.typed_dict.get_typed_key_builtin() == TYPE_INT,"original typed empty/nonempty metadata is retained")
	var mathematical: Dictionary = {Vector2i(1,2):Rect2(Vector2.ONE,Vector2(2,3)),true:Color(0.2,0.4,0.6),NodePath("root/child"):Transform2D.IDENTITY,&"named":Vector4(1,2,3,4),null:PackedFloat64Array([1.5,2.5])}
	compare(mathematical,"all original immutable key/value categories")
	for bad: Variant in [NAN,Vector2(INF,0),Vector3(0,NAN,0),Vector4(0,0,INF,0),Color(NAN,0,0),PackedFloat32Array([1.0,NAN]),RID()]: compare({"bad":bad},"rejected type/finite validation:"+str(typeof(bad)))
	var object: Node = Node.new(); compare({"bad":object},"actual engine object stays forbidden"); object.free()
	var cycle: Array = []; cycle.append(cycle); compare(cycle,"actual array cycle stays forbidden"); cycle.clear()
	var cycle_dict: Dictionary = {}; cycle_dict["self"] = cycle_dict; compare(cycle_dict,"actual dictionary cycle stays forbidden"); cycle_dict.clear()
	var rows: Array = []
	for i: int in range(1600): rows.append({"number":i,"distinct_empty":{},"pair":[i,i+1],"common":shared})
	var start: int = Time.get_ticks_usec()
	var baseline: Dictionary = Original.copy_and_seal(rows)
	var baseline_usec: int = Time.get_ticks_usec()-start
	start = Time.get_ticks_usec()
	var candidate: Dictionary = Current.copy_and_seal(rows)
	var candidate_usec: int = Time.get_ticks_usec()-start
	check(baseline.ok and candidate.ok and var_to_bytes(baseline.value) == var_to_bytes(candidate.value),"same full1600row workload produces identical results")
	check(is_same(candidate.value[0].common,candidate.value[1599].common),"distant aliases retain shared output identity")
	print("ENVIRONMENT_MEMO_SAME_INPUT_TIMING ",JSON.stringify({"rows":rows.size(),"baseline_usec":baseline_usec,"candidate_usec":candidate_usec,"scope":"same-input copy only, not Android/game FPS proof"}))
	var written: bool = _proof.write_receipt("environment_graph_identity_memo_20261017",_proof.records.size(),_failed)
	print("ENVIRONMENT_GRAPH_IDENTITY_MEMO_20261017_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
