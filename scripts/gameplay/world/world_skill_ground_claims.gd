extends RefCounted
const FIRE_WALL_SKILL_ID := "wizard.fire_wall"
const RUNTIME_TICK_CLAIM_RETENTION_MSEC := 60000
var _runtime_tick_claims: Dictionary = {}
var _audit_next_claim_gc_msec := 0
var _actors: RefCounted
var _clock: RefCounted

func _init(actors: RefCounted, clock: RefCounted) -> void:
	_actors = actors
	_clock = clock

func claim_fire_wall_controller_tick(
	claim_owner: Object,
	source: Object,
	skill_id_value: String,
	tick_interval_value: float,
	target: Object
) -> bool:
	if skill_id_value != FIRE_WALL_SKILL_ID or not _actors.is_runtime_present(source):
		return true
	if not _actors.is_runtime_present(target):
		return false
	var now_msec = _clock.now_msec()
	var claim_key = "%d:%s:%d" % [
		_actors.runtime_actor_id(source),
		skill_id_value,
		_actors.runtime_actor_id(target),
	]
	var current_claim: Dictionary = _runtime_tick_claims.get(claim_key, {})
	var owner_effect_id = int(current_claim.get("owner_effect_id", 0))
	var next_allowed_msec = int(current_claim.get("next_allowed_msec", -1))
	if (
		owner_effect_id != _actors.runtime_actor_id(claim_owner)
		and now_msec < next_allowed_msec
	):
		return false
	_runtime_tick_claims[claim_key] = {
		"owner_effect_id": _actors.runtime_actor_id(claim_owner),
		"next_allowed_msec": now_msec + roundi(tick_interval_value * 1000.0),
	}
	_cleanup_runtime_tick_claims(now_msec)
	return true

func reset_runtime_tick_claims_for_tests() -> void:
	_runtime_tick_claims.clear()
	_audit_next_claim_gc_msec = 0

func _cleanup_runtime_tick_claims(now_msec: int) -> void:
	# GC cadence is independent of damage cadence; claim keys/windows and
	# same-owner refresh semantics are intentionally unchanged.
	if _runtime_tick_claims.size() < 256:
		return
	if now_msec < _audit_next_claim_gc_msec:
		return
	_audit_next_claim_gc_msec = now_msec + 1000
	for raw_key: Variant in _runtime_tick_claims.keys():
		var claim: Dictionary = _runtime_tick_claims.get(raw_key, {})
		if int(claim.get("next_allowed_msec", 0)) + RUNTIME_TICK_CLAIM_RETENTION_MSEC < now_msec:
			_runtime_tick_claims.erase(raw_key)
