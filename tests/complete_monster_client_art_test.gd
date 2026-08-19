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
	assert(entries.size() == 156, "canonical appearance check must cover all 156 IDs")
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
		# P3C: all 156 active entries have exact formal animation; the old
		# runtime_allowed-or-editor-placement gate is replaced by a strict
		# per-entry formal requirement.
		assert(str(profile.get("status", "")) == "formal", "active monster_id=%d has unresolved art" % monster_id)
		allowed_count += 1
		assert(not MonsterIdentityScript.require_catalog_entry(monster_id, "appearance").is_empty(), "active monster_id=%d has no appearance API closure" % monster_id)
		formal_profile_ids[profile_id] = true
		var actions: Dictionary = profile.get("actions", {})
		for action_name: String in REQUIRED_ACTIONS:
			var action: Dictionary = actions.get(action_name, {})
			var path := str(action.get("path", ""))
			assert(not path.is_empty() and not str(action.get("path_sha256", "")).is_empty(), "monster_id=%d action=%s lacks explicit path/hash" % [monster_id, action_name])
			assert(bool(action.get("source_path_exists", false)) and FileAccess.file_exists(path), "monster_id=%d action=%s source art is missing" % [monster_id, action_name])

	assert(allowed_count == int(catalog.get("summary", {}).get("identity_count", -1)), "formal appearance count must equal the full P3C active universe")
	assert(MonsterIdentityScript.appearance_profile(77).get("status", "") == "formal", "Wooma 77 art must be formal in P3C")
	assert(MonsterIdentityScript.appearance_profile(78).get("status", "") == "formal", "Wooma 78 art must be formal in P3C")
	assert(MonsterIdentityScript.appearance_profile(239).get("status", "") == "formal", "Wooma 239 art must be formal in P3C")
	assert(formal_profile_ids.size() > 0, "canonical catalog must expose formal client art")
	print("COMPLETE_MONSTER_CLIENT_ART_CANONICAL_PASS: identities=156 allowed=%d formal_profiles=%d actions=5" % [allowed_count, formal_profile_ids.size()])
	get_tree().quit(0)


func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "missing JSON: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	assert(parsed is Dictionary, "invalid JSON: %s" % path)
	return parsed
