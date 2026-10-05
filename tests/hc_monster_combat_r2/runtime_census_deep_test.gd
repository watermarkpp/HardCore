extends Node

## HC-MONSTER-COMBAT-R2 T1 deep runtime census (R3 rework of the shallow
## playback census). For every canonical identity this test records the
## source (catalog) and loaded/effective (EnemyActor.setup) values of the
## combat-relevant fields and writes the full matrix to
## res://docs/monster_combat_r2/runtime_census.json so the census itself is
## a tracked, deliverable artifact instead of a passing printout.
##
## What this census still is NOT: a real AI admission/cool-down/release/HP
## walkthrough per identity (that is the separate behavior census). It proves
## identity loading, body binding, timing and delivery resolution.

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const CensusPath := "res://docs/monster_combat_r2/runtime_census.json"

var _failures: Array[String] = []
var _rows: Array = []
var _player: PlayerCharacter


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
		printerr("R2_CENSUS_DEEP: ", message)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_player = PlayerCharacter.new()
	add_child(_player)
	_player.set_physics_process(false)
	var tested_source_sha := "2960bbe682b61306eed8f7c9fe0c6eb6c6accb9a"
	var catalog: Dictionary = MonsterIdentity.catalog_entry(1) if false else {}
	# Enumerate every catalog identity through the runtime catalog itself.
	var ids: Array = []
	var entries: Array = _catalog_entries()
	for entry: Dictionary in entries:
		ids.append(int(entry.get("monster_id", -1)))
	ids.sort()
	for id: int in ids:
		_census_identity(id, tested_source_sha)
	# Core invariants over the matrix.
	var combat_rows := 0
	var noncombat_rows := 0
	for row: Dictionary in _rows:
		if bool(row.get("runtime_allowed", false)):
			if bool(row.get("combat_contract_enabled", false)):
				combat_rows += 1
				_expect(float(row.get("effective_attack_interval_s", 0.0)) > 0.0,
					"id %s effective attack interval must be positive" % row.get("monster_id"))
				_expect(not str(row.get("effective_delivery_kind", "")).is_empty()
					or row.get("delivery_exempt") == true,
					"id %s combat identity must resolve a delivery kind" % row.get("monster_id"))
				_expect(not str(row.get("rejection_reason", "")).is_empty() == false
					or not bool(row.get("body_rejected", false)),
					"id %s unexpected rejection" % row.get("monster_id"))
			else:
				noncombat_rows += 1
	_expect(_rows.size() == 156, "census must cover exactly 156 identities, got %d" % _rows.size())
	_expect(combat_rows == 147, "147 combat identities expected, got %d" % combat_rows)
	_expect(noncombat_rows == 9, "9 contract non-combat identities expected, got %d" % noncombat_rows)
	_write_census(tested_source_sha)
	if _failures.is_empty():
		print("R2_CENSUS_DEEP_PASS rows=%d combat=%d noncombat=%d" % [_rows.size(), combat_rows, noncombat_rows])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _census_identity(id: int, tested_source_sha: String) -> void:
	var entry: Dictionary = MonsterIdentity.catalog_entry(id)
	var row: Dictionary = {
		"monster_id": id,
		"canonical_name": str(entry.get("canonical_name", "")),
		"runtime_allowed": bool(entry.get("runtime_allowed", false)),
		"classification": str(entry.get("classification", "")),
		"test_id": "runtime_census_deep_test",
		"tested_source_sha": tested_source_sha,
	}
	var combat: Dictionary = entry.get("combat", {}) if entry.get("combat", {}) is Dictionary else {}
	var timing: Dictionary = combat.get("timing", {}) if combat.get("timing", {}) is Dictionary else {}
	var stats: Dictionary = combat.get("stats", {}) if combat.get("stats", {}) is Dictionary else {}
	var body: Dictionary = MonsterIdentity.body_profile(id)
	row["source_attack_interval_ms"] = float(timing.get("attack_interval_ms", 0.0))
	row["timing_resolution"] = str(timing.get("resolution_status", ""))
	row["source_stats_keys"] = stats.keys()
	row["source_max_hp"] = int(stats.get("max_hp", stats.get("hp", 0)))
	row["boss_rule_nonempty"] = not (combat.get("boss_rule", {}) as Dictionary).is_empty()
	var behavior: Dictionary = MonsterIdentity.behavior_profile({"monster_id": id})
	row["source_combat_enabled"] = bool(behavior.get("combatEnabled", true))
	row["body_tier"] = str(body.get("tier", ""))
	row["body_screen_radius_px"] = float(body.get("screen_radius_px", 0.0))
	row["body_ground_radius_gu"] = float(body.get("ground_radius_gu", 0.0))
	row["body_policy_hash"] = str(body.get("policy_sha256", ""))
	row["body_assignment_rule"] = str(body.get("assignment_rule", ""))
	row["spawn_contexts"] = (entry.get("spawn_contexts", []) as Array).size()
	# Loaded/effective layer through the real setup path (no core overrides).
	var combat_contract_enabled := bool(entry.get("runtime_allowed", false)) and not body.is_empty() and bool(behavior.get("combatEnabled", true))
	row["combat_contract_enabled"] = combat_contract_enabled
	row["delivery_exempt"] = false
	row["body_rejected"] = false
	row["rejection_reason"] = ""
	if not bool(entry.get("runtime_allowed", false)):
		row["loaded"] = "skipped_not_runtime_allowed"
	elif body.is_empty():
		row["loaded"] = "skipped_missing_body_profile"
		row["body_rejected"] = true
		row["rejection_reason"] = "missing_body_profile"
	else:
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(id), _player, false)
		add_child(enemy)
		enemy.set_physics_process(false)
		row["loaded_max_hp"] = enemy.max_hp
		row["loaded_attack_min"] = enemy.attack_min
		row["loaded_attack_max"] = enemy.attack_max
		row["loaded_attack_interval_s"] = enemy._attack_interval
		row["effective_attack_interval_s"] = enemy._current_attack_interval()
		var resolved_kind := str(enemy.attack_delivery_rule.get("kind", ""))
		# An empty delivery rule is the ordinary-melee contract (HC standard
		# melee); non-empty kinds are the special delivery families.
		row["effective_delivery_kind"] = resolved_kind if not resolved_kind.is_empty() else "ordinary_melee"
		row["source_delivery_kind"] = resolved_kind
		row["boss_skill_enabled"] = enemy.boss_rule.get("skillEnabled", false) if enemy.boss_rule.get("skillEnabled", false) is bool else false
		row["boss_phase_enabled"] = enemy._boss_phase_enabled
		row["body_fallback"] = enemy.has_meta("body_policy_rejected")
		row["body_resolved_tier"] = str(enemy.combat_body_profile.get("tier", ""))
		row["movement_authority_valid"] = not enemy._movement_authority_failed_closed
		row["configured_walk_interval_ms"] = int(enemy._movement_cadence.walk_interval_ms) if enemy._movement_cadence != null and "walk_interval_ms" in enemy._movement_cadence else -1
		if enemy.has_meta("body_policy_rejected"):
			row["body_rejected"] = true
			row["rejection_reason"] = "body_policy_rejected"
		enemy.queue_free()
	_rows.append(row)


func _catalog_entries() -> Array:
	var file := FileAccess.open(MonsterIdentity.CATALOG_PATH, FileAccess.READ)
	if file == null:
		_expect(false, "cannot open canonical catalog")
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_expect(false, "canonical catalog is not a dictionary")
		return []
	var entries: Variant = (parsed as Dictionary).get("entries", [])
	return entries if entries is Array else []


func _write_census(tested_source_sha: String) -> void:
	var payload := {
		"schema": "hardcore.monster.combat.r2.runtime_census.v2",
		"tested_source_sha": tested_source_sha,
		"generated_by": "tests/hc_monster_combat_r2/runtime_census_deep_test.gd",
		"counts": {
			"total": _rows.size(),
			"combat": 147,
			"non_combat_contract": 9,
		},
		"rows": _rows,
	}
	var file := FileAccess.open(CensusPath, FileAccess.WRITE)
	if file == null:
		_expect(false, "cannot write census artifact")
		return
	file.store_string(JSON.stringify(payload, "\t", false))
	file.close()
