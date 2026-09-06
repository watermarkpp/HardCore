extends Node

const PROFILE_PATH := "res://assets/data/monster_behavior_profiles.json"
const BOSS_RULE_PATH := "res://assets/data/boss_service_rules.json"
const SOURCE_PATH := "res://assets/data/monster_special_delivery_sources_v1.json"
const RANGE_POLICY_PATH := "res://assets/data/monster_attack_range_policy_v1.json"
const ENEMY_PATH := "res://scripts/enemy.gd"

var _failures: Array[String] = []


func _ready() -> void:
	var profiles := _read_json(PROFILE_PATH)
	var boss_rules := _read_json(BOSS_RULE_PATH)
	var sources := _read_json(SOURCE_PATH)
	var range_policy := _read_json(RANGE_POLICY_PATH)
	_assert_profiles(profiles)
	_assert_boss_rules(boss_rules)
	_assert_sources(sources)
	_assert_range_policy(range_policy)
	_assert_runtime_route()
	if _failures.is_empty():
		print("MONSTER_SPECIAL_DELIVERY_CONTRACT_PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	get_tree().quit(1)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("missing JSON: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_failures.append("invalid JSON object: %s" % path)
		return {}
	return parsed as Dictionary


func _assert_profiles(document: Dictionary) -> void:
	var profiles: Dictionary = document.get("profiles", {})
	var by_id: Dictionary = document.get("profileByMonsterId", {})
	var names: Dictionary = document.get("legacyNameToProfile", {})
	var flame: Dictionary = profiles.get("flame_wooma", {})
	var flame_delivery: Dictionary = flame.get("attackDelivery", {})
	_expect(float(flame.get("runtimeProjection", {}).get("attack_range_gu", -1.0)) == 1.0, "70 range must be 1 GU")
	_expect(not flame.get("runtimeProjection", {}).has("attackRange"), "70 legacy 155px range must be removed")
	_expect(str(flame_delivery.get("kind", "")) == "special_melee", "70 kind must be special_melee")
	_expect(str(flame_delivery.get("effectId", "")) == "monster.flame_wooma.magic_melee.v1", "70 effectId mismatch")
	_expect(str(flame_delivery.get("damageChannel", "")) == "magic_defense", "70 must use magic_defense")
	_expect(bool(flame_delivery.get("bodyOnly", false)), "70 must be body-only")
	_expect(str(by_id.get("70", "")) == "flame_wooma", "70 runtime mapping missing")
	_expect(not by_id.has("71"), "71 must not be runtime mapped")
	_expect(str(names.get("火焰沃玛", "")) == "flame_wooma", "70 legacy name missing")
	_expect(not names.has("火焰沃玛0"), "71 legacy name must be retired")

	var touch: Dictionary = profiles.get("touch_dragon", {})
	var touch_delivery: Dictionary = touch.get("attackDelivery", {})
	_expect(int(touch.get("timing", {}).get("attackIntervalMs", 0)) == 2000, "124 profile interval must be 2000ms")
	_expect(float(touch.get("runtimeProjection", {}).get("attack_range_gu", -1.0)) == 6.0, "124 range must be 6 GU")
	_expect(str(touch_delivery.get("kind", "")) == "area_magic", "124 kind must be area_magic")
	_expect(str(touch_delivery.get("effectId", "")) == "monster.touch_dragon.area_magic.v1", "124 effectId mismatch")
	_expect(str(touch_delivery.get("rangeShape", "")) == "chebyshev_axis_aligned_square", "124 shape mismatch")
	_expect(str(touch_delivery.get("boundary", "")) == "exclusive", "124 boundary must be exclusive")
	_expect(float(touch_delivery.get("hitDelaySeconds", 0.0)) == 0.6, "124 delay must be 600ms")
	_expect(str(touch_delivery.get("obstaclePolicy", "")) == "none_no_los", "124 must not add LOS")
	_expect(bool(touch_delivery.get("bodyOnly", false)), "124 must be body-only")
	_expect(int(touch_delivery.get("status", {}).get("poisonWeight", 0)) == 2, "124 poison weight mismatch")
	_expect(int(touch_delivery.get("status", {}).get("controlWeight", 0)) == 1, "124 control weight mismatch")


func _assert_boss_rules(document: Dictionary) -> void:
	var rules: Dictionary = document.get("runtimeRulesByMonsterId", {})
	var rule: Dictionary = rules.get("124", {})
	var delivery: Dictionary = rule.get("attackDelivery", {})
	_expect(int(rule.get("timing", {}).get("attackIntervalMs", 0)) == 2000, "124 boss rule must not retain 5000ms")
	_expect(str(delivery.get("kind", "")) == "area_magic", "124 boss delivery missing")
	_expect(str(delivery.get("obstaclePolicy", "")) == "none_no_los", "124 boss LOS policy mismatch")
	_expect(not bool(rule.get("specialSkill", {}).get("enabled", true)), "124 legacy warning skill must be disabled")
	_expect(not rule.get("specialSkill", {}).has("radius"), "124 must not retain circle radius")
	_expect(not rule.get("specialSkill", {}).has("warningSeconds"), "124 must not retain warning circle timing")


func _assert_sources(document: Dictionary) -> void:
	var records: Dictionary = {}
	for record_value: Variant in document.get("records", []):
		if record_value is Dictionary:
			records[int((record_value as Dictionary).get("monsterId", -1))] = record_value
	_expect(records.size() == 3, "special source manifest must contain exactly 70/71/124")
	var record70: Dictionary = records.get(70, {})
	var record71: Dictionary = records.get(71, {})
	var record124: Dictionary = records.get(124, {})
	_expect(str(record70.get("runtimeStatus", "")) == "active", "70 source status mismatch")
	_expect(str(record71.get("runtimeStatus", "")) == "retired_source_only", "71 source status mismatch")
	_expect(str(record124.get("runtimeStatus", "")) == "active", "124 source status mismatch")
	var record124_delivery: Dictionary = record124.get("attackDelivery", {})
	_expect(str(record124_delivery.get("effectId", "")) == "monster.touch_dragon.area_magic.v1", "124 source effect mismatch")


func _assert_range_policy(document: Dictionary) -> void:
	_expect(str(document.get("contractId", "")) == "monster.attack_range_policy.v1", "attack range policy contract mismatch")
	_expect(str(document.get("unitContract", "")) == "combat.unit.gu_gs_px.v1", "attack range policy unit contract mismatch")
	_expect(str(document.get("distanceMetric", "")) == "euclidean", "attack range policy must be Euclidean")
	_expect(str(document.get("sourcePriorityEvidence", {}).get("path", "")) == "assets/data/source_priority_policy.json", "attack range source-priority evidence missing")
	_expect(str(document.get("unitSource", {}).get("tier", "")) == "primary", "attack range unit source is not primary")
	_expect(str(document.get("unitSource", {}).get("sha256", "")).length() == 64, "attack range unit source hash missing")
	var expected_ranges := {
		70: 1.0,
		124: 6.0,
		150: 7.0,
		152: 7.0,
		206: 7.0,
		220: 2.0,
		222: 2.0,
	}
	var by_id: Dictionary = {}
	for record_value: Variant in document.get("records", []):
		if record_value is Dictionary:
			var record := record_value as Dictionary
			by_id[int(record.get("monsterId", -1))] = record
	_expect(by_id.size() == expected_ranges.size(), "attack range policy exact-ID record count mismatch")
	for monster_id_value: Variant in expected_ranges.keys():
		var monster_id := int(monster_id_value)
		var record: Dictionary = by_id.get(monster_id, {})
		_expect(not record.is_empty(), "attack range policy missing monsterId=%d" % monster_id)
		_expect(is_equal_approx(float(record.get("attackRangeGu", -1.0)), float(expected_ranges[monster_id])), "attack range GU mismatch for monsterId=%d" % monster_id)
		var source: Dictionary = record.get("source", {})
		_expect(str(source.get("distribution", "")) == "source.original_gameofmir.server_suite", "range source distribution mismatch for monsterId=%d" % monster_id)
		_expect(str(source.get("tier", "")) == "primary", "range source tier mismatch for monsterId=%d" % monster_id)
		_expect(str(source.get("path", "")).begins_with("dev_art_sources/reference/original_gameofmir/"), "range source is not primary server rule for monsterId=%d" % monster_id)
		_expect(str(source.get("sha256", "")).length() == 64, "range source hash missing for monsterId=%d" % monster_id)
		if monster_id in [150, 152, 206]:
			_expect(str(record.get("deliveryKind", "")) == "physical_projectile", "archer delivery mismatch for monsterId=%d" % monster_id)
			_expect(str(record.get("rangeShape", "")) == "euclidean_circle", "archer range shape mismatch for monsterId=%d" % monster_id)
		if monster_id in [220, 222]:
			_expect(str(record.get("deliveryKind", "")) == "target_magic", "caster delivery mismatch for monsterId=%d" % monster_id)
			_expect(str(record.get("rangeShape", "")) == "chebyshev_square", "caster source grid shape mismatch for monsterId=%d" % monster_id)
			_expect(bool(record.get("sourceContactMeleeFallback", false)), "caster source melee fallback missing for monsterId=%d" % monster_id)


func _assert_runtime_route() -> void:
	var file := FileAccess.open(ENEMY_PATH, FileAccess.READ)
	if file == null:
		_failures.append("missing runtime source: %s" % ENEMY_PATH)
		return
	var source := file.get_as_text()
	_expect(source.contains("_uses_special_magic_melee_delivery"), "enemy missing 70 delivery route")
	_expect(source.contains("_uses_area_magic_delivery"), "enemy missing 124 delivery route")
	_expect(source.contains("_deal_area_magic_damage"), "enemy missing 124 magic resolution")
	_expect(source.contains("take_direct_spell_damage"), "special deliveries must use magic-defense API")
	_expect(source.contains("_update_area_magic_delivery(delta)"), "124 exclusive early route missing")
	_expect(source.contains("MONSTER_AREA_MAGIC_EFFECT_ID"), "124 stable effect constant missing")
	_expect(source.contains("RETIRED_SOURCE_ONLY_MONSTER_IDS := [71]"), "71 runtime retirement guard missing")
	_expect(source.contains("MONSTER_ATTACK_RANGE_POLICY_PATH"), "attack range policy path missing")
	_expect(source.contains("_apply_attack_range_policy()"), "attack range policy is not applied after profile projection")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
