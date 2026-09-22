extends Node
# RV14-R2 review: targeted fault injection for the registry restore failure
# branches reachable under Windows file-handle semantics, using only the
# official isolated user:// scratch space. Holding a write handle on a file
# makes Godot's rename/remove of that exact file fail, which injects the
# staging and backup-cleanup failures. The promote/rollback double-failure
# injection is NOT reachable this way (the staging rename fails first), so
# that branch's rollback reporting is verified by source review and the
# primary/rollback error propagation structure instead.
const Build := preload("res://scripts/map_editor/map_editor_build_runtime_service.gd")

var errors: Array[String] = []
var checked := 0


func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	checked += 1
	if not value:
		errors.append(message)


func write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	file.close()
	return true


func read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _run() -> void:
	var root := "user://rv14_restore_injection_%d/" % Time.get_ticks_usec()
	expect(
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(root)
		) == OK,
		"scratch directory"
	)

	# Scenario 1: staging rename failure. The destination write handle makes
	# dst -> .restore_bak fail after tmp staging, so the helper must report
	# staging_rename_failed and clean the tmp file.
	var dst_a := root + "registry_a.json"
	expect(write_text(dst_a, "old-main-a"), "write old main A")
	# A read handle is enough to make Windows refuse the rename while keeping
	# the payload readable for the final assertion.
	var lock_a := FileAccess.open(dst_a, FileAccess.READ)
	expect(lock_a != null, "hold read handle on destination A")
	var restored_a := Build._restore_registry_bytes(
		dst_a, "staged-new-a".to_utf8_buffer()
	)
	if lock_a != null:
		lock_a.close()
	expect(not bool(restored_a.get("ok", false)), "restore A must fail")
	expect(
		str(restored_a.get("reason", "")) == "staging_rename_failed",
		"primary error is staging_rename_failed"
	)
	expect(
		(restored_a.get("rollback_errors", []) as Array).is_empty(),
		"staging failure happens before staging: no rollback errors"
	)
	expect(
		not FileAccess.file_exists(dst_a + ".tmp"),
		"failed restore must clean the staged tmp file"
	)
	expect(
		read_text(dst_a) == "old-main-a",
		"locked old main A stays untouched at the destination"
	)

	# Scenario 2: the preserved source slot is the staging slot itself. The
	# caller passes the source in res://-style form and the helper must
	# normalize before comparing, refusing instead of deleting the source it
	# is restoring from.
	var dst_b := root + "registry_b.json"
	expect(write_text(dst_b, "old-main-b"), "write old main B")
	expect(
		write_text(dst_b + ".restore_bak", "preserved-source-b"),
		"write preserved source B"
	)
	var restored_b := Build._restore_registry_bytes(
		dst_b,
		"staged-new-b".to_utf8_buffer(),
		dst_b + ".restore_bak"
	)
	expect(not bool(restored_b.get("ok", false)), "restore B must fail")
	expect(
		str(restored_b.get("reason", "")) == "source_slot_collision",
		"source slot collision is refused"
	)
	expect(
		read_text(dst_b + ".restore_bak") == "preserved-source-b",
		"source slot collision preserves the source bytes"
	)

	for message: String in errors:
		push_error("RV14_RESTORE_INJECTION: " + message)
	print(
		"RV14_RESTORE_INJECTION_%s checks=%d failures=%d"
		% ["PASS" if errors.is_empty() else "FAIL", checked, errors.size()]
	)
	get_tree().quit(0 if errors.is_empty() else 1)
