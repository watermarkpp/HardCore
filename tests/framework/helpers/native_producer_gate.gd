extends RefCounted

## Test evidence only: the native runner owns this invocation's successful
## producer association. Neither an expectation nor a receipt can select it.
const HANDOFF := "res://outputs/test_logs/framework/native_handoffs.json"

static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return null
	return parser.data

static func accepts(expected: Variant, scene_id: String) -> bool:
	var handoff: Variant = read_json(HANDOFF)
	var invocation := OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID")
	var source := OS.get_environment("HARDCORE_R3_CONTENT_SHA256")
	if not expected is Dictionary or not handoff is Dictionary or invocation.is_empty() or source.is_empty(): return false
	if handoff.get("schema_version") != 1 or handoff.get("invocation_id") != invocation \
		or handoff.get("source_content_sha256") != source or not handoff.get("producers") is Dictionary: return false
	var native: Variant = handoff.producers.get(scene_id)
	if not native is Dictionary or native.get("scene_id") != scene_id or native.get("result") != "PASS" \
		or native.get("process_exited") != true or native.get("effective_exit_code") != 0 \
		or native.get("source_content_sha256") != source: return false
	var run: Variant = native.get("run_id")
	if not run is String or run.is_empty() or run == OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID") \
		or expected.get("producer_run_id") != run or expected.get("invocation_id") != invocation \
		or expected.get("source_content_sha256") != source: return false
	var path := "res://outputs/test_logs/framework/"+scene_id+".result.json"
	var receipt: Variant = read_json(path)
	if not receipt is Dictionary or native.get("receipt_sha256") != FileAccess.get_sha256(path): return false
	if receipt.get("schema_version") != 1 or receipt.get("status") != "PASS" or receipt.get("run_id") != run \
		or receipt.get("scene_id") != scene_id or receipt.get("source_content_sha256") != source \
		or receipt.get("invocation_id") != invocation or receipt.get("failed") != 0 \
		or receipt.get("reported_failures") != 0 or not receipt.get("checks") is Array: return false
	var count: int = receipt.checks.size()
	if count == 0 or receipt.get("count") != count or receipt.get("passed") != count or receipt.get("reported_checks") != count: return false
	for index in count:
		var row: Variant = receipt.checks[index]
		if not row is Dictionary or row.get("id") != index+1 or row.get("passed") != true or not row.get("label") is String: return false
	return true
