class_name MonsterMovementCadence
extends RefCounted

## M01A's deliberately small movement-event state machine.
##
## This object knows only an explicitly supplied M00R movement record and a
## monotonic millisecond clock.  It does not know an actor, a target, a map,
## a position, collision, pathfinding, attacks, or presentation.

const CONTRACT_ID := "monster.movement.cadence.m01a.v1"
const AUTHORITY_VIOLATION_CODE := "M01A_AUTHORITY_CONTRACT_VIOLATION"
const MIN_WALK_INTERVAL_MS := 200

const STATUS_LOCKED := "LOCKED"
const STATUS_ACCEPTED_CANDIDATE := "ACCEPTED_CANDIDATE"
const STATUS_COMPATIBILITY_HOLD := "COMPATIBILITY_HOLD"

const DECISION_GRANT := "GRANT"
const DECISION_WAIT := "WAIT"
const DECISION_COMPATIBILITY := "COMPATIBILITY"
const DECISION_IMMOBILE := "IMMOBILE"

const _ALLOWED_SOURCE_STATUSES: Array[String] = [
	STATUS_LOCKED,
	STATUS_ACCEPTED_CANDIDATE,
	STATUS_COMPATIBILITY_HOLD,
]
const _EXPECTED_AUTHORITIES := {
	STATUS_LOCKED: "A_LOCKED",
	STATUS_ACCEPTED_CANDIDATE: "B_CANDIDATE",
	STATUS_COMPATIBILITY_HOLD: "C_COMPATIBILITY",
}

var monster_id := -1
var source_status := ""
var movement_enabled := false
var runtime_allowed := false
var walk_interval_ms := 0
var walk_step := 0
var walk_wait_ms := 0

var walk_count := 0
var walk_wait_locked := false
var walk_tick_ms := 0
var walk_wait_tick_ms := 0
var last_evaluated_ms := -1
var configured := false
var failed_closed := true
var authority_violation := true
var last_error_code := AUTHORITY_VIOLATION_CODE
var last_error_reason := "not_configured"


func _init(authority_record: Variant = null, initial_now_ms: Variant = 0) -> void:
	if authority_record != null:
		configure(authority_record, initial_now_ms)


## Bind one complete runtime-authority record.  There is intentionally no
## name lookup and no default row.  The record shape is the M00R runtime
## authority shape: { monster_id, runtime_allowed, movement: { ... } }.
func configure(authority_record: Variant, initial_now_ms: Variant = 0) -> bool:
	_reset_state()

	var record_status := ""
	if authority_record is Dictionary:
		var raw_record: Dictionary = authority_record
		var raw_movement: Variant = raw_record.get("movement", null)
		if raw_movement is Dictionary:
			var movement_hint: Dictionary = raw_movement
			var status_hint: Variant = movement_hint.get("movement_source_status", "")
			if status_hint is String:
				record_status = status_hint
		_source_status_set(record_status)

	if not authority_record is Dictionary:
		return _reject("authority_record_must_be_dictionary")
	var record: Dictionary = authority_record
	if not record.has("monster_id"):
		return _reject("missing_monster_id")
	if not _is_strict_int(record.get("monster_id")):
		return _reject("monster_id_must_be_integer")
	var bound_monster_id := int(record.get("monster_id"))
	if bound_monster_id <= 0:
		return _reject("monster_id_must_be_positive")

	if not record.has("runtime_allowed"):
		return _reject("missing_runtime_allowed")
	if not _is_strict_bool(record.get("runtime_allowed")):
		return _reject("runtime_allowed_must_be_boolean")

	var raw_movement: Variant = record.get("movement", null)
	if not raw_movement is Dictionary:
		return _reject("missing_movement_authority_record")
	var movement: Dictionary = raw_movement
	var required_fields: Array[String] = [
		"movement_source_status",
		"movement_enabled",
		"walk_interval_ms",
		"walk_interval_status",
		"walk_interval_authority",
		"walk_step",
		"walk_step_status",
		"walk_step_authority",
		"walk_wait_ms",
		"walk_wait_status",
		"walk_wait_authority",
		"walk_wait_explicit_zero",
	]
	for field_name: String in required_fields:
		if not movement.has(field_name):
			return _reject("missing_movement_field:%s" % field_name)
	var raw_source: Variant = movement.get("source", null)
	if not raw_source is Dictionary:
		return _reject("missing_movement_source_binding")
	var source: Dictionary = raw_source
	if source.get("runtime_lookup", "") != "monster_id_only":
		return _reject("movement_source_must_be_id_only")
	var resolution: Variant = movement.get("m00r_resolution", "")
	if not resolution is String or str(resolution).is_empty():
		return _reject("missing_m00r_resolution")

	var raw_status: Variant = movement.get("movement_source_status")
	if not raw_status is String:
		return _reject("movement_source_status_must_be_string")
	_source_status_set(raw_status)
	if not _ALLOWED_SOURCE_STATUSES.has(source_status):
		return _reject("unknown_movement_source_status")

	if not _is_strict_bool(movement.get("movement_enabled")):
		return _reject("movement_enabled_must_be_boolean")
	if not _is_strict_int(movement.get("walk_interval_ms")):
		return _reject("walk_interval_ms_must_be_integer")
	if not _is_strict_int(movement.get("walk_step")):
		return _reject("walk_step_must_be_integer")
	if not _is_strict_int(movement.get("walk_wait_ms")):
		return _reject("walk_wait_ms_must_be_integer")
	if not _is_strict_bool(movement.get("walk_wait_explicit_zero")):
		return _reject("walk_wait_explicit_zero_must_be_boolean")

	var expected_authority: String = _EXPECTED_AUTHORITIES[source_status]
	var expected_binding_status := "SOURCE_ROW_MISSING" if source_status == STATUS_COMPATIBILITY_HOLD else "EXACT_SOURCE_ROW"
	if source.get("binding_status", "") != expected_binding_status:
		return _reject("invalid_movement_source_binding_status")
	if source_status == STATUS_COMPATIBILITY_HOLD and source.get("source_binding_kind", "") != "explicit_stable_id_to_base_row":
		return _reject("compatibility_row_must_have_explicit_stable_id_binding")
	for authority_field: String in [
		"walk_interval_authority",
		"walk_step_authority",
		"walk_wait_authority",
	]:
		if movement.get(authority_field) != expected_authority:
			return _reject("invalid_%s" % authority_field)
	for status_field: String in [
		"walk_interval_status",
		"walk_step_status",
		"walk_wait_status",
	]:
		if movement.get(status_field) != source_status:
			return _reject("invalid_%s" % status_field)

	var enabled := bool(movement.get("movement_enabled"))
	var interval_ms := int(movement.get("walk_interval_ms"))
	var step_count := int(movement.get("walk_step"))
	var wait_ms := int(movement.get("walk_wait_ms"))
	var wait_zero_explicit := bool(movement.get("walk_wait_explicit_zero"))
	if wait_zero_explicit != (wait_ms == 0):
		return _reject("walk_wait_zero_marker_mismatch")

	if source_status == STATUS_LOCKED:
		if enabled or interval_ms != 0 or step_count != 0 or wait_ms != 0:
			return _reject("locked_record_must_be_stationary")
	else:
		if not enabled:
			return _reject("active_record_must_enable_movement")
		if interval_ms < MIN_WALK_INTERVAL_MS:
			return _reject("walk_interval_below_minimum")
		if step_count < 1:
			return _reject("walk_step_must_be_positive_for_active_record")
		if wait_ms < 0:
			return _reject("walk_wait_must_not_be_negative")

	if not _is_strict_int(initial_now_ms):
		return _reject("initial_now_ms_must_be_integer")
	var initial_tick := int(initial_now_ms)
	if initial_tick < 0:
		return _reject("initial_now_ms_must_not_be_negative")

	monster_id = bound_monster_id
	runtime_allowed = bool(record.get("runtime_allowed"))
	movement_enabled = enabled
	walk_interval_ms = interval_ms
	walk_step = step_count
	walk_wait_ms = wait_ms
	walk_count = 0
	walk_wait_locked = false
	walk_tick_ms = initial_tick
	walk_wait_tick_ms = initial_tick
	last_evaluated_ms = initial_tick - 1
	configured = true
	failed_closed = false
	authority_violation = false
	last_error_code = ""
	last_error_reason = ""
	return true


## Evaluate at most one autonomous movement grant.  The caller supplies the
## monotonic clock; this method never reads wall time or engine time.
func evaluate(now_ms: Variant) -> Dictionary:
	if not configured or authority_violation:
		return _result(
			DECISION_IMMOBILE,
			DECISION_IMMOBILE,
			false,
			"authority_contract_violation"
		)
	if not _is_strict_int(now_ms):
		_enter_violation("now_ms_must_be_integer")
		return _result(DECISION_IMMOBILE, DECISION_IMMOBILE, false, "time_invalid")
	var now := int(now_ms)
	if now < 0:
		_enter_violation("now_ms_must_not_be_negative")
		return _result(DECISION_IMMOBILE, DECISION_IMMOBILE, false, "time_invalid")
	if now < last_evaluated_ms:
		_enter_violation("monotonic_clock_regressed")
		return _result(DECISION_IMMOBILE, DECISION_IMMOBILE, false, "time_regression")
	if now == last_evaluated_ms:
		return _result(DECISION_WAIT, DECISION_WAIT, false, "same_timestamp")
	last_evaluated_ms = now

	if not runtime_allowed or not movement_enabled or source_status == STATUS_LOCKED:
		return _result(DECISION_IMMOBILE, DECISION_IMMOBILE, false, "stationary_or_runtime_disabled")

	# ObjMon.Run order: unlock the wait first, using strict >.  A zero wait
	# therefore remains locked for the same millisecond as the grant.
	if walk_wait_locked:
		if now - walk_wait_tick_ms > walk_wait_ms:
			walk_wait_locked = false
		else:
			return _result(DECISION_WAIT, DECISION_WAIT, false, "walk_wait_locked")

	# ObjMon.Run uses strict > here as well.  Do not catch up multiple elapsed
	# intervals: the accepted event resets walk_tick_ms to this exact now_ms.
	if now - walk_tick_ms <= walk_interval_ms:
		return _result(DECISION_WAIT, DECISION_WAIT, false, "cadence_not_elapsed")

	walk_tick_ms = now
	walk_count += 1
	if walk_count > walk_step:
		# The wait lock is recorded after the increment, but this cadence event
		# remains a grant, exactly as in ObjMon.pas.
		walk_count = 0
		walk_wait_locked = true
		walk_wait_tick_ms = now
	return _result(DECISION_GRANT, DECISION_GRANT, true, "cadence_grant")


## Public authority-aware decision.  For a HOLD, this returns COMPATIBILITY;
## cadence_decision/granted still expose the normal grant/wait action.
func evaluate_decision(now_ms: Variant) -> String:
	var result := evaluate(now_ms)
	return str(result.get("decision", DECISION_IMMOBILE))


## Optional authority diagnostic for callers that need to distinguish a HOLD
## from an accepted row.  This never replaces the executable `decision` key.
func evaluate_authority_decision(now_ms: Variant) -> String:
	var result := evaluate(now_ms)
	return str(result.get("public_decision", DECISION_IMMOBILE))


## Action-only convenience for callers that only need to dispatch one event.
func evaluate_cadence(now_ms: Variant) -> String:
	var result := evaluate(now_ms)
	return str(result.get("cadence_decision", DECISION_IMMOBILE))


func decision(now_ms: Variant) -> String:
	return evaluate_decision(now_ms)


func should_grant(now_ms: Variant) -> bool:
	return bool(evaluate(now_ms).get("granted", false))


## Re-anchor the cadence without changing the bound authority record.  Reset
## itself is monotonic: a past or malformed timestamp fails closed.
func reset(now_ms: Variant) -> bool:
	if not configured or authority_violation:
		_enter_violation("reset_requires_valid_configuration")
		return false
	if not _is_strict_int(now_ms):
		_enter_violation("reset_now_ms_must_be_integer")
		return false
	var reset_tick := int(now_ms)
	if reset_tick < 0:
		_enter_violation("reset_now_ms_must_not_be_negative")
		return false
	if reset_tick < last_evaluated_ms:
		_enter_violation("reset_clock_regressed")
		return false
	walk_count = 0
	walk_wait_locked = false
	walk_tick_ms = reset_tick
	walk_wait_tick_ms = reset_tick
	last_evaluated_ms = reset_tick - 1
	last_error_code = ""
	last_error_reason = ""
	return true


func state_snapshot() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"monster_id": monster_id,
		"source_status": source_status,
		"movement_enabled": movement_enabled,
		"runtime_allowed": runtime_allowed,
		"walk_interval_ms": walk_interval_ms,
		"walk_step": walk_step,
		"walk_wait_ms": walk_wait_ms,
		"walk_count": walk_count,
		"walk_wait_locked": walk_wait_locked,
		"walk_tick_ms": walk_tick_ms,
		"walk_wait_tick_ms": walk_wait_tick_ms,
		"last_evaluated_ms": last_evaluated_ms,
		"configured": configured,
		"failed_closed": failed_closed,
		"authority_violation": authority_violation,
		"last_error_code": last_error_code,
		"last_error_reason": last_error_reason,
	}


func _result(
	action_decision: String,
	cadence_decision: String,
	granted: bool,
	reason: String
) -> Dictionary:
	var public_decision := action_decision
	if source_status == STATUS_COMPATIBILITY_HOLD and action_decision != DECISION_IMMOBILE:
		public_decision = DECISION_COMPATIBILITY
	return {
		"contract_id": CONTRACT_ID,
		"decision": action_decision,
		"public_decision": public_decision,
		"authority_decision": public_decision,
		"cadence_decision": cadence_decision,
		"granted": granted,
		"grant": granted,
		"source_status": source_status,
		"monster_id": monster_id,
		"walk_count": walk_count,
		"walk_wait_locked": walk_wait_locked,
		"walk_tick_ms": walk_tick_ms,
		"walk_wait_tick_ms": walk_wait_tick_ms,
		"walk_interval_ms": walk_interval_ms,
		"walk_step": walk_step,
		"walk_wait_ms": walk_wait_ms,
		"reason": reason,
		"error_code": last_error_code,
		"authority_contract_violation": authority_violation,
	}


func _source_status_set(value: String) -> void:
	source_status = value


func _reset_state() -> void:
	monster_id = -1
	source_status = ""
	movement_enabled = false
	runtime_allowed = false
	walk_interval_ms = 0
	walk_step = 0
	walk_wait_ms = 0
	walk_count = 0
	walk_wait_locked = false
	walk_tick_ms = 0
	walk_wait_tick_ms = 0
	last_evaluated_ms = -1
	configured = false
	failed_closed = true
	authority_violation = true
	last_error_code = AUTHORITY_VIOLATION_CODE
	last_error_reason = "not_configured"


func _reject(reason: String) -> bool:
	_enter_violation(reason)
	return false


func _enter_violation(reason: String) -> void:
	configured = false
	failed_closed = true
	authority_violation = true
	last_error_code = AUTHORITY_VIOLATION_CODE
	last_error_reason = reason


static func _is_strict_int(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	# JSON.parse_string represents numeric fields as floats in the Godot
	# runtime.  Preserve integer semantics while rejecting fractional values.
	if typeof(value) == TYPE_FLOAT:
		var numeric := float(value)
		return is_finite(numeric) and numeric == floor(numeric)
	return false


static func _is_strict_bool(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL
