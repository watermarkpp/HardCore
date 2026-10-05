extends RefCounted

## Compiled view of accepted factory descriptors, never another spawner.
## Dead/deferred slots remain published for next lives and old-life children.
const Inputs := preload("res://scripts/features/contracts/published_monster_inputs.gd")
const Respawn := preload("res://scripts/monster_respawn_policy.gd")
const Summons := preload("res://scripts/monster_ai_package/m30/summon_queue.gd")
var _world: Dictionary = {}
var _slots: Dictionary = {}
var _closures: Dictionary = {}
var _inputs: Dictionary = {}
var _maximum := 0
var _reason := ""
var _sealed := false
var _plan_sha256 := ""

func sync_world(identity: Dictionary) -> void:
	if identity == _world: return
	_world = identity.duplicate(true)
	_world.make_read_only()
	_slots.clear(); _closures.clear(); _inputs.clear()
	_maximum = 0; _reason = ""; _sealed = false; _plan_sha256 = ""

func declare_base(slot: String, monster_id: int, position := Vector2.INF,
	respawn_seconds := -1.0, context: Dictionary = {}, actor_id := "") -> bool:
	if _sealed: return false
	if _world.is_empty(): return _collection_rejected("unpublished_world")
	if slot.is_empty(): return _collection_rejected("unidentified_base_spawn")
	if not position.is_finite() or not is_finite(respawn_seconds):
		return _collection_rejected("invalid_base_spawn_descriptor")
	if not str(context.get("summoner_spawn_slot", "")).is_empty():
		return _collection_rejected("summon_is_not_base_spawn")
	if context.has("respawn_enabled") and not context.respawn_enabled is bool:
		return _collection_rejected("invalid_base_respawn_enabled")
	var supplied_slot := str(context.get("spawn_slot_id", context.get("spawn_group_id", slot)))
	if supplied_slot != slot: return _collection_rejected("conflicting_base_spawn_slot")
	# Complete the frozen closure before admitting the descriptor to the plan.
	var closure := _closure(monster_id)
	if not bool(closure.get("proved", false)):
		return _collection_rejected(str(closure.get("reason", "unknown_spawn_monster")))
	var inputs: RefCounted = _inputs[monster_id]
	var monster: Dictionary = inputs.view().entry
	var enabled := bool(context.get("respawn_enabled", true))
	var policy: Dictionary = {}
	if enabled:
		policy = Respawn.resolve(str(context.get("respawn_policy_id", "")),
			str(monster.get("classification", "")), respawn_seconds,
			str(monster.get("spawn_classification", "")))
		if not bool(policy.get("valid", false)):
			return _collection_rejected("invalid_respawn_policy")
	var accepted_context := context.duplicate(true)
	accepted_context["spawn_slot_id"] = slot
	var descriptor := {"monster_id": monster_id, "position": position, "actor_id": actor_id,
		"respawn_seconds": respawn_seconds, "context": accepted_context,
		"respawn_enabled": enabled, "policy": policy,
		"effective_respawn_seconds": float(policy.get("seconds", maxf(0.0, respawn_seconds)))}
	if _slots.has(slot): return _collection_rejected("duplicate_base_spawn_descriptor")
	_freeze(descriptor)
	_slots[slot] = descriptor
	_maximum += 1 + int(closure.children)
	return true

func seal() -> bool:
	if _sealed: return _reason.is_empty()
	if _world.is_empty() or not _reason.is_empty(): return false
	var slots: Array = _slots.keys()
	slots.sort()
	var descriptors: Array = []
	for slot: String in slots:
		var descriptor: Dictionary = _slots[slot]
		var hashed := descriptor.duplicate(true)
		var position: Vector2 = descriptor.position
		hashed["position"] = [position.x, position.y]
		descriptors.append({"slot": slot, "descriptor": hashed})
	var ids: Array = _inputs.keys()
	ids.sort()
	var monsters: Array = []
	for id: int in ids:
		var inputs: RefCounted = _inputs[id]
		monsters.append({"monster_id": id, "inputs": inputs.view()})
	_plan_sha256 = JSON.stringify({"world": _world, "descriptors": descriptors,
		"monsters": monsters}, "", true, true).sha256_text()
	_sealed = true
	return true

func declared_base_matches(monster_id: int, position: Vector2, respawn_seconds: float,
	context: Dictionary, actor_id := "") -> bool:
	if _sealed or not _reason.is_empty(): return false
	var slot := str(context.get("spawn_slot_id", context.get("spawn_group_id", "")))
	if slot.is_empty() or not _slots.has(slot): return false
	var descriptor: Dictionary = _slots[slot]
	return descriptor.actor_id == actor_id and int(descriptor.monster_id) == monster_id \
		and position == descriptor.position \
		and respawn_seconds == float(descriptor.respawn_seconds) and _context_matches(descriptor, context)

func admit_base(monster_id: int, position: Vector2, respawn_seconds: float,
	context: Dictionary) -> Dictionary:
	if not _sealed or not _reason.is_empty(): return _rejected("unsealed_birth_plan")
	if not str(context.get("summoner_spawn_slot", "")).is_empty():
		return _rejected("summon_requires_queue_issuance")
	var slot := str(context.get("spawn_slot_id", context.get("spawn_group_id", "")))
	if slot.is_empty() or not _slots.has(slot): return _rejected("unpublished_base_spawn_slot")
	var descriptor: Dictionary = _slots[slot]
	if int(descriptor.monster_id) != monster_id: return _rejected("changed_base_spawn_identity")
	if position != descriptor.position: return _rejected("changed_base_spawn_position")
	if not is_finite(respawn_seconds) or (respawn_seconds != float(descriptor.respawn_seconds)
		and respawn_seconds != float(descriptor.effective_respawn_seconds)):
		return _rejected("changed_base_respawn_seconds")
	if not _context_matches(descriptor, context): return _rejected("changed_base_spawn_context")
	var inputs: RefCounted = _inputs[monster_id]
	return {"accepted": true, "reason": "", "monster": inputs.view().entry, "inputs": inputs,
		"policy": descriptor.policy, "effective_respawn": float(descriptor.effective_respawn_seconds)}

func admits_child(slot: String, monster_id: int) -> bool:
	if not _sealed or not _reason.is_empty() or not _slots.has(slot): return false
	var descriptor: Dictionary = _slots[slot]
	var closure: Dictionary = _closures[int(descriptor.monster_id)]
	return monster_id in closure.ids and _inputs.has(monster_id)

func monster_inputs(monster_id: int) -> RefCounted:
	return _inputs.get(monster_id) if _sealed and _reason.is_empty() else null

func summon_request_valid(slot: String, source_id: int, ids: Array,
	count: int, maximum: int) -> bool:
	if not _sealed or not _reason.is_empty() or not _slots.has(slot): return false
	var descriptor: Dictionary = _slots[slot]
	if int(descriptor.monster_id) != source_id or count <= 0 or maximum <= 0 or ids.is_empty():
		return false
	var closure: Dictionary = _closures[source_id]
	for rule: Dictionary in closure.rules:
		var behavior := str(rule.kind) == "behavior"
		var expected_maximum := int(rule.get("maxActive", 5 if behavior else 30))
		if behavior: expected_maximum = maxi(1, expected_maximum)
		if maximum != expected_maximum: continue
		if behavior:
			if count != maxi(1, int(rule.get("count", 1))): continue
			if ids.size() != rule.monsterIds.size(): continue
			var same_pool := true
			for index in range(ids.size()):
				var raw: Variant = ids[index]
				if (not raw is int and not raw is float) or not is_finite(float(raw)) \
					or float(raw) != float(rule.monsterIds[index]):
					same_pool = false; break
			if not same_pool: continue
		else:
			if count < int(rule.get("minCount", 6)) or count > int(rule.get("maxCount", 11)):
				continue
			if ids.size() != count: continue
		var valid := true
		for raw: Variant in ids:
			if not raw is int and not raw is float:
				valid = false; break
			if not is_finite(float(raw)) or float(raw) <= 0.0 or float(raw) > 9007199254740991.0:
				valid = false; break
			if float(raw) != floorf(float(raw)) or int(raw) not in rule.monsterIds:
				valid = false; break
		if valid: return true
	return false

func snapshot() -> Dictionary:
	return {"proved": _sealed and not _world.is_empty() and _reason.is_empty(),
		"sealed": _sealed, "reason": _reason, "base_slots": _slots.size(),
		"maximum_receivers": _maximum, "world": _world.duplicate(true), "plan_sha256": _plan_sha256}

func _collection_rejected(reason: String) -> bool:
	if _reason.is_empty(): _reason = reason
	return false

static func _rejected(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "monster": {}, "inputs": null}

func _capture_inputs(monster_id: int) -> RefCounted:
	if _inputs.has(monster_id): return _inputs[monster_id]
	var inputs: RefCounted = Inputs.capture(monster_id,
		EnemyActor._attack_range_policy_record_for_id(monster_id),
		EnemyActor._movement_authority_record_for_id(monster_id))
	if inputs != null: _inputs[monster_id] = inputs
	return inputs

func _closure(monster_id: int) -> Dictionary:
	if _closures.has(monster_id): return _closures[monster_id]
	var inputs := _capture_inputs(monster_id)
	if inputs == null: return {"proved": false, "reason": "unknown_spawn_monster"}
	var view: Dictionary = inputs.view()
	var rules := _summon_rules(view)
	var count := 0
	var ids: Array[int] = []
	for rule: Dictionary in rules:
		var behavior := str(rule.kind) == "behavior"
		var maximum := int(rule.get("maxActive", 5 if behavior else 30))
		if behavior: maximum = maxi(1, maximum)
		if maximum <= 0 or rule.get("monsterIds", []).is_empty():
			return {"proved": false, "reason": "invalid_summon_rule"}
		maximum = Summons.effective_maximum(str(view.entry.get("classification", "")) == "boss", maximum)
		# All producers share the queue's same per-owner live/reserved cap.
		count = maxi(count, maximum)
		var normalized: Array[int] = []
		for raw: Variant in rule.get("monsterIds", []):
			var child_id := GameData.canonical_monster_id(raw)
			var child_inputs := _capture_inputs(child_id)
			if child_inputs == null: return {"proved": false, "reason": "unknown_summon_child"}
			# Descendants can outlive replacement lives; acyclicity alone is insufficient.
			if not _summon_rules(child_inputs.view()).is_empty():
				return {"proved": false, "reason": "nested_summon_lifetime_unproved"}
			if child_id not in ids: ids.append(child_id)
			normalized.append(child_id)
		rule["monsterIds"] = normalized
	var result := {"proved": true, "reason": "", "children": count, "ids": ids, "rules": rules}
	_freeze(result)
	_closures[monster_id] = result
	return result

static func _summon_rules(view: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var behavior: Dictionary = view.get("behavior", {}).get("summonRule", {}).duplicate(true)
	if bool(behavior.get("enabled", false)):
		behavior["kind"] = "behavior"; result.append(behavior)
	if str(view.get("entry", {}).get("classification", "")) == "boss":
		var health: Dictionary = view.get("boss_rule", {}).get("mechanics", {}).get("healthStageSummon", {}).duplicate(true)
		if bool(health.get("enabled", false)):
			health["kind"] = "health"; result.append(health)
	return result

func _context_matches(descriptor: Dictionary, incoming: Dictionary) -> bool:
	var original: Dictionary = descriptor.context
	var normalized := incoming.duplicate(true)
	normalized["spawn_slot_id"] = str(incoming.get("spawn_slot_id", incoming.get("spawn_group_id", "")))
	var inputs: RefCounted = _inputs[int(descriptor.monster_id)]
	var entry: Dictionary = inputs.view().entry
	var enabled := bool(descriptor.respawn_enabled)
	if normalized.has("respawn_enabled") and not normalized.respawn_enabled is bool: return false
	if bool(normalized.get("respawn_enabled", true)) != enabled: return false
	var original_policy := str(original.get("respawn_policy_id", ""))
	var effective_policy := str(descriptor.policy.get("policy_id", "")) if enabled else ""
	var policy := str(normalized.get("respawn_policy_id", ""))
	if policy != original_policy and policy != effective_policy: return false
	# Only factory-derived fields may enrich the original authored context.
	var derived := {"respawn_policy_source": str(descriptor.policy.get("source", "respawn_disabled")),
		"respawn_policy_requires_authored_policy": bool(descriptor.policy.get("requires_authored_policy", false)),
		"respawn_runtime_map_id": int(_world.get("runtime_map_id", -1)),
		"respawn_base_seconds": float(descriptor.effective_respawn_seconds),
		"respawn_random_seconds": 0.0}
	if enabled: derived["spawn_classification"] = str(entry.get("spawn_classification", ""))
	for key: Variant in normalized:
		if key in ["respawn_policy_id", "respawn_enabled"]: continue
		if derived.has(key):
			if normalized[key] != derived[key] and (not original.has(key) or normalized[key] != original[key]):
				return false
		elif not original.has(key) or normalized[key] != original[key]: return false
	for key: Variant in original:
		if key in ["respawn_policy_id", "respawn_enabled"]: continue
		if not normalized.has(key) or (not derived.has(key) and normalized[key] != original[key]):
			return false
	return true

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values(): _freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: _freeze(child)
		value.make_read_only()
