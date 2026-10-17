extends Node

const Codec := preload("res://scripts/gameplay/world/world_environment_transport_codec.gd")
const NativeGraph := preload("res://scripts/gameplay/world/world_environment_native_value_graph.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var checks: Array[Dictionary] = []
func _check(label: String, condition: bool) -> void:
	proof.record(condition, label)
	checks.append({"label": label, "status": "PASS" if condition else "FAIL"})

func _ready() -> void:
	_check("actual_native_graph_class", ClassDB.class_exists("HardCoreContentValueGraph"))
	if ClassDB.class_exists("HardCoreContentValueGraph"):
		var native: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph") as RefCounted
		var cells := {Vector2i(3, 2): true, Vector2i(-1, 5): false}
		var shared := {"point": Vector2(0.125, -1.25)}
		var typed: Array[Vector2i] = [Vector2i(1, 2), Vector2i(3, 4)]
		var source := {"cells": cells, "a": shared, "b": shared, "typed": typed,
			"packed": PackedFloat64Array([0.49999999999999994, 0.5]), "transform": Transform2D(0.125, Vector2(3.25, -0.5))}
		_check("native_raw_vector_keys_rejected", not native.call("validate", source, false).success)
		var result: Dictionary = NativeGraph.copy_and_seal(source)
		_check("actual_native_encoded_boundary_accepts_math", result.ok)
		if result.ok:
			_check("math_values_exact", result.value == source)
			_check("vector_key_order_exact", result.value.cells.keys() == cells.keys())
			_check("shared_alias_identity_retained", is_same(result.value.a, result.value.b))
			_check("typed_array_retained", result.value.typed.is_typed() and result.value.typed.get_typed_builtin() == TYPE_VECTOR2I)
			_check("recursive_read_only", result.value.is_read_only() and result.value.cells.is_read_only() and result.value.typed.is_read_only())
		var encoded: Dictionary = Codec.encode(source)
		_check("native_host_wire_admissible", encoded.ok and native.call("validate", encoded.wire, false).success)
		var node := Node.new()
		_check("live_Node_rejected", not NativeGraph.copy_and_seal({"node": node}).ok)
		node.free()
		_check("Callable_rejected", not NativeGraph.copy_and_seal({"call": func(): return 1}).ok)
	var failures := 0
	for entry: Dictionary in checks:
		if entry.status == "FAIL": failures += 1
	if not proof.write_receipt("multicore_world_environment_boot_transport_20261014", checks.size(), failures): failures += 1
	var result := {"status": "PASS" if failures == 0 else "FAIL", "checks": checks,
		"scope": "actual native mathematical graph encoded transport; no physics ownership or WorldCore acceptance", "native_world": "NOT_RUN"}
	var file := FileAccess.open("user://multicore_world_environment_boot_transport_20261014.result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	print("WORLD_ENVIRONMENT_BOOT_TRANSPORT_RESULT ", JSON.stringify(result))
	if failures == 0: print("MULTICORE_WORLD_ENVIRONMENT_BOOT_TRANSPORT_PASS")
	else: print("WORLD_ENVIRONMENT_BOOT_TRANSPORT_FAIL")
	get_tree().quit(0 if failures == 0 else 1)
