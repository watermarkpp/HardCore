extends RefCounted

## Pure observation. Callers carry a frozen delivery identity explicitly.
## There is no ambient source stack and no control over a gameplay write.
const VERSION := "r4.explicit_identity.read_only.v1"
const MAX_ROWS := 8192
var recording_enabled := false
var events: Array = []
var terminal_events: Array = []
var admissions: Array = []
var deliveries: Array = []
var mutation_seq := 0
var overflowed := false
var dropped_rows := 0
var _row_count := 0

func reset() -> void:
	events.clear()
	terminal_events.clear()
	admissions.clear()
	deliveries.clear()
	mutation_seq = 0
	overflowed = false
	dropped_rows = 0
	_row_count = 0

func _reserve() -> bool:
	if _row_count >= MAX_ROWS:
		overflowed = true
		dropped_rows += 1
		return false
	_row_count += 1
	return true

func frozen_source(source: Variant) -> Dictionary:
	var result: Dictionary = source.duplicate(true) if source is Dictionary else {"source_identity": "UNKNOWN"}
	if result.is_empty():
		result["source_identity"] = "UNKNOWN"
	result.make_read_only()
	return result

func record_admission(source: Dictionary) -> void:
	if not recording_enabled or not _reserve():
		return
	admissions.append(frozen_source(source))

func record_delivery(source: Dictionary) -> void:
	if not recording_enabled or not _reserve():
		return
	deliveries.append(frozen_source(source))

func record_hp_mutation(victim: Object, resolved_damage: int, hp_before: int, hp_after: int, damage_type: String, source: Variant = null, mp_before := -1, mp_after := -1) -> void:
	if not recording_enabled or not _reserve():
		return
	mutation_seq += 1
	var row := {
		"mutation_id": mutation_seq, "source": frozen_source(source),
		"victim_instance_id": _access.canonical(victim).get_instance_id(),
		"victim_life": _access.read_property(victim, &"combat_epoch") if _access.is_kind(victim, &"player") else int(_access.invoke(victim, &"read_meta", ["hc_combat_life_epoch", 0])),
		"victim_generation": int(_access.invoke(victim, &"read_meta", ["zone_generation", -1])),
		"resolved_damage": resolved_damage, "hp_before": hp_before,
		"hp_after": hp_after, "actual_hp_delta": hp_before - hp_after,
		"damage_type": damage_type, "physics_tick": _clock.get_physics_frames(),
		"mp_before": mp_before, "mp_after": mp_after,
		"actual_mp_delta": mp_before - mp_after if mp_before >= 0 and mp_after >= 0 else -1,
	}
	row.make_read_only()
	events.append(row)

func record_terminal(source: Variant, kind: String, reason: String, hp_before := -1, hp_after := -1, mp_before := -1, mp_after := -1) -> void:
	if not recording_enabled or not _reserve():
		return
	var row := {
		"source": frozen_source(source), "terminal_kind": kind,
		"rejection_reason": reason, "physics_tick": _clock.get_physics_frames(),
		"hp_before": hp_before, "hp_after": hp_after,
		"mp_before": mp_before, "mp_after": mp_after,
		"actual_mp_delta": mp_before - mp_after if mp_before >= 0 and mp_after >= 0 else -1,
	}
	row.make_read_only()
	terminal_events.append(row)

var _owner := OS.get_thread_caller_id()
var _clock: RefCounted
var _access: RefCounted
func owner_thread_id() -> int: return _owner
func configure_owner(clock: RefCounted, access: RefCounted, enabled: bool) -> void:
	assert(_owner != OS.get_main_thread_id() and clock.owner_thread_id() == _owner and access.owner_thread_id() == _owner)
	_clock = clock
	_access = access
	recording_enabled = enabled
