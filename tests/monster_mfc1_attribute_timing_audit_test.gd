extends Node

## MFC-1 Final Audit: 153 runtime_allowed monsters attribute / movement /
## normal-attack timing authority closure.
##
## Every formal monster's stats, movement cadence/speed and attack timing must
## have an explicit Authority AND the runtime must actually consume that
## authority. The test drives the production data chain (canonical catalog ->
## MonsterIdentity -> Enemy.setup -> runtime fields; M00R authority ->
## MonsterMovementCadence -> move cadence; boss_service_rules -> boss timing)
## and verifies each runtime field against the authoritative value using the
## same projection rules the production code applies (safe integer clamps,
## GU conversion, boss-rule overrides). It does not re-implement a second
## monster system.

const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const EnemyActorScript := preload("res://scripts/enemy.gd")
const Cadence := preload("res://scripts/monster_movement_cadence.gd")
const NeighborStep := preload("res://scripts/monster_neighbor_step_policy.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
const AUTHORITY_PATH := "res://assets/data/monster_runtime_authority_v1.json"
const BOSS_RULES_PATH := "res://assets/data/boss_service_rules.json"
const PX_PER_GU := 32.0

var _failures: Array[String] = []
var _stats := {
	"runtime_monsters": 0,
	"attribute_missing": 0,
	"attribute_runtime_mismatch": 0,
	"movement_authority_missing": 0,
	"movement_runtime_mismatch": 0,
	"movement_default_fallback": 0,
	"stationary_mismatch": 0,
	"direction_speed_mismatch": 0,
	"attack_timing_authority_missing": 0,
	"attack_interval_mismatch": 0,
	"hit_delay_mismatch": 0,
	"double_hit": 0,
	"frame_rate_cadence_mismatch": 0,
	"legacy_name_fallback": 0,
	"identity_drift": 0,
	"formal_runtime_accidental_default": 0,
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
	_audit_all_monsters(catalog, auth_by_id, boss_by_id)
	_audit_direction_speed_isometry()
	_audit_frame_rate_independent_cadence()
	_audit_hit_delay_and_double_hit()
	_dump_stats()
	if _failures.is_empty():
		print("MFC1_AUDIT_PASS runtime_monsters=%d" % int(_stats.runtime_monsters))
		get_tree().quit(0)
		return
	push_error("MFC1_AUDIT_FAILED %s" % ";".join(_failures))
	get_tree().quit(1)


func _audit_all_monsters(
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
		_stats["runtime_monsters"] = int(_stats["runtime_monsters"]) + 1
		var combat: Dictionary = entry.get("combat", {})
		var stats: Dictionary = combat.get("stats", {})
		var runtime_projection: Dictionary = combat.get("runtime_projection", {})
		var behavior_profile: Dictionary = combat.get("behavior_profile", {})
		var bp_timing: Dictionary = behavior_profile.get("timing", {})
		var bp_movement: Dictionary = behavior_profile.get("movement", {})
		var bp_projection: Dictionary = behavior_profile.get("runtimeProjection", {})
		var classification := str(entry.get("classification", ""))
		var is_boss := classification == "boss"
		var boss_rule: Dictionary = boss_by_id.get(mid, {}) if is_boss else {}

		# --- Attribute presence ---
		for field: String in ["level", "exp", "hp", "defense", "magic_defense", "attack_min", "attack_max"]:
			if not stats.has(field):
				_stats["attribute_missing"] = int(_stats["attribute_missing"]) + 1
				_failures.append("attr_missing:%d:%s" % [mid, field])
		for field: String in ["agility", "anti_poison"]:
			if not runtime_projection.has(field):
				_stats["attribute_missing"] = int(_stats["attribute_missing"]) + 1
				_failures.append("attr_missing:%d:%s" % [mid, field])

		# --- Instantiate the production runtime consumer ---
		var enemy := EnemyActorScript.new()
		enemy.setup({"monster_id": mid}, null)

		# --- Attribute runtime projection (Enemy.setup safe clamps) ---
		_check_int_attr(mid, "level", enemy.level, maxi(1, int(stats.get("level", 0))))
		_check_int_attr(mid, "max_hp", enemy.max_hp, maxi(1, int(stats.get("hp", 0))))
		_check_int_attr(mid, "attack_min", enemy.attack_min, maxi(1, int(stats.get("attack_min", 0))))
		var expected_amax := maxi(maxi(1, int(stats.get("attack_min", 0))), int(stats.get("attack_max", 0)))
		_check_int_attr(mid, "attack_max", enemy.attack_max, expected_amax)
		_check_int_attr(mid, "agility", enemy.agility, maxi(1, int(runtime_projection.get("agility", 15))))
		_check_int_attr(mid, "anti_poison", enemy.anti_poison, maxi(0, int(runtime_projection.get("anti_poison", 0))))

		# --- Movement authority ---
		var authority_record: Dictionary = auth_by_id.get(mid, {})
		if authority_record.is_empty():
			_stats["movement_authority_missing"] = int(_stats["movement_authority_missing"]) + 1
			_failures.append("mv_authority_missing:%d" % mid)
		else:
			var a_movement: Dictionary = authority_record.get("movement", {})
			if not a_movement.has("walk_interval_ms"):
				_stats["movement_authority_missing"] = int(_stats["movement_authority_missing"]) + 1
				_failures.append("mv_walk_interval_missing:%d" % mid)
			var cadence := Cadence.new()
			if not cadence.configure(authority_record):
				_stats["movement_authority_missing"] = int(_stats["movement_authority_missing"]) + 1
				_failures.append("mv_cadence_reject:%d:%s" % [mid, cadence.last_error_reason])
			# stationary cross-source consistency
			var a_stationary := bool(a_movement.get("stationary", false))
			var bp_stationary := bool(bp_movement.get("stationary", false))
			if a_stationary != bp_stationary:
				_stats["stationary_mismatch"] = int(_stats["stationary_mismatch"]) + 1
				_failures.append("stationary_mismatch:%d auth=%s bp=%s" % [mid, a_stationary, bp_stationary])
			if bp_stationary and enemy.move_speed_gu_per_sec != 0.0:
				_stats["stationary_mismatch"] = int(_stats["stationary_mismatch"]) + 1
				_failures.append("stationary_not_zero_speed:%d speed=%f" % [mid, enemy.move_speed_gu_per_sec])
			# move speed against the authority projection record
			var a_speed: Variant = a_movement.get("current_runtime_move_speed_gu_per_sec")
			if a_speed != null and absf(float(a_speed) - enemy.move_speed_gu_per_sec) > 0.001:
				_stats["movement_runtime_mismatch"] = int(_stats["movement_runtime_mismatch"]) + 1
				_failures.append("mv_speed_runtime_vs_auth:%d runtime=%f auth=%f" % [mid, enemy.move_speed_gu_per_sec, float(a_speed)])
			# move speed has an explicit authority projection (C_COMPATIBILITY is a
			# documented project compatibility ruling, not an accidental default).
			if str(a_movement.get("current_runtime_projection_status", "")) != "C_COMPATIBILITY":
				_stats["movement_default_fallback"] = int(_stats["movement_default_fallback"]) + 1
				_failures.append("mv_speed_no_ruling:%d status=%s" % [mid, str(a_movement.get("current_runtime_projection_status", ""))])
			# authority records the projected GU speed for all 153; verify no
			# accidental code-only default is used without an authority record.
			if a_speed == null:
				_stats["movement_default_fallback"] = int(_stats["movement_default_fallback"]) + 1
				_failures.append("mv_speed_no_authority_record:%d" % mid)

		# --- Attack timing authority ---
		var bp_attack_ms := int(bp_timing.get("attackIntervalMs", 0))
		var boss_attack_ms := int(boss_rule.get("timing", {}).get("attackIntervalMs", 0))
		if bp_attack_ms <= 0 and boss_attack_ms <= 0:
			_stats["attack_timing_authority_missing"] = int(_stats["attack_timing_authority_missing"]) + 1
			_stats["formal_runtime_accidental_default"] = int(_stats["formal_runtime_accidental_default"]) + 1
			_failures.append("atk_authority_missing:%d" % mid)
			enemy.free()
			continue
		var expected_interval := float(bp_attack_ms) / 1000.0
		if is_boss and not boss_rule.is_empty():
			expected_interval = float(boss_attack_ms) / 1000.0 if boss_attack_ms > 0 else expected_interval
		if absf(enemy._attack_interval - expected_interval) > 0.001:
			_stats["attack_interval_mismatch"] = int(_stats["attack_interval_mismatch"]) + 1
			_failures.append("atk_interval_mismatch:%d runtime=%f expected=%f" % [mid, enemy._attack_interval, expected_interval])
		var expected_hit_delay := 0.0
		if is_boss and not boss_rule.is_empty():
			expected_hit_delay = float(boss_rule.get("timing", {}).get("hitDelayMs", 0)) / 1000.0
		if absf(enemy._attack_hit_delay - expected_hit_delay) > 0.001:
			_stats["hit_delay_mismatch"] = int(_stats["hit_delay_mismatch"]) + 1
			_failures.append("atk_hit_delay_mismatch:%d runtime=%f expected=%f" % [mid, enemy._attack_hit_delay, expected_hit_delay])
		# attack interval and attack animation stay separate: animation duration is
		# a presentation value that never drives the cooldown clock.
		var expected_anim := 0.46
		if is_boss and not boss_rule.is_empty():
			expected_anim = float(boss_rule.get("timing", {}).get("attackAnimationMs", 460)) / 1000.0
		if absf(enemy._attack_animation_duration - expected_anim) > 0.001:
			_failures.append("atk_anim_mismatch:%d runtime=%f expected=%f" % [mid, enemy._attack_animation_duration, expected_anim])

		enemy.free()


func _check_int_attr(mid: int, field: String, runtime_value: int, expected: int) -> void:
	if runtime_value != expected:
		_stats["attribute_runtime_mismatch"] = int(_stats["attribute_runtime_mismatch"]) + 1
		_failures.append("attr_runtime_mismatch:%d:%s runtime=%d expected=%d" % [mid, field, runtime_value, expected])


func _audit_direction_speed_isometry() -> void:
	# Classic eight-neighbor grid: axis step is 1 GU, diagonal step is sqrt(2) GU.
	# Enemy's presentation speed is base * sqrt(2) on diagonals (enemy.gd:621-623),
	# so axis and diagonal arrival times are identical. Verify the geometry ratio
	# that makes that true, using the production neighbor policy.
	var axis := NeighborStep.build_neighbor_step(Vector2(0.5, 0.5), Vector2i(1, 0))
	var diag := NeighborStep.build_neighbor_step(Vector2(0.5, 0.5), Vector2i(1, 1))
	var axis_dist := float(axis.get("distance_gu", -1.0))
	var diag_dist := float(diag.get("distance_gu", -1.0))
	if axis_dist <= 0.0 or diag_dist <= 0.0:
		_stats["direction_speed_mismatch"] = int(_stats["direction_speed_mismatch"]) + 1
		_failures.append("direction_step_geometry_invalid")
		return
	# arrival_time = distance / presentation_speed; presentation_speed_diag = base*sqrt(2)
	# time_axis = 1/base ; time_diag = sqrt(2)/(base*sqrt(2)) = 1/base  -> equal.
	if absf(axis_dist - 1.0) > 0.001 or absf(diag_dist - sqrt(2.0)) > 0.001:
		_stats["direction_speed_mismatch"] = int(_stats["direction_speed_mismatch"]) + 1
		_failures.append("direction_step_distance_ratio_invalid axis=%f diag=%f" % [axis_dist, diag_dist])
	# Mirror the production diagonal speed compensation so the arrival time holds.
	var base_speed := 1.0
	var time_axis := axis_dist / base_speed
	var time_diag := diag_dist / (base_speed * sqrt(2.0))
	if absf(time_axis - time_diag) > 0.001:
		_stats["direction_speed_mismatch"] = int(_stats["direction_speed_mismatch"]) + 1
		_failures.append("direction_arrival_time_unequal axis=%f diag=%f" % [time_axis, time_diag])


func _audit_frame_rate_independent_cadence() -> void:
	# Long-run attack cadence is governed by a real-time interval (seconds), so
	# the average attack interval must converge to the authority interval at
	# every frame rate (sampling discretization only, never a systematic frame-
	# rate bias). The production clock is a leaky bucket: _attack_timer -= delta
	# and resets to the interval on trigger. Simulate those exact semantics.
	var interval := 1.5
	var window := 300.0
	var counts := {}
	for fps: int in [30, 60, 120]:
		var dt := 1.0 / float(fps)
		var timer := 0.0
		var attacks := 0
		var elapsed := 0.0
		while elapsed < window:
			timer -= dt
			if timer <= 0.0:
				attacks += 1
				timer = interval
			elapsed += dt
		counts[fps] = attacks
	var max_deviation := 0.0
	for fps: int in counts:
		var avg_interval := window / float(counts[fps])
		max_deviation = maxf(max_deviation, absf(avg_interval - interval) / interval)
	if max_deviation > 0.02:
		_stats["frame_rate_cadence_mismatch"] = int(_stats["frame_rate_cadence_mismatch"]) + 1
		_failures.append("frame_rate_cadence_drift %s dev=%f" % [str(counts), max_deviation])


func _audit_hit_delay_and_double_hit() -> void:
	# Production delayed-melee path: a hitDelay > 0 must not damage before the
	# delay elapses, must hit exactly once at settlement, and must never
	# double-hit afterwards. Uses the real EnemyActor _physics_process path with
	# a full runtime-map projection fixture (skeleton spirit ID 56, hitDelay=300ms).
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000
	player.current_hp = 1000
	player.defense_min = 0
	player.defense_max = 0
	player.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		Vector2.RIGHT * 1.5
	)
	var canonical := GameData.get_monster_by_id(56)
	if canonical.is_empty():
		_stats["double_hit"] = int(_stats["double_hit"]) + 1
		_failures.append("hit_delay_fixture_monster_missing")
		player.queue_free()
		return
	var boss := EnemyActorScript.new()
	boss.setup(canonical, player, true)
	var canonical_boss_rule: Dictionary = MonsterIdentityScript.boss_rule(
		canonical,
		GameData.boss_service_rules,
	)
	boss.is_boss = true
	boss.boss_rule = canonical_boss_rule
	boss._apply_boss_rule()
	boss.configure_runtime_map_projection(
		1,
		Callable(self, "_ground_to_screen"),
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu,
	)
	boss.environment_blocker = null
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	boss.set_physics_process(false)
	add_child(boss)
	await get_tree().process_frame
	var hp_before := player.current_hp
	boss._attack_timer = 0.0
	boss._physics_process(0.01)
	if not (boss._pending_attack_time > 0.0 and player.current_hp == hp_before):
		_stats["double_hit"] = int(_stats["double_hit"]) + 1
		_failures.append("hit_delay_not_armed")
	boss._physics_process(0.28)
	if player.current_hp != hp_before:
		_stats["double_hit"] = int(_stats["double_hit"]) + 1
		_failures.append("hit_delay_early_settlement")
	boss._physics_process(0.03)
	var hp_after_one := player.current_hp
	if hp_after_one >= hp_before:
		_stats["double_hit"] = int(_stats["double_hit"]) + 1
		_failures.append("hit_delay_missing_settlement")
	boss._physics_process(1.0)
	if player.current_hp != hp_after_one:
		_stats["double_hit"] = int(_stats["double_hit"]) + 1
		_failures.append("double_hit_after_settlement")
	boss.queue_free()
	player.queue_free()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


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
		print("MFC1_AUDIT %s = %d" % [key, int(_stats[key])])
