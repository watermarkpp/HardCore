extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const EnemyActorScript := preload("res://scripts/enemy.gd")
const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MonsterIdentityScript.reset_caches_for_test()
	var catalog := _load_json(CATALOG_PATH)
	var entries: Array = catalog.get("entries", [])
	var entries_by_id: Dictionary = catalog.get("entries_by_id", {})
	var summary: Dictionary = catalog.get("summary", {})
	assert(entries.size() == 217, "canonical catalog must retain all 217 stable identities")
	assert(entries_by_id.size() == 217, "canonical ID index must close all stable identities")
	assert(catalog.get("identity_key", "") == "monster_id", "canonical catalog must be ID keyed")
	var seen_ids: Dictionary = {}
	var runtime_count := 0
	for value: Variant in entries:
		assert(value is Dictionary, "canonical catalog contains a non-dictionary entry")
		var entry: Dictionary = value
		var monster_id := int(entry.get("monster_id", -1))
		var key := str(monster_id)
		assert(monster_id >= 0 and not seen_ids.has(key), "duplicate or invalid monster_id=%s" % key)
		seen_ids[key] = true
		assert(entries_by_id.get(key, {}) == entry, "entries_by_id mismatch for monster_id=%d" % monster_id)
		var runtime_allowed := bool(entry.get("runtime_allowed", false))
		if runtime_allowed:
			runtime_count += 1
			assert(not MonsterIdentityScript.require_catalog_entry(monster_id, "runtime").is_empty(), "allowed ID=%d rejected at runtime" % monster_id)
			var profile := MonsterIdentityScript.behavior_profile({
				"monster_id": monster_id,
				"name": "intentionally wrong display name",
			})
			assert(not profile.is_empty(), "allowed ID=%d has no canonical behavior profile" % monster_id)
			assert(int(profile.get("timing", {}).get("attackIntervalMs", 0)) > 0, "ID=%d missing attack timing" % monster_id)
			assert(int(profile.get("serviceBehavior", {}).get("aiCode", -1)) >= 0, "ID=%d missing AI code" % monster_id)
		else:
			assert(MonsterIdentityScript.require_catalog_entry(monster_id, "runtime").is_empty(), "unresolved ID=%d must fail closed" % monster_id)
	assert(runtime_count == int(summary.get("runtime_allowed_count", -1)), "runtime allowed summary drifted")

	# A wrong display name never changes a canonical ID lookup.
	var id_18 := MonsterIdentityScript.behavior_profile({"monster_id": 18, "name": "conflicting old name"})
	assert(int(id_18.get("serviceBehavior", {}).get("aiCode", -1)) == 4, "ID 18 AI was not read from canonical service data")
	assert(int(id_18.get("timing", {}).get("moveIntervalMs", 0)) == 900, "ID 18 timing was not read from canonical service data")
	var id_124 := MonsterIdentityScript.behavior_profile({"monster_id": 124, "name": "conflicting old name"})
	assert(int(id_124.get("serviceBehavior", {}).get("aiCode", -1)) == 14, "ID 124 AI was not read from canonical service data")
	assert(is_equal_approx(float(id_124.get("runtimeProjection", {}).get("moveSpeed", -1.0)), 0.0), "ID 124 stationary projection was lost")
	var unresolved := MonsterIdentityScript.service_runtime_entry({"monster_id": 31})
	assert(not unresolved.is_empty() and int(unresolved.get("monster_id", -1)) == 31, "identity entry must remain inspectable by ID")
	assert(MonsterIdentityScript.service_runtime_entry({"name": "legacy-only"}).is_empty(), "name-only payload must fail closed")
	assert(MonsterIdentityScript.catalog_entry(999999).is_empty(), "unknown ID must fail closed")

	# EnemyActor receives only canonical combat projection; caller fields and boss
	# flags are deliberately ignored by the new runtime boundary.
	var ordinary_enemy := EnemyActorScript.new()
	ordinary_enemy.setup({
		"monster_id": 64,
		"name": "wrong",
		"hp": 1,
		"attackMin": 999,
		"attackMax": 999,
		"agility": 999,
		"antiPoison": 999,
	}, null, true)
	assert(not ordinary_enemy.is_boss and ordinary_enemy.max_hp == 285, "ID 64 caller payload changed canonical identity/stats")
	assert(ordinary_enemy.attack_min == 16 and ordinary_enemy.attack_max == 28, "ID 64 attack range was not projected from canonical stats")
	assert(ordinary_enemy.agility == 15 and ordinary_enemy.anti_poison == 0, "ID 64 legacy projection fields leaked into runtime")
	ordinary_enemy.free()

	print("ALL_MONSTER_LOADING_CANONICAL_PASS: identities=217 runtime_allowed=%d id_only=1" % runtime_count)
	get_tree().quit(0)


func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "missing JSON: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(parsed is Dictionary, "invalid JSON: %s" % path)
	return parsed
