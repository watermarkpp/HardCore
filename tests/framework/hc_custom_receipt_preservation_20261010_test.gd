extends Node

const Support := preload("res://tests/hc_monster_ai/test_support.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _run() -> void:
	var pass_support := Support.new()
	var fail_support := Support.new()
	add_child(pass_support)
	add_child(fail_support)
	pass_support.check(true, "fixture-pass-preserved", "PASS business check is retained")
	pass_support.check(true, "fixture-pass-second-check", "second PASS business check is retained")
	fail_support.check(false, "fixture-fail-preserved", "FAIL business check is retained")
	fail_support.check(true, "fixture-fail-second-check", "second FAIL receipt check is retained")
	var pass_name := "hc_custom_receipt_pass_20261010"
	var fail_name := "hc_custom_receipt_fail_20261010"
	check(pass_support.separate_write_receipt(pass_name), "PASS support writes its owned custom receipt")
	check(fail_support.separate_write_receipt(fail_name), "FAIL support writes its owned custom receipt")
	var pass_path := pass_support.last_receipt_path
	var fail_path := fail_support.last_receipt_path
	var pass_before := FileAccess.get_file_as_string(pass_path)
	var fail_before := FileAccess.get_file_as_string(fail_path)
	check(not pass_support.separate_write_receipt(pass_name), "same support identity rejects a second write")
	check(not fail_support.separate_write_receipt(fail_name), "failed support identity rejects a second write")
	var collision_support := Support.new()
	collision_support._receipt_nonce = pass_support._receipt_nonce
	add_child(collision_support)
	check(not collision_support.separate_write_receipt(pass_name), "different support instance collision fails closed")
	var pass_receipt := _read_json(pass_path)
	var fail_receipt := _read_json(fail_path)
	check(not pass_path.is_empty() and not fail_path.is_empty() and pass_path != fail_path,
		"independent support instances receive distinct owned paths")
	check(bool(pass_receipt.get("passed", false)) and pass_receipt.get("test", "") == pass_name,
		"PASS receipt retains its status and identity")
	check(not bool(fail_receipt.get("passed", true)) and fail_receipt.get("test", "") == fail_name,
		"FAIL receipt retains its status and identity")
	check(pass_receipt.get("checks", []) == pass_support.checks,
		"PASS receipt retains every original check and label")
	check(fail_receipt.get("checks", []) == fail_support.checks,
		"FAIL receipt retains every original check and label")
	for receipt: Dictionary in [pass_receipt, fail_receipt]:
		check(not str(receipt.get("source_content_sha256", "")).is_empty()
			and not str(receipt.get("engine_version", "")).is_empty()
			and not str(receipt.get("scene", "")).is_empty()
			and not str(receipt.get("run_id", "")).is_empty()
			and not str(receipt.get("invocation_id", "")).is_empty()
			and int(receipt.get("native_process_id", 0)) > 0,
			"custom receipt retains non-empty source, engine, scene, run, invocation and native metadata")
	check(FileAccess.get_file_as_string(pass_path) == pass_before and FileAccess.get_file_as_string(fail_path) == fail_before,
		"failed repeated writes preserve both original receipt byte streams")
	pass_support.free()
	fail_support.free()
	collision_support.free()
	var receipt_ok := proof.write_receipt("hc_custom_receipt_preservation_20261010_test", checks, failures.size())
	if not receipt_ok:
		failures.append("framework receipt write failed")
	print("HC_CUSTOM_RECEIPT_PRESERVATION_%s checks=%d failures=%s" % ["PASS" if receipt_ok and failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if receipt_ok and failures.is_empty() else 1)
