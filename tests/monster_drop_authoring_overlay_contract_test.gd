extends Node

const OVERLAY_PATH := (
	"res://assets/data/"
	+ "canonical_monster_drop_authoring_overrides_v1.json"
)
const OVERLAY_SOURCE_KEY := (
	"assets/data/"
	+ "canonical_monster_drop_authoring_overrides_v1.json"
)
const BASE_DROP_ROW_COUNT := 7032


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(
		GameData.ensure_loaded(),
		"GameData failed to load for drop authoring overlay test"
	)

	var overlay := _load_json(OVERLAY_PATH)
	assert(
		str(overlay.get("schema", ""))
		== "canonical_monster_drop_authoring_overlay_v1"
	)
	assert(str(overlay.get("authority", "")) == "user_editable")

	var global_raw: Variant = overlay.get("global_additions", null)
	var monster_raw: Variant = overlay.get("monster_additions", null)
	assert(global_raw is Array, "global_additions must be an Array")
	assert(monster_raw is Array, "monster_additions must be an Array")

	var catalog: Dictionary = GameData.canonical_monster_catalog
	var profiles: Dictionary = catalog.get("drop_profiles", {})
	var entries_by_id: Dictionary = catalog.get("entries_by_id", {})
	assert(profiles.size() == 156, "expected 156 active drop profiles")
	assert(
		(catalog.get("sources", {}) as Dictionary).has(
			OVERLAY_SOURCE_KEY
		),
		"generated catalog does not track the authoring overlay source"
	)

	var config_by_key := {}
	var enabled_global_keys: Array[String] = []
	var enabled_monster_keys: Array[String] = []
	var disabled_keys: Array[String] = []

	for raw_config: Variant in global_raw:
		var config := _validate_runtime_config(
			raw_config,
			"global",
			entries_by_id
		)
		var key := str(config.get("entry_key", ""))
		assert(not config_by_key.has(key), "duplicate entry_key: %s" % key)
		config_by_key[key] = config
		if bool(config.get("enabled", false)):
			enabled_global_keys.append(key)
		else:
			disabled_keys.append(key)

	for raw_config: Variant in monster_raw:
		var config := _validate_runtime_config(
			raw_config,
			"monster",
			entries_by_id
		)
		var key := str(config.get("entry_key", ""))
		assert(not config_by_key.has(key), "duplicate entry_key: %s" % key)
		config_by_key[key] = config
		if bool(config.get("enabled", false)):
			enabled_monster_keys.append(key)
		else:
			disabled_keys.append(key)

	var observed_by_key := {}
	var observed_authoring_rows := 0
	var total_drop_rows := 0

	for raw_profile_id: Variant in profiles.keys():
		var profile_id := str(raw_profile_id)
		assert(
			profile_id.begins_with("drop."),
			"unexpected drop profile id: %s" % profile_id
		)
		var monster_id := int(profile_id.trim_prefix("drop."))
		var profile_value: Variant = profiles.get(raw_profile_id, {})
		assert(profile_value is Dictionary)
		var profile: Dictionary = profile_value

		for raw_row: Variant in profile.get("entries", []):
			assert(raw_row is Dictionary)
			var row: Dictionary = raw_row
			total_drop_rows += 1
			if not row.has("authoring_entry_key"):
				continue

			observed_authoring_rows += 1
			var key := str(row.get("authoring_entry_key", ""))
			assert(
				config_by_key.has(key),
				"generated catalog contains unknown authoring key: %s" % key
			)
			var config: Dictionary = config_by_key[key]
			assert(
				bool(config.get("enabled", false)),
				"disabled authoring key was emitted: %s" % key
			)

			var scope := str(config.get("_scope", ""))
			assert(
				str(row.get("authoring_scope", "")) == scope,
				"scope mismatch for %s" % key
			)
			if scope == "monster":
				assert(
					int(config.get("monster_id", -1)) == monster_id,
					"monster-specific row leaked into monster_id=%d: %s"
					% [monster_id, key]
				)

			assert(
				str(row.get("chance", ""))
				== str(config.get("chance", "")),
				"chance mismatch for %s" % key
			)
			assert(
				str(row.get("item", ""))
				== str(config.get("item", "")),
				"item mismatch for %s" % key
			)
			if config.has("gold"):
				assert(
					int(row.get("gold", 0))
					== int(config.get("gold", 0)),
					"gold mismatch for %s" % key
				)
			else:
				assert(
					not row.has("gold"),
					"non-gold row gained gold field: %s" % key
				)

			var reward := GameData.resolve_canonical_drop_reward(row)
			assert(
				bool(reward.get("ok", false)),
				"authoring row does not resolve through item authority: "
				+ "%s -> %s" % [key, reward]
			)
			observed_by_key[key] = (
				int(observed_by_key.get(key, 0)) + 1
			)

	for key: String in enabled_global_keys:
		assert(
			int(observed_by_key.get(key, 0)) == profiles.size(),
			"global authoring row must appear once in every profile: %s"
			% key
		)

	for key: String in enabled_monster_keys:
		assert(
			int(observed_by_key.get(key, 0)) == 1,
			"monster authoring row must appear exactly once: %s"
			% key
		)

	for key: String in disabled_keys:
		assert(
			int(observed_by_key.get(key, 0)) == 0,
			"disabled authoring row was emitted: %s" % key
		)

	var expected_overlay_rows := (
		enabled_global_keys.size() * profiles.size()
		+ enabled_monster_keys.size()
	)
	assert(
		observed_authoring_rows == expected_overlay_rows,
		"authoring row projection mismatch: observed=%d expected=%d"
		% [observed_authoring_rows, expected_overlay_rows]
	)
	assert(
		total_drop_rows
		== BASE_DROP_ROW_COUNT + expected_overlay_rows,
		"canonical drop row count mismatch: observed=%d expected=%d"
		% [
			total_drop_rows,
			BASE_DROP_ROW_COUNT + expected_overlay_rows,
		]
	)

	var summary: Dictionary = catalog.get("summary", {})
	assert(
		int(summary.get("drop_base_row_count", -1))
		== BASE_DROP_ROW_COUNT
	)
	assert(
		int(summary.get(
			"drop_authoring_enabled_global_count",
			-1
		)) == enabled_global_keys.size()
	)
	assert(
		int(summary.get(
			"drop_authoring_global_expanded_row_count",
			-1
		)) == enabled_global_keys.size() * profiles.size()
	)
	assert(
		int(summary.get(
			"drop_authoring_enabled_monster_count",
			-1
		)) == enabled_monster_keys.size()
	)
	assert(
		int(summary.get("drop_final_row_count", -1))
		== total_drop_rows
	)

	print(
		"MONSTER_DROP_AUTHORING_OVERLAY_CONTRACT_PASS: "
		+ "profiles=%d base_rows=%d overlay_rows=%d final_rows=%d"
		% [
			profiles.size(),
			BASE_DROP_ROW_COUNT,
			expected_overlay_rows,
			total_drop_rows,
		]
	)
	get_tree().quit(0)


func _validate_runtime_config(
	raw_config: Variant,
	scope: String,
	entries_by_id: Dictionary
) -> Dictionary:
	assert(raw_config is Dictionary)
	var config: Dictionary = raw_config
	var key := str(config.get("entry_key", ""))
	assert(not key.is_empty(), "entry_key is empty")
	assert(
		config.get("enabled", null) is bool,
		"enabled must be Boolean for %s" % key
	)
	assert(
		_valid_chance(str(config.get("chance", ""))),
		"invalid chance for %s" % key
	)
	var item := str(config.get("item", ""))
	assert(
		not item.is_empty() and item == item.strip_edges(),
		"invalid item token for %s" % key
	)
	if scope == "monster":
		var monster_id := int(config.get("monster_id", -1))
		assert(
			entries_by_id.has(str(monster_id)),
			"unknown active monster_id=%d for %s"
			% [monster_id, key]
		)

	var reward_probe := {"item": item}
	if config.has("gold"):
		reward_probe["gold"] = int(config.get("gold", 0))
	var reward := GameData.resolve_canonical_drop_reward(reward_probe)
	assert(
		bool(reward.get("ok", false)),
		"overlay item token does not resolve: %s -> %s"
		% [key, reward]
	)

	var result := config.duplicate(true)
	result["_scope"] = scope
	return result


func _valid_chance(token: String) -> bool:
	var parts := token.split("/", false)
	if parts.size() != 2 or parts[0] != "1":
		return false
	var denominator_token := str(parts[1])
	if denominator_token.is_empty():
		return false
	for index in range(denominator_token.length()):
		var codepoint := denominator_token.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
			return false
	return int(denominator_token) > 0


func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "missing JSON: %s" % path)
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(path)
	)
	assert(parsed is Dictionary, "invalid JSON: %s" % path)
	return parsed
