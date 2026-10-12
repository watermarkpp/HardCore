extends RefCounted

## Read-only projection of the existing migration owner. No save contents,
## profile filenames, absolute paths or alternative persistence authority.
const CONTRACT := "hardcore.save.upgrade.diagnostic.v1"
const PHASES := ["backup", "completion_validation", "preflight", "relic_recovery", "migration", "completion"]
const PHASE_LABELS := {"backup":"备份校验", "completion_validation":"升级记录校验",
	"preflight":"旧存档校验", "relic_recovery":"损坏物品修复", "migration":"存档转换", "completion":"完成记录写入", "unknown":"待确认"}
const REASONS := [
	"unsupported_relic_roll_contract", "relic_recovery_backup_mismatch", "relic_recovery_source_changed", "relic_recovery_write_failed",
	"future_save_version", "invalid_json", "profile_id_mismatch",
	"invalid_character_identity_schema", "unsupported_character_identity_contract",
	"unknown_profession_identity", "conflicting_profession_identity",
	"invalid_legacy_profession_identity", "unknown_legacy_profession_identity",
	"invalid_item_binding_contract", "invalid_item_binding_identity", "conflicting_item_binding_identity",
	"invalid_skill_identity", "invalid_skill_binding_identity", "unsupported_world_state",
	"unsupported_world_clock_snapshot", "unsupported_death_event", "invalid_world_clock_snapshot",
	"invalid_world_clock_generation", "world_clock_generation_without_sequence", "invalid_death_event",
	"duplicate_drop_instance", "duplicate_drop_instance_across_shared",
	"invalid_item_transaction_journal", "unsupported_item_transaction_journal",
	"invalid_warehouse_transaction_log", "gold_not_exact_json_integer", "repeated_gold_overflow_migration",
	"upgrade_backup_manifest_invalid", "upgrade_backup_missing", "upgrade_backup_hash_mismatch",
	"upgrade_backup_copy_failed", "upgrade_backup_source_open_failed", "upgrade_backup_directory_failed",
	"upgrade_backup_directory_unavailable", "upgrade_backup_outside_account", "upgrade_backup_invalid_path",
	"upgrade_backup_manifest_write_failed", "upgrade_completion_invalid", "upgrade_completion_write_failed",
	"profile_directory_failed", "shared_warehouse_unavailable", "profile_index_unavailable",
	"legacy_profile_migration_failed", "shared_warehouse_identity_upgrade_failed",
	"profile_save_failed", "profile_load_failed", "atomic_write_failed", "candidate_business_invalid",
	"update_source_backup_invalid", "update_source_invalid", "update_snapshot_invalid",
	"source_changed", "update_source_changed", "validated_previous_bytes_changed", "request_context_changed",
	"prepare_open_failed", "prepare_write_failed", "prepare_flush_failed", "promote_failed",
	"unsupported_item_container", "private_runtime_item_field_on_wire", "item_extension_graph_capacity_or_type",
	"invalid_item_container_version", "invalid_item_container", "invalid_item_container_base",
	"wire_container_in_runtime", "invalid_runtime_item_extension", "non_record_formal_equipment",
	"unknown_legacy_equipment_identity", "unknown_item_identity", "conflicting_item_identity",
	"invalid_equipment_identity_contract", "unknown_or_conflicting_equipment_slot_identity",
	"invalid_equipment_cycle_owner", "unknown_or_conflicting_equipment_cycle_identity",
	"item_extension_namespace_capacity", "duplicate_embedded_instance_identity",
	"unsupported_item_extension_namespace", "invalid_socket_extension_version", "unsupported_socket_extension_version",
	"invalid_socket_extension", "invalid_socket_record", "invalid_socket_gem", "unsupported_gem_instance_contract",
	"unsupported_rune_instance_contract", "unknown_rune_item_identity", "invalid_rune_instance_contract",
	"invalid_rune_instance", "missing_rune_instance_contract", "invalid_gem_instance_contract",
	"invalid_gem_instance", "missing_gem_instance_contract", "unsupported_rune_extension_version",
	"unsupported_embedded_item_container", "invalid_rune_extension", "invalid_rune_slot", "invalid_embedded_rune",
	"previous_file_read_failed", "required_baseline_missing", "prepared_bytes_changed", "prepared_document_invalid",
	"serialized_document_invalid", "target_directory_failed", "temporary_already_exists", "temporary_open_failed",
	"temporary_readback_failed", "candidate_not_approved", "temporary_changed_before_promotion",
	"previous_file_changed_before_promotion", "journal_sequence_already_exists", "previous_document_terminal",
	"private_transaction_path_already_exists", "backup_hold_failed", "primary_rotation_failed",
	"primary_quarantine_failed", "promotion_failed", "promoted_readback_failed",
	"unsupported_item_identity_contract", "missing_formal_item_identity", "unknown_or_conflicting_item_identity",
	"unsupported_equipment_identity_contract", "invalid_equipment_identity_owner", "invalid_equipment_slot_identity",
	"unknown_equipment_slot_identity", "conflicting_equipment_slot_identity",
]
const FIELDS := [
	"profile_id", "save_version", "profile_index_version", "profile_index_profiles", "profile_index_entry",
	"profile_index_id", "profile_index_name", "profile_index_profession", "profile_index_gender",
	"profile_index_level", "profile_index_updated_at", "character_name", "level", "profession", "gender",
	"inventory", "warehouse_inventory", "equipment", "learned_skills", "quest_states", "game_mode_id",
	"later_content_enabled", "content_packages", "forge_tray", "synthesis_tray", "skill_progression",
	"skill_button_assignments", "equip_cycle_cursor", "warrior_runtime_state", "world_monster_respawn_state",
	"taoist_main_pet_runtime_state", "taoist_main_pet_runtime_states", "quick_slots", "quick_item_slots",
	"position", "position_screen_px", "position_ground_gu", "position_space_contract_id", "experience",
	"gold", "updated_at", "content_schema_version", "death_event_sequence", "gold_overflow_records",
	"map_id", "shared_warehouse", "warehouse_storage_contract_id", "player_payload",
]

static func build(result: Dictionary) -> Dictionary:
	var raw: String = str(result.get("reason", ""))
	var reason := raw if raw in REASONS else "unclassified_upgrade_failure"
	for prefix: String in ["invalid_", "missing_"]:
		if raw.begins_with(prefix) and raw.trim_prefix(prefix) in FIELDS:
			reason = raw
	var phase: String = str(result.get("phase", ""))
	if phase not in PHASES: phase = "unknown"
	var verified := bool(result.get("source_backup_verified", false))
	var custody := "升级前原档备份已验证。" if verified else "原档备份尚未验证，请保留现有应用数据。"
	# Unknown future diagnostics can still be correlated with internal reason
	# constants without displaying an untrusted reason payload or filename.
	var token := raw.sha256_text().substr(0, 12)
	var display_reason := reason if reason != "unclassified_upgrade_failure" else reason + ":" + token
	return {
		"contract_id": CONTRACT, "reason_code": reason, "phase": phase,
		"reason_fingerprint": token,
		"source_backup_verified": verified,
		"message": "存档升级未完成。\n兼容原因：%s\n失败阶段：%s\n%s\n可重试；若仍失败，请截图反馈。不要卸载或清除应用数据。" % [display_reason, PHASE_LABELS[phase], custody],
	}
