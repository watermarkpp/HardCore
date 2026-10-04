extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Actor := preload("res://scripts/features/contracts/actor_ref.gd")
const Ids := preload("res://scripts/identity/entity_registry.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Handlers := preload("res://scripts/features/handlers/handler_registry.gd")
const MAX_BASE_DEPTH := 8
const MAX_FACTS := 4096
var _world: RefCounted
var _world_identity: Dictionary = {}
var _release_id := ""
var _skill_id := ""
var _accepted_usec := 0
var _bindings: Array = []
var _credit: Dictionary = {}
var _chain_context: Dictionary = {}
var _source_class := "direct"
var _entries: Array = []
var _facts: Array = []
var _resources: RefCounted
var _depth := 0
var _sealed := false
var _consumed := false
var _reservation: RefCounted
var _fact_limit := MAX_FACTS
var errors: Array[String] = []

static func create(world: RefCounted, release_id: String, skill_id: String, bindings: Array, credit: Dictionary, accepted_usec: int = 0, reservation: RefCounted = null, resources: RefCounted = null, chain: Dictionary = {}, source_class := "direct") -> Dictionary:
	if resources != null and resources.get_script() != preload("res://scripts/features/contracts/feature_resource_lease.gd"):
		return {"success":false,"reason":"invalid_batch_resources","batch":null}
	if world == null or world.capture_world().is_empty() or release_id.is_empty() or Ids.resolve(skill_id,"skill").is_empty() \
		or bindings.size() > 32 or accepted_usec < 0:
		return {"success":false,"reason":"invalid_damage_batch_identity","batch":null}
	if not _lineage_valid(chain,release_id,skill_id,source_class):
		return {"success":false,"reason":"invalid_damage_batch_lineage","batch":null}
	var captured := Graph.capture({"bindings":bindings,"credit":credit,"chain":chain})
	if not bool(captured.success):
		return {"success":false,"reason":"non_plain_damage_batch_configuration","batch":null}
	if not validate_bindings(skill_id,captured.value.bindings):
		return {"success":false,"reason":"invalid_event_binding","batch":null}
	if not preload("res://scripts/features/contracts/feature_resource_lease.gd").supports_bindings(resources,captured.value.bindings):
		return {"success":false,"reason":"invalid_batch_resources","batch":null}
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
	result._resources = resources
	result._world = world
	result._world_identity = world.capture_world()
	result._release_id = release_id
	result._skill_id = skill_id
	result._accepted_usec = accepted_usec
	result._bindings = captured.value.bindings
	result._credit = captured.value.credit
	result._chain_context = captured.value.chain
	result._source_class = source_class
	return {"success":true,"reason":"","batch":result}

static func _lineage_valid(chain: Dictionary, release_id: String, skill_id: String, source_class: String) -> bool:
	if chain.is_empty(): return source_class == "direct"
	var fields := ["contract_id","root_release_id","release_id","parent_release_id","root_skill_id","generation","maximum_generation"]
	if chain.size() != fields.size(): return false
	for field: String in fields:
		if not chain.has(field): return false
	if chain.contract_id != "hardcore.combat.chain_context.v1" or source_class not in ["direct","periodic","child"]:
		return false
	for field: String in ["root_release_id","release_id","root_skill_id"]:
		if not chain[field] is String or chain[field].is_empty(): return false
	if not chain.parent_release_id is String or chain.release_id != release_id or chain.root_skill_id != skill_id:
		return false
	for field: String in ["generation","maximum_generation"]:
		var value: Variant = chain[field]
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0 \
			or float(value) > 9007199254740991.0 or float(value) != floor(float(value)): return false
	if chain.generation > chain.maximum_generation: return false
	if int(chain.generation) == 0:
		return source_class != "child" and chain.release_id == chain.root_release_id and chain.parent_release_id.is_empty()
	return source_class != "direct" and chain.release_id != chain.root_release_id and not chain.parent_release_id.is_empty()

func chain_context() -> Dictionary: return _chain_context

func requires_commit_context() -> bool: return not _chain_context.is_empty()

# Only the actual actor HP boundary supplies the geometry. No release-time
# target list or death observer can replace this commit-time mapped position.
func prepare_commit_context(target: Node, context: Dictionary) -> Dictionary:
	if _chain_context.is_empty(): return {"success":true,"context":context}
	if _depth <= 0 or _sealed or _consumed or not errors.is_empty() or _entries.size() >= _fact_limit \
		or not _world.matches_world(_world_identity) or Actor.capture(_world,target) == null \
		or context.get("source_class") != _source_class or context.get("damage_channel") not in ["physical","magic_defense"]:
		return {"success":false,"reason":"damage_chain_commit_context_rejected"}
	if not target is Node2D or target.get("runtime_map_id") != _world_identity.runtime_map_id \
		or not target.has_method("try_screen_position_px_to_ground_position_gu"):
		return {"success":false,"reason":"damage_chain_commit_projection_rejected"}
	var projection: Dictionary = target.call("try_screen_position_px_to_ground_position_gu",target.global_position)
	var origin: Variant = projection.get("value")
	if not bool(projection.get("success",false)) or not origin is Vector2 or not origin.is_finite():
		return {"success":false,"reason":"damage_chain_commit_projection_rejected"}
	var owned := context.duplicate(false)
	owned["commit_ground_origin"] = {"x":float(origin.x),"y":float(origin.y)}
	owned["historical_credit"] = _credit
	return {"success":true,"context":owned}

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
		var contract := Handlers.contract(str(binding.definition.get("handler_id","")))
		if contract.is_empty(): return false
		if not Compiler._mechanic_valid(binding.definition,{"capabilities":contract.capabilities,
			"handlers":[binding.definition.handler_id],"cost":{"commands_per_event":contract.commands,"states_per_target":contract.states}},authority,binding_errors) \
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
	if not _world.matches_world(_world_identity) or context.get("source_class") != _source_class \
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
	var value := {"contract_id":"hardcore.combat.damage_fact.v1",
		"fact_id":_release_id + ":hp:" + str(_entries.size()),"release_id":_release_id,"skill_id":_skill_id,"accepted_simulation_usec":_accepted_usec,
		"source_class":_source_class,"damage_channel":context.damage_channel,"requested_damage":requested,
		"hp_before":hp_before,"hp_after":hp_after,"actual_loss":hp_before-hp_after,"target_survived_commit":hp_after > 0,
		"target":target_ref.identity(),"source":source_identity,"historical_credit":_credit}
	if not _chain_context.is_empty():
		if not context.get("commit_ground_origin") is Dictionary:
			errors.append("damage_chain_commit_origin_missing"); return false
		value["chain_context"] = _chain_context
		value["commit_ground_origin"] = context.commit_ground_origin
	var fact := Graph.capture(value)
	if not bool(fact.success):
		errors.append("non_plain_damage_fact")
		return false
	var entry := {"fact":fact.value,"target":target_ref,"source":source_ref,"bindings":_bindings,
		"admission_id":_reservation.sequence() if _reservation != null else 0,"resource_lease":_resources}
	entry.make_read_only()
	_entries.append(entry)
	_facts.append(fact.value)
	return true

func facts() -> Array:
	var result: Array = _facts.duplicate(false)
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
	var result := _entries
	_entries = []
	_resources = null
	result.make_read_only()
	return result

func is_complete() -> bool:
	return _sealed

func reservation() -> RefCounted: return _reservation

func finish_production() -> void:
	if _reservation != null: _reservation.finish_batch()
	_resources = null

func _notification(what: int) -> void:
	# A claimed batch can be abandoned before sealing. Its last reference is
	# the exact terminal owner, even if an old action retains the closed ticket.
	if what == NOTIFICATION_PREDELETE and _reservation != null:
		_reservation.finish_batch()

func binding_count() -> int: return _bindings.size()

func event_bindings() -> Array: return _bindings
