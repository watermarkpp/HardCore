extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SOURCE := "res://scripts/startup_loading.gd"
var _proof := Proof.new()

func _check(condition: bool, label: String) -> void:
	_proof.record(condition, label)
	if not condition:
		push_error("B01 startup contract: " + label)

func _ready() -> void:
	await _real_owner_handoff_probe()
	var failure_count := 0
	for item: Dictionary in _proof.records:
		if not bool(item.passed):
			failure_count += 1
	var receipt_ok := _proof.write_receipt("startup_loading_terminal_get_contract_test", _proof.records.size(), failure_count)
	if not receipt_ok:
		failure_count += 1
	print("STARTUP_LOADING_TERMINAL_GET_CONTRACT_%s" % ("PASS" if failure_count == 0 else "FAIL"))
	get_tree().quit(0 if failure_count == 0 else 1)

func _real_owner_handoff_probe() -> void:
	var owner := StartupLoading.new()
	owner.target_scene_path_for_test = "res://scenes/character_select.tscn"
	owner._begin_target_load()
	var accepted := bool(owner._target_native_request_owned)
	var cached := ResourceLoader.has_cached(owner.target_scene_path_for_test)
	_check(accepted or cached, "startup target path follows real accepted-or-cached branch")
	var before: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	_check(owner.retire_threaded_resource_claims(), "startup handoff closes or transfers owned target")
	var after: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	if accepted:
		_check(int(after.get("transferred", 0)) - int(before.get("transferred", 0)) >= 1, "accepted startup target claim transferred")
	else:
		_check(int(after.get("transferred", 0)) == int(before.get("transferred", 0)), "cached startup target creates no foreign claim")
	var owner_wait_deadline_1 := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < owner_wait_deadline_1:
		if not accepted or int(ContentLayers.threaded_resource_claim_diagnostics().get("get", 0)) - int(before.get("get", 0)) >= 1:
			break
		await get_tree().process_frame
	if accepted:
		var final_diag: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
		_check(int(final_diag.get("get", 0)) == int(before.get("get", 0)) + 1, "resident owner actually consumed one startup claim")
		_check(int(final_diag.get("pending", 0)) == int(before.get("pending", 0)), "startup claim retirement finished")
	_check(owner.retire_threaded_resource_claims(), "repeated startup handoff is idempotent")
	_check(ContentLayers.threaded_resource_claim_diagnostics().get("transferred", 0) == after.get("transferred", 0), "startup does not transfer twice")
	owner.free()
