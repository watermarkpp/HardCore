extends Node2D

var checks: Array[Dictionary] = []
var failed := false

func check(condition: bool, id: String, message: String) -> void:
	checks.append({"id": id, "passed": condition, "message": message})
	if not condition:
		failed = true
		print("HC_TEST_FAIL ", id, " ", message)

func finish(name: String) -> void:
	var directory := "res://outputs/hc_monster_ai_package"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory + "/" + name + ".json", FileAccess.WRITE)
	if file == null:
		failed = true
	else:
		file.store_string(JSON.stringify({"test": name, "passed": not failed, "checks": checks}, "\t"))
		file.close()
	print("HC_", name.to_upper(), "_", "FAIL" if failed else "PASS", " checks=", checks.size())
	get_tree().quit(1 if failed else 0)
