extends RefCounted
const Gate := preload("res://tests/framework/helpers/native_producer_gate.gd")

static func accepts(value: Variant, nonce: String, source: String, cold_run: String) -> bool:
	if not value is Dictionary or nonce.is_empty() or source.length() != 64 or cold_run.is_empty(): return false
	if value.get("schema_version") != 1 or value.get("control_status") != "PASS" or value.get("nonce") != nonce or value.get("source_content_sha256") != source: return false
	if value.get("termination_verified") != true or value.get("producer_native_status") != "FAIL" or value.get("producer_timeout") != false: return false
	if not value.get("producer_native_exit") is float and not value.get("producer_native_exit") is int: return false
	if int(value.producer_native_exit) == 0 or not value.get("armed") is Dictionary: return false
	var armed: Dictionary = value.armed
	if armed.get("nonce") != nonce or armed.get("source_content_sha256") != source or armed.get("stage_observation") != "ARMED" or armed.get("failed") != 0: return false
	if armed.get("phase") not in ["PREPARED","PROMOTING"] or armed.get("scene_id") != "controlled_process_crash_test": return false
	if not armed.get("producer_run_id") is String or armed.producer_run_id.is_empty() or armed.producer_run_id == cold_run: return false
	if value.get("producer_run_id") != armed.producer_run_id or value.get("producer_invocation_id") != armed.get("producer_invocation_id"): return false
	if not armed.get("checks") is Array or armed.checks.is_empty() or armed.get("count") != armed.checks.size(): return false
	for index in armed.checks.size():
		var row: Variant = armed.checks[index]
		if not row is Dictionary or row.get("id") != index+1 or row.get("passed") != true or not row.get("label") is String: return false
	if not value.get("armed_path") is String or not value.get("armed_sha256") is String: return false
	if FileAccess.get_sha256(value.armed_path) != value.armed_sha256 or Gate.read_json(value.armed_path) != armed: return false
	return true
