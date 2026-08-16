extends Node

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
const REQUIRED_ACTIONS := ["idle", "walk", "attack", "hit", "death"]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MonsterIdentityScript.reset_caches_for_test()
	var catalog := _load_json(CATALOG_PATH)
	var entries: Array = catalog.get("entries", [])
	var appearance_profiles: Dictionary = catalog.get("appearance_profiles", {})
	assert(entries.size() == 217, "canonical appearance check must cover all 217 IDs")
	assert(appearance_profiles.size() == int(catalog.get("summary", {}).get("appearance_profile_count", -1)), "appearance profile summary drifted")
	var formal_profile_ids: Dictionary = {}
	var allowed_count := 0
	for value: Variant in entries:
		assert(value is Dictionary, "canonical entry is not a dictionary")
		var entry: Dictionary = value
		var monster_id := int(entry.get("monster_id", -1))
		var profile_id := str(entry.get("appearance_profile_id", ""))
		var profile: Dictionary = appearance_profiles.get(profile_id, {})
		assert(not profile.is_empty(), "monster_id=%d has no appearance profile" % monster_id)
		assert(profile_id == str(profile.get("appearance_profile_id", "")), "monster_id=%d appearance profile key mismatch" % monster_id)
		var allowed := bool(entry.get("runtime_allowed", false)) or bool(entry.get("editor_placement", {}).get("allowed", false))
		if allowed:
			allowed_count += 1
			assert(str(profile.get("status", "")) == "formal", "allowed monster_id=%d has unresolved art" % monster_id)
			assert(not MonsterIdentityScript.require_catalog_entry(monster_id, "appearance").is_empty(), "allowed monster_id=%d has no appearance API closure" % monster_id)
			formal_profile_ids[profile_id] = true
			var actions: Dictionary = profile.get("actions", {})
			for action_name: String in REQUIRED_ACTIONS:
				var action: Dictionary = actions.get(action_name, {})
				var path := str(action.get("path", ""))
				assert(not path.is_empty() and not str(action.get("path_sha256", "")).is_empty(), "monster_id=%d action=%s lacks explicit path/hash" % [monster_id, action_name])
				assert(bool(action.get("source_path_exists", false)) and FileAccess.file_exists(path), "monster_id=%d action=%s source art is missing" % [monster_id, action_name])
		else:
			if str(profile.get("status", "")) != "formal":
				assert(MonsterIdentityScript.require_catalog_entry(monster_id, "appearance").is_empty(), "unresolved monster_id=%d must fail closed for appearance" % monster_id)

	assert(allowed_count == int(catalog.get("summary", {}).get("runtime_allowed_count", -1)), "allowed appearance count must equal runtime/editor closure")
	assert(MonsterIdentityScript.appearance_profile(68).get("appearance_profile_id", "") == MonsterIdentityScript.appearance_profile(69).get("appearance_profile_id", ""), "Wooma 68/69 must explicitly share one art profile")
	assert(MonsterIdentityScript.appearance_profile(77).get("status", "") != "formal", "Wooma 77 art must remain unresolved")
	assert(MonsterIdentityScript.appearance_profile(78).get("status", "") != "formal", "Wooma 78 art must remain unresolved")
	assert(MonsterIdentityScript.appearance_profile(239).get("status", "") == "formal", "Wooma 239 art must retain its explicit profile")
	assert(not MonsterIdentityScript.require_catalog_entry(239, "runtime").is_empty(), "Wooma 239 must be runtime-enabled after R2 combat closure")
	assert(formal_profile_ids.size() > 0, "canonical catalog must expose formal client art")
	print("COMPLETE_MONSTER_CLIENT_ART_CANONICAL_PASS: identities=217 allowed=%d formal_profiles=%d actions=5" % [allowed_count, formal_profile_ids.size()])
	get_tree().quit(0)


func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "missing JSON: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(parsed is Dictionary, "invalid JSON: %s" % path)
	return parsed
