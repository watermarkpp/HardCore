extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const EnemyActorScript := preload("res://scripts/enemy.gd")
const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"

const WOOma_EXPECTED := {
	64: "ordinary",
	65: "ordinary",
	66: "ordinary",
	67: "ordinary",
	68: "ordinary",
	69: "ordinary",
	70: "ordinary",
	71: "ordinary",
	73: "elite",
	74: "elite",
	75: "elite",
	76: "boss",
	77: "special",
	78: "version_difference",
	239: "boss",
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MonsterIdentityScript.reset_caches_for_test()
	var catalog := _load_json(CATALOG_PATH)
	var entries: Array = catalog.get("entries", [])
	var entries_by_id: Dictionary = catalog.get("entries_by_id", {})
	var appearance_profiles: Dictionary = catalog.get("appearance_profiles", {})
	var drop_profiles: Dictionary = catalog.get("drop_profiles", {})
	for source_path: String in catalog.get("sources", {}):
		var source_evidence: Dictionary = catalog.get("sources", {}).get(source_path, {})
		var expected_hash_mode := "lf_text" if source_path.to_lower().ends_with(".json") else "raw_bytes"
		assert(source_evidence.get("hash_normalization", "") == expected_hash_mode, "source hash normalization mismatch for %s" % source_path)
	assert(entries.size() == 217, "canonical catalog must contain 217 stable identities")
	assert(entries_by_id.size() == 217, "entries_by_id must close all 217 identities")
	var seen_ids: Dictionary = {}
	for value: Variant in entries:
		assert(value is Dictionary, "catalog entries must be dictionaries")
		var entry: Dictionary = value
		var monster_id := int(entry.get("monster_id", -1))
		var key := str(monster_id)
		assert(monster_id >= 0 and not seen_ids.has(key), "duplicate/invalid monster_id=%s" % key)
		seen_ids[key] = true
		assert(entries_by_id.get(key, {}) == entry, "entries_by_id closure failed for monster_id=%d" % monster_id)
		var runtime_projection: Dictionary = entry.get("combat", {}).get("runtime_projection", {})
		assert(runtime_projection.get("agility") == 15 and runtime_projection.get("anti_poison") == 0, "monster_id=%d runtime projection defaults changed" % monster_id)
		for projection_field: String in ["agility", "anti_poison"]:
			assert(str(runtime_projection.get("source_evidence", {}).get(projection_field, {}).get("tier", "")) == "project_rule", "monster_id=%d projection evidence missing for %s" % [monster_id, projection_field])
		for required: String in [
			"canonical_name",
			"classification",
			"editor_placement",
			"runtime_allowed",
			"status",
			"drop_policy",
			"combat",
			"appearance_profile_id",
			"drop_profile_id",
			"spawn_contexts",
			"source_evidence",
		]:
			assert(entry.has(required), "monster_id=%d missing %s" % [monster_id, required])
		for evidence_field: String in [
			"canonical_name",
			"classification",
			"combat_stats",
			"combat_ai_timing",
			"appearance",
			"drops",
			"status",
		]:
			assert(entry.get("source_evidence", {}).has(evidence_field), "monster_id=%d missing source evidence %s" % [monster_id, evidence_field])
		var drop_id := str(entry.get("drop_profile_id", ""))
		var drop: Dictionary = drop_profiles.get(drop_id, {})
		assert(not drop.is_empty(), "monster_id=%d missing drop profile closure" % monster_id)
		var drop_count := int(drop.get("entry_count", drop.get("entries", []).size()))
		var hostile := str(entry.get("classification", "")) in ["ordinary", "elite", "boss", "special"]
		if hostile and bool(entry.get("runtime_allowed", false)):
			assert(drop_count > 0, "hostile runtime monster_id=%d has no drop rows" % monster_id)
		if hostile and bool(entry.get("editor_placement", {}).get("allowed", false)):
			assert(drop_count > 0, "hostile editor placement monster_id=%d has no drop rows" % monster_id)
		var profile_id := str(entry.get("appearance_profile_id", ""))
		var appearance: Dictionary = appearance_profiles.get(profile_id, {})
		assert(not appearance.is_empty(), "monster_id=%d missing appearance profile closure" % monster_id)
		if bool(entry.get("runtime_allowed", false)) or bool(entry.get("editor_placement", {}).get("allowed", false)):
			assert(str(appearance.get("status", "")) == "formal", "allowed monster_id=%d has unresolved appearance" % monster_id)
			for action_name: String in ["idle", "walk", "attack", "hit", "death"]:
				var action: Dictionary = appearance.get("actions", {}).get(action_name, {})
				assert(not str(action.get("path", "")).is_empty() and not str(action.get("path_sha256", "")).is_empty(), "monster_id=%d action=%s missing path/hash" % [monster_id, action_name])
				assert(bool(action.get("source_path_exists", false)), "monster_id=%d action=%s path missing" % [monster_id, action_name])
		_assert_clean_source_paths(entry, monster_id)
	for drop_profile_id: String in drop_profiles:
		var profile: Dictionary = drop_profiles.get(drop_profile_id, {})
		var drop_monster_id := int(drop_profile_id.trim_prefix("drop."))
		if drop_monster_id not in [68, 69]:
			continue
		for row: Variant in profile.get("entries", []):
			var item := str(row.get("item", "")) if row is Dictionary else ""
			assert(item != "LongBow" and item != "SilverBow", "runtime drop profile %s contains audited private item token %s" % [drop_profile_id, item])

	for monster_id: int in WOOma_EXPECTED:
		var wooma: Dictionary = entries_by_id.get(str(monster_id), {})
		assert(str(wooma.get("classification", "")) == WOOma_EXPECTED[monster_id], "Wooma matrix classification mismatch for %d" % monster_id)
		if monster_id == 78:
			assert(str(wooma.get("status", "")) == "version_difference" and not bool(wooma.get("editor_placement", {}).get("allowed", false)), "Wooma 78 must remain version_difference and unplaceable")
		if monster_id == 77:
			assert(str(wooma.get("editor_placement", {}).get("placement_kind", "")) == "monster_spawn" and not bool(wooma.get("editor_placement", {}).get("allowed", false)), "Wooma 77 must keep ordinary spawn semantics but remain unresolved")
		if monster_id in [68, 69]:
			var stats: Dictionary = wooma.get("combat", {}).get("stats", {})
			assert(stats.get("level") == 30 and stats.get("hp") == 285 and stats.get("defense") == 3 and stats.get("magic_defense") == 2 and stats.get("attack_min") == 16 and stats.get("attack_max") == 28 and stats.get("exp") == 310, "Wooma %d aux1 full combat row mismatch" % monster_id)
			var drop: Dictionary = drop_profiles.get(str(wooma.get("drop_profile_id", "")), {})
			assert(int(drop.get("entry_count", -1)) > 0, "Wooma %d must carry an audited Excel drop table" % monster_id)
			assert(drop.get("status", "") == "exact_slots", "Wooma %d drop status must be exact_slots (Excel authority)" % monster_id)
		if monster_id == 239:
			assert(int(wooma.get("monster_id", -1)) != int(entries_by_id.get("76", {}).get("monster_id", -1)), "Wooma 239 identity collapsed into 76")

	# Excel drop authority anchors.
	for anchor: Array in [[76, 33], [239, 54], [240, 54]]:
		var anchor_id: int = anchor[0]
		var anchor_entry: Dictionary = entries_by_id.get(str(anchor_id), {})
		var anchor_drop: Dictionary = drop_profiles.get(str(anchor_entry.get("drop_profile_id", "")), {})
		assert(int(anchor_drop.get("entry_count", -1)) == anchor[1], "Excel drop anchor %d slot count mismatch" % anchor_id)
	var snowman: Dictionary = entries_by_id.get("33", {})
	assert(drop_profiles.get(str(snowman.get("drop_profile_id", "")), {}).get("status", "") == "no_drop_confirmed", "Snowman must be no_drop_confirmed")

	var correct_id := MonsterIdentityScript.catalog_entry(64)
	var wrong_name := MonsterIdentityScript.catalog_entry(64)
	assert(int(correct_id.get("monster_id", -1)) == 64, "correct ID lookup failed")
	assert(wrong_name == correct_id, "catalog lookup must not vary with display name")
	assert(MonsterIdentityScript.monster_id({"monster_id": 64, "name": "intentionally wrong"}) == 64, "ID transport should win over a wrong display name")
	assert(MonsterIdentityScript.catalog_entry(999999).is_empty(), "unknown ID must be rejected")
	assert(MonsterIdentityScript.require_catalog_entry(999999, "runtime").is_empty(), "unknown runtime ID must fail closed")
	assert(MonsterIdentityScript.catalog_entry(-1).is_empty(), "missing ID must be rejected")
	assert(MonsterIdentityScript.monster_id({"name": "legacy-only"}) == -1, "name-only payload must not resolve an ID")
	assert(MonsterIdentityScript.service_runtime_entry({"name": "legacy-only"}).is_empty(), "service runtime API must not name-fallback")
	for malformed: Variant in [0, -1, "", " ", "64.0", "64x", "abc", 64.5, true]:
		assert(MonsterIdentityScript.monster_id({"monster_id": malformed}) == -1, "malformed ID token was not rejected: %s" % str(malformed))
	assert(MonsterIdentityScript.monster_id({"monsterId": "64"}) == 64, "numeric string transport ID must remain supported")
	var ordinary_enemy := EnemyActorScript.new()
	ordinary_enemy.setup({"monster_id": 64, "name": "wrong", "agility": 999, "antiPoison": 999}, null, true)
	assert(not ordinary_enemy.is_boss, "caller boss flag must not upgrade an ordinary canonical monster")
	assert(ordinary_enemy.agility == 15 and ordinary_enemy.anti_poison == 0, "legacy combat payload fields must not override canonical safe defaults")
	assert(not ordinary_enemy.monster_data.has("agility") and not ordinary_enemy.monster_data.has("name"), "legacy caller fields must not leak into EnemyActor payload")
	var boss_enemy := EnemyActorScript.new()
	boss_enemy.setup({"monster_id": 76, "name": "wrong"}, null, false)
	assert(boss_enemy.is_boss, "canonical boss classification must not be downgraded by caller flag")
	ordinary_enemy.free()
	boss_enemy.free()

	var identity_source := _read_text("res://scripts/monster_identity.gd")
	var visual_source := _read_text("res://scripts/monster_visual.gd")
	var enemy_source := _read_text("res://scripts/enemy.gd")
	for forbidden: String in ["baseName", "trim_suffix", "legacyNameToMonsterId", "legacyAliases", "PresentationAssets", "data.get(\"agility\"", "data.get(\"antiPoison\""]:
		assert(not identity_source.contains(forbidden) and not visual_source.contains(forbidden) and not enemy_source.contains(forbidden), "production monster path contains forbidden fallback token %s" % forbidden)
	assert(enemy_source.contains("is_boss = classification == \"boss\""), "EnemyActor must derive boss identity from canonical classification")
	print("CANONICAL_MONSTER_CATALOG_TEST_PASS: identities=217 wooma_matrix=15 id_only=1 drop_closure=1 excel_authority=1")
	get_tree().quit(0)


func _assert_clean_source_paths(entry: Dictionary, monster_id: int) -> void:
	var evidence: Dictionary = entry.get("source_evidence", {})
	for value: Variant in evidence.values():
		_assert_clean_value(value, monster_id)


func _assert_clean_value(value: Variant, monster_id: int) -> void:
	if value is Dictionary:
		for key: Variant in value:
			var child: Variant = value[key]
			if key in ["original_path", "source_path"] and child is String:
				assert(not child.contains("�") and not child.contains("??"), "monster_id=%d source path contains replacement characters" % monster_id)
			_assert_clean_value(child, monster_id)
	elif value is Array:
		for child: Variant in value:
			_assert_clean_value(child, monster_id)


func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "missing JSON: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(parsed is Dictionary, "invalid JSON: %s" % path)
	return parsed

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""
