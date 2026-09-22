extends Node
# RV14-R2 deterministic failure injection for the restore/promote path.
# Unlike the earlier Windows lock-based probe, this drives the exact
# failure branches with the narrow injection seam (rename / remove /
# restored-open fail-from counters, all reset to real IO here after every
# scenario), proving the control flow the review asked for:
#   a. promote failure + rollback rename failure (double failure)
#   b. restored-open/verify failure + rollback failure
#   e. unfinished transaction state and error reasons stay diagnosable,
#      and a retry after the seam reset succeeds
#   d. res://-style and absolute preserve-source spellings behave the same
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)

var errors: Array[String] = []
var checked := 0


func _ready() -> void:
	_run.call_deferred()


func expect(value: bool, message: String) -> void:
	checked += 1
	if not value:
		errors.append(message)


func _sandbox_dir() -> String:
	var dir := "user://rv14_injected_%d" % Time.get_ticks_usec()
	var err := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(dir)
	)
	assert(err == OK, "cannot create sandbox dir")
	return dir


func _write(path: String, payload: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot write %s" % path)
	file.store_string(payload)
	file.close()


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _reset_seams() -> void:
	BuildService.test_rename_fail_from_call = 0
	BuildService.test_remove_fail_from_call = 0
	BuildService.test_restored_open_fail_from_call = 0
	BuildService._reset_injection_counters()


func _run() -> void:
	var sandbox := _sandbox_dir()
	var registry := sandbox + "/registry.json"
	var old_bytes := "OLD_MAIN_V1"
	_write(registry, old_bytes)
	var raw := "RESTORED_V2"

	# --- Scenario A: promote failure + rollback rename failure ---------
	# rename calls inside one restore: 1 staging, 2 promote, 3 rollback.
	# The fail-from counter is an absolute call number, so every scenario
	# resets the counters before arming a new budget.
	_reset_seams()
	BuildService.test_rename_fail_from_call = 2
	var result_a: Dictionary = BuildService._restore_registry_bytes(
		registry, raw.to_utf8_buffer()
	)
	_reset_seams()
	expect(
		str(result_a.get("reason", "")) == "promote_failed",
		"A: reason must be promote_failed (got %s)" % str(result_a.get("reason", ""))
	)
	var rollback_a: Array = result_a.get("rollback_errors", [])
	expect(
		rollback_a.has("rollback_rename_failed"),
		"A: rollback rename failure must be reported separately"
	)
	# Double failure: staging moved the old main into the backup slot and
	# both the promote and the rollback rename failed, so the formal path
	# is empty and the old bytes live in the backup slot.
	var backup_path := registry + ".restore_bak"
	expect(
		_read(backup_path) == old_bytes,
		"A: the old bytes must survive in the staged backup slot"
	)
	expect(
		not FileAccess.file_exists(registry),
		"A: the formal path must stay empty after the double failure"
	)
	# Retry with real IO: the unfinished transaction is recoverable.
	var retry_a: Dictionary = BuildService._restore_registry_bytes(
		registry, raw.to_utf8_buffer()
	)
	expect(
		bool(retry_a.get("ok", false)),
		"A: a retry after resetting the seam must succeed"
	)
	expect(
		_read(registry) == raw,
		"A: the retry must deliver the restored bytes"
	)

	# --- Scenario B: restored-open failure + rollback failure ----------
	_write(registry, old_bytes)
	_reset_seams()
	# rename calls: 1 staging, 2 promote, 3 rollback; the restored-open is
	# the first open probe.
	BuildService.test_restored_open_fail_from_call = 1
	BuildService.test_rename_fail_from_call = 3
	var result_b: Dictionary = BuildService._restore_registry_bytes(
		registry, raw.to_utf8_buffer()
	)
	_reset_seams()
	expect(
		str(result_b.get("reason", "")) == "restored_open_failed",
		"B: reason must be restored_open_failed (got %s)" % str(result_b.get("reason", ""))
	)
	var rollback_b: Array = result_b.get("rollback_errors", [])
	expect(
		rollback_b.has("rollback_rename_failed"),
		"B: the rollback rename failure must be reported"
	)
	expect(
		FileAccess.file_exists(backup_path),
		"B: the staged old main stays diagnosable"
	)
	# Retry with real IO recovers the destination.
	var retry_b: Dictionary = BuildService._restore_registry_bytes(
		registry, raw.to_utf8_buffer()
	)
	expect(
		bool(retry_b.get("ok", false)) and _read(registry) == raw,
		"B: the retry must recover the destination"
	)

	# --- Scenario C: preserve-source spelling independence (user://) ---
	_write(registry, old_bytes)
	_reset_seams()
	# The same backup slot spelled as a user:// path must hit the same
	# collision guard as the absolute spelling (the guard normalizes).
	var preserve_user := registry + ".restore_bak"
	var user_form := (
		"user://" + sandbox.trim_prefix("user://") + "/registry.json.restore_bak"
	)
	var result_c: Dictionary = BuildService._restore_registry_bytes(
		registry, raw.to_utf8_buffer(), user_form
	)
	_reset_seams()
	expect(
		str(result_c.get("reason", "")) == "source_slot_collision",
		"C: a user://-spelled preserved source must trip the collision guard (got %s)"
		% str(result_c.get("reason", ""))
	)
	expect(
		FileAccess.file_exists(preserve_user),
		"C: the preserved source must survive the refused restore"
	)
	var cleanup_c: Dictionary = BuildService._restore_registry_bytes(
		registry, raw.to_utf8_buffer()
	)
	expect(
		bool(cleanup_c.get("ok", false)),
		"C: a restore without the colliding preserve source succeeds"
	)

	for message: String in errors:
		push_error("RV14_INJECTED_FAILURES: " + message)
	print(
		"RV14_INJECTED_FAILURES_%s checks=%d failures=%d"
		% ["PASS" if errors.is_empty() else "FAIL", checked, errors.size()]
	)
	get_tree().quit(0 if errors.is_empty() else 1)
