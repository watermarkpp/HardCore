extends Node

const SNAPSHOT_SCHEMA := "monster_drop_p1a_runtime_snapshot_v2"
const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
const OUTPUT_PATH := "res://outputs/monster_drop_p1a/runtime_snapshot.json"

# P1A current-corpus freeze for codex/integration.
# These values describe the current P0R base-only catalog and are intentionally
# not presented as universal future rules for user-authoring overlays.
const EXPECTED_DROP_PROFILE_COUNT := 156
const EXPECTED_BASE_DROP_ROW_COUNT := 7032
const EXPECTED_FINAL_DROP_ROW_COUNT := 7032
const EXPECTED_AUDIT_ONLY_COUNT := 7032
const EXPECTED_CONFIRMED_SOURCE_SLOT_COUNT := 7032
const EXPECTED_INVALID_CHANCE_COUNT := 1

const EXPECTED_ANOMALY_DROP_PROFILE_ID := "drop.168"
const EXPECTED_ANOMALY_MONSTER_ID := 168
const EXPECTED_ANOMALY_LINE_NUMBER := 20
const EXPECTED_ANOMALY_SLOT_INDEX := "slot_020"
const EXPECTED_ANOMALY_CHANCE := "1/00"
const EXPECTED_ANOMALY_RAW_TEXT := "1/00 灵魂战衣(男)"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: Array[String] = []

	if not GameData.ensure_loaded():
		_fail(["GameData.ensure_loaded() returned false"])
		return
	if not LootRuntime.has_method("_chance_denominator"):
		_fail([
			"LootRuntime._chance_denominator is missing; "
			+ "P1A refuses to invent a second chance parser"
		])
		return
	if not FileAccess.file_exists(CATALOG_PATH):
		_fail(["missing canonical catalog: %s" % CATALOG_PATH])
		return

	var catalog_text_before := FileAccess.get_file_as_string(CATALOG_PATH)
	var source_sha256_before := _sha256_text(catalog_text_before)
	var parsed: Variant = JSON.parse_string(catalog_text_before)
	if not parsed is Dictionary:
		_fail(["canonical catalog is not a JSON object"])
		return
	var catalog: Dictionary = parsed
	var profiles_value: Variant = catalog.get("drop_profiles", null)
	if not profiles_value is Dictionary:
		_fail(["canonical catalog drop_profiles is not a Dictionary"])
		return
	var profiles: Dictionary = profiles_value
	var catalog_summary_value: Variant = catalog.get("summary", {})
	var catalog_summary: Dictionary = (
		catalog_summary_value
		if catalog_summary_value is Dictionary
		else {}
	)

	_check_current_corpus_summary(catalog_summary, profiles, failures)

	var slots: Array = []
	var rate_policy_counts := {}
	var slot_status_counts := {}
	var non_rollable_reason_counts := {}
	var runtime_rejection_reason_counts := {}
	var reward_resolution_reason_counts := {}
	var monster_runtime_gate_counts := {}
	var invalid_slots: Array = []
	var slot_runtime_rollable_count := 0
	var runtime_reachable_count := 0
	var reward_resolvable_count := 0

	var monster_ids: Array[int] = []
	for raw_profile_id: Variant in profiles.keys():
		var profile_id := str(raw_profile_id)
		if not profile_id.begins_with("drop."):
			failures.append("unexpected drop profile id: %s" % profile_id)
			continue
		var suffix := profile_id.trim_prefix("drop.")
		if not suffix.is_valid_int():
			failures.append("non-numeric drop profile id: %s" % profile_id)
			continue
		monster_ids.append(int(suffix))
	monster_ids.sort()

	for monster_id: int in monster_ids:
		var profile_id := "drop.%d" % monster_id
		var profile_value: Variant = profiles.get(profile_id, {})
		if not profile_value is Dictionary:
			failures.append("%s is not a Dictionary" % profile_id)
			continue
		var profile: Dictionary = profile_value
		var entries_value: Variant = profile.get("entries", [])
		if not entries_value is Array:
			failures.append("%s entries is not an Array" % profile_id)
			continue

		var closure: Dictionary = (
			GameData.canonical_monster_runtime_drop_closure(monster_id)
		)
		var monster_runtime_allowed := bool(closure.get("allowed", false))
		var monster_runtime_reason := str(closure.get("reason", ""))
		var monster_gate_key := "allowed"
		if not monster_runtime_allowed:
			monster_gate_key = (
				monster_runtime_reason
				if not monster_runtime_reason.is_empty()
				else "blocked_unspecified"
			)
		_bump(monster_runtime_gate_counts, monster_gate_key)

		var entries: Array = entries_value
		for ordinal_zero_based: int in range(entries.size()):
			var entry_value: Variant = entries[ordinal_zero_based]
			if not entry_value is Dictionary:
				failures.append(
					"%s entry[%d] is not a Dictionary"
					% [profile_id, ordinal_zero_based]
				)
				continue
			var entry: Dictionary = entry_value
			var slot := _snapshot_slot(
				profile_id,
				monster_id,
				ordinal_zero_based,
				entry,
				closure
			)
			slots.append(slot)

			var source_entry: Dictionary = slot.get("source_entry", {})
			_bump(
				rate_policy_counts,
				str(source_entry.get("rate_policy", "<missing>"))
			)
			_bump(
				slot_status_counts,
				str(source_entry.get("slot_status", "<missing>"))
			)

			if bool(slot.get("chance_valid", false)):
				pass
			else:
				invalid_slots.append(slot)

			if bool(slot.get("reward_resolvable", false)):
				reward_resolvable_count += 1
			else:
				_bump(
					reward_resolution_reason_counts,
					str(slot.get(
						"reward_resolution_reason",
						"unresolved_unspecified"
					))
				)

			if bool(slot.get("slot_runtime_rollable", false)):
				slot_runtime_rollable_count += 1
			else:
				_bump(
					non_rollable_reason_counts,
					str(slot.get(
						"non_rollable_reason",
						"non_rollable_unspecified"
					))
				)
				_bump(
					runtime_rejection_reason_counts,
					str(slot.get(
						"runtime_rejection_reason",
						"runtime_rejection_unspecified"
					))
				)

			if bool(slot.get("runtime_reachable", false)):
				runtime_reachable_count += 1

	_check_current_corpus_rows(
		slots,
		rate_policy_counts,
		slot_status_counts,
		invalid_slots,
		failures
	)

	var catalog_text_after := FileAccess.get_file_as_string(CATALOG_PATH)
	var source_sha256_after := _sha256_text(catalog_text_after)
	if source_sha256_before != source_sha256_after:
		failures.append(
			"canonical catalog changed during export: before=%s after=%s"
			% [source_sha256_before, source_sha256_after]
		)

	if not failures.is_empty():
		_fail(failures)
		return

	var summary := {
		"drop_profile_count": profiles.size(),
		"slot_count": slots.size(),
		"rate_policy_counts": rate_policy_counts,
		"slot_status_counts": slot_status_counts,
		"chance_valid_count": slots.size() - invalid_slots.size(),
		"chance_invalid_count": invalid_slots.size(),
		"reward_resolvable_count": reward_resolvable_count,
		"reward_unresolved_count": slots.size() - reward_resolvable_count,
		"slot_runtime_rollable_count": slot_runtime_rollable_count,
		"slot_runtime_non_rollable_count": (
			slots.size() - slot_runtime_rollable_count
		),
		"runtime_reachable_count": runtime_reachable_count,
		"runtime_unreachable_count": slots.size() - runtime_reachable_count,
		"non_rollable_reason_counts": non_rollable_reason_counts,
		"runtime_rejection_reason_counts": runtime_rejection_reason_counts,
		"reward_resolution_reason_counts": reward_resolution_reason_counts,
		"monster_runtime_gate_counts": monster_runtime_gate_counts,
	}

	var snapshot := {
		"schema": SNAPSHOT_SCHEMA,
		"generated_at_utc": Time.get_datetime_string_from_system(true, true),
		"authority": {
			"catalog_path": CATALOG_PATH,
			"catalog_sha256_before": source_sha256_before,
			"catalog_sha256_after": source_sha256_after,
			"runtime_chance_parser": (
				"LootRuntime._chance_denominator"
			),
			"runtime_reward_resolver": (
				"GameData.resolve_canonical_drop_reward"
			),
			"monster_runtime_gate": (
				"GameData.canonical_monster_runtime_drop_closure"
			),
			"rate_policy_runtime_semantics": (
				"provenance_only; not used by LootRuntime"
			),
		},
		"current_corpus_freeze": {
			"expected_drop_profile_count": EXPECTED_DROP_PROFILE_COUNT,
			"expected_base_drop_row_count": EXPECTED_BASE_DROP_ROW_COUNT,
			"expected_final_drop_row_count": EXPECTED_FINAL_DROP_ROW_COUNT,
			"expected_audit_only_count": EXPECTED_AUDIT_ONLY_COUNT,
			"expected_confirmed_source_slot_count": (
				EXPECTED_CONFIRMED_SOURCE_SLOT_COUNT
			),
			"expected_invalid_chance_count": EXPECTED_INVALID_CHANCE_COUNT,
			"expected_anomaly": {
				"drop_profile_id": EXPECTED_ANOMALY_DROP_PROFILE_ID,
				"monster_id": EXPECTED_ANOMALY_MONSTER_ID,
				"line_number": EXPECTED_ANOMALY_LINE_NUMBER,
				"slot_index": EXPECTED_ANOMALY_SLOT_INDEX,
				"chance": EXPECTED_ANOMALY_CHANCE,
				"raw_text": EXPECTED_ANOMALY_RAW_TEXT,
			},
		},
		"catalog_summary": catalog_summary.duplicate(true),
		"summary": summary,
		"slots": slots,
	}

	var output_dir := OUTPUT_PATH.get_base_dir()
	var mkdir_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(output_dir)
	)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		_fail([
			"cannot create output directory %s: error=%d"
			% [output_dir, mkdir_error]
		])
		return

	var output := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if output == null:
		_fail(["cannot open output for write: %s" % OUTPUT_PATH])
		return
	output.store_string(JSON.stringify(snapshot, "\t"))
	output.store_string("\n")
	output.close()

	print(
		(
			"MONSTER_DROP_P1A_RUNTIME_EXPORT_PASS: "
			+ "profiles=%d slots=%d chance_invalid=%d "
			+ "reward_unresolved=%d slot_rollable=%d reachable=%d"
		)
		% [
			profiles.size(),
			slots.size(),
			invalid_slots.size(),
			slots.size() - reward_resolvable_count,
			slot_runtime_rollable_count,
			runtime_reachable_count,
		]
	)
	get_tree().quit(0)


func _snapshot_slot(
	profile_id: String,
	monster_id: int,
	ordinal_zero_based: int,
	entry: Dictionary,
	closure: Dictionary
) -> Dictionary:
	var chance_raw := str(entry.get("chance", ""))
	# Deliberately call the real LootRuntime parser. P1A must not maintain a
	# second parser with subtly different semantics.
	var chance_denominator := int(
		LootRuntime.call("_chance_denominator", chance_raw)
	)
	var chance_valid := chance_denominator > 0

	# Probe the real reward resolver for every row so the audit can distinguish
	# source metadata from actual item authority. The runtime itself only reaches
	# this resolver after chance validation; runtime_reward_attempted records that.
	var reward_probe: Dictionary = (
		GameData.resolve_canonical_drop_reward(entry)
	)
	var reward_resolvable := bool(reward_probe.get("ok", false))
	var reward_resolution_reason := (
		""
		if reward_resolvable
		else str(reward_probe.get(
			"reason",
			"item_authority_unresolved"
		))
	)
	var reward_resolution_status := (
		"resolved" if reward_resolvable else "unresolved"
	)

	var slot_runtime_rollable := chance_valid and reward_resolvable
	var non_rollable_reason: Variant = null
	var runtime_rejection_reason: Variant = null
	if not chance_valid:
		non_rollable_reason = "invalid_chance"
		runtime_rejection_reason = "chance_token_invalid"
	elif not reward_resolvable:
		non_rollable_reason = "unresolved_reward"
		runtime_rejection_reason = reward_resolution_reason

	var monster_runtime_allowed := bool(closure.get("allowed", false))
	var monster_runtime_reason := str(closure.get("reason", ""))
	var runtime_reachable := (
		monster_runtime_allowed and slot_runtime_rollable
	)

	return {
		"drop_profile_id": profile_id,
		"monster_id": monster_id,
		"profile_entry_ordinal_zero_based": ordinal_zero_based,
		"profile_entry_ordinal_one_based": ordinal_zero_based + 1,
		"line_number": int(entry.get("line_number", -1)),
		"slot_index": str(entry.get("slot_index", "")),
		"raw_text": str(entry.get("raw_text", "")),
		"chance_raw": chance_raw,
		"chance_denominator": (
			chance_denominator if chance_valid else null
		),
		"chance_valid": chance_valid,
		"item_resolution_status": str(entry.get(
			"item_resolution_status",
			""
		)),
		"reward_probe_performed": true,
		"reward_resolution_status": reward_resolution_status,
		"reward_resolvable": reward_resolvable,
		"reward_resolution_reason": (
			reward_resolution_reason
			if not reward_resolvable
			else null
		),
		"reward_probe": reward_probe.duplicate(true),
		"runtime_reward_attempted": chance_valid,
		"slot_runtime_rollable": slot_runtime_rollable,
		# Compatibility alias for the partially implemented R1 tooling.
		"runtime_rollable": slot_runtime_rollable,
		"non_rollable_reason": non_rollable_reason,
		# Exact reason emitted by the real LootRuntime rejection path.
		"runtime_rejection_reason": runtime_rejection_reason,
		"monster_runtime_allowed": monster_runtime_allowed,
		"monster_runtime_reason": monster_runtime_reason,
		"monster_runtime_closure": closure.duplicate(true),
		"runtime_reachable": runtime_reachable,
		# Full, untouched row from the generated canonical catalog.
		"source_entry": entry.duplicate(true),
	}


func _check_current_corpus_summary(
	catalog_summary: Dictionary,
	profiles: Dictionary,
	failures: Array[String]
) -> void:
	_expect_int(
		"drop profile count",
		profiles.size(),
		EXPECTED_DROP_PROFILE_COUNT,
		failures
	)
	_expect_int(
		"summary.drop_base_row_count",
		int(catalog_summary.get("drop_base_row_count", -1)),
		EXPECTED_BASE_DROP_ROW_COUNT,
		failures
	)
	_expect_int(
		"summary.drop_final_row_count",
		int(catalog_summary.get("drop_final_row_count", -1)),
		EXPECTED_FINAL_DROP_ROW_COUNT,
		failures
	)
	_expect_int(
		"summary.drop_authoring_enabled_global_count",
		int(catalog_summary.get(
			"drop_authoring_enabled_global_count",
			-1
		)),
		0,
		failures
	)
	_expect_int(
		"summary.drop_authoring_global_expanded_row_count",
		int(catalog_summary.get(
			"drop_authoring_global_expanded_row_count",
			-1
		)),
		0,
		failures
	)
	_expect_int(
		"summary.drop_authoring_enabled_monster_count",
		int(catalog_summary.get(
			"drop_authoring_enabled_monster_count",
			-1
		)),
		0,
		failures
	)
	_expect_int(
		"summary.drop_authoring_monster_added_row_count",
		int(catalog_summary.get(
			"drop_authoring_monster_added_row_count",
			-1
		)),
		0,
		failures
	)


func _check_current_corpus_rows(
	slots: Array,
	rate_policy_counts: Dictionary,
	slot_status_counts: Dictionary,
	invalid_slots: Array,
	failures: Array[String]
) -> void:
	_expect_int(
		"observed slot count",
		slots.size(),
		EXPECTED_FINAL_DROP_ROW_COUNT,
		failures
	)
	_expect_int(
		"rate_policy=AUDIT_ONLY count",
		int(rate_policy_counts.get("AUDIT_ONLY", 0)),
		EXPECTED_AUDIT_ONLY_COUNT,
		failures
	)
	_expect_int(
		"slot_status=CONFIRMED_SOURCE_SLOT count",
		int(slot_status_counts.get("CONFIRMED_SOURCE_SLOT", 0)),
		EXPECTED_CONFIRMED_SOURCE_SLOT_COUNT,
		failures
	)
	_expect_int(
		"invalid chance count",
		invalid_slots.size(),
		EXPECTED_INVALID_CHANCE_COUNT,
		failures
	)

	if invalid_slots.size() != 1:
		return
	var anomaly_value: Variant = invalid_slots[0]
	if not anomaly_value is Dictionary:
		failures.append("invalid slot snapshot is not a Dictionary")
		return
	var anomaly: Dictionary = anomaly_value
	_expect_string(
		"anomaly.drop_profile_id",
		str(anomaly.get("drop_profile_id", "")),
		EXPECTED_ANOMALY_DROP_PROFILE_ID,
		failures
	)
	_expect_int(
		"anomaly.monster_id",
		int(anomaly.get("monster_id", -1)),
		EXPECTED_ANOMALY_MONSTER_ID,
		failures
	)
	_expect_int(
		"anomaly.line_number",
		int(anomaly.get("line_number", -1)),
		EXPECTED_ANOMALY_LINE_NUMBER,
		failures
	)
	_expect_int(
		"anomaly.profile_entry_ordinal_zero_based",
		int(anomaly.get(
			"profile_entry_ordinal_zero_based",
			-1
		)),
		EXPECTED_ANOMALY_LINE_NUMBER - 1,
		failures
	)
	_expect_int(
		"anomaly.profile_entry_ordinal_one_based",
		int(anomaly.get(
			"profile_entry_ordinal_one_based",
			-1
		)),
		EXPECTED_ANOMALY_LINE_NUMBER,
		failures
	)
	_expect_string(
		"anomaly.slot_index",
		str(anomaly.get("slot_index", "")),
		EXPECTED_ANOMALY_SLOT_INDEX,
		failures
	)
	_expect_string(
		"anomaly.chance_raw",
		str(anomaly.get("chance_raw", "")),
		EXPECTED_ANOMALY_CHANCE,
		failures
	)
	_expect_string(
		"anomaly.raw_text",
		str(anomaly.get("raw_text", "")),
		EXPECTED_ANOMALY_RAW_TEXT,
		failures
	)
	_expect_string(
		"anomaly.non_rollable_reason",
		str(anomaly.get("non_rollable_reason", "")),
		"invalid_chance",
		failures
	)
	_expect_string(
		"anomaly.runtime_rejection_reason",
		str(anomaly.get("runtime_rejection_reason", "")),
		"chance_token_invalid",
		failures
	)
	if bool(anomaly.get("runtime_reward_attempted", true)):
		failures.append(
			"1/00 anomaly must be rejected before runtime reward resolution"
		)
	if bool(anomaly.get("slot_runtime_rollable", true)):
		failures.append("1/00 anomaly must not be slot_runtime_rollable")


func _expect_int(
	label: String,
	actual: int,
	expected: int,
	failures: Array[String]
) -> void:
	if actual != expected:
		failures.append(
			"%s mismatch: actual=%d expected=%d"
			% [label, actual, expected]
		)


func _expect_string(
	label: String,
	actual: String,
	expected: String,
	failures: Array[String]
) -> void:
	if actual != expected:
		failures.append(
			"%s mismatch: actual=%s expected=%s"
			% [label, actual, expected]
		)


func _bump(counter: Dictionary, raw_key: String) -> void:
	var key := raw_key if not raw_key.is_empty() else "<empty>"
	counter[key] = int(counter.get(key, 0)) + 1


func _sha256_text(text: String) -> String:
	var context := HashingContext.new()
	var start_error := context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return "HASH_START_ERROR_%d" % start_error
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()


func _fail(failures: Array[String]) -> void:
	for failure: String in failures:
		push_error("MONSTER_DROP_P1A_RUNTIME_EXPORT_FAIL: %s" % failure)
	print(
		"MONSTER_DROP_P1A_RUNTIME_EXPORT_FAIL_COUNT=%d"
		% failures.size()
	)
	get_tree().quit(1)
