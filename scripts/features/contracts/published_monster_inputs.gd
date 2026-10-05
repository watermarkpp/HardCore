extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Identity := preload("res://scripts/monster_identity.gd")

var _monster_id := -1
var _snapshot: Dictionary = {}

# Compile through the existing identity and EnemyActor policy authorities at
# publication. The caller supplies policy records to avoid an Enemy preload cycle.
static func capture(monster_id: int, range_policy: Dictionary, movement_policy: Dictionary) -> RefCounted:
	if monster_id <= 0:
		return null
	var entry := Identity.require_catalog_entry(monster_id, "runtime")
	var raw_id: Variant = entry.get("monster_id", null)
	if entry.is_empty() or (not raw_id is int and not raw_id is float):
		return null
	if not is_finite(float(raw_id)) or float(raw_id) != float(monster_id):
		return null
	# Preserve the original runtime projection: JSON IDs become exact integers
	# before the strict EnemyActor identity boundary, without coercing aliases.
	entry["monster_id"] = monster_id
	if not range_policy.is_empty() and int(range_policy.get("monsterId", -1)) != monster_id:
		return null
	if not movement_policy.is_empty() and int(movement_policy.get("monster_id", -1)) != monster_id:
		return null
	var identity := {"monster_id": monster_id}
	var captured := Graph.capture({
		"entry": entry,
		"appearance": Identity.appearance_profile(monster_id),
		"body": Identity.body_profile(monster_id),
		"behavior": Identity.behavior_profile(identity),
		"boss_rule": Identity.runtime_boss_rule(identity, GameData.boss_service_rules),
		"attack_range_policy": range_policy,
		"movement_policy": movement_policy,
		"drop": Identity.drop_profile(monster_id),
	})
	if not bool(captured.success):
		return null
	var result := new()
	result._monster_id = monster_id
	result._snapshot = captured.value
	return result

func view() -> Dictionary:
	return _snapshot

func valid_for(monster_id: int) -> bool:
	return monster_id > 0 and _monster_id == monster_id and not _snapshot.is_empty()
