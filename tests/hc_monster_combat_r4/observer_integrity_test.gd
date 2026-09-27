extends Node

const Observer := preload("res://scripts/damage_ledger_observer.gd")
const Verifier := preload("res://tests/hc_monster_combat_r4/damage_attribution_verifier.gd")

class Victim extends Node2D:
	var current_hp := 100
	var combat_epoch := 2

var failures: Array = []

func _ready() -> void:
	Observer.recording_enabled = true
	var victim := Victim.new()
	add_child(victim)
	var source := {
		"source_instance_id": 12, "source_life": 3,
		"parent_action_id": 4, "release_id": "r1", "child_effect_id": "hit",
		"victim_instance_id": victim.get_instance_id(), "victim_life": 2,
		"runtime_map_id": 6, "zone_generation": 7,
	}
	Observer.reset()
	# The observer may record an already committed debit; it may never write HP.
	victim.set_meta("hc_combat_life_epoch", 2)
	Observer.record_hp_mutation(victim, 7, 100, 93, "physical", source)
	_check(victim.current_hp == 100, "observer_wrote_hp")
	# Recorded rows must not alias mutable source dictionaries.
	source["release_id"] = "changed_after_recording"
	_check(str(Observer.events[0].source.get("release_id", "")) != "changed_after_recording", "source_alias_mutates_evidence")
	var start := {
		"source_instance_id": 12, "source_life": 3, "parent_action_id": 4,
		"release_id": "r1", "target_id": victim.get_instance_id(), "target_life": 2, "target_generation": -1,
		"map_id": 6, "generation": 7,
	}
	var foreign := {"source": {"source_instance_id": 99, "release_id": "r1"}, "terminal_kind": "miss"}
	var audit := Verifier.audit_releases([start], [], [foreign], 12)
	_check(not audit.failures.is_empty(), "foreign_terminal_accepted")
	var forged_source := source.duplicate(true)
	forged_source.release_id = "r1"
	forged_source.zone_generation = 999
	var forged := {"source": forged_source, "mutation_id": 1, "hp_before": 100, "hp_after": 93, "actual_hp_delta": 7}
	audit = Verifier.audit_releases([start], [forged], [], 12)
	_check(not audit.failures.is_empty(), "wrong_generation_accepted")
	# Full identity positive control and legal multi-target relation.
	var child := source.duplicate(true)
	child.release_id = "r1"
	child.admission_release_id = "r1"
	child.victim_generation = -1
	var write := {"source": child, "mutation_id": 1, "victim_instance_id": victim.get_instance_id(), "victim_life": 2, "victim_generation": -1, "resolved_damage": 7, "hp_before": 100, "hp_after": 93, "actual_hp_delta": 7}
	audit = Verifier.audit_releases([start], [write], [], 12, [child])
	_check(audit.failures.is_empty(), "valid_identity_rejected")
	# Omission on both sides must not turn default sentinel values into a
	# complete parent identity. This preserves the intact positive above.
	for fields: Array in [["source_life", "source_life"], ["parent_action_id", "parent_action_id"], ["map_id", "runtime_map_id"], ["generation", "zone_generation"]]:
		var incomplete_start := start.duplicate(true)
		incomplete_start.erase(fields[0])
		var incomplete_child := child.duplicate(true)
		incomplete_child[fields[1]] = -1
		var incomplete_write := write.duplicate(true)
		incomplete_write.source = incomplete_child
		audit = Verifier.audit_releases([incomplete_start], [incomplete_write], [], 12, [incomplete_child])
		_check(not audit.failures.is_empty(), "incomplete_parent_identity_accepted_" + str(fields[0]))
	var unknown_child := child.duplicate(true)
	unknown_child.source_identity = "UNKNOWN"
	var unknown_write := write.duplicate(true)
	unknown_write.source = unknown_child
	audit = Verifier.audit_releases([start], [unknown_write], [], 12, [unknown_child])
	_check(not audit.failures.is_empty(), "explicit_unknown_completed_owned_release")
	var fractional_child := child.duplicate(true)
	fractional_child.victim_life = 2.5
	var fractional_write := write.duplicate(true)
	fractional_write.source = fractional_child
	fractional_write.victim_life = 2.5
	audit = Verifier.audit_releases([start], [fractional_write], [], 12, [fractional_child])
	_check(not audit.failures.is_empty(), "fractional_target_life_accepted")
	var rejection_source := child.duplicate(true)
	rejection_source.child_effect_id = "admission"
	var rejection := {"source": rejection_source, "terminal_kind": "rejected", "rejection_reason": "target_gone"}
	audit = Verifier.audit_releases([start], [], [rejection], 12)
	_check(audit.failures.is_empty(), "valid_admission_rejection_rejected")
	var wrong_rejection := rejection.duplicate(true)
	wrong_rejection.source.victim_generation = 999
	audit = Verifier.audit_releases([start], [], [wrong_rejection], 12)
	_check(not audit.failures.is_empty(), "admission_rejection_wrong_target_generation_accepted")
	var second := child.duplicate(true)
	second.victim_instance_id = 12345
	second.child_effect_id = "hit-second-target"
	var second_write := write.duplicate(true)
	second_write.source = second
	second_write.victim_instance_id = 12345
	audit = Verifier.audit_releases([start], [write, second_write], [], 12, [child, second])
	_check(audit.failures.is_empty(), "legal_multi_target_rejected")
	for field: String in ["source_instance_id", "source_life", "parent_action_id", "victim_instance_id", "victim_life", "victim_generation", "zone_generation", "runtime_map_id", "admission_release_id"]:
		var bad := write.duplicate(true)
		bad.source[field] = "forged" if field == "admission_release_id" else 999999
		audit = Verifier.audit_releases([start], [bad], [], 12, [child])
		_check(not audit.failures.is_empty(), "identity_mismatch_accepted_" + field)
	audit = Verifier.audit_releases([start], [write, write], [], 12, [child])
	_check(not audit.failures.is_empty(), "duplicate_write_accepted")
	audit = Verifier.audit_releases([start], [write], [], 12, [child], true)
	_check(not audit.failures.is_empty(), "overflow_accepted")
	# Same seed and actual damage calls with the observer off/on: HP and RNG
	# must stay identical. No synthetic observation replaces gameplay here.
	var outcomes: Array = []
	for enabled: bool in [false, true]:
		PlayerState.test_mode = true
		PlayerState.reset_progress()
		var actual := PlayerCharacter.new()
		add_child(actual)
		actual.set_physics_process(false)
		actual.max_hp = 100000
		actual.current_hp = 100000
		actual.defense_min = 1
		actual.defense_max = 8
		actual._rng.seed = 8765
		Observer.recording_enabled = enabled
		Observer.reset()
		for i in range(100):
			actual.take_damage(31, false)
		outcomes.append({"hp": actual.current_hp, "rng": actual._rng.state})
		_check(Observer.events.size() == (100 if enabled else 0), "off_on_record_count")
		actual.free()
	_check(outcomes[0] == outcomes[1], "observer_changed_gameplay_or_rng")
	Observer.recording_enabled = true
	Observer.reset()
	for i in range(9000):
		Observer.record_hp_mutation(victim, 1, 100, 99, "physical")
	_check(Observer.events.size() < 9000, "unbounded_event_buffer")
	Observer.recording_enabled = false
	Observer.reset()
	victim.free()
	if failures.is_empty():
		print("R4_OBSERVER_INTEGRITY_PASS")
		get_tree().quit(0)
	else:
		printerr("R4_OBSERVER_INTEGRITY_FAIL: ", failures)
		get_tree().quit(1)

func _check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)
