extends Node

const Policy := preload("res://scripts/monster_respawn_policy.gd")
const WorldState := preload("res://scripts/world_monster_respawn_state.gd")

var _checks := 0


func _ready() -> void:
	_test_five_authoritative_durations()
	_test_classification_lock()
	_test_special_normal_spawn_classification_lock()
	_test_ordinary_explicit_policy()
	_test_legacy_seconds_fold_into_allowed_tiers()
	_test_absolute_world_state()
	_test_unstable_runtime_slot_is_rejected()
	print("MONSTER_RESPAWN_POLICY_PASS checks=%d" % _checks)
	get_tree().quit(0)


func _test_five_authoritative_durations() -> void:
	var expected := {
		Policy.BEGINNER_OUTDOOR: 300.0,
		Policy.NORMAL_CAVE: 480.0,
		Policy.SPECIAL_NORMAL: 900.0,
		Policy.ELITE: 1800.0,
		Policy.BOSS: 3600.0,
	}
	assert(Policy.SECONDS_BY_POLICY.size() == 5)
	_checks += 1
	for policy_id: String in expected:
		assert(is_equal_approx(Policy.seconds_for(policy_id), float(expected[policy_id])))
		_checks += 1


func _test_classification_lock() -> void:
	var boss := Policy.resolve("", "boss", 180.0)
	assert(boss.valid and boss.policy_id == Policy.BOSS and boss.seconds == 3600.0)
	var elite := Policy.resolve("", "elite", 60.0)
	assert(elite.valid and elite.policy_id == Policy.ELITE and elite.seconds == 1800.0)
	assert(not Policy.resolve(Policy.NORMAL_CAVE, "boss", 480.0).valid)
	assert(not Policy.resolve(Policy.BOSS, "elite", 3600.0).valid)
	_checks += 4


func _test_special_normal_spawn_classification_lock() -> void:
	var elite_variant := Policy.resolve(
		Policy.SPECIAL_NORMAL,
		"elite",
		480.0,
		Policy.SPECIAL_NORMAL
	)
	assert(elite_variant.valid)
	assert(elite_variant.policy_id == Policy.SPECIAL_NORMAL)
	assert(elite_variant.seconds == 900.0)
	assert(elite_variant.source == "canonical_spawn_classification")
	assert(
		not Policy.resolve(
			Policy.NORMAL_CAVE,
			"elite",
			480.0,
			Policy.SPECIAL_NORMAL
		).valid
	)
	_checks += 5


func _test_ordinary_explicit_policy() -> void:
	for policy_id: String in Policy.ORDINARY_POLICIES:
		var resolved := Policy.resolve(policy_id, "normal", 60.0)
		assert(resolved.valid)
		assert(resolved.policy_id == policy_id)
		assert(resolved.explicit)
		assert(not resolved.requires_authored_policy)
		_checks += 4
	assert(not Policy.resolve(Policy.BOSS, "normal", 3600.0).valid)
	assert(not Policy.resolve(Policy.ELITE, "normal", 1800.0).valid)
	_checks += 2


func _test_legacy_seconds_fold_into_allowed_tiers() -> void:
	var old_60 := Policy.resolve("", "normal", 60.0)
	assert(
		old_60.valid
		and old_60.policy_id == Policy.BEGINNER_OUTDOOR
		and old_60.seconds == 300.0
		and old_60.requires_authored_policy
	)
	var old_400 := Policy.resolve("", "normal", 400.0)
	assert(old_400.policy_id == Policy.NORMAL_CAVE and old_400.seconds == 480.0)
	var old_600 := Policy.resolve("", "normal", 600.0)
	assert(old_600.policy_id == Policy.SPECIAL_NORMAL and old_600.seconds == 900.0)
	for legacy_value: float in [60.0, 180.0, 300.0, 400.0, 480.0, 600.0, 900.0, 3600.0]:
		var resolved := Policy.resolve("", "normal", legacy_value)
		assert(resolved.seconds in [300.0, 480.0, 900.0])
		assert(resolved.random_seconds == 0.0)
		_checks += 2
	_checks += 3


func _test_absolute_world_state() -> void:
	var state := WorldState.empty_snapshot()
	state = WorldState.with_deadline(
		state,
		401,
		"goblin_group:2",
		64,
		Policy.NORMAL_CAVE,
		1000.0
	)
	var entry := WorldState.entry_for(state, 401, "goblin_group:2")
	assert(not entry.is_empty())
	assert(entry.runtime_map_id == 401)
	assert(entry.spawn_slot_id == "goblin_group:2")
	assert(entry.monster_id == 64)
	assert(entry.policy_id == Policy.NORMAL_CAVE)
	assert(entry.respawn_at_unix == 1000.0)
	assert(WorldState.remaining_seconds(entry, 700.0) == 300.0)
	assert(WorldState.remaining_seconds(entry, 1000.0) == 0.0)
	assert(WorldState.remaining_seconds(entry, 1500.0) == 0.0)
	var normalized := WorldState.normalize_snapshot(state)
	assert(normalized.contract_id == WorldState.CONTRACT_ID)
	assert((normalized.entries as Dictionary).size() == 1)
	state = WorldState.without_slot(state, 401, "goblin_group:2")
	assert(WorldState.entry_for(state, 401, "goblin_group:2").is_empty())
	_checks += 11


func _test_unstable_runtime_slot_is_rejected() -> void:
	assert(WorldState.slot_key(401, "").is_empty())
	assert(WorldState.slot_key(-1, "group:0").is_empty())
	assert(WorldState.slot_key(401, "runtime:8:17").is_empty())
	var state := WorldState.with_deadline(
		WorldState.empty_snapshot(),
		401,
		"runtime:8:17",
		64,
		Policy.BEGINNER_OUTDOOR,
		1234.0
	)
	assert((state.entries as Dictionary).is_empty())
	_checks += 4
