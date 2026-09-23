class_name HCMonsterMeleePolicy
extends RefCounted

# This policy owns only the user-authorized override, never source statistics.
const PATH := "res://assets/data/monster_melee_ai_package_v3.json"
const CONTRACT_ID := "hardcore.monster.melee_ai.1p5gu.v3"
const START_GU := 1.5
const MELEE_DELIVERY_KINDS := ["", "special_melee", "gas_adjacent", "mixed_target_tile"]
const PREFERRED_GU := 1.5
const DELAY_TOLERANCE_GU := 0.25
const LANE_GU := 0.10
const GU := preload("res://scripts/ground_unit_space.gd")
const EPS := GU.EPSILON_GU
static var _loaded := false
static var _valid := false

static func valid() -> bool:
	if _loaded:
		return _valid
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("HC monster policy: missing " + PATH)
		return false
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not raw is Dictionary:
		push_error("HC monster policy: invalid JSON")
		return false
	var d: Dictionary = raw
	_valid = (
		int(d.get("schema_version", -1)) == 3
		and str(d.get("contract_id", "")) == CONTRACT_ID
		and str(d.get("authority", "")) == "user_gameplay_override"
	)
	var expected := {
		"attack_commit_reach_gu": START_GU,
		"preferred_melee_distance_gu": PREFERRED_GU,
		"existing_delayed_melee_tolerance_gu": DELAY_TOLERANCE_GU,
		"lane_half_width_gu": LANE_GU,
	}
	for key: String in expected:
		var value: Variant = d.get(key)
		if value is bool or not (value is float or value is int):
			_valid = false
		elif not is_finite(float(value)) or not is_equal_approx(float(value), float(expected[key])):
			_valid = false
	var rules: Variant = d.get("rules", {})
	if not rules is Dictionary:
		_valid = false
	else:
		for key: String in ["preserve_ranged_delivery_channels", "preserve_damage_channels_and_status", "do_not_read_player_skill_state"]:
			if not rules.get(key) is bool or not bool(rules.get(key)):
				_valid = false
		if rules.get("melee_delivery_kinds") != MELEE_DELIVERY_KINDS:
			_valid = false
	if not _valid:
		push_error("HC monster policy: schema or frozen numeric contract rejected")
	return _valid

static func within(a: Vector2, b: Vector2, reach: float) -> bool:
	return (
		a.is_finite() and b.is_finite() and is_finite(reach) and reach >= 0.0
		and a.distance_squared_to(b) <= (reach + EPS) * (reach + EPS)
	)

static func preferred(physical_contact_gu: float) -> float:
	return maxf(PREFERRED_GU, physical_contact_gu)

static func should_close(distance_gu: float, preferred_gu: float) -> bool:
	return is_finite(distance_gu) and distance_gu > preferred_gu + EPS

static func rank_before(a: Vector2, a_id: int, b: Vector2, b_id: int, target: Vector2) -> bool:
	# Strict ordering, NOT an epsilon comparator (which can produce cycles).
	var da := a.distance_squared_to(target)
	var db := b.distance_squared_to(target)
	return da < db or (da == db and a_id < b_id)

static func frontline_blocks(
	a: Vector2, target: Vector2, blocker: Vector2,
	ra: float, rt: float, rb: float, attacker_order: int, blocker_order: int,
	lane := LANE_GU,
) -> bool:
	if not a.is_finite() or not target.is_finite() or not blocker.is_finite():
		return true
	var d := a.distance_to(target)
	var overlaps_attacker := a.distance_squared_to(blocker) <= (ra + rb) * (ra + rb)
	if overlaps_attacker and not rank_before(blocker, blocker_order, a, attacker_order, target):
		return false
	if d <= EPS:
		return overlaps_attacker and rank_before(blocker, blocker_order, a, attacker_order, target)
	var u := (target - a) / d
	var along := (blocker - a).dot(u)
	# A same-origin tie is intentionally resolved by stable order above.
	if not overlaps_attacker and (along <= EPS or along >= d - EPS):
		return false
	if overlaps_attacker and (along < -EPS or along >= d + EPS):
		return false
	var s := a + u * maxf(0.0, ra)
	var e := target - u * maxf(0.0, rt)
	if (e - s).dot(u) <= EPS or overlaps_attacker:
		s = a
		e = target
	var q := Geometry2D.get_closest_point_to_segment(blocker, s, e)
	return q.distance_squared_to(blocker) <= pow(maxf(0.0, rb) + maxf(0.0, lane) + EPS, 2.0)

static func core_crossed(a: Vector2, b: Vector2, c: Vector2, ra: float, rb: float) -> bool:
	# Navigation-side early avoidance. Runtime physics remains the final hard
	# occupancy authority for monsters, players, and summons.
	var r := maxf(0.0, ra + rb)
	var before := a.distance_squared_to(c)
	var after := b.distance_squared_to(c)
	if before < r * r:
		# Endpoints alone would allow moving through the centre and out again.
		return (b - a).dot(a - c) < -EPS or after < before - EPS
	var q := Geometry2D.get_closest_point_to_segment(c, a, b)
	return q.distance_squared_to(c) < r * r - EPS
