class_name WorldMonsterRespawnState
extends RefCounted

const MonsterRespawnPolicyScript := preload(
	"res://scripts/monster_respawn_policy.gd"
)

const CONTRACT_ID := "monster.world_respawn_state.absolute_unix.v1"
const SCHEMA_VERSION := 1


static func empty_snapshot() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"schema_version": SCHEMA_VERSION,
		"entries": {},
	}


static func slot_key(runtime_map_id: int, spawn_slot_id: String) -> String:
	var slot := spawn_slot_id.strip_edges()
	if runtime_map_id < 0 or slot.is_empty() or slot.begins_with("runtime:"):
		return ""
	return "%d|%s" % [runtime_map_id, slot]


static func normalize_snapshot(raw_snapshot: Variant) -> Dictionary:
	var result := empty_snapshot()
	if not raw_snapshot is Dictionary:
		return result
	var raw_root := raw_snapshot as Dictionary
	var raw_contract := str(raw_root.get("contract_id", ""))
	if not raw_contract.is_empty() and raw_contract != CONTRACT_ID:
		return result
	var raw_entries: Variant = raw_root.get("entries", {})
	if not raw_entries is Dictionary:
		return result
	var entries: Dictionary = {}
	for raw_entry: Variant in (raw_entries as Dictionary).values():
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		var runtime_map_id := int(entry.get("runtime_map_id", -1))
		var spawn_slot_id := str(entry.get("spawn_slot_id", ""))
		var monster_id := int(entry.get("monster_id", -1))
		var policy_id := str(entry.get("policy_id", ""))
		var respawn_at_unix := float(entry.get("respawn_at_unix", 0.0))
		var key := slot_key(runtime_map_id, spawn_slot_id)
		if (
			key.is_empty()
			or monster_id <= 0
			or not MonsterRespawnPolicyScript.is_known(policy_id)
			or respawn_at_unix <= 0.0
		):
			continue
		entries[key] = {
			"runtime_map_id": runtime_map_id,
			"spawn_slot_id": spawn_slot_id,
			"monster_id": monster_id,
			"policy_id": policy_id,
			"respawn_at_unix": respawn_at_unix,
		}
	result["entries"] = entries
	return result


static func entry_for(
	snapshot: Variant,
	runtime_map_id: int,
	spawn_slot_id: String
) -> Dictionary:
	var normalized := normalize_snapshot(snapshot)
	var key := slot_key(runtime_map_id, spawn_slot_id)
	if key.is_empty():
		return {}
	var raw_entry: Variant = (normalized.get("entries", {}) as Dictionary).get(key, {})
	return (raw_entry as Dictionary).duplicate(true) if raw_entry is Dictionary else {}


static func with_deadline(
	snapshot: Variant,
	runtime_map_id: int,
	spawn_slot_id: String,
	monster_id: int,
	policy_id: String,
	respawn_at_unix: float
) -> Dictionary:
	var normalized := normalize_snapshot(snapshot)
	var key := slot_key(runtime_map_id, spawn_slot_id)
	if (
		key.is_empty()
		or monster_id <= 0
		or not MonsterRespawnPolicyScript.is_known(policy_id)
		or respawn_at_unix <= 0.0
	):
		return normalized
	var entries: Dictionary = normalized.get("entries", {})
	entries[key] = {
		"runtime_map_id": runtime_map_id,
		"spawn_slot_id": spawn_slot_id,
		"monster_id": monster_id,
		"policy_id": policy_id,
		"respawn_at_unix": respawn_at_unix,
	}
	normalized["entries"] = entries
	return normalized


static func without_slot(
	snapshot: Variant,
	runtime_map_id: int,
	spawn_slot_id: String
) -> Dictionary:
	var normalized := normalize_snapshot(snapshot)
	var key := slot_key(runtime_map_id, spawn_slot_id)
	if key.is_empty():
		return normalized
	var entries: Dictionary = normalized.get("entries", {})
	entries.erase(key)
	normalized["entries"] = entries
	return normalized


static func remaining_seconds(entry: Dictionary, now_unix: float) -> float:
	if entry.is_empty():
		return 0.0
	return maxf(
		0.0,
		float(entry.get("respawn_at_unix", 0.0)) - now_unix
	)
