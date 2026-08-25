class_name MonsterRespawnPolicy
extends RefCounted

## MONSTER-FINAL-CLOSURE / MFC-4
##
## Single numeric authority for world-monster respawn duration.
##
## Ordinary monster timing belongs to the authored map/spawn slot.
## Elite/Boss timing belongs to canonical classification.
##
## Historical respawn_seconds are accepted only as a temporary migration
## input and are folded into one of the five allowed HardCore tiers. Final
## closure must migrate every formal ordinary spawn to an explicit policy_id.

const CONTRACT_ID := "monster.respawn.policy.hardcore.v1"

const BEGINNER_OUTDOOR := "beginner_outdoor"
const NORMAL_CAVE := "normal_cave"
const SPECIAL_NORMAL := "special_normal"
const ELITE := "elite"
const BOSS := "boss"

const BEGINNER_OUTDOOR_SECONDS := 300.0
const NORMAL_CAVE_SECONDS := 480.0
const SPECIAL_NORMAL_SECONDS := 900.0
const ELITE_SECONDS := 1800.0
const BOSS_SECONDS := 3600.0

const SECONDS_BY_POLICY := {
	BEGINNER_OUTDOOR: BEGINNER_OUTDOOR_SECONDS,
	NORMAL_CAVE: NORMAL_CAVE_SECONDS,
	SPECIAL_NORMAL: SPECIAL_NORMAL_SECONDS,
	ELITE: ELITE_SECONDS,
	BOSS: BOSS_SECONDS,
}

const ORDINARY_POLICIES := [
	BEGINNER_OUTDOOR,
	NORMAL_CAVE,
	SPECIAL_NORMAL,
]


static func is_known(policy_id: String) -> bool:
	return SECONDS_BY_POLICY.has(policy_id)


static func seconds_for(policy_id: String) -> float:
	return float(SECONDS_BY_POLICY.get(policy_id, 0.0))


static func resolve(
	requested_policy_id: String,
	classification: String,
	legacy_respawn_seconds := -1.0
) -> Dictionary:
	var normalized_classification := classification.strip_edges().to_lower()
	var explicit_policy := requested_policy_id.strip_edges()

	if normalized_classification == "boss":
		if not explicit_policy.is_empty() and explicit_policy != BOSS:
			return _invalid("boss_policy_mismatch", explicit_policy)
		return _result(BOSS, "canonical_classification", false, false, legacy_respawn_seconds)

	if normalized_classification == "elite":
		if not explicit_policy.is_empty() and explicit_policy != ELITE:
			return _invalid("elite_policy_mismatch", explicit_policy)
		return _result(ELITE, "canonical_classification", false, false, legacy_respawn_seconds)

	if not explicit_policy.is_empty():
		if explicit_policy not in ORDINARY_POLICIES:
			return _invalid("ordinary_policy_mismatch", explicit_policy)
		return _result(
			explicit_policy,
			"explicit_spawn_policy",
			true,
			false,
			legacy_respawn_seconds
		)

	# Transitional migration only. This deliberately never emits historical
	# 60/180/etc. values: every result is one of the frozen five tiers.
	var legacy := float(legacy_respawn_seconds)
	var migrated_policy := BEGINNER_OUTDOOR
	if legacy > BEGINNER_OUTDOOR_SECONDS and legacy <= NORMAL_CAVE_SECONDS:
		migrated_policy = NORMAL_CAVE
	elif legacy > NORMAL_CAVE_SECONDS:
		migrated_policy = SPECIAL_NORMAL
	return _result(
		migrated_policy,
		"legacy_seconds_tier_migration",
		false,
		true,
		legacy_respawn_seconds
	)


static func _result(
	policy_id: String,
	source: String,
	explicit: bool,
	requires_authored_policy: bool,
	legacy_respawn_seconds: float
) -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"valid": true,
		"policy_id": policy_id,
		"seconds": seconds_for(policy_id),
		"source": source,
		"explicit": explicit,
		"requires_authored_policy": requires_authored_policy,
		"legacy_respawn_seconds": legacy_respawn_seconds,
		# MFC-4 retires historical random respawn variance.
		"random_seconds": 0.0,
	}


static func _invalid(reason: String, policy_id := "") -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"valid": false,
		"policy_id": policy_id,
		"seconds": 0.0,
		"source": "",
		"explicit": false,
		"requires_authored_policy": false,
		"legacy_respawn_seconds": -1.0,
		"random_seconds": 0.0,
		"reason": reason,
	}
