extends RefCounted

## R4 T5-P2: read-only damage attribution ledger observer.
##
## Recording is enabled ONLY by explicit test switches. When disabled the
## observer costs a single boolean read at the few wired call sites - no
## per-frame queries, no per-hit dictionaries, no timers, no gameplay
## changes. Damage formulas, timing, RNG, saves and all existing contracts
## are untouched; the observer never mutates gameplay state.
##
## Identity comes from the REAL delivery call stack: the monster's damage
## dispatch pushes its concrete release context before calling into the
## victim, and pops right after the synchronous call returns, so every
## entry point explicitly covers its own scope and early returns inside
## the victim cannot leak identity. A debit observed with an empty stack
## is recorded as UNKNOWN - it never inherits "the most recent seq".

static var recording_enabled := false
## Fault injections for the counterexample suite. Only honored while
## recording_enabled; each flag applies to exactly one mutation.
static var suppress_next_hit := false
static var duplicate_next_hit := false

static var events: Array = []
static var terminal_events: Array = []
static var mutation_seq := 0
static var source_stack: Array = []


static func reset() -> void:
	events.clear()
	terminal_events.clear()
	mutation_seq = 0
	source_stack.clear()
	suppress_next_hit = false
	duplicate_next_hit = false


static func push_source(ctx: Dictionary) -> void:
	if not recording_enabled:
		return
	source_stack.append(ctx)


static func pop_source() -> void:
	if not recording_enabled or source_stack.is_empty():
		return
	source_stack.pop_back()


static func current_source() -> Dictionary:
	if not recording_enabled or source_stack.is_empty():
		return {"source_identity": "UNKNOWN"}
	return source_stack.back()


## Called at the victim's unique HP write site. Records the raw mutation
## with the resolved source identity, before/after values and the actual
## applied amount. Test switches may suppress (fault: lost damage) or
## duplicate (fault: repeated application) exactly this write.
static func record_hp_mutation(victim: Node, resolved_damage: int, hp_before: int, hp_after: int, damage_type: String) -> int:
	if not recording_enabled:
		return resolved_damage
	if suppress_next_hit:
		suppress_next_hit = false
		events.append({
			"mutation_id": -1,
			"suppressed": true,
			"source": current_source(),
			"victim_instance_id": victim.get_instance_id(),
			"resolved_damage": resolved_damage,
			"damage_type": damage_type,
			"physics_tick": Engine.get_physics_frames(),
		})
		return 0
	mutation_seq += 1
	var mutation_id := mutation_seq
	events.append({
		"mutation_id": mutation_id,
		"source": current_source(),
		"victim_instance_id": victim.get_instance_id(),
		"resolved_damage": resolved_damage,
		"hp_before": hp_before,
		"hp_after": hp_after,
		"actual_hp_delta": hp_before - hp_after,
		"damage_type": damage_type,
		"physics_tick": Engine.get_physics_frames(),
	})
	if duplicate_next_hit:
		duplicate_next_hit = false
		# A REAL second write: the HP write happens again with the SAME
		# source identity and a distinct mutation_id. The raw ledger keeps
		# both events; nothing is silently deduplicated.
		var second_after := maxi(0, hp_after - resolved_damage)
		mutation_seq += 1
		events.append({
			"mutation_id": mutation_seq,
			"source": current_source(),
			"victim_instance_id": victim.get_instance_id(),
			"resolved_damage": resolved_damage,
			"hp_before": hp_after,
			"hp_after": second_after,
			"actual_hp_delta": resolved_damage,
			"damage_type": damage_type,
			"physics_tick": Engine.get_physics_frames(),
			"duplicate_of": mutation_id,
		})
		victim.current_hp = second_after
	return resolved_damage


## Terminal results reported from the REAL miss / rejection / cancel /
## applied branches - never inferred from an observation window.
static func record_terminal(source: Dictionary, kind: String, reason: String) -> void:
	if not recording_enabled:
		return
	terminal_events.append({
		"source": source,
		"terminal_kind": kind,
		"rejection_reason": reason,
		"physics_tick": Engine.get_physics_frames(),
	})
