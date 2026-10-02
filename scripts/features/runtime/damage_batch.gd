extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Actor := preload("res://scripts/features/contracts/actor_ref.gd")
const Ids := preload("res://scripts/identity/entity_registry.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const MAX_BASE_DEPTH := 8
const MAX_FACTS := 4096
var _world: RefCounted
var _world_identity: Dictionary = {}
var _release_id := ""
var _skill_id := ""
var _accepted_usec := 0
var _bindings: Array = []
var _credit: Dictionary = {}
var _entries: Array = []
var _depth := 0
var _sealed := false
var _consumed := false
var _reservation: RefCounted
var _fact_limit := MAX_FACTS
var errors: Array[String] = []

static func create(world: RefCounted, release_id: String, skill_id: String, bindings: Array, credit: Dictionary, accepted_usec: int = 0, reservation: RefCounted = null) -> Dictionary:
	if world == null or world.capture_world().is_empty() or release_id.is_empty() or Ids.resolve(skill_id,"skill").is_empty() \
		or bindings.size() > 32 or accepted_usec < 0:
		return {"success":false,"reason":"invalid_damage_batch_identity","batch":null}
	var captured := Graph.capture({"bindings":bindings,"credit":credit})
	if not bool(captured.success):
		return {"success":false,"reason":"non_plain_damage_batch_configuration","batch":null}
	if not validate_bindings(skill_id,captured.value.bindings):
		return {"success":false,"reason":"invalid_event_binding","batch":null}
	var limit := MAX_FACTS
	if reservation != null:
		if reservation.get_script() != preload("res://scripts/features/contracts/effect_reservation.gd"):
			return {"success":false,"reason":"invalid_effect_reservation","batch":null}
		var claimed: Dictionary = reservation.claim(world.capture_world(),release_id,skill_id,captured.value.bindings)
		if not bool(claimed.get("success",false)):
			return {"success":false,"reason":"closed_effect_reservation","batch":null}
		limit = int(claimed.maximum_facts)
	var result := new()
	result._reservation = reservation; result._fact_limit = limit
	result._world = world
	result._world_identity = world.capture_world()
	result._release_id = release_id
	result._skill_id = skill_id
	result._accepted_usec = accepted_usec
	result._bindings = captured.value.bindings
	result._credit = captured.value.credit
	return {"success":true,"reason":"","batch":result}

static func validate_bindings(skill_id: String, bindings: Array) -> bool:
	if bindings.size() > 32: return false
	var binding_errors: Array[String] = []
	var authority: Dictionary = preload("res://scripts/features/adapters/feature_authority.gd").build()
	for binding: Variant in bindings:
		if not binding is Dictionary or binding.size() != 3 or not binding.get("definition") is Dictionary \
			or not binding.get("source") is Dictionary or not binding.get("handle") is String:
			return false
		for key: Variant in binding.source:
			if key not in ["slot","instance_id","extension_id","mechanic_id"] \
				or not binding.source[key] is String or binding.source[key].is_empty(): return false
		if not binding.source.has("instance_id"): return false
		if not Compiler._mechanic_valid(binding.definition,{"capabilities":["combat.post_hit","effects.periodic"],
			"handlers":["hc.ignite.v1"],"cost":{"commands_per_event":1,"states_per_target":1}},authority,binding_errors) \
			or binding.definition.get("kind") != "trigger" or binding.definition.get("skill_id") != skill_id \
			or binding.handle != Compiler.source_handle(binding.source) \
			or binding.source.get("mechanic_id") != binding.definition.mechanic_id \
			or Ids.resolve(str(binding.source.get("slot","")),"slot").is_empty():
			return false
	return true

func begin_base_scope() -> bool:
	if _sealed or _consumed or _depth >= MAX_BASE_DEPTH:
		errors.append("damage_batch_scope_rejected")
		return false
	_depth += 1
	return true

func finish_base_scope() -> bool:
	if _depth <= 0 or _sealed:
		errors.append("damage_batch_scope_mismatch")
		return false
	_depth -= 1
	_sealed = _depth == 0
	return _sealed

# Called only immediately after the existing HP write. The returned plain
# fact never rereads HP after a callback, heal, death or synchronous revival.
func capture_commit(target: Node, source: Node, hp_before: int, hp_after: int, requested: int, context: Dictionary) -> bool:
	if _depth <= 0 or _sealed or _consumed or not errors.is_empty():
		return false
	if _entries.size() >= _fact_limit:
		errors.append("damage_batch_capacity")
		return false
	if not _world.matches_world(_world_identity) or context.get("source_class") != "direct" \
		or context.get("damage_channel") not in ["physical","magic_defense"] \
		or requested <= 0 or hp_before < 0 or hp_after < 0 or hp_after > hp_before:
		errors.append("damage_fact_contract_rejected")
		return false
	var target_ref: RefCounted = Actor.capture(_world,target)
	if target_ref == null:
		errors.append("damage_fact_target_identity_rejected")
		return false
	var source_ref: RefCounted = null
	if is_instance_valid(source):
		var life_authority: String = Actor.LIFE_PLAYER if source.has_method("combat_transition_is_active") else Actor.LIFE_METADATA
		source_ref = Actor.capture(_world,source,life_authority)
	var source_identity: Dictionary = source_ref.identity() if source_ref != null else {}
	var fact := Graph.capture({"contract_id":"hardcore.combat.damage_fact.v1",
		"fact_id":_release_id + ":hp:" + str(_entries.size()),"release_id":_release_id,"skill_id":_skill_id,"accepted_simulation_usec":_accepted_usec,
		"source_class":"direct","damage_channel":context.damage_channel,"requested_damage":requested,
		"hp_before":hp_before,"hp_after":hp_after,"actual_loss":hp_before-hp_after,"target_survived_commit":hp_after > 0,
		"target":target_ref.identity(),"source":source_identity,"historical_credit":_credit})
	if not bool(fact.success):
		errors.append("non_plain_damage_fact")
		return false
	var entry := {"fact":fact.value,"target":target_ref,"source":source_ref,"bindings":_bindings,
		"admission_id":_reservation.sequence() if _reservation != null else 0}
	entry.make_read_only()
	_entries.append(entry)
	return true

func facts() -> Array:
	var result: Array = []
	for entry: Dictionary in _entries:
		result.append(entry.fact)
	result.make_read_only()
	return result

# A rejected queue submission must not spend this batch's one-shot right.
# Only complete, valid, unconsumed batches advertise transferable facts.
func pending_fact_count() -> int:
	return _entries.size() if _sealed and not _consumed and errors.is_empty() else 0

func consume() -> Array:
	if not _sealed or _consumed or not errors.is_empty():
		return []
	_consumed = true
	var result := _entries.duplicate(false)
	result.make_read_only()
	return result

func is_complete() -> bool:
	return _sealed

func reservation() -> RefCounted: return _reservation

func binding_count() -> int: return _bindings.size()

func event_bindings() -> Array: return _bindings
