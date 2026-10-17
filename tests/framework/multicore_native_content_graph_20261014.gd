extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failures := 0

class ThreadCase extends RefCounted:
	func run() -> Dictionary:
		var graph: Object = ClassDB.instantiate("HardCoreContentValueGraph")
		var empty: Array = []
		var result: Dictionary = graph.call("capture", {"a":empty,"b":empty}, false)
		if not result.success: return {"success":false}
		result.value.a.append(42)
		return {"success":result.value.b == [42] and empty.is_empty(),"owner":OS.get_thread_caller_id()}

func _check(value: bool, label: String) -> void:
	_proof.record(value, label)
	if not value: _failures += 1

func _ready() -> void:
	var exists := ClassDB.class_exists("HardCoreContentValueGraph")
	_check(exists, "native content graph implementation is compiled into the fixed engine")
	if exists:
		var graph: Object = ClassDB.instantiate("HardCoreContentValueGraph")
		var shared: Array = []
		var original := {"a":shared,"b":shared,"separate":[]}
		var result: Dictionary = graph.call("capture", original, false)
		_check(result.success, "plain graph capture accepts shared empty containers")
		if result.success:
			result.value.a.append(7)
			_check(result.value.b == [7], "same-instance empty aliases remain aliases in the private copy")
			_check(result.value.separate.is_empty(), "equal but distinct empty containers remain independent")
			_check(shared.is_empty(), "owner-local mutation never changes the source graph")
		var integers: Array[int] = [1, 2]
		var typed: Dictionary[int, String] = {3:"value"}
		var typed_copy: Dictionary = graph.call("capture", {"array":integers,"dictionary":typed}, true)
		_check(typed_copy.success and typed_copy.value.array.is_typed() and typed_copy.value.dictionary.is_typed(), "typed container declarations survive capture")
		_check(typed_copy.success and typed_copy.value.is_read_only() and typed_copy.value.array.is_read_only(), "published container graph is recursively read-only")
		var cycle: Dictionary = {}
		cycle.self = cycle
		_check(not graph.call("capture", cycle, true).success, "gray back-edge rejects cyclic graphs")
		cycle.erase("self")
		_check(not graph.call("capture", {"node":self}, true).success, "engine objects cannot cross content publication")
		_check(not graph.call("validate", {"nan":NAN}).success, "nonfinite content values fail before serialization")
		var deep_alias: Variant = []
		for _i in 32: deep_alias = [deep_alias]
		var deeper_path: Variant = deep_alias
		for _i in 40: deeper_path = [deeper_path]
		_check(not graph.call("validate", [deep_alias,deeper_path]).success, "a reused alias on a deeper path still obeys the original depth limit")
		var many: Array = []
		for _i in 4096: many.append([])
		var linear: Dictionary = graph.call("capture", many, true)
		_check(linear.success and int(linear.memo_entries) == 4097, "4096 equal empty instances use exactly one identity entry per container")
		var thread := Thread.new()
		var work := ThreadCase.new()
		_check(thread.start(work.run) == OK, "native graph API is callable from a real Godot worker thread")
		var worker: Dictionary = thread.wait_to_finish()
		_check(worker.get("success", false) and worker.get("owner", 0) != OS.get_main_thread_id(), "S captures its own graph while preserving aliases and source isolation")
	var okay: bool = _proof.write_receipt("multicore_native_content_graph_20261014", _proof.records.size(), _failures)
	print("MULTICORE_NATIVE_CONTENT_GRAPH_20261014_", "PASS" if okay and _failures == 0 else "FAIL")
	get_tree().quit(0 if okay and _failures == 0 else 1)
