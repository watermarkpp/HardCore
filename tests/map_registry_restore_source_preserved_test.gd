extends Node

## RV14-02 (green-phase): _restore_registry_bytes source-preservation contract.
## Restoring FROM a backup must never delete that source: the source survives
## until the restored destination bytes are verified, and a failed restore
## keeps the source and reports a diagnostic instead of destroying the only
## recoverable copy. This test requires the RV14-02 signature
## (preserve_source_absolute parameter returning Dictionary).

const Fixtures := preload(
	"res://tests/helpers/map_runtime_transaction_test_fixtures.gd"
)
const BuildService := preload(
	"res://scripts/map_editor/map_editor_build_runtime_service.gd"
)

const REG_PATH := "user://rv14_restore_source_preserved.json"

var failures: Array[String] = []
var checks := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _ready() -> void:
	_run.call_deferred()

func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path)

func _run() -> void:
	Fixtures.reset_seams()
	Fixtures.write_registry(REG_PATH, [])
	DirAccess.copy_absolute(REG_PATH, _absolute(REG_PATH) + ".restore_bak")
	var src_file := FileAccess.open(_absolute(REG_PATH) + ".restore_bak", FileAccess.READ)
	var src_bytes: PackedByteArray = src_file.get_buffer(src_file.get_length())
	src_file.close()
	DirAccess.remove_absolute(REG_PATH)

	# R7a: a successful source-preserving restore keeps the source alive.
	var restore_ok: Dictionary = BuildService._restore_registry_bytes(
		REG_PATH, src_bytes, _absolute(REG_PATH) + ".restore_bak"
	)
	expect(bool(restore_ok.get("ok", false)), "R7a: source-preserving restore must succeed: %s" % str(restore_ok))
	var dst_file := FileAccess.open(REG_PATH, FileAccess.READ)
	var dst_bytes: PackedByteArray = dst_file.get_buffer(dst_file.get_length())
	dst_file.close()
	expect(dst_bytes == src_bytes, "R7a: restored destination bytes must match the source")
	expect(
		FileAccess.file_exists(_absolute(REG_PATH) + ".restore_bak"),
		"R7a: the source backup must survive the restore"
	)

	# R7b: a failed restore (destination occupied by a directory) keeps the
	# source and reports failure without destroying anything.
	DirAccess.make_dir_recursive_absolute(_absolute(REG_PATH))
	var restore_fail: Dictionary = BuildService._restore_registry_bytes(
		REG_PATH, src_bytes, _absolute(REG_PATH) + ".restore_bak"
	)
	expect(not bool(restore_fail.get("ok", false)), "R7b: restore onto a directory must fail")
	expect(
		FileAccess.file_exists(_absolute(REG_PATH) + ".restore_bak"),
		"R7b: the source backup must survive the failed restore"
	)
	DirAccess.remove_absolute(_absolute(REG_PATH))
	Fixtures.write_registry(REG_PATH, [])

	Fixtures.reset_seams()
	for failure: String in failures:
		push_error("REGISTRY_RESTORE_SOURCE_PRESERVED: " + failure)
	print(
		"REGISTRY_RESTORE_SOURCE_PRESERVED_%s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()]
	)
	get_tree().quit(0 if failures.is_empty() else 1)
