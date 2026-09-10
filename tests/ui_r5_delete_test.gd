extends Node
## Execute the EXACT installed deletion function in a persistence fault seam.
## This tests transaction flow/rollback, not physical storage durability.
var failures: Array[String] = []
var checks := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func extract_function(source: String, function_name: String) -> String:
	var begin := source.find("\nfunc " + function_name + "(")
	if begin < 0:
		return ""
	begin += 1
	var end := source.find("\nfunc ", begin + 1)
	return source.substr(begin, end - begin) if end >= 0 else source.substr(begin)

func _ready() -> void:
	var production := FileAccess.get_file_as_string("res://scripts/player_state.gd")
	var methods := ""
	for function_name: String in ["destroy_inventory_indices", "_inventory_slot_is_occupied", "_trim_inventory_empty_tail"]:
		var method := extract_function(production, function_name)
		expect(not method.is_empty(), "installed method exists: " + function_name)
		methods += method + "\n"
	var script := GDScript.new()
	script.source_code = "extends RefCounted\nvar inventory: Array = []\nvar save_ok := false\nvar save_calls := 0\nsignal inventory_changed\nsignal profile_changed\nfunc _commit_save() -> bool:\n\tsave_calls += 1\n\treturn save_ok\n\n" + methods
	var parse_error := script.reload()
	expect(parse_error == OK, "installed deletion code compiles inside fault seam")
	if parse_error == OK:
		var subject = script.new()
		var events := {"inventory": 0, "profile": 0}
		subject.inventory_changed.connect(func() -> void: events["inventory"] += 1)
		subject.profile_changed.connect(func() -> void: events["profile"] += 1)
		subject.inventory = [{"name": "A", "count": 1}, {}, {"name": "B", "instance_id": "B1"}]
		var before: Array = subject.inventory.duplicate(true)
		var result: Dictionary = subject.destroy_inventory_indices([0, 2])
		expect(not result["success"] and result["destroyed"] == 0 and result["reason"] == "save_failed", "failed commit is not success")
		expect(subject.inventory == before, "failed commit restores all exact records")
		expect(events["inventory"] == 0 and events["profile"] == 0, "failed commit emits no successful removal")
		subject.save_ok = true
		result = subject.destroy_inventory_indices([0, 2])
		expect(result["success"] and result["destroyed"] == 2, "successful batch result")
		expect(subject.inventory.is_empty(), "successful batch trims empty tail")
		expect(events["inventory"] == 1 and events["profile"] == 1, "success emits exactly once after commit")
		subject.inventory = before.duplicate(true)
		var saves: int = subject.save_calls
		result = subject.destroy_inventory_indices([0, 0])
		expect(not result["success"] and subject.inventory == before, "duplicate target rejected atomically")
		expect(subject.save_calls == saves, "invalid batch performs no commit")
		result = subject.destroy_inventory_indices([1])
		expect(not result["success"] and subject.inventory == before, "empty target rejected")
		result = subject.destroy_inventory_indices([])
		expect(result["success"] and result["destroyed"] == 0, "empty selection remains a no-op")
	for failure: String in failures:
		push_error("UI_R5_DELETE: " + failure)
	print("UI_R5_DELETE_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
