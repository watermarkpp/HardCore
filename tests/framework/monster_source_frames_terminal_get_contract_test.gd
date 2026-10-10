extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SourceFrames := preload("res://scripts/monster_source_frames.gd")
const SOURCE := "res://scripts/monster_source_frames.gd"
var _proof := Proof.new()

func _check(condition: bool, label: String) -> void:
	_proof.record(condition, label)
	if not condition:
		push_error("B01 source-frame contract: " + label)

func _ready() -> void:
	await _real_owner_handoff_probe()
	var failure_count := 0
	for item: Dictionary in _proof.records:
		if not bool(item.passed):
			failure_count += 1
	var receipt_ok := _proof.write_receipt("monster_source_frames_terminal_get_contract_test", _proof.records.size(), failure_count)
	if not receipt_ok:
		failure_count += 1
	print("MONSTER_SOURCE_FRAMES_TERMINAL_GET_CONTRACT_%s" % ("PASS" if failure_count == 0 else "FAIL"))
	get_tree().quit(0 if failure_count == 0 else 1)

func _real_owner_handoff_probe() -> void:
	var profile: Dictionary = SourceFrames.profile_for_id(224)
	var records: Array = profile.get("frames", [])
	var path := ""
	if not records.is_empty() and records[0] is Dictionary:
		path = str((records[0] as Dictionary).get("path", ""))
	_check(not path.is_empty() and ResourceLoader.exists(path), "formal overlay frame path exists")
	SourceFrames.request(path)
	SourceFrames.poll()
	var source_diag: Dictionary = SourceFrames.diagnostics()
	_check(int(source_diag.get("requested", 0)) >= 1, "source-frame producer accepted a real request")
	var before: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	_check(SourceFrames.retire_pending_threaded_claims(), "source-frame owner handoff accepted")
	var after: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	_check(int(after.get("transferred", 0)) - int(before.get("transferred", 0)) >= 1, "source-frame claim transferred to resident owner")
	for _frame in range(120):
		if int(ContentLayers.threaded_resource_claim_diagnostics().get("get", 0)) - int(before.get("get", 0)) >= 1:
			break
		await get_tree().process_frame
	var final_diag: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	_check(int(final_diag.get("get", 0)) - int(before.get("get", 0)) >= 1, "resident owner consumed source-frame claim")
