extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SOURCE := "res://scripts/monster_visual_streaming_coordinator.gd"

var _proof := Proof.new()

func _check(condition: bool, label: String) -> void:
	_proof.record(condition, label)
	if not condition:
		push_error("B01 visual contract: " + label)

func _ready() -> void:
	await _real_owner_handoff_probe()
	var failure_count := 0
	for item: Dictionary in _proof.records:
		if not bool(item.passed):
			failure_count += 1
	var receipt_ok := _proof.write_receipt(
		"monster_visual_streaming_terminal_get_contract_test",
		_proof.records.size(),
		failure_count,
	)
	if not receipt_ok:
		failure_count += 1
	print("MONSTER_VISUAL_STREAMING_TERMINAL_GET_CONTRACT_%s" % ("PASS" if failure_count == 0 else "FAIL"))
	get_tree().quit(0 if failure_count == 0 else 1)

func _real_owner_handoff_probe() -> void:
	var helper := MonsterVisual.new()
	var data: Dictionary = GameData.get_monster_by_id(19)
	var mapping: Dictionary = helper._client_mapping_for(data)
	_check(not mapping.is_empty(), "formal GameData mapping exists")
	var actions: Dictionary = mapping.get("actions", {})
	_check(actions.size() == 5, "formal mapping has five action claims")
	var first_path := ""
	for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
		var action: Dictionary = actions.get(action_name, {})
		var path := str(action.get("path", ""))
		_check(not path.is_empty() and ResourceLoader.exists(path), "formal action path exists: " + action_name)
		if first_path.is_empty():
			first_path = path
	var foreign_error := ResourceLoader.load_threaded_request(first_path, "Texture2D", false, ResourceLoader.CACHE_MODE_IGNORE)
	_check(foreign_error == OK, "foreign same-path claim accepted")
	var coordinator := MonsterVisualStreamingCoordinator.new()
	coordinator.configure_process_owner(self)
	coordinator.request_client_profile(mapping, 19, 1)
	var accepted_count := 0
	var owner_wait_deadline_1 := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < owner_wait_deadline_1:
		coordinator._pump_threaded_profile_queue()
		accepted_count = 0
		for job: Dictionary in coordinator._threaded_profile_requests.values():
			for count: int in job.get("native_requested_paths", {}).values():
				accepted_count += count
		if accepted_count == 5:
			break
		await get_tree().process_frame
	_check(accepted_count == 5, "coordinator accepted all five real action claims")
	var before: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	_check(coordinator.retire_threaded_resource_claims(), "visual owner handoff accepted")
	var after_transfer: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	_check(int(after_transfer.get("transferred", 0)) - int(before.get("transferred", 0)) == 5, "five claims transferred to resident owner")
	var owner_wait_deadline_2 := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < owner_wait_deadline_2:
		if int(ContentLayers.threaded_resource_claim_diagnostics().get("get", 0)) - int(before.get("get", 0)) >= 5:
			break
		await get_tree().process_frame
	var after_get: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	_check(int(after_get.get("get", 0)) - int(before.get("get", 0)) == 5, "resident owner eventually consumes exactly five claims")
	var transferred_before_retry := int(after_get.get("transferred", 0))
	_check(coordinator.retire_threaded_resource_claims(), "repeated visual handoff is idempotent")
	var after_retry: Dictionary = ContentLayers.threaded_resource_claim_diagnostics()
	_check(int(after_retry.get("transferred", 0)) == transferred_before_retry, "repeated handoff adds no claims")
	var foreign_status := ResourceLoader.load_threaded_get_status(first_path)
	_check(foreign_status == ResourceLoader.THREAD_LOAD_LOADED, "foreign same-path claim remains observable")
	if foreign_status in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
		ResourceLoader.load_threaded_get(first_path)
	helper.free()
	coordinator = null
