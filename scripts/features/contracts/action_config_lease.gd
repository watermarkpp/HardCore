extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const ACCEPTED_PRIMARY_STATS := "accepted_configuration"
const LEGACY_RELEASE_PRIMARY_STATS := "legacy_release_owner"
var _snapshot: Dictionary = {}
var _accepted := false

# Configuration is accepted separately from live target/facing sampling. The
# old release boundary continues to own positions, receiver life and facing.
static func create(definition: Dictionary, rank: int, actor_level: int, primary_stats: Dictionary,
	versions: Dictionary, actor_identity: Dictionary, partner_definition: Dictionary = {}, partner_rank := 0,
	primary_policy: String = ACCEPTED_PRIMARY_STATS, melee: Dictionary = {}, event_index: Dictionary = {}) -> Dictionary:
	if not _definition_identity_valid(definition) or (not partner_definition.is_empty() and not _definition_identity_valid(partner_definition)):
		return {"success": false, "reason": "lease_unknown_skill", "lease": null}
	if not _versions_valid(versions) or not _actor_valid(actor_identity) or rank < 0 or actor_level < 1 \
		or primary_policy not in [ACCEPTED_PRIMARY_STATS, LEGACY_RELEASE_PRIMARY_STATS]:
		return {"success": false, "reason": "lease_invalid_identity", "lease": null}
	if not _melee_valid(melee) or not _events_valid(event_index):
		return {"success":false,"reason":"lease_invalid_melee_configuration","lease":null}
	var captured := Graph.capture({"definition": definition, "rank": rank, "actor_level": actor_level,
		"primary_stats": primary_stats, "versions": versions, "actor_identity": actor_identity,
		"partner_definition": partner_definition, "partner_rank":partner_rank, "primary_policy":primary_policy, "melee":melee,"event_index":event_index})
	if not bool(captured.success):
		return {"success": false, "reason": "lease_non_plain_snapshot", "lease": null}
	var lease := new()
	lease._snapshot = captured.value
	return {"success": true, "reason": "", "lease": lease}

func current_before_accept(versions: Dictionary, actor_identity: Dictionary) -> bool:
	return not _snapshot.is_empty() and not _accepted and _snapshot.versions == versions \
		and _snapshot.actor_identity == actor_identity

func accept(versions: Dictionary, actor_identity: Dictionary) -> bool:
	if not current_before_accept(versions, actor_identity):
		return false
	_accepted = true
	return true

func valid_for_release(actor_identity: Dictionary) -> bool:
	return _accepted and not _snapshot.is_empty() and _snapshot.actor_identity == actor_identity

func definition_for(skill_id: String) -> Dictionary:
	var canonical_id := Loader.stable_skill_id(skill_id)
	if _snapshot.is_empty():
		return {}
	if str(_snapshot.definition.skill_id) == canonical_id:
		return _snapshot.definition
	return melee_context().get("definitions", {}).get(Loader.entity_skill_id(canonical_id), {})

func rank_for(skill_id: String) -> int:
	if not _snapshot.is_empty() and str(_snapshot.definition.skill_id) == Loader.stable_skill_id(skill_id):
		return rank()
	return int(melee_context().get("ranks", {}).get(Loader.entity_skill_id(skill_id), 0))

func melee_context() -> Dictionary:
	return _snapshot.get("melee", {})

func event_bindings_for(skill_id: String) -> Array:
	var index: Dictionary = _snapshot.get("event_index", {})
	if index.is_empty(): return []
	return index.get("damage_committed:" + Loader.entity_skill_id(skill_id), [])

func rank() -> int:
	return int(_snapshot.get("rank", 0))

func actor_level() -> int:
	return int(_snapshot.get("actor_level", 0))

func primary_stats() -> Dictionary:
	return _snapshot.get("primary_stats", {})

func primary_stat_policy() -> String:
	return str(_snapshot.get("primary_policy", ""))

func partner_definition() -> Dictionary:
	return _snapshot.get("partner_definition", {})

func partner_rank() -> int:
	return int(_snapshot.get("partner_rank", 0))

func is_accepted() -> bool:
	return _accepted

static func resolve_definition(skill_id: String, lease: Variant) -> Dictionary:
	if lease == null:
		return Loader.skill(skill_id)
	if not lease is RefCounted or lease.get_script() == null \
		or lease.get_script().resource_path != "res://scripts/features/contracts/action_config_lease.gd" or not lease.is_accepted():
		return {}
	return lease.definition_for(skill_id)

func versions() -> Dictionary:
	return _snapshot.get("versions", {})


static func _definition_identity_valid(value: Dictionary) -> bool:
	var old: Variant = value.get("skill_id")
	return old is String and Loader.is_canonical_skill_id(old) \
		and value.get("entity_id") == Loader.entity_skill_id(old)

static func _melee_valid(value: Dictionary) -> bool:
	if value.is_empty():
		return true
	if value.size() != 4 or not value.get("definitions") is Dictionary or not value.get("ranks") is Dictionary \
		or not value.get("learned_skills") is Dictionary or not value.get("toggles") is Dictionary:
		return false
	if value.definitions.size() > 7 or value.definitions.size() != value.ranks.size():
		return false
	for id: Variant in value.definitions:
		if not id is String or not value.definitions[id] is Dictionary or not _definition_identity_valid(value.definitions[id]) \
			or value.definitions[id].entity_id != id or not value.ranks.get(id) is int or value.ranks[id] < 0:
			return false
	for id: Variant in value.learned_skills:
		if not value.definitions.has(id) or not value.learned_skills[id] is int or value.learned_skills[id] != value.ranks[id]:
			return false
	for id: Variant in value.toggles:
		if id not in ["warrior.fire_sword","warrior.half_moon","warrior.thrusting"] or not value.toggles[id] is bool:
			return false
	return true

static func _events_valid(index: Dictionary) -> bool:
	var count := 0
	for key: Variant in index:
		if not key is String or not key.begins_with("damage_committed:") or not index[key] is Array: return false
		var id: String = key.trim_prefix("damage_committed:")
		if Loader.entity_skill_id(id) != id or id.is_empty(): return false
		if not preload("res://scripts/features/runtime/damage_batch.gd").validate_bindings(id,index[key]): return false
		count += index[key].size()
	return count <= 32

static func _versions_valid(value: Dictionary) -> bool:
	if value.size() != 2:
		return false
	return value.get("base_revision") is String and not str(value.base_revision).is_empty() \
		and value.get("loadout_revision") is String and not str(value.loadout_revision).is_empty()

static func _actor_valid(value: Dictionary) -> bool:
	if value.size() != 3:
		return false
	for key: String in ["world_generation", "runtime_id", "life_generation"]:
		if not value.get(key) is int or int(value[key]) < 0:
			return false
	return int(value.runtime_id) > 0
