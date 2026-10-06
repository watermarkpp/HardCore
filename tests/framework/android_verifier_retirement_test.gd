extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Verifier := preload("res://scripts/features/compilation/android_export_representation_verifier.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# Exercise real RefCounted last-reference retirement, not a manual call to
	# _notification. A second file owner reveals whether cleanup really closed it.
	var path := "user://android_verifier_retirement_owned.tmp"
	var file := FileAccess.open(path, FileAccess.WRITE_READ)
	check(file != null and file.is_open(), "owned native file opens")
	if file == null:
		get_tree().quit(1)
		return
	file.store_string("owned retirement probe")
	var verifier: RefCounted = Verifier.new()
	verifier._file = file
	var observed: WeakRef = weakref(verifier)
	verifier = null
	check(observed.get_ref() == null, "verifier retires on actual last-reference release")
	check(not file.is_open(), "predelete directly closes owned file without calling a zero-reference self method")
	if file.is_open(): file.close() # RED-only fixture cleanup, not acceptance.
	var explicit: RefCounted = Verifier.new()
	explicit._file = FileAccess.open(path, FileAccess.READ)
	var explicit_file: FileAccess = explicit._file
	explicit.cancel()
	check(not explicit_file.is_open() and explicit._file == null, "ordinary explicit cancel remains complete")
	explicit = null
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "only owned fixture file removed")
	if not proof.write_receipt("android_verifier_retirement_test", checks, failures.size()): failures.append("receipt")
	print("ANDROID_VERIFIER_RETIREMENT_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
