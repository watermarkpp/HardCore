extends RefCounted

var records: Array[Dictionary] = []

func record(passed: bool, label: String) -> void:
	records.append({"id": records.size() + 1, "label": label, "passed": passed})

func write_receipt(scene_id: String, reported_checks: int, reported_failures: int) -> bool:
	var passed := 0
	for item: Dictionary in records:
		passed += 1 if bool(item.passed) else 0
	var failed := records.size() - passed
	var nonce := OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	var valid := not records.is_empty() and not nonce.is_empty() and failed == 0
	valid = valid and reported_checks == records.size() and reported_failures == failed
	var receipt := {"schema_version": 1, "run_id": nonce, "scene_id": scene_id,
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
		"engine_version": Engine.get_version_info().string, "checks": records,
		"count": records.size(), "passed": passed, "failed": failed,
		"reported_checks": reported_checks, "reported_failures": reported_failures,
		"status": "PASS" if valid else "FAIL"}
	var directory := "res://outputs/test_logs/framework"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return false
	var file := FileAccess.open(directory.path_join(scene_id + ".result.json"), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(receipt, "  "))
	file.close()
	return valid
