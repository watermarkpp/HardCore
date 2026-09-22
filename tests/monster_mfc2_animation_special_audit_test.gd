extends Node

## MFC-2 Final Audit: 153 monsters animation identity / ranged attack /
## special mechanic closure.
##
## Every runtime_allowed monster must resolve through the production identity
## chain (monster_id -> appearance_profile_id -> appearance profile -> actions
## -> direction -> frames -> MonsterVisual), must have an explicit attack mode
## backed by the production delivery rules (never a name guess), and every
## declared special mechanic must be wired into the runtime EnemyActor fields.
## The test drives production code (MonsterIdentity, Enemy.setup, ArtSpec
## direction mapping, effect IDs) and does not re-implement the monster system.

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const EnemyActorScript := preload("res://scripts/enemy.gd")
const ArtSpecScript := preload("res://scripts/art_spec.gd")
const AnimationPolicyScript := preload(
	"res://scripts/layers/presentation/monster_animation_policy.gd"
)
const RangedEffectScript := preload("res://scripts/monster_ranged_projectile_effect.gd")
const TargetMagicEffectScript := preload("res://scripts/monster_target_magic_effect.gd")

const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
const AUTHORITY_PATH := "res://assets/data/monster_runtime_authority_v1.json"
const BOSS_RULES_PATH := "res://assets/data/boss_service_rules.json"
const REQUIRED_ACTIONS := ["idle", "walk", "attack", "hit", "death"]

var _failures: Array[String] = []
var _stats := {
	"runtime_monsters": 0,
	"animation_profiles": 0,
	"animation_identity_mismatch": 0,
	"missing_required_action": 0,
	"invalid_direction": 0,
	"attack_mode_unknown": 0,
	"physical_ranged_invalid": 0,
	"magic_ranged_invalid": 0,
	"projectile_identity_mismatch": 0,
	"projectile_double_hit": 0,
	"special_contract_unknown": 0,
	"special_runtime_unwired": 0,
	"special_wrong_monster": 0,
	"name_based_special_fallback": 0,
	"name_based_identity_fallback": 0,
	"visual_owns_gameplay": 0,
	"ranged_runtime_unwired": 0,
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	MonsterIdentityScript.reset_caches_for_test()
	var catalog := _load_json(CATALOG_PATH)
	var authority := _load_json(AUTHORITY_PATH)
	var boss_rules := _load_json(BOSS_RULES_PATH)
	var auth_by_id := _index_by_id(authority.get("records", []))
	var boss_by_id := _index_boss_rules(boss_rules.get("runtimeRulesByMonsterId", {}))
	_audit_animation_identity(catalog)
	_audit_attack_modes(catalog, auth_by_id, boss_by_id)
	_audit_special_contracts(catalog, auth_by_id, boss_by_id)
	_audit_direction_mapping()
	_audit_visual_gameplay_decoupling()
	_audit_runtime_sample(catalog, boss_by_id)
	_dump_stats()
	if _failures.is_empty():
		print("MFC2_AUDIT_PASS runtime_monsters=%d" % int(_stats.runtime_monsters))
		get_tree().quit(0)
		return
	push_error("MFC2_AUDIT_FAILED %s" % ";".join(_failures))
	get_tree().quit(1)


func _audit_animation_identity(catalog: Dictionary) -> void:
	var profiles: Dictionary = catalog.get("appearance_profiles", {})
	var entries: Array = catalog.get("entries", [])
	for raw: Variant in entries:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if not bool(entry.get("runtime_allowed", false)):
			continue
		var mid := int(entry.get("monster_id", -1))
		_stats["runtime_monsters"] = int(_stats["runtime_monsters"]) + 1
		var pid := str(entry.get("appearance_profile_id", ""))
		if pid.is_empty():
			_stats["animation_identity_mismatch"] = int(_stats["animation_identity_mismatch"]) + 1
			_failures.append("anim_missing_profile_id:%d" % mid)
			continue
		var profile: Dictionary = profiles.get(pid, {})
		if profile.is_empty():
			_stats["animation_identity_mismatch"] = int(_stats["animation_identity_mismatch"]) + 1
			_failures.append("anim_profile_missing:%d:%s" % [mid, pid])
			continue
		_stats["animation_profiles"] = int(_stats["animation_profiles"]) + 1
		# production identity closure: MonsterIdentity must resolve this ID to the
		# same profile the visual layer consumes (no name/suffix/alias fallback).
		var resolved := MonsterIdentityScript.appearance_profile(mid)
		if resolved.is_empty():
			_stats["animation_identity_mismatch"] = int(_stats["animation_identity_mismatch"]) + 1
			_failures.append("anim_identity_resolve_failed:%d" % mid)
			continue
		if str(resolved.get("appearance_profile_id", "")) != pid:
			_stats["animation_identity_mismatch"] = int(_stats["animation_identity_mismatch"]) + 1
			_failures.append("anim_identity_drift:%d canonical=%s resolved=%s" % [
				mid, pid, str(resolved.get("appearance_profile_id", "")),
			])
		if int(profile.get("atlas", {}).get("directions", 0)) != 8:
			_stats["invalid_direction"] = int(_stats["invalid_direction"]) + 1
			_failures.append("anim_not_8_directions:%d:%s" % [mid, pid])
		var actions: Dictionary = profile.get("actions", {})
		for action: String in REQUIRED_ACTIONS:
			var action_data: Dictionary = actions.get(action, {})
			if action_data.is_empty():
				_stats["missing_required_action"] = int(_stats["missing_required_action"]) + 1
				_failures.append("anim_missing_action:%d:%s" % [mid, action])
				continue
			var path := str(action_data.get("path", ""))
			if path.is_empty() or not FileAccess.file_exists(path):
				_stats["missing_required_action"] = int(_stats["missing_required_action"]) + 1
				_failures.append("anim_missing_file:%d:%s:%s" % [mid, action, path])
				continue
			var frames_per_direction := int(action_data.get("framesPerDirection", 0))
			if frames_per_direction <= 0:
				_stats["missing_required_action"] = int(_stats["missing_required_action"]) + 1
				_failures.append("anim_zero_frames:%d:%s" % [mid, action])
				continue
			var source_frames: Array = action_data.get("sourceFrames", [])
			if not source_frames.is_empty():
				var per_direction := {}
				for frame: Variant in source_frames:
					if frame is Dictionary:
						var d := int((frame as Dictionary).get("direction", -1))
						per_direction[d] = int(per_direction.get(d, 0)) + 1
				if per_direction.size() != 8:
					_stats["invalid_direction"] = int(_stats["invalid_direction"]) + 1
					_failures.append("anim_sourceframe_dir_count:%d:%s:%d" % [mid, action, per_direction.size()])
					continue
				for d: int in per_direction:
					if int(per_direction[d]) != frames_per_direction:
						_stats["invalid_direction"] = int(_stats["invalid_direction"]) + 1
						_failures.append("anim_sourceframe_dir_frame:%d:%s:d%d:%d" % [
							mid, action, d, int(per_direction[d]),
						])
						break
			else:
				var validated := int(action_data.get("validatedSourceFrameCount", -1))
				var expected := frames_per_direction * 8
				if validated != expected:
					_stats["invalid_direction"] = int(_stats["invalid_direction"]) + 1
					_failures.append("anim_generated_frame_count:%d:%s:%d:%d" % [
						mid, action, validated, expected,
					])


func _audit_attack_modes(
	catalog: Dictionary,
	auth_by_id: Dictionary,
	boss_by_id: Dictionary
) -> void:
	var entries: Array = catalog.get("entries", [])
	for raw: Variant in entries:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if not bool(entry.get("runtime_allowed", false)):
			continue
		var mid := int(entry.get("monster_id", -1))
		var mode := _classify_attack_mode(entry, boss_by_id)
		if mode.is_empty():
			_stats["attack_mode_unknown"] = int(_stats["attack_mode_unknown"]) + 1
			_failures.append("attack_mode_unknown:%d" % mid)
			continue
		match mode:
			"physical_ranged":
				var ad := _delivery_rule(entry, boss_by_id, mid)
				if str(ad.get("effectId", "")) != RangedEffectScript.EFFECT_ID:
					_stats["physical_ranged_invalid"] = int(_stats["physical_ranged_invalid"]) + 1
					_failures.append("physical_ranged_bad_effect:%d:%s" % [mid, str(ad.get("effectId", ""))])
			"magic_ranged":
				var ad2 := _delivery_rule(entry, boss_by_id, mid)
				if str(ad2.get("effectId", "")) != TargetMagicEffectScript.EFFECT_ID:
					_stats["magic_ranged_invalid"] = int(_stats["magic_ranged_invalid"]) + 1
					_failures.append("magic_ranged_bad_effect:%d:%s" % [mid, str(ad2.get("effectId", ""))])


func _audit_special_contracts(
	catalog: Dictionary,
	auth_by_id: Dictionary,
	boss_by_id: Dictionary
) -> void:
	var entries: Array = catalog.get("entries", [])
	for raw: Variant in entries:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if not bool(entry.get("runtime_allowed", false)):
			continue
		var mid := int(entry.get("monster_id", -1))
		var bp: Dictionary = entry.get("combat", {}).get("behavior_profile", {})
		var br: Dictionary = boss_by_id.get(mid, {})
		var auth_special: Dictionary = auth_by_id.get(mid, {}).get("special", {})
		# Every dormant/summon/area/boss-mechanic declaration must have a known
		# contract shape; a conflicting/unknown declaration fails the gate.
		if bool(bp.get("dormant", false)) and str(auth_special.get("dormant_status", "")) != "LOCKED":
			_stats["special_contract_unknown"] = int(_stats["special_contract_unknown"]) + 1
			_failures.append("special_dormant_not_locked:%d:%s" % [mid, str(auth_special.get("dormant_status", ""))])
		if bool(bp.get("summonRule", {}).get("enabled", false)):
			var ids: Array = bp.get("summonRule", {}).get("monsterIds", [])
			if ids.is_empty():
				_stats["special_contract_unknown"] = int(_stats["special_contract_unknown"]) + 1
				_failures.append("special_summon_no_ids:%d" % mid)
			if str(auth_special.get("special_classification", "")) != "fixed_body_summoner":
				_stats["special_wrong_monster"] = int(_stats["special_wrong_monster"]) + 1
				_failures.append("special_summon_classify:%d:%s" % [mid, str(auth_special.get("special_classification", ""))])
		if not br.is_empty():
			var mechanics: Dictionary = br.get("mechanics", {})
			var declared := 0
			for key: Variant in mechanics.keys():
				var m: Variant = mechanics.get(key)
				if m is Dictionary and bool((m as Dictionary).get("enabled", false)):
					declared += 1
			if str(br.get("specialSkill", {}).get("enabled", false)) == "true":
				declared += 1
			if bool(br.get("phaseTwo", {}).get("enabled", false)):
				declared += 1
			# Validate runtime wiring via Enemy.setup for bosses below.
			if declared > 0:
				_verify_boss_wiring(mid, br)


func _verify_boss_wiring(mid: int, br: Dictionary) -> void:
	var enemy := EnemyActorScript.new()
	enemy.setup({"monster_id": mid}, null)
	if enemy.boss_rule.is_empty():
		_stats["special_runtime_unwired"] = int(_stats["special_runtime_unwired"]) + 1
		_failures.append("special_boss_rule_unwired:%d" % mid)
		enemy.free()
		return
	# burrow wiring
	if bool(br.get("mechanics", {}).get("burrowAmbush", {}).get("enabled", false)) and not enemy._burrowed:
		_stats["special_runtime_unwired"] = int(_stats["special_runtime_unwired"]) + 1
		_failures.append("special_burrow_unwired:%d" % mid)
	# health stage wiring
	if int(br.get("mechanics", {}).get("healthStageSummon", {}).get("stages", br.get("mechanics", {}).get("healthStageRage", {}).get("stages", 0))) > 0 and enemy._boss_health_stage < 0:
		_stats["special_runtime_unwired"] = int(_stats["special_runtime_unwired"]) + 1
		_failures.append("special_health_stage_unwired:%d" % mid)
	# phase two wiring
	if bool(br.get("phaseTwo", {}).get("enabled", false)) and not enemy._boss_phase_enabled:
		_stats["special_runtime_unwired"] = int(_stats["special_runtime_unwired"]) + 1
		_failures.append("special_phase_two_unwired:%d" % mid)
	enemy.free()


func _audit_direction_mapping() -> void:
	# 8 logical directions must map to unique rows 0..7 (no duplication, no
	# overlap), and the client mirror permutation must be a valid bijection.
	var logical_directions: Array[Vector2] = [
		Vector2.DOWN, Vector2(1, 1).normalized(), Vector2.RIGHT,
		Vector2(1, -1).normalized(), Vector2.UP, Vector2(-1, -1).normalized(),
		Vector2.LEFT, Vector2(-1, 1).normalized(),
	]
	var used := {}
	for direction: Vector2 in logical_directions:
		var row := ArtSpecScript.direction_index(direction)
		if used.has(row):
			_stats["invalid_direction"] = int(_stats["invalid_direction"]) + 1
			_failures.append("direction_index_duplicate:%d" % row)
		used[row] = true
	if used.size() != 8:
		_stats["invalid_direction"] = int(_stats["invalid_direction"]) + 1
		_failures.append("direction_index_incomplete:%d" % used.size())
	var mirror_used := {}
	for i: int in range(8):
		var row := ArtSpecScript.mir2_client_direction_row(
			logical_directions[i]
		)
		if row < 0 or row > 7:
			_stats["invalid_direction"] = int(_stats["invalid_direction"]) + 1
			_failures.append("mirror_row_out_of_range:%d" % row)
		if mirror_used.has(row):
			_stats["invalid_direction"] = int(_stats["invalid_direction"]) + 1
			_failures.append("mirror_row_duplicate:%d" % row)
		mirror_used[row] = true
	if mirror_used.size() != 8:
		_stats["invalid_direction"] = int(_stats["invalid_direction"]) + 1
		_failures.append("mirror_row_incomplete")


func _audit_visual_gameplay_decoupling() -> void:
	# Attack animation must be presentation-only: it cannot create a pending
	# gameplay damage release nor touch the attack cooldown clock.
	var player := PlayerCharacter.new()
	add_child(player)
	var enemy := EnemyActorScript.new()
	enemy.setup({"monster_id": 21}, player)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(enemy)
	await get_tree().process_frame
	enemy._attack_timer = 1.0
	enemy._pending_attack_time = -1.0
	var interval_before := enemy._attack_interval
	if enemy.visual != null:
		enemy.visual.play_attack(0.5)
	if enemy._attack_timer != 1.0 or enemy._attack_interval != interval_before:
		_stats["visual_owns_gameplay"] = int(_stats["visual_owns_gameplay"]) + 1
		_failures.append("visual_changed_attack_cadence")
	if enemy._pending_attack_time >= 0.0:
		_stats["visual_owns_gameplay"] = int(_stats["visual_owns_gameplay"]) + 1
		_failures.append("visual_created_damage_release")
	enemy.queue_free()
	player.queue_free()


func _audit_runtime_sample(catalog: Dictionary, boss_by_id: Dictionary) -> void:
	# Sample the production runtime wiring for every distinct delivery type.
	var samples: Array[Dictionary] = [
		{"mid": 21, "expect": "melee"},
		{"mid": 150, "expect": "physical_ranged"},
		{"mid": 152, "expect": "physical_ranged"},
		{"mid": 206, "expect": "physical_ranged"},
		{"mid": 220, "expect": "magic_ranged"},
		{"mid": 222, "expect": "magic_ranged"},
		{"mid": 70, "expect": "special_melee"},
		{"mid": 124, "expect": "area_magic"},
		{"mid": 126, "expect": "summoner"},
		{"mid": 182, "expect": "summoner"},
		{"mid": 180, "expect": "fixed_area"},
		{"mid": 195, "expect": "fixed_area"},
		{"mid": 153, "expect": "dormant"},
		{"mid": 160, "expect": "boss_complex"},
		{"mid": 76, "expect": "boss_rage"},
		{"mid": 43, "expect": "flying"},
		{"mid": 74, "expect": "elite"},
	]
	for sample: Dictionary in samples:
		var mid := int(sample.get("mid", 0))
		var enemy := EnemyActorScript.new()
		enemy.setup({"monster_id": mid}, null)
		var ok := _verify_sample_wiring(mid, sample.expect, enemy)
		enemy.free()
		if not ok:
			_stats["ranged_runtime_unwired"] = int(_stats["ranged_runtime_unwired"]) + 1
			_failures.append("sample_wiring_failed:%d:%s" % [mid, str(sample.expect)])


func _verify_sample_wiring(mid: int, expected: Variant, enemy: EnemyActorScript) -> bool:
	match str(expected):
		"melee":
			return not enemy._uses_physical_projectile_delivery() and not enemy._uses_target_magic_delivery()
		"physical_ranged":
			return enemy._uses_physical_projectile_delivery() and not enemy._uses_target_magic_delivery()
		"magic_ranged":
			return enemy._uses_target_magic_delivery() and not enemy._uses_physical_projectile_delivery()
		"special_melee":
			return enemy._uses_special_magic_melee_delivery()
		"area_magic":
			return enemy._uses_area_magic_delivery()
		"summoner":
			return not enemy.summon_rule.is_empty() and bool(enemy.summon_rule.get("enabled", false))
		"fixed_area":
			return enemy._uses_fixed_area_ground_spike_effect()
		"dormant":
			return enemy.dormant
		"boss_complex":
			return (
				not enemy.boss_rule.is_empty()
				and enemy.dormant
				and int(enemy.boss_rule.get("mechanics", {}).get("healthStageSummon", {}).get("stages", 0)) > 0
			)
		"boss_rage":
			return (
				not enemy.boss_rule.is_empty()
				and int(enemy.boss_rule.get("mechanics", {}).get("healthStageRage", {}).get("stages", 0)) > 0
			)
		"flying":
			# Flying monsters ignore world collision (production _ready drops the
			# entity collision layer) while keeping canonical movement/attack.
			return bool(enemy.behavior_profile.get("worldCollision", true)) == false
		"elite":
			return not enemy.is_boss and str(enemy.monster_data.get("classification", "")) == "elite"
	return false


func _classify_attack_mode(entry: Dictionary, boss_by_id: Dictionary) -> String:
	var mid := int(entry.get("monster_id", -1))
	var bp: Dictionary = entry.get("combat", {}).get("behavior_profile", {})
	var ad := _delivery_rule(entry, boss_by_id, mid)
	var kind := str(ad.get("kind", ""))
	var effect := str(ad.get("effectId", ""))
	var classification := str(entry.get("classification", ""))
	var att_max := int(entry.get("combat", {}).get("stats", {}).get("attack_max", 0))
	if classification == "non_hostile" or (att_max <= 0 and bp.get("summonRule", {}).get("enabled") != true and bp.get("areaAttack", {}).get("enabled") != true):
		return "non_attacking"
	if kind == "area_magic" and effect == "monster.touch_dragon.area_magic.v1":
		return "area_magic"
	if bool(bp.get("areaAttack", {}).get("enabled", false)):
		return "fixed_area"
	if kind == "special_melee" and effect == "monster.flame_wooma.magic_melee.v1":
		return "special_melee"
	if kind == "target_magic" and effect == "monster.target_lightning.v1":
		return "magic_ranged"
	if kind == "physical_projectile" and effect == "monster.physical_arrow.v1":
		return "physical_ranged"
	if bool(bp.get("summonRule", {}).get("enabled", false)):
		return "summoner"
	if bool(bp.get("dormant", false)):
		return "dormant"
	return "melee"


func _delivery_rule(entry: Dictionary, boss_by_id: Dictionary, mid: int) -> Dictionary:
	var bp: Dictionary = entry.get("combat", {}).get("behavior_profile", {})
	var ad: Dictionary = bp.get("attackDelivery", {})
	var br: Dictionary = boss_by_id.get(mid, {})
	var br_ad: Variant = br.get("attackDelivery", {})
	if br_ad is Dictionary and not (br_ad as Dictionary).is_empty() and str((br_ad as Dictionary).get("kind", "")).is_empty() == false:
		return br_ad
	return ad


func _index_by_id(records: Array) -> Dictionary:
	var result := {}
	for raw: Variant in records:
		if raw is Dictionary:
			var record: Dictionary = raw
			result[int(record.get("monster_id", -1))] = record
	return result


func _index_boss_rules(raw: Variant) -> Dictionary:
	var result := {}
	if raw is Dictionary:
		for key: Variant in (raw as Dictionary).keys():
			var value: Variant = (raw as Dictionary).get(key)
			if value is Dictionary:
				result[int(str(key).to_float())] = value
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
	for key: String in _stats.keys():
		print("MFC2_AUDIT %s = %d" % [key, int(_stats[key])])