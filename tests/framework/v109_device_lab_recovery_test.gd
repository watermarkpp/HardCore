extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const DeviceLabRuntimeScript := preload("res://scripts/device_lab_runtime.gd")
const InventoryPanelScript := preload("res://tests/framework/inventory_panel.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var proof := Proof.new()
	await _test_interrupted_claim_is_retired(proof)
	_test_explicit_missing_target_fails_closed(proof)
	var failures := proof.records.filter(func(item: Dictionary) -> bool: return not bool(item.get("passed", false))).size()
	var receipt_ok: bool = proof.write_receipt("v109_device_lab_recovery_test", proof.records.size(), failures)
	print("V109_DEVICE_LAB_RECOVERY_%s interrupted_claim explicit_target" % ("PASS" if receipt_ok else "FAIL"))
	get_tree().quit(0 if receipt_ok else 1)

func _test_interrupted_claim_is_retired(proof: RefCounted) -> void:
	var nonce := "v109_interrupted_%d" % Time.get_ticks_usec()
	var claim := {
		"schemaVersion": 1,
		"nonce": nonce,
		"action": "ensure_chiyue_test_roster",
		"allowlist": [DeviceLabRuntimeScript.ALLOWLIST_ID, "ensure_chiyue_test_roster"],
	}
	proof.record(DeviceLabRuntimeScript.validate_command(claim).get("ok", false), "replay claim passes formal validation")
	var setup := DeviceLabRuntimeScript.new()
	add_child(setup)
	setup.call("_ensure_mailbox_dirs")
	var result_path := DeviceLabRuntimeScript.OUTBOX_DIR + "/result_%s.json" % nonce
	var existing_result := {"ok": true, "nonce": nonce, "protocolVersion": DeviceLabRuntimeScript.PROTOCOL_VERSION, "sentinel": "completed_before_restart"}
	var result_file := FileAccess.open(result_path, FileAccess.WRITE)
	result_file.store_string(JSON.stringify(existing_result))
	result_file.close()
	var claim_file := FileAccess.open(DeviceLabRuntimeScript.PROCESSING_PATH, FileAccess.WRITE)
	proof.record(claim_file != null, "processing claim fixture opens")
	if claim_file == null:
		return
	claim_file.store_string(JSON.stringify(claim))
	claim_file.close()
	setup.queue_free()
	await get_tree().process_frame
	var restarted := DeviceLabRuntimeScript.new()
	add_child(restarted)
	await get_tree().process_frame
	var result_bytes := FileAccess.get_file_as_bytes(result_path)
	proof.record(not FileAccess.file_exists(DeviceLabRuntimeScript.PROCESSING_PATH), "stale processing claim is retired at startup")
	proof.record(result_bytes == JSON.stringify(existing_result).to_utf8_buffer(), "existing result bytes are preserved")
	proof.record(bool(restarted.get("_processed_nonces").has(nonce)), "interrupted nonce is loaded and retained")
	var replay := JSON.stringify(claim).to_utf8_buffer()
	await restarted.call("_process_command_bytes", replay)
	proof.record(FileAccess.get_file_as_bytes(result_path) == result_bytes, "same nonce follow-up cannot replace completed result")
	restarted.queue_free()
	await get_tree().process_frame
	var reloaded := DeviceLabRuntimeScript.new()
	add_child(reloaded)
	await get_tree().process_frame
	proof.record(bool(reloaded.get("_processed_nonces").has(nonce)), "nonce history survives a second restart")
	var fresh_nonce := "v109_fresh_%d" % Time.get_ticks_usec()
	var fresh_claim := claim.duplicate(true)
	fresh_claim["nonce"] = fresh_nonce
	var fresh_file := FileAccess.open(DeviceLabRuntimeScript.PROCESSING_PATH, FileAccess.WRITE)
	proof.record(fresh_file != null, "fresh processing claim fixture opens")
	if fresh_file != null:
		fresh_file.store_string(JSON.stringify(fresh_claim))
		fresh_file.close()
	reloaded.queue_free()
	await get_tree().process_frame
	var fresh_runtime := DeviceLabRuntimeScript.new()
	add_child(fresh_runtime)
	await get_tree().process_frame
	var fresh_result_path := DeviceLabRuntimeScript.OUTBOX_DIR + "/result_%s.json" % fresh_nonce
	proof.record(FileAccess.file_exists(fresh_result_path), "unpublished claim receives interrupted result")
	var fresh_result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fresh_result_path)) as Dictionary
	proof.record(fresh_result.get("error", "") == "interrupted", "new interruption is explicitly marked")
	proof.record(not FileAccess.file_exists(DeviceLabRuntimeScript.PROCESSING_PATH), "published interruption retires fresh claim")
	fresh_runtime.queue_free()

func _test_explicit_missing_target_fails_closed(proof: RefCounted) -> void:
	var root := Node.new()
	root.name = "RecoveryRoot"
	add_child(root)
	var first := Control.new()
	first.name = "InventoryA"
	first.set_script(InventoryPanelScript)
	root.add_child(first)
	var second := Control.new()
	second.name = "InventoryB"
	second.set_script(InventoryPanelScript)
	root.add_child(second)
	var runtime := DeviceLabRuntimeScript.new()
	runtime.configure(root)
	add_child(runtime)
	var implicit: Variant = runtime.call("_find_profile_target", "inventory", "")
	proof.record(implicit == first, "omitted target uses the default profile target")
	var missing: Variant = runtime.call("_find_profile_target", "inventory", "/MissingInventory")
	proof.record(missing == null, "missing explicit rootPath fails closed")
	var hidden := Control.new()
	hidden.name = "HiddenInventory"
	hidden.visible = false
	hidden.set_script(InventoryPanelScript)
	root.add_child(hidden)
	var hidden_path := str(root.get_path_to(hidden))
	var hidden_target: Variant = runtime.call("_find_profile_target", "inventory", hidden_path)
	proof.record(hidden_target == hidden, "explicit hidden target resolves exactly")
	runtime.queue_free()
	root.queue_free()
