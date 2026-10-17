extends RefCounted

## Value schema only. Acceptance does not authorize arrival: the actual Core,
## Registry, Session, settled map scope and Native CAS must still authenticate it.
const CONTRACT := "hardcore.source.map_arrival.v2"
const KEYS := ["contract_id","before_world","after_world","source_root_id","world_core_id","registry_id","owner_session_id","player_runtime_id","player_identity","coordinator_generation","transition_id","loading_scope","finish_identity","finish_reply"]

static func _world(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 5: return false
	return value.get("contract_id") == "hardcore.execution.world_context.v1" and value.get("world_runtime_id") is int and value.world_runtime_id > 0 and value.get("profile_id") is String and not value.profile_id.is_empty() and value.get("world_epoch") is int and value.world_epoch >= 0 and value.get("runtime_map_id") is int and (value.runtime_map_id >= 0 or (value.runtime_map_id == -1 and value.world_epoch == 0))

static func accepts(transaction: Dictionary) -> bool:
	if transaction.size() != KEYS.size() or not transaction.has_all(KEYS) or transaction.contract_id != CONTRACT: return false
	if not _world(transaction.before_world) or not _world(transaction.after_world): return false
	var before: Dictionary = transaction.before_world
	var after: Dictionary = transaction.after_world
	if before.world_runtime_id != after.world_runtime_id or before.profile_id != after.profile_id or before.world_epoch == 9223372036854775807 or after.world_epoch != before.world_epoch + 1 or after.runtime_map_id < 0: return false
	for key: String in ["source_root_id","world_core_id","registry_id"]:
		if not transaction[key] is int or transaction[key] == 0: return false
	for key: String in ["owner_session_id","player_runtime_id"]:
		if not transaction[key] is int or transaction[key] <= 0: return false
	if not transaction.coordinator_generation is int or transaction.coordinator_generation < 0 or not transaction.transition_id is String or transaction.transition_id.is_empty(): return false
	for key: String in ["loading_scope","finish_identity","finish_reply","player_identity"]:
		if not transaction[key] is Dictionary: return false
	var player: Dictionary = transaction.player_identity
	return player.size() == 3 and player.get("world") == after and player.get("runtime_id") == transaction.player_runtime_id and player.get("runtime_id") is int and player.get("life_generation") is int and player.life_generation > 0
