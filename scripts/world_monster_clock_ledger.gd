class_name WorldMonsterClockLedger
extends RefCounted

const WorldState := preload("res://scripts/world_monster_respawn_state.gd")
const Delta := preload("res://scripts/world_clock_delta.gd")

const SNAPSHOT_CONTRACT_ID := "monster.world_clock.snapshot.v1"
const EVENT_CONTRACT_ID := "monster.world_clock.death_event.v1"
const DELTA_EVENT_CONTRACT_ID := "monster.world_clock.death_event.v2"


static func snapshot_document(profile_id: String, sequence: int, state: Dictionary, generation := "") -> Dictionary:
	return {
		"contract_id": SNAPSHOT_CONTRACT_ID,
		"profile_id": profile_id,
		"sequence": sequence,
		"world_clock_generation": generation,
		"world_state": state.duplicate(true),
	}


static func death_event_document(
	profile_id: String,
	sequence: int,
	level: int,
	experience: int,
	quest_states: Dictionary,
	world_state: Dictionary,
	generation := "",
) -> Dictionary:
	return {
		"contract_id": EVENT_CONTRACT_ID,
		"world_clock_generation": generation,
		"profile_id": profile_id,
		"sequence": sequence,
		"level": level,
		"experience": experience,
		"quest_states": quest_states.duplicate(true),
		"world_state": world_state.duplicate(true),
	}


static func delta_death_event_document(
	profile_id: String, sequence: int, level: int, experience: int,
	quest_states: Dictionary, changes: Dictionary, generation := "",
) -> Dictionary:
	return {
		"contract_id": DELTA_EVENT_CONTRACT_ID,
		"world_clock_generation": generation,
		"profile_id": profile_id, "sequence": sequence,
		"level": level, "experience": experience,
		# Non-death quest transactions may share the same journal sequence.
		# Keep the reward snapshot so backup replay cannot resurrect old quests.
		"quest_states": quest_states.duplicate(true),
		"world_delta": Delta.patch_from_changes(changes),
	}


static func valid_world_state(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var state: Dictionary = value
	if (
		str(state.get("contract_id", "")) != WorldState.CONTRACT_ID
		or int(state.get("schema_version", -1)) != WorldState.SCHEMA_VERSION
		or not state.get("entries", null) is Dictionary
	):
		return false
	var raw_entries: Dictionary = state["entries"]
	var normalized: Dictionary = WorldState.normalize_snapshot(state)
	var clean_entries: Dictionary = normalized["entries"]
	if raw_entries.size() != clean_entries.size():
		return false
	for key: Variant in raw_entries:
		if not clean_entries.has(key):
			return false
	return true


static func valid_generation(value: Variant) -> bool:
	if not value is String:
		return false
	if value.is_empty():
		return true # Pre-generation journals remain in their original namespace.
	if value.length() != 32:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func valid_snapshot(value: Variant, expected_profile_id: String, generation := "") -> bool:
	if not value is Dictionary:
		return false
	var document: Dictionary = value
	return (
		str(document.get("contract_id", "")) == SNAPSHOT_CONTRACT_ID
		and str(document.get("profile_id", "")) == expected_profile_id
		and valid_generation(generation)
		and document.get("world_clock_generation", "") == generation
		and _nonnegative_sequence(document.get("sequence", null))
		and valid_world_state(document.get("world_state", null))
	)


static func valid_death_event(value: Variant, expected_profile_id: String, expected_sequence: int, generation := "") -> bool:
	if not value is Dictionary:
		return false
	var document: Dictionary = value
	return (
		str(document.get("contract_id", "")) in [EVENT_CONTRACT_ID, DELTA_EVENT_CONTRACT_ID]
		and str(document.get("profile_id", "")) == expected_profile_id
		and valid_generation(generation)
		and document.get("world_clock_generation", "") == generation
		and _nonnegative_sequence(document.get("sequence", null))
		and int(document.get("sequence", -1)) == expected_sequence
		and _nonnegative_sequence(document.get("level", null))
		and int(document.get("level", 0)) > 0
		and _nonnegative_sequence(document.get("experience", null))
		and document.get("quest_states", null) is Dictionary
		and (
			valid_world_state(document.get("world_state", null))
			if document.get("contract_id", "") == EVENT_CONTRACT_ID
			else Delta.valid_world_patch(document.get("world_delta", null))
		)
	)


static func replay(
	profile_document: Dictionary,
	world_snapshot: Dictionary,
	events: Array,
) -> Dictionary:
	var profile_id := str(profile_document.get("profile_id", ""))
	var generation: Variant = profile_document.get("world_clock_generation", "")
	if not valid_generation(generation):
		return {"ok": false, "reason": "invalid_world_clock_generation"}
	var profile_sequence_value: Variant = profile_document.get("death_event_sequence", 0)
	if profile_id.is_empty() or not _nonnegative_sequence(profile_sequence_value):
		return {"ok": false, "reason": "invalid_profile_sequence"}
	var profile_sequence := int(profile_sequence_value)
	var world_sequence := 0
	var world_state: Dictionary
	if world_snapshot.is_empty():
		if not generation.is_empty():
			return {"ok": false, "reason": "world_snapshot_missing"}
		if profile_sequence > 0 and not profile_document.has("world_monster_respawn_state"):
			return {"ok": false, "reason": "world_snapshot_missing"}
		var legacy: Variant = profile_document.get("world_monster_respawn_state", WorldState.empty_snapshot())
		if not valid_world_state(legacy):
			return {"ok": false, "reason": "invalid_legacy_world_state"}
		world_state = (legacy as Dictionary).duplicate(true)
	else:
		if not valid_snapshot(world_snapshot, profile_id, generation):
			return {"ok": false, "reason": "invalid_world_snapshot"}
		world_sequence = int(world_snapshot["sequence"])
		world_state = (world_snapshot["world_state"] as Dictionary).duplicate(true)
	var result := {
		"ok": true,
		"snapshot_present": not world_snapshot.is_empty(),
		"source_profile_sequence": profile_sequence,
		"source_world_sequence": world_sequence,
		"profile_sequence": profile_sequence,
		"world_sequence": world_sequence,
		"latest_sequence": maxi(profile_sequence, world_sequence),
		"level": int(profile_document.get("level", 1)),
		"experience": int(profile_document.get("experience", 0)),
		"quest_states": (profile_document.get("quest_states", {}) as Dictionary).duplicate(true),
		"world_state": world_state,
	}
	var previous := mini(profile_sequence, world_sequence)
	for raw_event: Variant in events:
		if not raw_event is Dictionary:
			return {"ok": false, "reason": "invalid_death_event"}
		var event: Dictionary = raw_event
		var sequence := int(event.get("sequence", -1))
		if sequence <= previous or not valid_death_event(event, profile_id, sequence, generation):
			return {"ok": false, "reason": "invalid_death_event"}
		if sequence != previous + 1:
			return {"ok": false, "reason": "death_event_gap"}
		previous = sequence
		if sequence > profile_sequence:
			result["level"] = int(event["level"])
			result["experience"] = int(event["experience"])
			result["quest_states"] = (event["quest_states"] as Dictionary).duplicate(true)
		if sequence > world_sequence:
			if event["contract_id"] == EVENT_CONTRACT_ID:
				result["world_state"] = (event["world_state"] as Dictionary).duplicate(true)
			else:
				Delta.apply_patch_owned(result["world_state"]["entries"], event["world_delta"])
		result["latest_sequence"] = sequence
	if previous < maxi(profile_sequence, world_sequence):
		return {"ok": false, "reason": "death_event_gap"}
	result["profile_sequence"] = maxi(profile_sequence, previous)
	result["world_sequence"] = maxi(world_sequence, previous)
	return result


static func _nonnegative_sequence(value: Variant) -> bool:
	return (value is int or (value is float and is_finite(value) and floorf(value) == value)) and int(value) >= 0
