extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failures := 0
var _executed := false

func _check(value: bool, label: String) -> void:
	_proof.record(value, label)
	if not value:
		_failures += 1

func _finish() -> void:
	var receipt_ok: bool = _proof.write_receipt("multicore_engine_integration_20261014", _proof.records.size(), _failures)
	print("MULTICORE_ENGINE_INTEGRATION_20261014_", "PASS" if receipt_ok and _failures == 0 else "FAIL")
	get_tree().quit(0 if receipt_ok and _failures == 0 else 1)

func _physics_process(_delta: float) -> void:
	if _executed:
		return
	_executed = true
	var has_probe := ClassDB.class_exists("HardCoreMulticoreProbe")
	_check(has_probe, "fixed custom engine registers the compiled multicore probe")
	if not has_probe:
		push_error("FAIL multicore engine integration: compiled probe class missing")
		_finish()
		return
	var probe: Object = ClassDB.instantiate("HardCoreMulticoreProbe")
	var transport: Dictionary = probe.call("run_worker_transport")
	print("MULTICORE_TRANSPORT_RECEIPT ", JSON.stringify(transport))
	_check(bool(transport.get("success", false)), "actual Godot worker pool completes exact batch and presentation transport")
	_check(int(transport.get("completed_blocks", 0)) == 8 and not bool(transport.get("kernel_ran_on_caller", true)), "eight blocks execute on workers and retire without caller execution")
	if not bool(transport.get("success", false)):
		push_error("FAIL real Godot transport: " + str(transport.get("reason", "unknown")))
		_finish()
		return
	var motion: Dictionary = probe.call("run_motion_parity")
	print("MULTICORE_MOTION_RECEIPT ", JSON.stringify(motion))
	var cases: Array = motion.get("cases", [])
	var motion_ok := str(motion.get("status", "")) == "PASS" and cases.size() == 12
	_check(motion_ok, "same-backend original Node and Node-free motion adapters cover all twelve cases")
	for result: Dictionary in cases:
		_check(str(result.get("status", "")) == "PASS", "real motion adapter parity: " + str(result.get("case", "unknown")))
	if not motion_ok:
		push_error("FAIL motion parity: " + str(motion.get("reason", "unknown")))
		_finish()
		return
	print("PASS multicore engine integration; transport and motion scope only")
	_finish()
