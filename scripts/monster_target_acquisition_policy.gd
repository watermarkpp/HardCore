class_name MonsterTargetAcquisitionPolicy
extends RefCounted


## M02A owns first active target acquisition only. Pursuit, focus, disengage,
## threat, and return-to-spawn remain EnemyActor responsibilities.

const CONTRACT_ID := "monster.target.acquisition.m02a.v1"
const RUNNABLE_ACQUISITION_STATUSES := ["CANDIDATE", "LOCKED"]

var monster_id := -1
var view_range_cells := 0
var configured := false
var failed_closed := true
var rejection_reason := "not_configured"


func configure(authority_record: Variant, expected_monster_id: int) -> bool:
	_reset()
	if expected_monster_id <= 0:
		return _reject("expected_monster_id_invalid")
	if not authority_record is Dictionary:
		return _reject("authority_record_must_be_dictionary")
	var record: Dictionary = authority_record
	if not _is_strict_int(record.get("monster_id", null)):
		return _reject("monster_id_must_be_integer")
	if int(record.get("monster_id")) != expected_monster_id:
		return _reject("monster_id_mismatch")
	var raw_targeting: Variant = record.get("targeting", null)
	if not raw_targeting is Dictionary:
		return _reject("targeting_record_missing")
	var targeting: Dictionary = raw_targeting
	var acquisition_status := str(targeting.get("acquisition_status", "")).strip_edges()
	if acquisition_status not in RUNNABLE_ACQUISITION_STATUSES:
		return _reject("acquisition_status_not_runnable:%s" % acquisition_status)
	if not _is_strict_int(targeting.get("view_range_cells", null)):
		return _reject("view_range_cells_must_be_integer")
	var configured_view_range := int(targeting.get("view_range_cells"))
	if configured_view_range <= 0:
		return _reject("view_range_cells_must_be_positive")
	monster_id = expected_monster_id
	view_range_cells = configured_view_range
	configured = true
	failed_closed = false
	rejection_reason = ""
	return true


func contains_ground_delta_gu(delta_ground_gu: Vector2) -> bool:
	if not configured or failed_closed or not delta_ground_gu.is_finite():
		return false
	var view := float(view_range_cells)
	return absf(delta_ground_gu.x) <= view and absf(delta_ground_gu.y) <= view


func state_snapshot() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"monster_id": monster_id,
		"view_range_cells": view_range_cells,
		"configured": configured,
		"failed_closed": failed_closed,
		"rejection_reason": rejection_reason,
	}


func _reset() -> void:
	monster_id = -1
	view_range_cells = 0
	configured = false
	failed_closed = true
	rejection_reason = "not_configured"


func _reject(reason: String) -> bool:
	rejection_reason = reason
	return false


static func _is_strict_int(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	# JSON.parse_string exposes JSON numbers as floats. Accept only values that
	# preserve exact integer semantics; fractional and non-finite values fail closed.
	if typeof(value) == TYPE_FLOAT:
		var numeric := float(value)
		return is_finite(numeric) and numeric == floor(numeric)
	return false
