extends Node

const SNAPSHOT_SCHEMA := "monster_drop_p1a_runtime_snapshot_v3"
const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
const CORRECTION_PATH := (
	"res://assets/data/drop/dpv2_21cq_source_corrections_v1.json"
)
const OUTPUT_PATH := "res://outputs/monster_drop_p1a/runtime_snapshot.json"

# P1A deliberately keeps the source audit and the compiled Runtime view
# separate. Source rows are evidence; only compiled V2 slots can reach RNG.
const EXPECTED_SOURCE_PROFILE_COUNT := 156
const EXPECTED_SOURCE_ROW_COUNT := 7032
const EXPECTED_ENABLED_SOURCE_ROW_COUNT := 5995
const EXPECTED_NON_LOOT_SOURCE_ROW_COUNT := 1037
const EXPECTED_MALFORMED_SOURCE_PROVENANCE_COUNT := 1
const EXPECTED_RUNTIME_PROFILE_COUNT := 156
const EXPECTED_RUNTIME_ENABLED_PROFILE_COUNT := 131
const EXPECTED_RUNTIME_NON_LOOT_PROFILE_COUNT := 25
const EXPECTED_RUNTIME_SLOT_COUNT := 5995
const EXPECTED_LEGACY_RUNTIME_SLOT_COUNT := 5926
const EXPECTED_EXTENSION_RUNTIME_SLOT_COUNT := 69

const EXPECTED_ANOMALY_SOURCE_PROFILE_ID := "drop.168"
const EXPECTED_ANOMALY_MONSTER_ID := 168
const EXPECTED_ANOMALY_LINE_NUMBER := 20
const EXPECTED_ANOMALY_SLOT_INDEX := "slot_020"
const EXPECTED_ANOMALY_CHANCE := "1/00"
const EXPECTED_ANOMALY_RAW_TEXT := "1/00 灵魂战衣(男)"
const EXPECTED_ANOMALY_CORRECTED_DENOMINATOR := 2800


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: Array[String] = []

	if not GameData.ensure_loaded():
		_fail(["GameData.ensure_loaded() returned false"])
		return
	if not GameData.is_dpv2_direct_baseline_loaded():
		_fail([
			"GameData direct baseline is unavailable: %s" % GameData.load_error
		])
		return
	if not LootRuntime.has_method("_chance_denominator"):
		_fail(["LootRuntime source-provenance chance parser is missing"])
		return
	if not FileAccess.file_exists(CATALOG_PATH):
		_fail(["missing canonical catalog: %s" % CATALOG_PATH])
		return

	var catalog_text_before := FileAccess.get_file_as_string(CATALOG_PATH)
	var catalog_sha256_before := _sha256_text(catalog_text_before)
	var parsed_catalog: Variant = JSON.parse_string(catalog_text_before)
	if not parsed_catalog is Dictionary:
		_fail(["canonical catalog is not a JSON object"])
		return
	var catalog: Dictionary = parsed_catalog
	var source_profiles_value: Variant = catalog.get("drop_profiles", null)
	if not source_profiles_value is Dictionary:
		_fail(["canonical catalog drop_profiles is not a Dictionary"])
		return
	var source_profiles: Dictionary = source_profiles_value
	var catalog_profile_to_id := _build_catalog_profile_index(
		catalog,
		failures
	)

	var source_rows: Array = []
	var compiled_slots: Array = []
	var source_profile_summaries: Array = []
	var compiled_profile_summaries: Array = []
	var source_rate_policy_counts: Dictionary = {}
	var source_status_counts: Dictionary = {}
	var origin_counts: Dictionary = {}
	var item_occurrences: Dictionary = {}
	var malformed_source_rows: Array = []
	var enabled_source_row_count := 0
	var disabled_source_row_count := 0
	var runtime_enabled_profile_count := 0
	var runtime_non_loot_profile_count := 0
	var seen_canonical_ids: Dictionary = {}
	var seen_runtime_profile_ids: Dictionary = {}
	var seen_slot_uids: Dictionary = {}

	var source_profile_ids := _sorted_numeric_keys(source_profiles)
	_expect_int(
		"source profile count",
		source_profile_ids.size(),
		EXPECTED_SOURCE_PROFILE_COUNT,
		failures
	)

	for raw_source_profile_id: Variant in source_profile_ids:
		var source_profile_id := str(raw_source_profile_id)
		var source_profile_value: Variant = source_profiles.get(
			source_profile_id,
			{}
		)
		if not source_profile_value is Dictionary:
			failures.append(
				"source profile %s is not a Dictionary" % source_profile_id
			)
			continue
		var source_profile: Dictionary = source_profile_value
		var canonical_id := int(
			catalog_profile_to_id.get(source_profile_id, -1)
		)
		if canonical_id <= 0:
			failures.append(
				"source profile %s has no exact canonical monster ID" %
				source_profile_id
			)
			continue
		if seen_canonical_ids.has(canonical_id):
			failures.append(
				"canonical monster ID appears more than once: %d" %
				canonical_id
			)
			continue
		seen_canonical_ids[canonical_id] = true

		# This is the only Runtime join: the source catalog's drop.* label is
		# audit metadata, while GameData is queried by canonical monster ID.
		var direct_profile: Dictionary = GameData.dpv2_direct_profile(
			canonical_id
		)
		if direct_profile.is_empty():
			failures.append(
				"direct profile unresolved for canonical monster ID %d" %
				canonical_id
			)
			continue
		var direct_profile_id_value: Variant = direct_profile.get(
			"drop_profile_id",
			null,
		)
		var direct_profile_id := (
			"" if direct_profile_id_value == null
			else str(direct_profile_id_value)
		)

		var entries_value: Variant = source_profile.get("entries", [])
		if not entries_value is Array:
			failures.append(
				"source profile %s entries is not an Array" %
				source_profile_id
			)
			continue
		var entries: Array = entries_value
		var direct_slots_value: Variant = direct_profile.get("slots", [])
		if not direct_slots_value is Array:
			failures.append(
				"direct profile %s slots is not an Array" % direct_profile_id
			)
			continue
		var direct_slots: Array = direct_slots_value
		var runtime_drop_enabled := bool(direct_profile.get(
			"drop_enabled",
			false
		))
		if runtime_drop_enabled:
			if not direct_profile_id.begins_with("dpv2.direct."):
				failures.append(
					"direct profile ID is not V2 for monster %d: %s" %
					[canonical_id, direct_profile_id]
				)
			if seen_runtime_profile_ids.has(direct_profile_id):
				failures.append(
					"direct profile ID collision: %s" % direct_profile_id
				)
			seen_runtime_profile_ids[direct_profile_id] = true
			runtime_enabled_profile_count += 1
			if entries.size() != direct_slots.size():
				failures.append(
					"source/direct slot count mismatch for canonical ID %d: " %
					canonical_id
					+ "source=%d direct=%d" % [entries.size(), direct_slots.size()]
				)
		else:
			if not direct_profile_id.is_empty():
				failures.append(
					"NON_LOOT direct profile %d has a runtime profile ID: %s" %
					[canonical_id, direct_profile_id]
				)
			runtime_non_loot_profile_count += 1
			if not direct_slots.is_empty():
				failures.append(
					"NON_LOOT direct profile %s contains slots" %
					direct_profile_id
				)

		source_profile_summaries.append({
			"source_profile_id": source_profile_id,
			"canonical_monster_id": canonical_id,
			"source_row_count": entries.size(),
			"source_status": str(source_profile.get("status", "")),
			"runtime_profile_id": direct_profile_id,
			"runtime_drop_enabled": runtime_drop_enabled,
			"runtime_slot_count": direct_slots.size(),
			"runtime_baseline_origin": str(
				direct_profile.get("baseline_origin", "")
			),
		})
		compiled_profile_summaries.append({
			"canonical_monster_id": canonical_id,
			"canonical_monster_name": str(
				direct_profile.get("canonical_monster_name", "")
			),
			"runtime_profile_id": direct_profile_id,
			"drop_enabled": runtime_drop_enabled,
			"baseline_origin": str(
				direct_profile.get("baseline_origin", "")
			),
			"slot_count": direct_slots.size(),
		})

		for ordinal_zero_based: int in range(entries.size()):
			var entry_value: Variant = entries[ordinal_zero_based]
			if not entry_value is Dictionary:
				failures.append(
					"%s source entry[%d] is not a Dictionary" %
					[source_profile_id, ordinal_zero_based]
				)
				continue
			var entry: Dictionary = entry_value
			var direct_slot: Dictionary = {}
			if runtime_drop_enabled:
				if ordinal_zero_based >= direct_slots.size():
					failures.append(
						"missing direct slot for canonical ID %d ordinal %d" %
						[canonical_id, ordinal_zero_based]
					)
					continue
				var direct_slot_value: Variant = direct_slots[
					ordinal_zero_based
				]
				if not direct_slot_value is Dictionary:
					failures.append(
						"direct slot is not a Dictionary for canonical ID %d " +
						"ordinal %d" % [canonical_id, ordinal_zero_based]
					)
					continue
				direct_slot = direct_slot_value

			var snapshot_row := _build_source_row(
				source_profile_id,
				canonical_id,
				ordinal_zero_based,
				entry,
				direct_profile,
				direct_slot,
				runtime_drop_enabled,
				failures
			)
			source_rows.append(snapshot_row)
			_bump(
				source_rate_policy_counts,
				str(entry.get("rate_policy", "<missing>"))
			)
			_bump(
				source_status_counts,
				str(entry.get("slot_status", "<missing>"))
			)
			if not bool(snapshot_row.get("source_chance_valid", false)):
				malformed_source_rows.append(snapshot_row)

			if runtime_drop_enabled:
				enabled_source_row_count += 1
				compiled_slots.append(snapshot_row.duplicate(true))
				var compiled_slot_uid := str(snapshot_row.get(
					"slot_uid",
					""
				))
				if compiled_slot_uid.is_empty():
					failures.append(
						"compiled row is missing slot_uid for canonical ID %d" %
						canonical_id
					)
				elif seen_slot_uids.has(compiled_slot_uid):
					failures.append(
						"compiled slot UID collision: %s" % compiled_slot_uid
					)
				else:
					seen_slot_uids[compiled_slot_uid] = true
				if bool(snapshot_row.get("runtime_reward_resolved", false)) \
						and bool(snapshot_row.get(
							"runtime_probability_resolved",
							false
						)) \
						and bool(snapshot_row.get("runtime_rng_eligible", false)):
					var origin := str(snapshot_row.get(
						"baseline_origin",
						""
					))
					_bump(origin_counts, origin)
				var item_id_value: Variant = snapshot_row.get(
					"canonical_item_id",
					null
				)
				var item_id := int(item_id_value) if item_id_value != null else -1
				if item_id > 0:
					_bump(item_occurrences, str(item_id))
			else:
				disabled_source_row_count += 1

	var catalog_text_after := FileAccess.get_file_as_string(CATALOG_PATH)
	var catalog_sha256_after := _sha256_text(catalog_text_after)
	if catalog_sha256_before != catalog_sha256_after:
		failures.append(
			"canonical catalog changed during export: before=%s after=%s" %
			[catalog_sha256_before, catalog_sha256_after]
		)

	_check_runtime_summary(
		GameData.dpv2_direct_baseline,
		origin_counts,
		compiled_slots,
		runtime_enabled_profile_count,
		runtime_non_loot_profile_count,
		failures
	)
	_check_source_summary(
		source_profiles,
		source_rows,
		enabled_source_row_count,
		disabled_source_row_count,
		malformed_source_rows,
		source_rate_policy_counts,
		source_status_counts,
		failures
	)
	var correction_provenance := _load_correction_provenance(failures)
	_check_correction_provenance(
		malformed_source_rows,
		correction_provenance,
		failures
	)

	if not failures.is_empty():
		_fail(failures)
		return

	var duplicate_item_occurrences := 0
	for raw_count: Variant in item_occurrences.values():
		var count := int(raw_count)
		if count > 1:
			duplicate_item_occurrences += count - 1

	var source_summary := {
		"profile_count": source_profiles.size(),
		"row_count": source_rows.size(),
		"enabled_source_row_count": enabled_source_row_count,
		"non_loot_disabled_source_row_count": disabled_source_row_count,
		"malformed_source_provenance_count": malformed_source_rows.size(),
		"rate_policy_counts": source_rate_policy_counts,
		"slot_status_counts": source_status_counts,
	}
	var runtime_summary := {
		"profile_count": seen_canonical_ids.size(),
		"enabled_profile_count": runtime_enabled_profile_count,
		"non_loot_profile_count": runtime_non_loot_profile_count,
		"slot_count": compiled_slots.size(),
		"baseline_origin_counts": origin_counts,
		"reward_resolved_slot_count": compiled_slots.size(),
		"probability_resolved_slot_count": compiled_slots.size(),
		"rng_eligible_slot_count": compiled_slots.size(),
		"rng_roll_stage_slot_count": compiled_slots.size(),
		"all_compiled_slots_rng_before_overflow": true,
		"duplicate_canonical_item_occurrences": duplicate_item_occurrences,
		"unique_slot_uid_count": seen_slot_uids.size(),
		"post_rng_ground_slot_limit": GameData.dpv2_ground_slot_limit(),
	}
	var summary := {
		"source_corpus": source_summary,
		"compiled_runtime": runtime_summary,
	}
	var snapshot := {
		"schema": SNAPSHOT_SCHEMA,
		"authority": {
			"catalog_path": CATALOG_PATH,
			"catalog_sha256_before": catalog_sha256_before,
			"catalog_sha256_after": catalog_sha256_after,
			"runtime_authority": {
				"authority_id": str(
					GameData.dpv2_direct_baseline.get("authority_id", "")
				),
				"schema": str(
					GameData.dpv2_direct_baseline.get("schema", "")
				),
				"production_runtime": str(
					GameData.dpv2_direct_baseline.get(
						"production_runtime",
						""
					)
				),
				"identity_key": "canonical_monster_id",
				"direct_profile_join": "canonical_monster_id_exact",
				"source_profile_id_is_audit_only": true,
				"fallback_forbidden": true,
				"probability_formula": (
					"min(1, base_numerator * scale_num "
					+ "/(base_denominator * scale_den))"
				),
			},
			"active_global_drop_rate": (
				GameData.dpv2_active_global_drop_rate()
			),
			"source_slot_gate": GameData.dpv2_source_slot_gate(),
			"source_corpus_is_audit_only": true,
			"compiled_runtime_is_rng_authority": true,
			"overflow_stage": "after_all_probability_rolls",
		},
		"direct_baseline_summary": (
			GameData.dpv2_direct_baseline.get("summary", {})
		),
		"source_summary": source_summary,
		"compiled_runtime_summary": runtime_summary,
		"summary": summary,
		"correction_provenance": correction_provenance,
		"source_profiles": source_profile_summaries,
		"compiled_profiles": compiled_profile_summaries,
		"source_rows": source_rows,
		"compiled_slots": compiled_slots,
	}

	var output_dir := OUTPUT_PATH.get_base_dir()
	var mkdir_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(output_dir)
	)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		_fail([
			"cannot create output directory %s: error=%d" %
			[output_dir, mkdir_error]
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
		("MONSTER_DROP_P1A_RUNTIME_EXPORT_PASS: "
		+ "source_profiles=%d source_rows=%d enabled_source=%d "
		+ "non_loot_source=%d malformed_provenance=%d "
		+ "compiled_profiles=%d enabled_profiles=%d non_loot_profiles=%d "
		+ "compiled_slots=%d") % [
			source_summary.profile_count,
			source_summary.row_count,
			source_summary.enabled_source_row_count,
			source_summary.non_loot_disabled_source_row_count,
			source_summary.malformed_source_provenance_count,
			runtime_summary.profile_count,
			runtime_summary.enabled_profile_count,
			runtime_summary.non_loot_profile_count,
			runtime_summary.slot_count,
		]
	)
	get_tree().quit(0)


func _build_catalog_profile_index(
	catalog: Dictionary,
	failures: Array[String]
) -> Dictionary:
	var result: Dictionary = {}
	var entries_by_id_value: Variant = catalog.get("entries_by_id", {})
	if not entries_by_id_value is Dictionary:
		failures.append("canonical catalog entries_by_id is not a Dictionary")
		return result
	var entries_by_id: Dictionary = entries_by_id_value
	for raw_id: Variant in entries_by_id.keys():
		var key_id := int(str(raw_id))
		var entry_value: Variant = entries_by_id.get(raw_id, {})
		if not entry_value is Dictionary:
			failures.append("catalog entry %s is not a Dictionary" % raw_id)
			continue
		var entry: Dictionary = entry_value
		var monster_id := int(entry.get("monster_id", key_id))
		if monster_id != key_id or monster_id <= 0:
			failures.append("catalog canonical ID key mismatch: %s" % raw_id)
			continue
		var source_profile_id := str(entry.get("drop_profile_id", ""))
		if source_profile_id.is_empty():
			failures.append(
				"catalog monster %d has no source drop profile ID" % monster_id
			)
			continue
		if result.has(source_profile_id):
			failures.append(
				"source drop profile ID maps to multiple canonical IDs: %s" %
				source_profile_id
			)
			continue
		result[source_profile_id] = monster_id
	return result


func _build_source_row(
	source_profile_id: String,
	canonical_id: int,
	ordinal_zero_based: int,
	entry: Dictionary,
	direct_profile: Dictionary,
	direct_slot: Dictionary,
	runtime_drop_enabled: bool,
	failures: Array[String]
) -> Dictionary:
	var source_chance := str(entry.get("chance", ""))
	var source_chance_denominator := int(
		LootRuntime.call("_chance_denominator", source_chance)
	)
	var source_chance_valid := source_chance_denominator > 0
	var runtime_profile_id_value: Variant = direct_profile.get(
		"drop_profile_id",
		null,
	)
	var runtime_profile_id := (
		"" if runtime_profile_id_value == null
		else str(runtime_profile_id_value)
	)
	var row := {
		"source_profile_id": source_profile_id,
		"canonical_monster_id": canonical_id,
		"source_entry_ordinal_zero_based": ordinal_zero_based,
		"source_entry_ordinal_one_based": ordinal_zero_based + 1,
		"source_line_number": int(entry.get("line_number", -1)),
		"source_slot_index": str(entry.get("slot_index", "")),
		"source_item_label": str(entry.get("item", "")),
		"source_raw_text": str(entry.get("raw_text", "")),
		"source_chance": source_chance,
		"source_chance_denominator": (
			source_chance_denominator if source_chance_valid else null
		),
		"source_chance_valid": source_chance_valid,
		"source_rate_policy": str(entry.get("rate_policy", "")),
		"source_slot_status": str(entry.get("slot_status", "")),
		"source_kind": str(entry.get("source_kind", "")),
		"source_ref": str(entry.get("source_ref", "")),
		"source_entry": entry.duplicate(true),
		"runtime_profile_id": runtime_profile_id,
		"runtime_compiled": runtime_drop_enabled,
		"runtime_reward_resolved": false,
		"runtime_probability_resolved": false,
		"runtime_rng_eligible": false,
		"runtime_rng_eligible_before_overflow": false,
		"runtime_rejection_reason": (
			"" if runtime_drop_enabled else "non_loot_profile"
		),
		"runtime_slot": null,
		"slot_uid": "",
		"source_provenance_id": "",
		"canonical_item_id": null,
		"gold_amount": null,
		"reward_kind": "",
		"item_name": "",
		"baseline_origin": "",
		"base_numerator": null,
		"base_denominator": null,
		"base_probability": null,
		"global_preset": "",
		"global_scale_numerator": null,
		"global_scale_denominator": null,
		"global_scale": null,
		"final_numerator": null,
		"final_denominator": null,
		"final_probability": null,
		"overflow_priority": null,
		"protected_drop": null,
	}
	if not runtime_drop_enabled:
		return row
	if direct_slot.is_empty():
		failures.append(
			"compiled source row has no direct slot: %s line=%d" %
			[source_profile_id, int(entry.get("line_number", -1))]
		)
		return row

	var slot_uid := str(direct_slot.get("slot_uid", ""))
	var provenance_id := str(direct_slot.get("source_provenance_id", ""))
	var expected_provenance_id := "dpv2.source.m%d.%s" % [
		canonical_id,
		str(entry.get("slot_index", "")),
	]
	if slot_uid.is_empty() or provenance_id.is_empty():
		failures.append(
			"compiled slot identity is incomplete: %s" % direct_slot
		)
	if provenance_id != expected_provenance_id:
		failures.append(
			"source/direct slot provenance mismatch for canonical ID %d: " %
			canonical_id
			+ "%s != %s" % [provenance_id, expected_provenance_id]
		)

	var reward := GameData.dpv2_direct_resolve_slot_reward(direct_slot)
	var probability := GameData.dpv2_direct_slot_probability(
		canonical_id,
		slot_uid
	)
	var reward_ok := bool(reward.get("ok", false))
	var probability_ok := bool(probability.get("ok", false))
	if not reward_ok:
		failures.append(
			"direct reward unresolved for %s: %s" %
			[slot_uid, str(reward.get("reason", ""))]
		)
	if not probability_ok:
		failures.append(
			"direct probability unresolved for %s: %s" %
			[slot_uid, str(probability.get("reason", ""))]
		)
	row["runtime_slot"] = direct_slot.duplicate(true)
	row["slot_uid"] = slot_uid
	row["source_provenance_id"] = provenance_id
	row["runtime_reward_resolved"] = reward_ok
	row["runtime_probability_resolved"] = probability_ok
	row["runtime_rng_eligible"] = reward_ok and probability_ok
	row["runtime_rng_eligible_before_overflow"] = (
		reward_ok and probability_ok
	)
	if not reward_ok or not probability_ok:
		row["runtime_rejection_reason"] = (
			str(reward.get("reason", ""))
			if not reward_ok
			else str(probability.get("reason", ""))
		)
	if reward_ok:
		row["reward_kind"] = str(reward.get("kind", ""))
		row["canonical_item_id"] = (
			int(reward.get("canonical_item_id", -1))
			if str(reward.get("kind", "")) == "item"
			else null
		)
		row["gold_amount"] = (
			int(reward.get("gold_amount", -1))
			if str(reward.get("kind", "")) == "gold"
			else null
		)
		row["item_name"] = str(reward.get("item_name", ""))
	if probability_ok:
		for field: String in [
			"baseline_origin",
			"base_numerator",
			"base_denominator",
			"base_probability",
			"global_preset",
			"global_scale_numerator",
			"global_scale_denominator",
			"global_scale",
			"final_numerator",
			"final_denominator",
			"final_probability",
			"overflow_priority",
			"protected_drop",
		]:
			row[field] = probability.get(field, row.get(field))
		if row.get("canonical_item_id") == null \
				and str(probability.get("reward_kind", "")) == "item":
			row["canonical_item_id"] = int(
				probability.get("canonical_item_id", -1)
			)
		if row.get("gold_amount") == null \
				and str(probability.get("reward_kind", "")) == "gold":
			row["gold_amount"] = int(probability.get("gold_amount", -1))
	return row


func _check_runtime_summary(
	baseline: Dictionary,
	origin_counts: Dictionary,
	compiled_slots: Array,
	runtime_enabled_profile_count: int,
	runtime_non_loot_profile_count: int,
	failures: Array[String]
) -> void:
	var baseline_summary_value: Variant = baseline.get("summary", {})
	if not baseline_summary_value is Dictionary:
		failures.append("direct baseline summary is not a Dictionary")
		return
	var summary: Dictionary = baseline_summary_value
	_expect_int(
		"runtime profile count",
		int(summary.get("active_monsters", -1)),
		EXPECTED_RUNTIME_PROFILE_COUNT,
		failures
	)
	_expect_int(
		"runtime enabled profile count",
		int(summary.get("drop_enabled_monsters", -1)),
		EXPECTED_RUNTIME_ENABLED_PROFILE_COUNT,
		failures
	)
	_expect_int(
		"runtime NON_LOOT profile count",
		int(summary.get("non_loot_monsters", -1)),
		EXPECTED_RUNTIME_NON_LOOT_PROFILE_COUNT,
		failures
	)
	_expect_int(
		"runtime compiled slot count",
		int(summary.get("compiled_slots", -1)),
		EXPECTED_RUNTIME_SLOT_COUNT,
		failures
	)
	_expect_int(
		"observed runtime enabled profile count",
		runtime_enabled_profile_count,
		EXPECTED_RUNTIME_ENABLED_PROFILE_COUNT,
		failures
	)
	_expect_int(
		"observed runtime NON_LOOT profile count",
		runtime_non_loot_profile_count,
		EXPECTED_RUNTIME_NON_LOOT_PROFILE_COUNT,
		failures
	)
	_expect_int(
		"observed runtime compiled slot count",
		compiled_slots.size(),
		EXPECTED_RUNTIME_SLOT_COUNT,
		failures
	)
	var expected_origins := {
		"LEGACY_21CQ_MONITEMS": EXPECTED_LEGACY_RUNTIME_SLOT_COUNT,
		"PROJECT_EXTENSION": EXPECTED_EXTENSION_RUNTIME_SLOT_COUNT,
	}
	if origin_counts != expected_origins:
		failures.append(
			"runtime baseline origin counts mismatch: actual=%s expected=%s" %
			[origin_counts, expected_origins]
		)
	_expect_int(
		"baseline invalid probability count",
		int(summary.get("invalid_compiled_numerator_or_denominator", -1)),
		0,
		failures
	)
	_expect_int(
		"baseline x1 mismatch count",
		int(summary.get("x1_probability_mismatch", -1)),
		0,
		failures
	)
	_expect_int(
		"baseline duplicate slot collapse count",
		int(summary.get("duplicate_slot_collapse", -1)),
		0,
		failures
	)
	for raw_slot: Variant in compiled_slots:
		if not raw_slot is Dictionary:
			failures.append("compiled slot snapshot is not a Dictionary")
			continue
		var slot: Dictionary = raw_slot
		if not bool(slot.get("runtime_reward_resolved", false)) \
				or not bool(slot.get("runtime_probability_resolved", false)) \
				or not bool(slot.get("runtime_rng_eligible", false)):
			failures.append(
				"compiled slot did not close reward/probability/RNG: %s" %
				slot.get("slot_uid", "")
			)


func _check_source_summary(
	source_profiles: Dictionary,
	source_rows: Array,
	enabled_source_row_count: int,
	disabled_source_row_count: int,
	malformed_source_rows: Array,
	source_rate_policy_counts: Dictionary,
	source_status_counts: Dictionary,
	failures: Array[String]
) -> void:
	_expect_int(
		"source corpus profile count",
		source_profiles.size(),
		EXPECTED_SOURCE_PROFILE_COUNT,
		failures
	)
	_expect_int(
		"source corpus row count",
		source_rows.size(),
		EXPECTED_SOURCE_ROW_COUNT,
		failures
	)
	_expect_int(
		"enabled source row count",
		enabled_source_row_count,
		EXPECTED_ENABLED_SOURCE_ROW_COUNT,
		failures
	)
	_expect_int(
		"NON_LOOT source row count",
		disabled_source_row_count,
		EXPECTED_NON_LOOT_SOURCE_ROW_COUNT,
		failures
	)
	_expect_int(
		"malformed source provenance count",
		malformed_source_rows.size(),
		EXPECTED_MALFORMED_SOURCE_PROVENANCE_COUNT,
		failures
	)
	_expect_int(
		"source rate_policy=AUDIT_ONLY count",
		int(source_rate_policy_counts.get("AUDIT_ONLY", 0)),
		EXPECTED_SOURCE_ROW_COUNT,
		failures
	)
	_expect_int(
		"source slot_status=CONFIRMED_SOURCE_SLOT count",
		int(source_status_counts.get("CONFIRMED_SOURCE_SLOT", 0)),
		EXPECTED_SOURCE_ROW_COUNT,
		failures
	)
	if enabled_source_row_count + disabled_source_row_count \
			!= source_rows.size():
		failures.append(
			"source corpus enabled/disabled partition does not close"
		)
	for raw_row: Variant in source_rows:
		if not raw_row is Dictionary:
			failures.append("source row snapshot is not a Dictionary")
			continue
		var row: Dictionary = raw_row
		var runtime_compiled := bool(row.get("runtime_compiled", false))
		if not runtime_compiled and (
			bool(row.get("runtime_rng_eligible", false))
			or row.get("runtime_slot", null) != null
		):
			failures.append(
				"NON_LOOT source row reached Runtime fields: %s" %
				row.get("source_profile_id", "")
			)


func _load_correction_provenance(failures: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(CORRECTION_PATH):
		failures.append(
			"missing source correction authority: %s" % CORRECTION_PATH
		)
		return {}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CORRECTION_PATH)
	)
	if not parsed is Dictionary:
		failures.append("source correction authority is not a JSON object")
		return {}
	var authority: Dictionary = parsed
	if str(authority.get("schema", "")) \
			!= "hardcore.dpv2.21cq_source_corrections.v1":
		failures.append("source correction authority schema mismatch")
	if str(authority.get("status", "")) != "VERIFIED_SOURCE_CORRECTION":
		failures.append("source correction authority is not verified")
	var corrections_value: Variant = authority.get("corrections", [])
	if not corrections_value is Array or (corrections_value as Array).size() != 1:
		failures.append("source correction authority must contain one correction")
		return {}
	var correction_value: Variant = (corrections_value as Array)[0]
	if not correction_value is Dictionary:
		failures.append("source correction record is not a Dictionary")
		return {}
	var correction: Dictionary = correction_value
	var evidence_value: Variant = correction.get("evidence", {})
	var evidence: Dictionary = (
		evidence_value.duplicate(true)
		if evidence_value is Dictionary
		else {}
	)
	return {
		"authority_id": str(authority.get("authority_id", "")),
		"path": CORRECTION_PATH,
		"correction_id": str(correction.get("correction_id", "")),
		"source_profile_id": "drop.%d" % int(correction.get("stable_monster_id", -1)),
		"canonical_monster_id": int(correction.get("stable_monster_id", -1)),
		"stable_monster_id": int(correction.get("stable_monster_id", -1)),
		"source_line_number": int(
			correction.get("source_line_number", -1)
		),
		"source_slot_index": str(
			correction.get("source_slot_index", "")
		),
		"source_item_label": str(
			correction.get("source_item_label", "")
		),
		"source_chance": str(correction.get("original_chance", "")),
		"source_raw_text": "%s %s" % [
			str(correction.get("original_chance", "")),
			str(correction.get("source_item_label", "")),
		],
		"original_chance": str(correction.get("original_chance", "")),
		"corrected_base_numerator": int(
			correction.get("corrected_base_numerator", -1)
		),
		"corrected_base_denominator": int(
			correction.get("corrected_base_denominator", -1)
		),
		"reason": str(correction.get("reason", "")),
		"evidence": evidence,
	}


func _check_correction_provenance(
	malformed_source_rows: Array,
	correction: Dictionary,
	failures: Array[String]
) -> void:
	if malformed_source_rows.size() != 1:
		return
	var row_value: Variant = malformed_source_rows[0]
	if not row_value is Dictionary:
		return
	var row: Dictionary = row_value
	_expect_string(
		"malformed source profile",
		str(row.get("source_profile_id", "")),
		EXPECTED_ANOMALY_SOURCE_PROFILE_ID,
		failures
	)
	_expect_int(
		"malformed source monster ID",
		int(row.get("canonical_monster_id", -1)),
		EXPECTED_ANOMALY_MONSTER_ID,
		failures
	)
	_expect_int(
		"malformed source line",
		int(row.get("source_line_number", -1)),
		EXPECTED_ANOMALY_LINE_NUMBER,
		failures
	)
	_expect_string(
		"malformed source slot",
		str(row.get("source_slot_index", "")),
		EXPECTED_ANOMALY_SLOT_INDEX,
		failures
	)
	_expect_string(
		"malformed source chance",
		str(row.get("source_chance", "")),
		EXPECTED_ANOMALY_CHANCE,
		failures
	)
	_expect_string(
		"malformed source raw text",
		str(row.get("source_raw_text", "")),
		EXPECTED_ANOMALY_RAW_TEXT,
		failures
	)
	_expect_int(
		"correction monster ID",
		int(correction.get("stable_monster_id", -1)),
		EXPECTED_ANOMALY_MONSTER_ID,
		failures
	)
	_expect_string(
		"correction source slot",
		str(correction.get("source_slot_index", "")),
		EXPECTED_ANOMALY_SLOT_INDEX,
		failures
	)
	_expect_string(
		"correction original chance",
		str(correction.get("original_chance", "")),
		EXPECTED_ANOMALY_CHANCE,
		failures
	)
	_expect_int(
		"correction numerator",
		int(correction.get("corrected_base_numerator", -1)),
		1,
		failures
	)
	_expect_int(
		"correction denominator",
		int(correction.get("corrected_base_denominator", -1)),
		EXPECTED_ANOMALY_CORRECTED_DENOMINATOR,
		failures
	)
	var runtime_slot_value: Variant = row.get("runtime_slot", null)
	if not runtime_slot_value is Dictionary:
		failures.append("malformed source row has no compiled runtime slot")
		return
	var runtime_slot: Dictionary = runtime_slot_value
	_expect_int(
		"malformed source compiled denominator",
		int(runtime_slot.get("base_denominator", -1)),
		EXPECTED_ANOMALY_CORRECTED_DENOMINATOR,
		failures
	)
	if not bool(row.get("runtime_rng_eligible", false)):
		failures.append(
			"malformed source provenance must not block direct Runtime RNG"
		)


func _sorted_numeric_keys(value: Dictionary) -> Array:
	var result: Array = value.keys()
	result.sort_custom(func(left: Variant, right: Variant) -> bool:
		return int(str(left).trim_prefix("drop.")) \
			< int(str(right).trim_prefix("drop."))
	)
	return result


func _expect_int(
	label: String,
	actual: int,
	expected: int,
	failures: Array[String]
) -> void:
	if actual != expected:
		failures.append(
			"%s mismatch: actual=%d expected=%d" % [label, actual, expected]
		)


func _expect_string(
	label: String,
	actual: String,
	expected: String,
	failures: Array[String]
) -> void:
	if actual != expected:
		failures.append(
			"%s mismatch: actual=%s expected=%s" % [label, actual, expected]
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
		"MONSTER_DROP_P1A_RUNTIME_EXPORT_FAIL_COUNT=%d" % failures.size()
	)
	get_tree().quit(1)
