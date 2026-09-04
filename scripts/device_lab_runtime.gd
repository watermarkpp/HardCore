class_name DeviceLabRuntime
extends Node

## Debug-only, file-mailbox bridge for the Android Device Lab.
##
## The bridge deliberately has no socket, eval, or arbitrary path API.  Its
## save replacement endpoint is schema-checked, debug-only, checkpointed, and
## limited to the active experimental character.
## A host writes one small command to user://device_lab/inbox/pending.json;
## this node atomically claims it, validates it, performs a bounded read-only
## action, and publishes user://device_lab/outbox/result_<nonce>.json.

const UIRuntimeLayoutOverridesScript := preload("res://scripts/ui_runtime_layout_overrides.gd")

const PROTOCOL_VERSION := 1
const POLL_INTERVAL_SECONDS := 0.15
const MAX_COMMAND_BYTES := 64 * 1024
## A fully populated experimental character may contain 100 bag records and
## 500 warehouse records.  Keep this bounded, but large enough to round-trip
## the production save schema without inventing a lossy lab format.
const MAX_PAYLOAD_BYTES := 4 * 1024 * 1024
const MAX_NONCE_LENGTH := 64
const MAX_SNAPSHOT_DEPTH := 12
const MAX_SNAPSHOT_NODES := 1024
const MAX_SNAPSHOT_CONTROLS := 320
const MAX_SNAPSHOT_NODE2D := 320
const MAX_SNAPSHOT_ENEMY_ACTIVITY_SCAN := 512
const MAX_TEXT_HASH_BYTES := 16 * 1024
const MAX_RESULT_BYTES := 4 * 1024 * 1024
const MAX_OUTBOX_ENTRIES := 32
const MAX_OUTBOX_TOTAL_BYTES := 16 * 1024 * 1024
const MAX_OUTBOX_AGE_SECONDS := 7 * 24 * 60 * 60
const MAX_PROCESSED_NONCES := 256
const ALLOWLIST_ID := "device_lab.v1"
const INBOX_DIR := "user://device_lab/inbox"
const OUTBOX_DIR := "user://device_lab/outbox"
const PENDING_PATH := INBOX_DIR + "/pending.json"
const PROCESSING_PATH := INBOX_DIR + "/processing.json"
const NONCE_HISTORY_PATH := "user://device_lab/nonce_history.json"
const CHECKPOINT_DIR := "user://device_lab/checkpoints"
const MAX_CHECKPOINTS := 20

const COMMON_COMMAND_FIELDS := {
	"schemaVersion": true,
	"nonce": true,
	"action": true,
	"allowlist": true,
}
const ACTION_COMMAND_FIELDS := {
	"status": {},
	"snapshot": {},
	"reset_diagnostics": {},
	"read_diagnostics": {},
	"stop_diagnostics": {},
	"repair_diagnostics": {},
	"export_player_state": {},
	"ensure_chiyue_test_roster": {},
	"list_checkpoints": {},
	"apply_ui_profile": {
		"profile": true,
		"path": true,
		"checksum": true,
		"size": true,
		"layout": true,
		"rootPath": true,
	},
	"apply_player_state": {
		"path": true,
		"checksum": true,
		"size": true,
	},
	"rollback_player_state": {
		"checkpoint": true,
	},
	"rollback_ui_profile": {
		"checkpoint": true,
	},
}

const PROFILE_SCRIPT_SUFFIXES := {
	"character_hall": "/character_select.gd",
	"confirmation_dialog": "/gothic_confirmation_panel.gd",
	"death_revival": "/death_revival_panel.gd",
	"inventory": "/inventory_panel.gd",
	"map": "/map_panel.gd",
	"quest": "/quest_panel.gd",
	"shop_buy": "/shop_panel.gd",
	"shop_sell": "/shop_panel.gd",
	"skill": "/skill_panel.gd",
	"system_menu": "/system_menu_panel.gd",
	"warehouse": "/warehouse_panel.gd",
}

const ENEMY_DIAGNOSTIC_FIELDS := RuntimeDiagnostics.PERFORMANCE_FIELDS

const MONSTER_STREAMING_DIAGNOSTIC_FIELDS := [
	"registered_visual_count",
	"request_enqueue_count",
	"unique_request_count",
	"duplicate_request_count",
	"active_request_count",
	"queued_request_count",
	"loading_request_count",
	"loaded_request_count",
	"failed_request_count",
	"ready_resource_count",
	"decoded_rgba8_bytes",
	"protected_overbudget_bytes",
	"failed_resource_count",
	"status_poll_count",
	"resource_apply_count",
	"stale_completion_count",
	"waiting_visual_count",
	"leased_visual_count",
	"leased_profile_count",
	"pin_rejection_count",
	"immediate_eviction_count",
	"same_key_reload_count",
	"evicted_before_first_apply_count",
	"late_completion_resident_skip_count",
]

var _game_root: Node
var _poll_elapsed := 0.0
var _busy := false
var _last_command_nonce := ""
var _processed_nonces: Dictionary = {}
var _processed_nonce_order: Array[String] = []
var _debug_gate_override := -1
var _mailbox_initialized := false


func configure(game_root: Node) -> DeviceLabRuntime:
	_game_root = game_root
	return self


## Test-only gate injection.  No production caller sets this value; it lets a
## headless test prove that a non-debug service never initializes user://.
func set_debug_gate_for_test(enabled: bool) -> void:
	_debug_gate_override = 1 if enabled else 0


func mailbox_initialized_for_test() -> bool:
	return _mailbox_initialized


func _debug_enabled() -> bool:
	return OS.is_debug_build() if _debug_gate_override < 0 else _debug_gate_override == 1


func _ready() -> void:
	# A release APK has no active mailbox even if a stale user:// directory is
	# present. OS.is_debug_build() is the only activation gate in this service.
	if not _debug_enabled():
		set_process(false)
		return
	_ensure_mailbox_dirs()
	_load_nonce_history()
	_prune_outbox()
	if _game_root == null:
		_game_root = get_parent()


func _process(delta: float) -> void:
	if not _debug_enabled():
		return
	# DeviceLab is the sole per-frame sampling owner. RuntimeDiagnostics still
	# applies the explicit Debug/performance gate, so a normal Debug build and
	# every Release build remain free of frame-sample work unless a diagnostics
	# window was deliberately opened by the lab command.
	RuntimeDiagnostics.record_frame_time_ms(maxf(delta, 0.0) * 1000.0)
	if _busy:
		return
	_poll_elapsed += maxf(delta, 0.0)
	if _poll_elapsed < POLL_INTERVAL_SECONDS:
		return
	_poll_elapsed = 0.0
	_poll_inbox()


func _poll_inbox() -> void:
	if _busy or not FileAccess.file_exists(PENDING_PATH):
		return
	# Claim the command before parsing. A host can safely write a new pending
	# command only after this rename has completed.
	if FileAccess.file_exists(PROCESSING_PATH):
		return
	var inbox := DirAccess.open(INBOX_DIR)
	if inbox == null or inbox.rename("pending.json", "processing.json") != OK:
		return
	_busy = true
	var bytes := FileAccess.get_file_as_bytes(PROCESSING_PATH)
	var command := _parse_command(bytes)
	var nonce := str(command.get("nonce", ""))
	if nonce.is_empty():
		nonce = "invalid_%d" % Time.get_ticks_msec()
	_last_command_nonce = nonce
	var result: Dictionary
	if bool(command.get("ok", false)) and _processed_nonces.has(nonce):
		result = _error_result({"error": "nonce_replay"})
		# A replay must never replace the first result for this nonce.
		_write_result(nonce, result)
		DirAccess.remove_absolute(PROCESSING_PATH)
		_busy = false
		return
	if bool(command.get("ok", false)):
		_remember_nonce(nonce)
	if not bool(command.get("ok", false)):
		result = _error_result(command)
	else:
		result = await _execute(command["command"] as Dictionary)
	var raw_command: Variant = command.get("command", {})
	if raw_command is Dictionary:
		_remove_payload(raw_command as Dictionary)
	_write_result(nonce, result)
	DirAccess.remove_absolute(PROCESSING_PATH)
	_busy = false


func _parse_command(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_COMMAND_BYTES:
		return {"ok": false, "error": "command_too_large", "nonce": ""}
	if bytes.is_empty():
		return {"ok": false, "error": "command_empty", "nonce": ""}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		return {"ok": false, "error": "command_json", "nonce": ""}
	var raw := parsed as Dictionary
	var nonce := str(raw.get("nonce", ""))
	var validation := validate_command(raw)
	validation["nonce"] = nonce
	if bool(validation.get("ok", false)):
		validation["command"] = raw
	return validation


func _load_nonce_history() -> void:
	_processed_nonces.clear()
	_processed_nonce_order.clear()
	if not FileAccess.file_exists(NONCE_HISTORY_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(NONCE_HISTORY_PATH))
	if not parsed is Array:
		return
	for value: Variant in parsed as Array:
		var nonce := str(value)
		if not _is_safe_token(nonce) or _processed_nonces.has(nonce):
			continue
		_processed_nonces[nonce] = true
		_processed_nonce_order.append(nonce)
		if _processed_nonce_order.size() >= MAX_PROCESSED_NONCES:
			break


func _remember_nonce(nonce: String) -> void:
	if _processed_nonces.has(nonce):
		return
	_processed_nonces[nonce] = true
	_processed_nonce_order.append(nonce)
	while _processed_nonce_order.size() > MAX_PROCESSED_NONCES:
		var expired: String = _processed_nonce_order.pop_front()
		_processed_nonces.erase(expired)
	var temporary := NONCE_HISTORY_PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_processed_nonce_order))
	file.flush()
	file.close()
	var root_dir := DirAccess.open("user://device_lab")
	if root_dir != null:
		root_dir.rename("nonce_history.json.tmp", "nonce_history.json")


## Pure protocol validation used by the runtime and headless tests.
static func validate_command(command: Dictionary) -> Dictionary:
	if int(command.get("schemaVersion", 0)) != PROTOCOL_VERSION:
		return {"ok": false, "error": "schema_version"}
	var nonce := str(command.get("nonce", ""))
	if nonce.is_empty() or nonce.length() > MAX_NONCE_LENGTH or not _is_safe_token(nonce):
		return {"ok": false, "error": "nonce"}
	var action := str(command.get("action", ""))
	if action not in ["status", "snapshot", "reset_diagnostics", "read_diagnostics", "stop_diagnostics", "repair_diagnostics", "export_player_state", "ensure_chiyue_test_roster", "list_checkpoints", "apply_ui_profile", "apply_player_state", "rollback_player_state", "rollback_ui_profile"]:
		return {"ok": false, "error": "unknown_action"}
	var allowed_fields: Dictionary = COMMON_COMMAND_FIELDS.duplicate()
	var action_fields: Dictionary = ACTION_COMMAND_FIELDS.get(action, {})
	for field: Variant in action_fields.keys():
		allowed_fields[str(field)] = true
	for raw_key: Variant in command.keys():
		if not allowed_fields.has(str(raw_key)):
			return {"ok": false, "error": "unknown_field:%s" % str(raw_key)}
	var allowlist: Variant = command.get("allowlist", [])
	if allowlist is String:
		if str(allowlist) != ALLOWLIST_ID:
			return {"ok": false, "error": "allowlist"}
	elif allowlist is Array:
		if allowlist.size() != 2 or not ALLOWLIST_ID in allowlist or not action in allowlist:
			return {"ok": false, "error": "allowlist"}
	else:
		return {"ok": false, "error": "allowlist"}
	if command.has("path"):
		var path_result := _validate_payload_path(str(command.get("path", "")))
		if not bool(path_result.get("ok", false)):
			return path_result
		if not command.has("checksum") or not command.has("size"):
			return {"ok": false, "error": "payload_metadata"}
		if int(command.get("size", -1)) < 0 or int(command.get("size", -1)) > MAX_PAYLOAD_BYTES:
			return {"ok": false, "error": "payload_size"}
		var checksum := str(command.get("checksum", "")).to_upper()
		if checksum.length() != 64 or not _is_hex(checksum):
			return {"ok": false, "error": "payload_checksum"}
	if action == "apply_ui_profile":
		var profile := str(command.get("profile", ""))
		if not UIRuntimeLayoutOverridesScript.KNOWN_PROFILE_IDS.has(profile):
			return {"ok": false, "error": "unknown_profile"}
		if command.has("path") == command.has("layout"):
			return {"ok": false, "error": "profile_payload_ambiguous"}
		if not command.has("path") and not command.has("layout"):
			return {"ok": false, "error": "profile_payload_missing"}
	if action == "apply_player_state" and not command.has("path"):
		return {"ok": false, "error": "player_state_payload_missing"}
	if action in ["rollback_player_state", "rollback_ui_profile"]:
		var checkpoint := str(command.get("checkpoint", ""))
		if not _is_safe_token(checkpoint) or checkpoint.contains(".."):
			return {"ok": false, "error": "checkpoint"}
	if command.has("rootPath"):
		var root_path := str(command.get("rootPath", ""))
		if root_path.length() > 256 or root_path.contains("..") or root_path.contains("\\") or root_path.begins_with("/"):
			return {"ok": false, "error": "root_path"}
	return {"ok": true}


static func _validate_payload_path(path: String) -> Dictionary:
	if path.is_empty() or path.length() > 256 or not path.begins_with(INBOX_DIR + "/"):
		return {"ok": false, "error": "payload_path"}
	var base := path.trim_prefix(INBOX_DIR + "/")
	if base.is_empty() or base.contains("/") or base.contains("\\") or base.contains("..") or base.begins_with("."):
		return {"ok": false, "error": "payload_path"}
	if not _is_safe_token(base.replace(".json", "")):
		return {"ok": false, "error": "payload_path"}
	return {"ok": true}


static func _is_safe_token(value: String) -> bool:
	if value.is_empty():
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9") or character in ["_", "-", "."]):
			return false
	return true


static func _is_hex(value: String) -> bool:
	for character in value:
		if not ((character >= "0" and character <= "9") or (character >= "A" and character <= "F")):
			return false
	return true


func _execute(command: Dictionary) -> Dictionary:
	var action := str(command.get("action", ""))
	match action:
		"status":
			return {"ok": true, "action": action, "status": status_snapshot()}
		"snapshot":
			return {"ok": true, "action": action, "snapshot": build_snapshot(_game_root)}
		"reset_diagnostics":
			if not RuntimeDiagnostics.set_device_lab_performance_enabled(true):
				return {"ok": false, "action": action, "error": "performance_unavailable"}
			RuntimeDiagnostics.reset_performance_window()
			return {
				"ok": true,
				"action": action,
				"performance_diagnostics": _performance_window_snapshot(_game_root),
			}
		"read_diagnostics":
			return {
				"ok": true,
				"action": action,
				"performance_diagnostics": _performance_window_snapshot(_game_root),
			}
		"stop_diagnostics":
			if not RuntimeDiagnostics.set_device_lab_performance_enabled(false):
				return {"ok": false, "action": action, "error": "performance_unavailable"}
			return {
				"ok": true,
				"action": action,
				"performance_diagnostics": _performance_window_snapshot(_game_root),
			}
		"repair_diagnostics":
			return _repair_diagnostics()
		"export_player_state":
			return _export_player_state()
		"ensure_chiyue_test_roster":
			return _ensure_chiyue_test_roster()
		"list_checkpoints":
			return {"ok": true, "action": action, "checkpoints": _list_checkpoints()}
		"apply_ui_profile":
			return await _apply_ui_profile(command)
		"apply_player_state":
			return _apply_player_state(command)
		"rollback_player_state":
			return _rollback_player_state(command)
		"rollback_ui_profile":
			return await _rollback_ui_profile(command)
		_:
			return _error_result({"error": "unknown_action"})


func status_snapshot() -> Dictionary:
	var patch_status := {
		"loadedPatchId": "",
		"loadedPatchSha256": "",
		"loadError": "",
	}
	var patch_loader := get_node_or_null("/root/DeviceLabPatch")
	if patch_loader != null:
		patch_status["loadedPatchId"] = str(patch_loader.get("loaded_patch_id"))
		patch_status["loadedPatchSha256"] = str(patch_loader.get("loaded_patch_sha256"))
		patch_status["loadError"] = str(patch_loader.get("load_error"))
	return {
		"protocolVersion": PROTOCOL_VERSION,
		"allowlist": ALLOWLIST_ID,
		"debugBuild": _debug_enabled(),
		"pollIntervalMs": int(POLL_INTERVAL_SECONDS * 1000.0),
		"inbox": PENDING_PATH,
		"outbox": OUTBOX_DIR,
		"lastCommandNonce": _last_command_nonce,
		"capabilities": ["ui_profile", "player_state", "chiyue_test_roster", "checkpoints", "snapshot", "reset_diagnostics", "read_diagnostics", "stop_diagnostics", "frame_sampling", "repair_diagnostics", "resource_patch"],
		"resourcePatch": patch_status,
	}


func _repair_diagnostics() -> Dictionary:
	var context: Dictionary = GameData.merchant_context("starter_gear")
	var plan: Dictionary = PlayerState._repair_plan(context)
	var quoted_by_slot := {}
	for raw_entry: Variant in plan.get("entries", []):
		if raw_entry is Dictionary:
			quoted_by_slot[str((raw_entry as Dictionary).get("slot", ""))] = (raw_entry as Dictionary).get("quote", {})
	var equipment_rows: Array[Dictionary] = []
	for slot: String in PlayerState.EQUIPMENT_SLOTS:
		var instance: Variant = PlayerState.equipment.get(slot, {})
		if not instance is Dictionary or instance.is_empty():
			continue
		var item_name := str((instance as Dictionary).get("name", ""))
		# Repair authority resolves the stable item/service identity first. The
		# display name is retained only for diagnostics and old-save fallback.
		var price_record: Dictionary = GameData.get_item_price_record(instance)
		var catalog: Dictionary = GameData.get_item_record(instance)
		var direct_quote: Dictionary = PricingService.quote_repair(
			price_record,
			catalog,
			(instance as Dictionary).duplicate(true),
			context
		)
		equipment_rows.append({
			"slot": slot,
			"item": item_name,
			"itemId": int(catalog.get("itemId", (instance as Dictionary).get("item_id", (instance as Dictionary).get("itemId", -1)))),
			"serviceIndex": int(price_record.get("service_index", (instance as Dictionary).get("service_index", (instance as Dictionary).get("serviceIndex", -1)))),
			"durabilityRaw": int((instance as Dictionary).get("durability_raw", -1)),
			"maximumDurabilityRaw": int((instance as Dictionary).get("max_durability_raw", -1)),
			"priceRecord": price_record,
			"quote": direct_quote,
			"planned": quoted_by_slot.has(slot),
		})
	return {
		"ok": true,
		"action": "repair_diagnostics",
		"context": context,
		"plan": plan,
		"equipment": equipment_rows,
	}


func _export_player_state() -> Dictionary:
	var document: Dictionary = PlayerState.device_lab_active_save_document()
	if document.is_empty():
		return _error_result({"error": "active_save_unavailable"})
	return {
		"ok": true,
		"action": "export_player_state",
		"document": document,
		"checksum": _sha256(JSON.stringify(document).to_utf8_buffer()),
	}


func _ensure_chiyue_test_roster() -> Dictionary:
	var result: Dictionary = PlayerState.ensure_chiyue_test_roster()
	result["action"] = "ensure_chiyue_test_roster"
	return result


func _apply_player_state(command: Dictionary) -> Dictionary:
	var loaded := _load_json_payload(command)
	if not bool(loaded.get("ok", false)):
		return _error_result(loaded)
	var document: Variant = loaded.get("data", {})
	if not document is Dictionary:
		return _error_result({"error": "player_state_json"})
	var checkpoint := _create_player_checkpoint(str(command.get("nonce", "")))
	if checkpoint.is_empty():
		return _error_result({"error": "checkpoint_failed"})
	var result: Dictionary = PlayerState.device_lab_apply_save_document(document as Dictionary)
	result["action"] = "apply_player_state"
	result["checkpoint"] = checkpoint
	return result


func _rollback_player_state(command: Dictionary) -> Dictionary:
	var checkpoint := str(command.get("checkpoint", ""))
	var path := CHECKPOINT_DIR + "/%s.json" % checkpoint
	if not FileAccess.file_exists(path):
		return _error_result({"error": "checkpoint_not_found"})
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or str((parsed as Dictionary).get("kind", "player_state")) != "player_state":
		return _error_result({"error": "checkpoint_json"})
	var document: Dictionary = (parsed as Dictionary).get("document", parsed) as Dictionary
	var before_rollback := _create_player_checkpoint("before_rollback_%s" % str(command.get("nonce", "")))
	if before_rollback.is_empty():
		return _error_result({"error": "checkpoint_failed"})
	var result: Dictionary = PlayerState.device_lab_apply_save_document(document)
	result["action"] = "rollback_player_state"
	result["restoredCheckpoint"] = checkpoint
	result["undoCheckpoint"] = before_rollback
	return result


func _load_json_payload(command: Dictionary) -> Dictionary:
	var path := str(command.get("path", ""))
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > MAX_PAYLOAD_BYTES:
		return {"ok": false, "error": "payload_size"}
	if int(command.get("size", -1)) != bytes.size():
		return {"ok": false, "error": "payload_size_mismatch"}
	if _sha256(bytes) != str(command.get("checksum", "")).to_upper():
		return {"ok": false, "error": "payload_checksum_mismatch"}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if parsed == null:
		return {"ok": false, "error": "payload_json"}
	return {"ok": true, "data": parsed}


func _create_player_checkpoint(label: String) -> String:
	var document: Dictionary = PlayerState.device_lab_active_save_document()
	if document.is_empty():
		return ""
	return _write_checkpoint(label, {"kind": "player_state", "document": document})


func _write_checkpoint(label: String, payload: Dictionary) -> String:
	var safe_label := label if _is_safe_token(label) else "checkpoint_%d" % Time.get_ticks_msec()
	var name := "%d_%s" % [int(Time.get_unix_time_from_system()), safe_label.left(48)]
	var path := CHECKPOINT_DIR + "/%s.json" % name
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file.close()
	var directory := DirAccess.open(CHECKPOINT_DIR)
	if directory == null or directory.rename("%s.json.tmp" % name, "%s.json" % name) != OK:
		DirAccess.remove_absolute(path + ".tmp")
		return ""
	_prune_checkpoints()
	return name


func _create_ui_checkpoint(profile_id: String, root_path: String, contract: Dictionary, label: String) -> String:
	if contract.is_empty():
		return ""
	return _write_checkpoint(label, {
		"kind": "ui_profile",
		"profile": profile_id,
		"rootPath": root_path,
		"contract": contract,
	})


func _list_checkpoints() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for file_name: String in DirAccess.get_files_at(CHECKPOINT_DIR):
		if file_name.ends_with(".json") and _is_safe_token(file_name.trim_suffix(".json")):
			var path := CHECKPOINT_DIR + "/" + file_name
			var kind := "unknown"
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				kind = str((parsed as Dictionary).get("kind", "player_state"))
			result.append({"id": file_name.trim_suffix(".json"), "kind": kind, "bytes": _file_size(path), "modified": FileAccess.get_modified_time(path)})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.modified) > int(b.modified))
	return result


func _prune_checkpoints() -> void:
	var records := _list_checkpoints()
	for index in range(MAX_CHECKPOINTS, records.size()):
		DirAccess.remove_absolute(CHECKPOINT_DIR + "/%s.json" % str(records[index].id))


func _apply_ui_profile(command: Dictionary) -> Dictionary:
	var profile_id := str(command.get("profile", ""))
	var contract_result := _load_external_contract(command)
	if not bool(contract_result.get("ok", false)):
		return _error_result(contract_result)
	var contract := contract_result["contract"] as Dictionary
	var validation := UIRuntimeLayoutOverridesScript.validate_external_profile(profile_id, contract)
	if not bool(validation.get("ok", false)):
		return _error_result(validation)
	var target := _find_profile_target(profile_id, str(command.get("rootPath", "")))
	if target == null:
		return _error_result({"error": "profile_target_not_found"})
	var root_path := str(_game_root.get_path_to(target)) if _game_root != null else ""
	var profile: Dictionary = (contract.get("profiles", {}) as Dictionary).get(profile_id, {})
	var before_contract := UIRuntimeLayoutOverridesScript.capture_external_profile(target, profile_id, profile.get("nodes", {}))
	var checkpoint := _create_ui_checkpoint(profile_id, root_path, before_contract, "ui_%s_%s" % [profile_id, str(command.get("nonce", ""))])
	if checkpoint.is_empty():
		return _error_result({"error": "checkpoint_failed"})
	# External writes use the transactional loader.  It validates the complete
	# plan, backs up every property, and reports rollback instead of claiming a
	# successful apply when the scene changes mid-commit.
	var transaction: Dictionary = await UIRuntimeLayoutOverridesScript.apply_external_profile_transaction(
		target,
		profile_id,
		contract
	)
	transaction["action"] = "apply_ui_profile"
	transaction["checkpoint"] = checkpoint
	transaction["targetPath"] = str(_game_root.get_path_to(target)) if _game_root != null and is_instance_valid(target) else ""
	if bool(transaction.get("ok", false)):
		transaction["actual"] = _snapshot_control_subtree(target)
	return transaction


func _rollback_ui_profile(command: Dictionary) -> Dictionary:
	var checkpoint := str(command.get("checkpoint", ""))
	var path := CHECKPOINT_DIR + "/%s.json" % checkpoint
	if not FileAccess.file_exists(path):
		return _error_result({"error": "checkpoint_not_found"})
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or str((parsed as Dictionary).get("kind", "")) != "ui_profile":
		return _error_result({"error": "checkpoint_kind"})
	var saved := parsed as Dictionary
	var profile_id := str(saved.get("profile", ""))
	var contract: Variant = saved.get("contract", {})
	if not contract is Dictionary:
		return _error_result({"error": "checkpoint_json"})
	var target := _find_profile_target(profile_id, str(saved.get("rootPath", "")))
	if target == null:
		return _error_result({"error": "profile_target_not_found"})
	var profile: Dictionary = ((contract as Dictionary).get("profiles", {}) as Dictionary).get(profile_id, {})
	var undo_contract := UIRuntimeLayoutOverridesScript.capture_external_profile(target, profile_id, profile.get("nodes", {}))
	var undo := _create_ui_checkpoint(profile_id, str(saved.get("rootPath", "")), undo_contract, "ui_undo_%s" % str(command.get("nonce", "")))
	if undo.is_empty():
		return _error_result({"error": "checkpoint_failed"})
	var result: Dictionary = await UIRuntimeLayoutOverridesScript.apply_external_profile_transaction(target, profile_id, contract as Dictionary)
	result["action"] = "rollback_ui_profile"
	result["restoredCheckpoint"] = checkpoint
	result["undoCheckpoint"] = undo
	return result


func _load_external_contract(command: Dictionary) -> Dictionary:
	var parsed: Variant
	if command.has("path"):
		var path := str(command.get("path", ""))
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() > MAX_PAYLOAD_BYTES:
			return {"ok": false, "error": "payload_size"}
		if int(command.get("size", -1)) != bytes.size():
			return {"ok": false, "error": "payload_size_mismatch"}
		if _sha256(bytes) != str(command.get("checksum", "")).to_upper():
			return {"ok": false, "error": "payload_checksum_mismatch"}
		parsed = JSON.parse_string(bytes.get_string_from_utf8())
	else:
		parsed = command.get("layout", {})
	if not parsed is Dictionary:
		return {"ok": false, "error": "profile_json"}
	var profile_id := str(command.get("profile", ""))
	var source := parsed as Dictionary
	if source.has("nodes") and not source.has("profiles"):
		source = {"schemaVersion": UIRuntimeLayoutOverridesScript.SCHEMA_VERSION, "profiles": {profile_id: source}}
	return {"ok": true, "contract": source}


func _find_profile_target(profile_id: String, requested_path: String) -> Control:
	if _game_root == null or not is_instance_valid(_game_root):
		return null
	var candidates: Array[Control] = []
	_collect_profile_candidates(_game_root, profile_id, candidates, 0)
	for candidate: Control in candidates:
		var candidate_path := str(_game_root.get_path_to(candidate))
		if not requested_path.is_empty() and candidate_path != requested_path:
			continue
		if candidate.is_visible_in_tree():
			return candidate
	if not requested_path.is_empty():
		for candidate: Control in candidates:
			if str(_game_root.get_path_to(candidate)) == requested_path:
				return candidate
	return candidates[0] if not candidates.is_empty() else null


func _collect_profile_candidates(node: Node, profile_id: String, result: Array[Control], depth: int) -> void:
	if node == null or depth > MAX_SNAPSHOT_DEPTH or result.size() >= 16:
		return
	if node is Control and _control_matches_profile(node as Control, profile_id):
		result.append(node as Control)
	for child in node.get_children():
		_collect_profile_candidates(child as Node, profile_id, result, depth + 1)


func _control_matches_profile(control: Control, profile_id: String) -> bool:
	var script: Script = control.get_script()
	if script == null:
		return false
	var suffix := str(PROFILE_SCRIPT_SUFFIXES.get(profile_id, ""))
	return not suffix.is_empty() and str(script.resource_path).ends_with(suffix)


## Builds the bounded, content-redacted runtime snapshot requested by the host.
static func build_snapshot(root: Node) -> Dictionary:
	_record_engine_window_sample()
	var enemy_activity := _enemy_activity_snapshot(root)
	var snapshot := {
		"timestamp": Time.get_unix_time_from_system(),
		"frame": Engine.get_process_frames(),
		"fps": Engine.get_frames_per_second(),
		"performance": _performance_snapshot(),
		"window": _window_snapshot(root),
		"scene": _scene_snapshot(root),
		"map": _map_snapshot(root),
		"player": _player_snapshot(root),
		"enemy_activity": enemy_activity,
		"loot_runtime": _loot_runtime_snapshot(root),
		"performance_diagnostics": _performance_window_snapshot(root, enemy_activity),
		"monster_streaming": _monster_streaming_snapshot(root),
		"controls": [],
		"node2d": [],
		"limits": {
			"maxDepth": MAX_SNAPSHOT_DEPTH,
			"maxNodes": MAX_SNAPSHOT_NODES,
			"maxControls": MAX_SNAPSHOT_CONTROLS,
			"maxNode2D": MAX_SNAPSHOT_NODE2D,
		},
	}
	if root == null or not is_instance_valid(root):
		return snapshot
	var state := {"nodes": 0, "controls": 0, "node2d": 0}
	_collect_snapshot(root, root, 0, snapshot, state)
	return snapshot


static func _record_engine_window_sample() -> void:
	RuntimeDiagnostics.add_performance_value(
		&"draw_calls",
		_performance_value(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	)
	RuntimeDiagnostics.add_performance_value(
		&"render_primitives",
		_performance_value(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
	)
	RuntimeDiagnostics.add_performance_value(
		&"texture_mem",
		_performance_value(Performance.RENDER_TEXTURE_MEM_USED),
	)
	RuntimeDiagnostics.add_performance_value(
		&"video_mem",
		_performance_value(Performance.RENDER_VIDEO_MEM_USED),
	)


static func _performance_window_snapshot(
	root: Node,
	enemy_activity: Dictionary = {},
) -> Dictionary:
	var activity := enemy_activity
	if activity.is_empty():
		activity = _enemy_activity_snapshot(root)
	return RuntimeDiagnostics.read_performance_window(
		_performance_context(root, activity)
	)


static func _performance_context(root: Node, activity: Dictionary) -> Dictionary:
	var player_position := Vector2.ZERO
	var player_profession := ""
	var raw_player: Variant = root.get("player") if root != null else null
	if raw_player is Node2D and is_instance_valid(raw_player):
		player_position = (raw_player as Node2D).global_position
		player_profession = str((raw_player as Node).get("profession_id"))
	var map := _map_snapshot(root)
	var scene := _scene_snapshot(root)
	var nearby_1600 := int(activity.get("within_1600_px", 0))
	var nearby_2000 := int(activity.get("within_2000_px", 0))
	var nearby_8gu := int(activity.get("within_8gu", 0))
	var nearby_16gu := int(activity.get("within_16gu", 0))
	var active_ground_loot_count := int(activity.get("active_ground_loot_count", 0))
	var active_corpse_count := int(activity.get("active_corpse_count", 0))
	var loot_runtime := _loot_runtime_snapshot(root)
	var loot_index: Dictionary = loot_runtime.get("spatial_index", {})
	var release_context := RuntimeDiagnostics.performance_release_context()
	RuntimeDiagnostics.set_performance_value(
		&"active_loot_pickups",
		float(active_ground_loot_count),
	)
	var counters := RuntimeDiagnostics.performance_counters()
	return {
		"map_id": int(map.get("mapId", -1)),
		"commit": str(root.get_meta("build_commit", "unknown")) if root != null else "unknown",
		"total_monster_count": int(activity.get("total", 0)),
		"nearby_1600_px": nearby_1600,
		"nearby_2000_px": nearby_2000,
		"moving_count": int(activity.get("moving_count", 0)),
		"engaged_count": int(activity.get("engaged_count", 0)),
		"active_visual_count": int(activity.get("visual_resources_active", 0)),
		"player_position": _vec2(player_position),
		"camera_zoom": float(scene.get("camera_zoom", 1.0)),
		"release_id": str(release_context.get("release_id", "")),
		"skill_id": str(release_context.get("skill_id", "")),
		"player_profession": player_profession,
		"nearby_enemy_count_8gu": nearby_8gu,
		"nearby_enemy_count_16gu": nearby_16gu,
		"engaged_enemy_count": int(activity.get("engaged_count", 0)),
		"moving_enemy_count": int(activity.get("moving_count", 0)),
		"aoe_selected_target_count": int(counters.get("aoe_selected_targets", 0)),
		"lethal_target_count": int(counters.get("lethal_damage_count", 0)),
		"active_ground_loot_count": active_ground_loot_count,
		"active_corpse_count": active_corpse_count,
		"loot_registered_pickup_count": int(loot_runtime.get("registered_pickup_count", active_ground_loot_count)),
		"loot_spatial_query_count": int(loot_index.get("index_query_count", 0)),
		"loot_spatial_candidate_count": int(loot_index.get("index_candidate_count", 0)),
		"loot_full_scan_count": int(loot_runtime.get("manager_full_scan_count", 0)) + int(loot_index.get("index_full_scan_count", 0)),
	}


static func _loot_runtime_snapshot(root: Node) -> Dictionary:
	if root == null or not is_instance_valid(root):
		return {}
	var manager: Variant = root.get("_loot_pickup_runtime_manager")
	if manager is Node and is_instance_valid(manager) and manager.has_method("diagnostics_snapshot"):
		var snapshot: Variant = manager.call("diagnostics_snapshot")
		if snapshot is Dictionary:
			return snapshot as Dictionary
	return {}


## Returns only a fixed set of numeric engine monitors.  This is intentionally
## content-free and bounded so a host can compare frame pacing against scene
## and actor counts without receiving arbitrary runtime data.
static func _performance_snapshot() -> Dictionary:
	return {
		"fps": _performance_value(Performance.TIME_FPS),
		"process_ms": _performance_ms(Performance.TIME_PROCESS),
		"physics_process_ms": _performance_ms(Performance.TIME_PHYSICS_PROCESS),
		"node_count": _performance_value(Performance.OBJECT_NODE_COUNT),
		"object_count": _performance_value(Performance.OBJECT_COUNT),
		"resource_count": _performance_value(Performance.OBJECT_RESOURCE_COUNT),
		"render_objects": _performance_value(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"render_primitives": _performance_value(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"draw_calls": _performance_value(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"video_mem": _performance_value(Performance.RENDER_VIDEO_MEM_USED),
		"texture_mem": _performance_value(Performance.RENDER_TEXTURE_MEM_USED),
		"buffer_mem": _performance_value(Performance.RENDER_BUFFER_MEM_USED),
	}


static func _performance_value(monitor: int) -> float:
	var value := float(Performance.get_monitor(monitor))
	if is_nan(value) or is_inf(value) or value < 0.0:
		return 0.0
	return value


static func _performance_ms(monitor: int) -> float:
	return _seconds_to_milliseconds(_performance_value(monitor))


static func _seconds_to_milliseconds(seconds: float) -> float:
	if is_nan(seconds) or is_inf(seconds) or seconds < 0.0:
		return 0.0
	return seconds * 1000.0


static func _enemy_activity_snapshot(root: Node) -> Dictionary:
	var result := {
		"total": 0,
		"visible": 0,
		"within_1600_px": 0,
		"within_2000_px": 0,
		"within_8gu": 0,
		"within_16gu": 0,
		"visual_resources_active": 0,
		"moving_count": 0,
		"engaged_count": 0,
		"active_ground_loot_count": 0,
		"active_corpse_count": 0,
		"background_ai_eligible": 0,
		"inspected": 0,
		"enemy_diagnostics": _enemy_diagnostics_snapshot(),
	}
	if root == null or not is_instance_valid(root) or root.get_tree() == null:
		return result
	var raw_player: Variant = root.get("player")
	var player := raw_player as Node2D if raw_player is Node2D and is_instance_valid(raw_player) else null
	var enemies: Array[Node] = root.get_tree().get_nodes_in_group("enemies")
	result["total"] = enemies.size()
	var loot_runtime := _loot_runtime_snapshot(root)
	result["active_ground_loot_count"] = int(
		loot_runtime.get("registered_pickup_count", 0)
	)
	var active_enemy_cache: Variant = root.get("_active_enemy_cache")
	if active_enemy_cache is Dictionary:
		for raw_enemy: Variant in (active_enemy_cache as Dictionary).values():
			if not raw_enemy is EnemyActor or not is_instance_valid(raw_enemy):
				continue
			if bool((raw_enemy as EnemyActor).get("_death_pending")) or bool((raw_enemy as EnemyActor).get("_dying")):
				result["active_corpse_count"] = int(result["active_corpse_count"]) + 1
	var inspected := mini(enemies.size(), MAX_SNAPSHOT_ENEMY_ACTIVITY_SCAN)
	result["inspected"] = inspected
	for index in range(inspected):
		var raw_enemy: Variant = enemies[index]
		if not raw_enemy is Node or not is_instance_valid(raw_enemy):
			continue
		var enemy := raw_enemy as Node
		if enemy is CanvasItem and (enemy as CanvasItem).is_visible_in_tree():
			result["visible"] = int(result["visible"]) + 1
		if player != null and enemy is Node2D:
			var distance_squared := (enemy as Node2D).global_position.distance_squared_to(player.global_position)
			var eight_gu_px := GroundUnitSpace.ground_delta_gu_to_screen_delta_px(Vector2(8.0, 0.0)).length()
			var sixteen_gu_px := GroundUnitSpace.ground_delta_gu_to_screen_delta_px(Vector2(16.0, 0.0)).length()
			if distance_squared <= eight_gu_px * eight_gu_px:
				result["within_8gu"] = int(result["within_8gu"]) + 1
			if distance_squared <= sixteen_gu_px * sixteen_gu_px:
				result["within_16gu"] = int(result["within_16gu"]) + 1
			if distance_squared <= 1600.0 * 1600.0:
				result["within_1600_px"] = int(result["within_1600_px"]) + 1
			if distance_squared <= 2000.0 * 2000.0:
				result["within_2000_px"] = int(result["within_2000_px"]) + 1
		if not enemy is EnemyActor:
			continue
		var enemy_actor := enemy as EnemyActor
		var enemy_velocity: Variant = enemy_actor.get("velocity")
		if enemy_velocity is Vector2 and (enemy_velocity as Vector2).length_squared() > 0.000001:
			result["moving_count"] = int(result.get("moving_count", 0)) + 1
		if is_instance_valid(enemy_actor.get("target")):
			result["engaged_count"] = int(result.get("engaged_count", 0)) + 1
		var visual: Variant = enemy_actor.get("visual")
		if visual is Node and is_instance_valid(visual):
			var active_resources: Variant = (visual as Node).get("active_resources")
			if active_resources is Dictionary and not (active_resources as Dictionary).is_empty():
				result["visual_resources_active"] = int(result["visual_resources_active"]) + 1
	return result


static func _enemy_diagnostics_snapshot() -> Dictionary:
	var result := {}
	for field: String in ENEMY_DIAGNOSTIC_FIELDS:
		result[field] = 0
	var diagnostics: Variant = EnemyActor.performance_diagnostics()
	if not diagnostics is Dictionary:
		return result
	var source := diagnostics as Dictionary
	for field: String in ENEMY_DIAGNOSTIC_FIELDS:
		result[field] = _non_negative_counter(source.get(field, 0))
	return result


static func _monster_streaming_snapshot(root: Node) -> Dictionary:
	var result := {}
	for field: String in MONSTER_STREAMING_DIAGNOSTIC_FIELDS:
		result[field] = 0
	if root == null or not is_instance_valid(root):
		return result
	var has_coordinator_property := false
	for property: Dictionary in root.get_property_list():
		if str(property.get("name", "")) == "_streaming_coordinator":
			has_coordinator_property = true
			break
	if not has_coordinator_property:
		return result
	var coordinator: Variant = root.get("_streaming_coordinator")
	if not coordinator is Object or not is_instance_valid(coordinator):
		return result
	if not (coordinator as Object).has_method("monster_streaming_diagnostics"):
		return result
	var raw_diagnostics: Variant = (coordinator as Object).call("monster_streaming_diagnostics")
	if not raw_diagnostics is Dictionary:
		return result
	var diagnostics := raw_diagnostics as Dictionary
	for field: String in MONSTER_STREAMING_DIAGNOSTIC_FIELDS:
		result[field] = _non_negative_counter(diagnostics.get(field, 0))
	return result


static func _non_negative_counter(value: Variant) -> int:
	if value is int:
		return maxi(int(value), 0)
	if value is float:
		var numeric := float(value)
		if is_nan(numeric) or is_inf(numeric):
			return 0
		return maxi(int(numeric), 0)
	return 0


static func _window_snapshot(root: Node) -> Dictionary:
	var logical := Vector2.ZERO
	if root != null and root.get_viewport() != null:
		logical = root.get_viewport().get_visible_rect().size
	var physical := DisplayServer.window_get_size()
	return {
		"logical": _vec2(logical),
		"physical": _vec2(Vector2(physical)),
	}


static func _scene_snapshot(root: Node) -> Dictionary:
	var result := {
		"name": root.name if root != null else "",
		"class": root.get_class() if root != null else "",
		"treeRoot": str(root.get_tree().current_scene.name) if root != null and root.get_tree() != null and root.get_tree().current_scene != null else "",
	}
	if root != null and is_instance_valid(root):
		var world_camera := root.get_node_or_null("WorldCamera")
		if world_camera is Camera2D:
			result["camera_zoom"] = maxf(float((world_camera as Camera2D).zoom.x), 0.0)
	return result


static func _map_snapshot(root: Node) -> Dictionary:
	if root == null:
		return {}
	var result := {}
	var map_id: Variant = root.get("current_map_id")
	var zone: Variant = root.get("current_zone")
	if map_id is int or map_id is float:
		result["mapId"] = int(map_id)
	if zone is String:
		result["zone"] = str(zone)
	return result


static func _player_snapshot(root: Node) -> Dictionary:
	if root == null:
		return {}
	var player: Variant = root.get("player")
	if not player is Node:
		return {}
	var node := player as Node
	var result := {
		"path": str(root.get_path_to(node)),
		"class": node.get_class(),
		"visible": node is CanvasItem and (node as CanvasItem).is_visible_in_tree(),
	}
	if node is Node2D:
		result["globalPosition"] = _vec2((node as Node2D).global_position)
	for property_name in ["level", "profession_id", "current_hp", "max_hp", "current_mp", "max_mp"]:
		var value: Variant = node.get(property_name)
		if value is String or value is int or value is float:
			result[property_name] = value
	return result


static func _collect_snapshot(root: Node, node: Node, depth: int, snapshot: Dictionary, state: Dictionary) -> void:
	if node == null or depth > MAX_SNAPSHOT_DEPTH or int(state.nodes) >= MAX_SNAPSHOT_NODES:
		return
	state.nodes = int(state.nodes) + 1
	var path := str(root.get_path_to(node))
	if node is Control and int(state.controls) < MAX_SNAPSHOT_CONTROLS and not _is_dynamic_layout_path(path):
		var control := node as Control
		if control.is_visible_in_tree():
			(snapshot["controls"] as Array).append(_control_snapshot(root, control, path))
			state.controls = int(state.controls) + 1
	if node is Node2D and int(state.node2d) < MAX_SNAPSHOT_NODE2D:
		(snapshot["node2d"] as Array).append(_node2d_snapshot(root, node as Node2D, path))
		state.node2d = int(state.node2d) + 1
	for child in node.get_children():
		if int(state.nodes) >= MAX_SNAPSHOT_NODES:
			break
		_collect_snapshot(root, child as Node, depth + 1, snapshot, state)


static func _control_snapshot(root: Node, control: Control, path: String) -> Dictionary:
	var global_rect := control.get_global_rect()
	var text := _control_text(control)
	return {
		"path": path,
		"class": control.get_class(),
		"globalRect": _rect2(global_rect),
		"localRect": _rect2(Rect2(control.position, control.size)),
		"anchors": [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom],
		"visible": control.is_visible_in_tree(),
		"z": control.z_index,
		"themeVariation": control.theme_type_variation,
		"textHash": _sha256(text.to_utf8_buffer() if text.length() <= MAX_TEXT_HASH_BYTES else text.left(MAX_TEXT_HASH_BYTES).to_utf8_buffer()),
		"runtime_text": bool(control.get_meta("calibration_runtime_text", false)) or bool(control.get_meta("runtime_text", false)),
	}


static func _node2d_snapshot(root: Node, node: Node2D, path: String) -> Dictionary:
	var groups: Array[String] = []
	for raw_group: Variant in node.get_groups():
		if groups.size() >= 8:
			break
		groups.append(str(raw_group))
	return {
		"path": path,
		"class": node.get_class(),
		"globalPosition": _vec2(node.global_position),
		"visible": node.is_visible_in_tree(),
		"groups": groups,
	}


static func _snapshot_control_subtree(target: Control) -> Array:
	var result: Array = []
	if target == null or not is_instance_valid(target):
		return result
	var stack: Array = [target]
	var count := 0
	while not stack.is_empty() and count < MAX_SNAPSHOT_CONTROLS:
		var node := stack.pop_back() as Node
		if node is Control and (node as Control).is_visible_in_tree() and not _is_dynamic_layout_path(str(target.get_path_to(node))):
			result.append(_control_snapshot(target, node as Control, str(target.get_path_to(node))))
			count += 1
		for child in node.get_children():
			stack.append(child)
	return result


static func _is_dynamic_layout_path(path: String) -> bool:
	return (
		path.begins_with("BagPanel/InventoryScroll/ItemGrid/")
		or path.contains("/BagPanel/InventoryScroll/ItemGrid/")
		or path.begins_with("MapListPanel/MapListScroll/MapCards/")
		or path.contains("/MapListPanel/MapListScroll/MapCards/")
		or path.begins_with("MapPreviewPanel/WorldTreeScroll/WorldTree/")
		or path.contains("/MapPreviewPanel/WorldTreeScroll/WorldTree/")
		or path.begins_with("GoodsPanel/GoodsScroll/GoodsGrid/")
		or path.contains("/GoodsPanel/GoodsScroll/GoodsGrid/")
		or path.begins_with("QuestListPanel/QuestListScroll/QuestList/")
		or path.contains("/QuestListPanel/QuestListScroll/QuestList/")
		or path.begins_with("StashSection/StashScroll/StashGrid/")
		or path.contains("/StashSection/StashScroll/StashGrid/")
		or path.begins_with("BagSection/BagScroll/BagGrid/")
		or path.contains("/BagSection/BagScroll/BagGrid/")
	)


static func _control_text(control: Control) -> String:
	if control is Label or control is Button or control is LineEdit or control is TextEdit or control is RichTextLabel:
		var value: Variant = control.get("text")
		return str(value) if value != null else ""
	return ""


static func _vec2(value: Vector2) -> Array:
	return [value.x, value.y]


static func _rect2(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]


static func _sha256(bytes: PackedByteArray) -> String:
	if bytes.is_empty():
		return "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().to_upper()


func _error_result(source: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"error": str(source.get("error", "invalid_command")),
	}


func _ensure_mailbox_dirs() -> void:
	var root_dir := DirAccess.open("user://")
	if root_dir != null:
		root_dir.make_dir_recursive("device_lab/inbox")
		root_dir.make_dir_recursive("device_lab/outbox")
		root_dir.make_dir_recursive("device_lab/checkpoints")
		_mailbox_initialized = true


func _write_result(nonce: String, result: Dictionary) -> bool:
	_ensure_mailbox_dirs()
	var safe_nonce := nonce if _is_safe_token(nonce) else "invalid_%d" % Time.get_ticks_msec()
	var name := "result_%s.json" % safe_nonce
	var temporary := ".%s.tmp" % name
	var path := OUTBOX_DIR + "/" + name
	var temp_path := OUTBOX_DIR + "/" + temporary
	if FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	var output := result.duplicate(true)
	output["protocolVersion"] = PROTOCOL_VERSION
	output["nonce"] = nonce
	var serialized := JSON.stringify(output, "\t")
	if serialized.to_utf8_buffer().size() > MAX_RESULT_BYTES:
		file.close()
		DirAccess.remove_absolute(temp_path)
		return false
	file.store_string(serialized)
	file.flush()
	file.close()
	var outbox := DirAccess.open(OUTBOX_DIR)
	if outbox != null:
		if outbox.rename(temporary, name) != OK:
			DirAccess.remove_absolute(temp_path)
			return false
	_prune_outbox()
	return true


func _prune_outbox() -> void:
	if not DirAccess.dir_exists_absolute(OUTBOX_DIR):
		return
	var files: PackedStringArray = DirAccess.get_files_at(OUTBOX_DIR)
	var records: Array = []
	var total_bytes := 0
	var now := Time.get_unix_time_from_system()
	for file_name: String in files:
		if not file_name.begins_with("result_") or not file_name.ends_with(".json"):
			continue
		if not _is_safe_token(file_name.trim_suffix(".json")):
			continue
		var path := OUTBOX_DIR + "/" + file_name
		var size := _file_size(path)
		var modified := FileAccess.get_modified_time(path)
		var age := maxi(0, int(now - modified))
		total_bytes += size
		records.append({"name": file_name, "size": size, "modified": modified, "age": age})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("modified", 0)) < int(b.get("modified", 0))
	)
	var keep_count := records.size()
	for record: Dictionary in records:
		if int(record.get("age", 0)) > MAX_OUTBOX_AGE_SECONDS:
			DirAccess.remove_absolute(OUTBOX_DIR + "/" + str(record.get("name", "")))
			total_bytes -= int(record.get("size", 0))
			keep_count -= 1
	var index := 0
	while keep_count > MAX_OUTBOX_ENTRIES or total_bytes > MAX_OUTBOX_TOTAL_BYTES:
		if index >= records.size():
			break
		var record: Dictionary = records[index]
		index += 1
		var candidate := OUTBOX_DIR + "/" + str(record.get("name", ""))
		if not FileAccess.file_exists(candidate):
			continue
		DirAccess.remove_absolute(candidate)
		total_bytes -= int(record.get("size", 0))
		keep_count -= 1


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return int(size)


func _remove_payload(command: Dictionary) -> void:
	var path := str(command.get("path", ""))
	if path.is_empty() or not bool(_validate_payload_path(path).get("ok", false)):
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
