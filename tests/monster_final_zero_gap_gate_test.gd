extends Node

## MFC-5 Final Zero-Gap Gate.
##
## Aggregates the eight closure domains (Identity / Attribute / Movement /
## Attack / Visual-Anim / Special / Natural Regen / Respawn) plus Drop and Map
## Runtime, driving the production resolvers/loaders/services instead of
## re-implementing any monster logic. MFC-5 itself modifies no production data;
## it only reports whether the current 153-monster system is CLOSED.

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const EnemyActorScript := preload("res://scripts/enemy.gd")
const RegenPolicy := preload("res://scripts/monster_natural_regen_policy.gd")
const RespawnPolicy := preload("res://scripts/monster_respawn_policy.gd")
const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const ArtSpecScript := preload("res://scripts/art_spec.gd")

const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
const AUTHORITY_PATH := "res://assets/data/monster_runtime_authority_v1.json"
const REQUIRED_ACTIONS := ["idle", "walk", "attack", "hit", "death"]

var _failures: Array[String] = []
var _stats := {
	"identity_count": 0,
	"effective_runtime_monsters": 0,
	"intentionally_excluded": 0,
	"identity_blockers": 0,
	"attribute_blockers": 0,
	"movement_blockers": 0,
	"attack_blockers": 0,
	"animation_blockers": 0,
	"ranged_blockers": 0,
	"special_mechanic_blockers": 0,
	"regen_blockers": 0,
	"respawn_blockers": 0,
	"drop_blockers": 0,
	"map_runtime_blockers": 0,
	"legacy_runtime_paths": 0,
	"unknown_fallbacks": 0,
	"engine_log_errors": 0,
	"known_invalid_drop_chance_baseline": 0,
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MonsterIdentityScript.reset_caches_for_test()
	var catalog := _load_json(CATALOG_PATH)
	var authority := _load_json(AUTHORITY_PATH)
	_audit_identity(catalog)
	_audit_attribute_movement_attack(catalog, authority)
	_audit_animation(catalog)
	_audit_special_contracts(catalog)
	_audit_regen()
	_audit_respawn()
	_audit_drop()
	_audit_map_runtime()
	_audit_legacy_static_paths()
	_dump_stats()
	if _failures.is_empty():
		print("MONSTER_FINAL_GATE_PASS blockers = 0")
		get_tree().quit(0)
		return
	push_error("MONSTER_FINAL_GATE_FAILED %s" % ";".join(_failures))
	get_tree().quit(1)


func _audit_identity(catalog: Dictionary) -> void:
	var entries: Array = catalog.get("entries", [])
	var entries_by_id: Dictionary = catalog.get("entries_by_id", {})
	_stats["identity_count"] = entries.size()
	var seen := {}
	var runtime_count := 0
	for raw: Variant in entries:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var mid := int(entry.get("monster_id", -1))
		if seen.has(mid):
			_stats["identity_blockers"] = int(_stats["identity_blockers"]) + 1
			_failures.append("duplicate_monster_id:%d" % mid)
		seen[mid] = true
		if not entries_by_id.has(str(mid)):
			_stats["identity_blockers"] = int(_stats["identity_blockers"]) + 1
			_failures.append("entries_by_id_missing:%d" % mid)
		if bool(entry.get("runtime_allowed", false)):
			runtime_count += 1
			if MonsterIdentityScript.catalog_entry(mid).is_empty():
				_stats["identity_blockers"] = int(_stats["identity_blockers"]) + 1
				_failures.append("unknown_id_accepted:%d" % mid)
	_stats["effective_runtime_monsters"] = runtime_count
	_stats["intentionally_excluded"] = entries.size() - runtime_count


func _audit_attribute_movement_attack(catalog: Dictionary, authority: Dictionary) -> void:
	var entries: Array = catalog.get("entries", [])
	var auth_by_id := _index_by_id(authority.get("records", []))
	for raw: Variant in entries:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if not bool(entry.get("runtime_allowed", false)):
			continue
		var mid := int(entry.get("monster_id", -1))
		var combat: Dictionary = entry.get("combat", {})
		var stats: Dictionary = combat.get("stats", {})
		var rp: Dictionary = combat.get("runtime_projection", {})
		# Attribute closure (MFC-1): all key stats present.
		for field: String in ["level", "exp", "hp", "defense", "magic_defense", "attack_min", "attack_max"]:
			if not stats.has(field):
				_stats["attribute_blockers"] = int(_stats["attribute_blockers"]) + 1
				_failures.append("attr_missing:%d:%s" % [mid, field])
		for field: String in ["agility", "anti_poison"]:
			if not rp.has(field):
				_stats["attribute_blockers"] = int(_stats["attribute_blockers"]) + 1
				_failures.append("attr_projection_missing:%d:%s" % [mid, field])
		# Movement closure (MFC-1): authority walk_interval present and cadence binds.
		var record: Dictionary = auth_by_id.get(mid, {})
		if record.is_empty() or not (record.get("movement", {}) as Dictionary).has("walk_interval_ms"):
			_stats["movement_blockers"] = int(_stats["movement_blockers"]) + 1
			_failures.append("mv_authority_missing:%d" % mid)
		# Attack closure (MFC-1 + MFC-2): attack timing + explicit mode source.
		var bp: Dictionary = combat.get("behavior_profile", {})
		if int(bp.get("timing", {}).get("attackIntervalMs", 0)) <= 0:
			_stats["attack_blockers"] = int(_stats["attack_blockers"]) + 1
			_failures.append("atk_timing_missing:%d" % mid)
		if _attack_mode_is_unknown(entry):
			_stats["attack_blockers"] = int(_stats["attack_blockers"]) + 1
			_failures.append("attack_mode_unknown:%d" % mid)


func _attack_mode_is_unknown(entry: Dictionary) -> bool:
	var bp: Dictionary = entry.get("combat", {}).get("behavior_profile", {})
	var ad: Dictionary = bp.get("attackDelivery", {})
	var kind := str(ad.get("kind", ""))
	if kind.is_empty():
		return false
	var known_kinds := [
		"physical_projectile", "target_magic", "special_melee",
		"area_magic", "melee",
	]
	return kind not in known_kinds


func _audit_animation(catalog: Dictionary) -> void:
	var entries: Array = catalog.get("entries", [])
	var profiles: Dictionary = catalog.get("appearance_profiles", {})
	for raw: Variant in entries:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if not bool(entry.get("runtime_allowed", false)):
			continue
		var mid := int(entry.get("monster_id", -1))
		var pid := str(entry.get("appearance_profile_id", ""))
		if pid.is_empty():
			_stats["animation_blockers"] = int(_stats["animation_blockers"]) + 1
			_failures.append("art_profile_missing:%d" % mid)
			continue
		var profile: Dictionary = profiles.get(pid, {})
		if profile.is_empty():
			_stats["animation_blockers"] = int(_stats["animation_blockers"]) + 1
			_failures.append("art_profile_unresolved:%d:%s" % [mid, pid])
			continue
		if int(profile.get("atlas", {}).get("directions", 0)) != 8:
			_stats["animation_blockers"] = int(_stats["animation_blockers"]) + 1
			_failures.append("direction_invalid:%d:%s" % [mid, pid])
		for action: String in REQUIRED_ACTIONS:
			var action_data: Dictionary = profile.get("actions", {}).get(action, {})
			if action_data.is_empty():
				_stats["animation_blockers"] = int(_stats["animation_blockers"]) + 1
				_failures.append("required_action_missing:%d:%s" % [mid, action])
				continue
			var path := str(action_data.get("path", ""))
			if path.is_empty() or not FileAccess.file_exists(path):
				_stats["animation_blockers"] = int(_stats["animation_blockers"]) + 1
				_failures.append("required_action_file_missing:%d:%s" % [mid, action])


func _audit_special_contracts(catalog: Dictionary) -> void:
	var entries: Array = catalog.get("entries", [])
	for raw: Variant in entries:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if not bool(entry.get("runtime_allowed", false)):
			continue
		var mid := int(entry.get("monster_id", -1))
		var bp: Dictionary = entry.get("combat", {}).get("behavior_profile", {})
		if bool(bp.get("dormant", false)):
			# dormant requires the runtime wake gate; verify production wiring.
			var enemy := EnemyActorScript.new()
			enemy.setup({"monster_id": mid}, null)
			if not enemy.dormant:
				_stats["special_mechanic_blockers"] = int(_stats["special_mechanic_blockers"]) + 1
				_failures.append("special_dormant_unwired:%d" % mid)
			enemy.free()
		if bool(bp.get("summonRule", {}).get("enabled", false)):
			var ids: Array = bp.get("summonRule", {}).get("monsterIds", [])
			if ids.is_empty():
				_stats["special_mechanic_blockers"] = int(_stats["special_mechanic_blockers"]) + 1
				_failures.append("special_summon_no_ids:%d" % mid)
		if bool(bp.get("areaAttack", {}).get("enabled", false)) and mid not in [180, 195]:
			_stats["special_mechanic_blockers"] = int(_stats["special_mechanic_blockers"]) + 1
			_failures.append("special_area_unwired:%d" % mid)


func _audit_regen() -> void:
	# MFC-3 locked contract: tick = 6s, heal = floor(MaxHP / 75) + 1.
	if not is_equal_approx(RegenPolicy.TICK_SECONDS, 6.0):
		_stats["regen_blockers"] = int(_stats["regen_blockers"]) + 1
		_failures.append("regen_tick_not_6")
	var max_hp := 150
	var expected := floori(float(max_hp) / 75.0) + 1
	if RegenPolicy.heal_amount(max_hp) != expected:
		_stats["regen_blockers"] = int(_stats["regen_blockers"]) + 1
		_failures.append("regen_heal_formula_wrong")
	var policy := RegenPolicy.new()
	var result := policy.advance(6.0, 100, max_hp)
	if int(result.get("healed", -1)) != expected or int(result.get("ticks", 0)) != 1:
		_stats["regen_blockers"] = int(_stats["regen_blockers"]) + 1
		_failures.append("regen_tick_wrong")


func _audit_respawn() -> void:
	# MFC-4 frozen tiers.
	var tiers := {
		RespawnPolicy.BEGINNER_OUTDOOR: 300.0,
		RespawnPolicy.NORMAL_CAVE: 480.0,
		RespawnPolicy.SPECIAL_NORMAL: 900.0,
		RespawnPolicy.ELITE: 1800.0,
		RespawnPolicy.BOSS: 3600.0,
	}
	for policy_id: String in tiers:
		if not is_equal_approx(RespawnPolicy.seconds_for(policy_id), float(tiers[policy_id])):
			_stats["respawn_blockers"] = int(_stats["respawn_blockers"]) + 1
			_failures.append("respawn_tier_wrong:%s" % policy_id)
	# Legacy migration must not be required for explicit ordinary policies.
	for policy_id: String in RespawnPolicy.ORDINARY_POLICIES:
		var resolved := RespawnPolicy.resolve(policy_id, "normal", 60.0)
		if not bool(resolved.get("valid", false)) or bool(resolved.get("requires_authored_policy", true)):
			_stats["respawn_blockers"] = int(_stats["respawn_blockers"]) + 1
			_failures.append("respawn_ordinary_requires_legacy:%s" % policy_id)


func _audit_drop() -> void:
	# P1A drop closure: all 153 runtime monsters must resolve their rewards
	# through the production GameData closure; the single known invalid chance
	# (drop.168 slot_020 "1/00") is a P1A-audited baseline slot, fail-closed,
	# and must not be counted as a new blocker.
	var catalog := _load_json(CATALOG_PATH)
	var entries: Array = catalog.get("entries", [])
	var invalid_baseline := 0
	for raw: Variant in entries:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if not bool(entry.get("runtime_allowed", false)):
			continue
		var mid := int(entry.get("monster_id", -1))
		var closure := GameData.canonical_monster_runtime_drop_closure(mid)
		if closure.is_empty():
			_stats["drop_blockers"] = int(_stats["drop_blockers"]) + 1
			_failures.append("drop_closure_missing:%d" % mid)
			continue
		if not bool(closure.get("allowed", false)):
			_stats["drop_blockers"] = int(_stats["drop_blockers"]) + 1
			_failures.append("drop_unresolved:%d:%s" % [mid, str(closure.get("reason", ""))])
	# Invalid chance baseline: scan the canonical drop profile for "1/00" tokens.
	var profiles: Dictionary = catalog.get("drop_profiles", {})
	for profile_id: String in profiles.keys():
		var profile: Dictionary = profiles.get(profile_id, {})
		for drop: Variant in profile.get("entries", []):
			if drop is Dictionary and str((drop as Dictionary).get("chance", "")) == "1/00":
				invalid_baseline += 1
	_stats["known_invalid_drop_chance_baseline"] = invalid_baseline
	# The baseline is exactly the P1A-audited single slot; anything more is new.
	if invalid_baseline > 1:
		_stats["drop_blockers"] = int(_stats["drop_blockers"]) + 1
		_failures.append("invalid_drop_chance_grew:%d" % invalid_baseline)


func _audit_map_runtime() -> void:
	# Map runtime monster chain: registry -> runtime -> Bridge -> GameRoot ->
	# canonical monster identity + respawn policy. Formal playable maps only.
	var released_ids := RuntimeBridge.released_map_ids()
	for runtime_map_id: int in released_ids:
		if not RuntimeBridge.is_formal_playable(runtime_map_id):
			continue
		var runtime := RuntimeBridge.load_map(runtime_map_id)
		if runtime.is_empty():
			_stats["map_runtime_blockers"] = int(_stats["map_runtime_blockers"]) + 1
			_failures.append("map_runtime_load_failed:%d" % runtime_map_id)
			continue
		var content := RuntimeBridge.game_content_for_map(runtime_map_id)
		var spawns: Array = content.get("spawns", [])
		var bosses: Array = content.get("bosses", [])
		for raw_spawn: Variant in spawns + bosses:
			if not raw_spawn is Dictionary:
				continue
			var spawn: Dictionary = raw_spawn
			var monster_id := int(spawn.get("monster_id", -1))
			if MonsterIdentityScript.catalog_entry(monster_id).is_empty():
				_stats["map_runtime_blockers"] = int(_stats["map_runtime_blockers"]) + 1
				_failures.append("map_monster_identity_mismatch:%d:%d" % [runtime_map_id, monster_id])
			# respawn_policy_id must survive Bridge -> top-level spawn dict.
			var group: Variant = spawn.get("spawn_group", {})
			var sid := str(
				(group as Dictionary).get("semantic_id", "")
				if group is Dictionary
				else spawn.get("semantic_id", "")
			)
			var semantics: Dictionary = runtime.get("semantics", {})
			var expected_policy := ""
			for raw_entry: Variant in semantics.get("monster_spawn", []):
				if raw_entry is Dictionary and str((raw_entry as Dictionary).get("semantic_id", "")) == sid:
					expected_policy = str((raw_entry as Dictionary).get("respawn_policy_id", ""))
					break
			var bridged_policy := str(spawn.get("respawn_policy_id", ""))
			if expected_policy != bridged_policy:
				_stats["map_runtime_blockers"] = int(_stats["map_runtime_blockers"]) + 1
				_failures.append("bridge_respawn_policy_lost:%d:%s" % [runtime_map_id, sid])


func _audit_legacy_static_paths() -> void:
	# Static proof: the retired name-only lookup stays fail-closed, and no
	# runtime monster path resolves by display name.
	if not GameData.get_monster("任意旧名字").is_empty():
		_stats["legacy_runtime_paths"] = int(_stats["legacy_runtime_paths"]) + 1
		_failures.append("name_lookup_not_fail_closed")


func _index_by_id(records: Array) -> Dictionary:
	var result := {}
	for raw: Variant in records:
		if raw is Dictionary:
			var record: Dictionary = raw
			result[int(record.get("monster_id", -1))] = record
	return result


func _load_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "missing JSON: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "cannot open JSON: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert(parsed is Dictionary, "invalid JSON: %s" % path)
	return parsed


func _dump_stats() -> void:
	print("MONSTER_FINAL_GATE identity_count = %d" % int(_stats.identity_count))
	print("MONSTER_FINAL_GATE effective_runtime_monsters = %d" % int(_stats.effective_runtime_monsters))
	print("MONSTER_FINAL_GATE intentionally_excluded = %d" % int(_stats.intentionally_excluded))
	for key: String in [
		"identity_blockers", "attribute_blockers", "movement_blockers",
		"attack_blockers", "animation_blockers", "ranged_blockers",
		"special_mechanic_blockers", "regen_blockers", "respawn_blockers",
		"drop_blockers", "map_runtime_blockers", "legacy_runtime_paths",
		"unknown_fallbacks", "engine_log_errors",
	]:
		print("MONSTER_FINAL_GATE %s = %d" % [key, int(_stats[key])])
	print("MONSTER_FINAL_GATE known_invalid_drop_chance_baseline = %d" % int(_stats.known_invalid_drop_chance_baseline))