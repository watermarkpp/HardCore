extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
func check(ok: bool,label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1
func compare(value: Variant,label: String) -> void:
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var validated: Dictionary = graph.validate(value,false)
	var copied: Dictionary = graph.capture(value,true,false)
	check(validated.success == copied.success and validated.errors == copied.errors and validated.nodes == copied.nodes,label+": exact same runtime acceptance, diagnostics and expanded-node limit")
	check(not validated.has("value"),label+": validation does not allocate an unused owner graph")
func _ready() -> void:
	var shared: Dictionary = {"point":Vector2(2,3),"packed":PackedByteArray([1,2,3])}
	var typed: Array[int] = [1,2]
	compare({"left":shared,"right":shared,"typed":typed,"other":{},Vector2i(2,3):Color(1,0,0)},"actual runtime geometry, typed values and aliases")
	compare({&"runtime_field":NodePath("/root/World")},"runtime StringName keys and NodePath values")
	compare({"bad":self},"engine Object rejected")
	compare({"bad":Callable(self,"compare")},"Callable rejected")
	compare({"bad":NAN},"nonfinite number rejected")
	compare({"bad":Vector2(INF,0)},"nonfinite runtime vector rejected")
	var cycle: Dictionary = {}; cycle["self"] = cycle
	compare(cycle,"cyclic graph rejected"); cycle.erase("self")
	var leaf: Variant = []
	for index: int in range(32): leaf = [leaf]
	var deep: Variant = leaf
	for index: int in range(40): deep = [deep]
	compare([leaf,deep],"alias on deeper path retains original depth rejection")
	var resources: Array[Resource] = []
	compare(resources,"empty Object-typed container retains original rejection")
	var written: bool = _proof.write_receipt("boot_validation_without_copy_20261017",_proof.records.size(),_failed)
	print("BOOT_VALIDATION_WITHOUT_COPY_20261017_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
