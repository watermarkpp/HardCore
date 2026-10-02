extends RefCounted

## A view of declared factory slots, not a second spawner or geometry planner.
## Keep dead/deferred slots: their next life can enter a release-time query.
const Identity := preload("res://scripts/monster_identity.gd")
const Summons := preload("res://scripts/monster_ai_package/m30/summon_queue.gd")
var _world: Dictionary = {}
var _slots: Dictionary = {}
var _closures: Dictionary = {}
var _maximum := 0
var _reason := ""

func sync_world(identity: Dictionary) -> void:
	if identity == _world: return
	_world = identity; _slots.clear(); _closures.clear(); _maximum = 0; _reason = ""

func declare_base(slot: String, monster_id: int) -> void:
	if slot.is_empty(): _reason = "unidentified_base_spawn"; return
	if _slots.has(slot):
		if int(_slots[slot]) != monster_id: _reason = "conflicting_base_spawn_identity"
		return
	var closure := _closure(monster_id)
	_slots[slot] = monster_id
	if not bool(closure.proved): _reason = str(closure.reason); return
	_maximum += 1+int(closure.children)

func observe_child(slot: String, monster_id: int) -> void:
	if not _slots.has(slot): _reason = "undeclared_summon_owner"; return
	var closure := _closure(int(_slots[slot]))
	if not bool(closure.proved) or monster_id not in closure.ids:
		_reason = "undeclared_summon_child"

func snapshot() -> Dictionary:
	return {"proved":not _world.is_empty() and _reason.is_empty(),"reason":_reason,
		"base_slots":_slots.size(),"maximum_receivers":_maximum,"world":_world.duplicate()}

func _closure(monster_id: int) -> Dictionary:
	if _closures.has(monster_id): return _closures[monster_id]
	var data: Dictionary = GameData.get_monster_by_id(monster_id)
	if data.is_empty(): return {"proved":false,"reason":"unknown_spawn_monster"}
	var rules := _summon_rules(data)
	var count := 0
	var ids: Array[int] = []
	for rule: Dictionary in rules:
		var maximum := int(rule.get("maxActive",5 if rule.get("kind") == "behavior" else 30))
		if rule.get("kind") == "behavior": maximum = maxi(1,maximum)
		maximum = Summons.effective_maximum(str(data.get("classification","")) == "boss",maximum)
		# Both producers use the same per-owner queue; its greatest authored cap
		# bounds their combined live/reserved children, not the sum of both caps.
		count = maxi(count,maximum)
		for raw: Variant in rule.get("monsterIds",[]):
			var child_id := GameData.canonical_monster_id(raw)
			var child: Dictionary = GameData.get_monster_by_id(child_id)
			if child.is_empty(): return {"proved":false,"reason":"unknown_summon_child"}
			# Descendants may outlive a replaced summoning child. Even an acyclic
			# graph alone would not prove its lifetime bound, so do not multiply it.
			if not _summon_rules(child).is_empty(): return {"proved":false,"reason":"nested_summon_lifetime_unproved"}
			if child_id not in ids: ids.append(child_id)
	var result := {"proved":true,"reason":"","children":count,"ids":ids}
	_closures[monster_id] = result
	return result

static func _summon_rules(data: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var behavior: Dictionary = Identity.behavior_profile(data).get("summonRule",{})
	if bool(behavior.get("enabled",false)):
		behavior["kind"] = "behavior"; result.append(behavior)
	if str(data.get("classification","")) == "boss":
		var boss := Identity.runtime_boss_rule(data,GameData.boss_service_rules)
		var health: Dictionary = boss.get("mechanics",{}).get("healthStageSummon",{}).duplicate(true)
		if bool(health.get("enabled",false)):
			health["kind"] = "health"; result.append(health)
	return result
