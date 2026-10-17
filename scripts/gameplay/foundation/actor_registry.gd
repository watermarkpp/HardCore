extends RefCounted

const Handle := preload("res://scripts/gameplay/foundation/actor_handle.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const WorldClockLedger := preload("res://scripts/world_monster_clock_ledger.gd")
const WORLD_CONTRACT := "hardcore.execution.world_context.v1"
const KINDS := [&"player", &"enemy", &"summon", &"projectile", &"field", &"loot", &"npc", &"zone_portal"]

var _owner_thread := OS.get_thread_caller_id()
var _world: Dictionary = {}
var _profile: Dictionary = {}
var _actors: Dictionary = {}
var _leases: Dictionary = {}
var _next_lease := 1

func _owned() -> bool:
	var valid := OS.get_thread_caller_id() == _owner_thread
	assert(valid, "actor registry accessed outside its simulation owner")
	return valid

# The original Root has map -1 / generation 0 before the first arrival.
# Admitting that identity creates no geometry or positive combat-life claim.
func configure_world(world: Dictionary, world_clock_generation: String) -> bool:
	if not _owned() or not _actors.is_empty() or not _leases.is_empty() \
		or world.size() != 5 or world.get("contract_id") != WORLD_CONTRACT \
		or not world.get("world_runtime_id") is int or world.world_runtime_id <= 0 \
		or not world.get("world_epoch") is int or world.world_epoch < 0 \
		or not world.get("runtime_map_id") is int \
		or (world.runtime_map_id < 0 and not (world.runtime_map_id == -1 and world.world_epoch == 0 and (_world.is_empty() or _world == world))) \
		or not world.get("profile_id") is String or world.profile_id.is_empty() \
		or not WorldClockLedger.valid_generation(world_clock_generation):
		return false
	var captured := Graph.capture(world)
	if not captured.success:
		return false
	_world = captured.value
	_profile = Graph.capture({"profile_id":world.profile_id,"world_clock_generation":world_clock_generation}).value
	return true

func capture_world() -> Dictionary:
	return _world if _owned() else {}

func rebind_world_with_player(runtime_id: int, world: Dictionary, world_clock_generation: String) -> bool:
	if not _owned() or runtime_id <= 0 or _world.is_empty() or world.size() != 5 \
		or world.get("contract_id") != WORLD_CONTRACT \
		or world.get("world_runtime_id") != _world.world_runtime_id \
		or world.get("profile_id") != _world.profile_id \
		or not world.get("world_epoch") is int or world.world_epoch <= int(_world.world_epoch) \
		or not world.get("runtime_map_id") is int or world.runtime_map_id < 0 \
		or not WorldClockLedger.valid_generation(world_clock_generation):
		return false
	var player: Object = resolve_runtime_actor(runtime_id)
	if player == null or player.kind() != &"player" or player.is_inside_world() or player.is_queued_for_retirement():
		return false
	for other_id: int in _actors:
		if other_id == runtime_id: continue
		var actor: Object = _actors[other_id]
		if is_instance_valid(actor) and actor.runtime_object_is_present(): return false
	var captured := Graph.capture(world)
	if not captured.success or not player.rebind_world_while_detached(captured.value): return false
	_world = captured.value
	_profile = Graph.capture({"profile_id":world.profile_id,"world_clock_generation":world_clock_generation}).value
	return true

func capture_profile() -> Dictionary:
	return _profile if _owned() else {}

func capture_attached_player_map_arrival_identity(runtime_id: int, before: Dictionary, after: Dictionary) -> Dictionary:
	if not _owned() or _world != before or _world.is_empty(): return {}
	var player: Object = resolve_runtime_actor(runtime_id)
	return player.capture_attached_player_map_arrival_identity(before,after) if player != null else {}

func can_commit_attached_player_map_arrival(runtime_id: int, before: Dictionary, after: Dictionary, player_identity: Dictionary) -> bool:
	if not _owned() or _world != before or _world.is_empty() or not _unconfigured_births.is_empty(): return false
	var player: Object = resolve_runtime_actor(runtime_id)
	var actual: Dictionary = capture_attached_player_map_arrival_identity(runtime_id,before,after)
	if player == null or actual.is_empty() or actual != player_identity: return false
	for other_id: int in _actors:
		if other_id == runtime_id: continue
		var actor: Object = _actors[other_id]
		# Retained old actors keep their original world until actual exit/free.
		# Their leases and callbacks are debts, not reasons to discard them here.
		if is_instance_valid(actor) and not actor.is_queued_for_retirement(): return false
	return Graph.capture(after).success

func commit_attached_player_map_arrival(runtime_id: int, before: Dictionary, after: Dictionary, player_identity: Dictionary) -> bool:
	if not can_commit_attached_player_map_arrival(runtime_id,before,after,player_identity): return false
	var captured := Graph.capture(after)
	if not captured.success: return false
	var player: Object = resolve_runtime_actor(runtime_id)
	# No yield or callbacks between the complete validation and this mutation.
	if not player.rebind_attached_player_at_map_arrival(before,captured.value,player_identity): return false
	_world = captured.value
	return true

func matches_world(identity: Dictionary) -> bool:
	return _owned() and not _world.is_empty() and identity == _world

func matches_profile(identity: Dictionary) -> bool:
	return _owned() and not _profile.is_empty() and identity == _profile

func register_actor(model: Object, life: int, kind: StringName, stable_order: int) -> Object:
	if not _owned() or _world.is_empty() or not is_instance_valid(model) \
		or model is Node or model is Resource or life < 0 or kind not in KINDS or stable_order < 0:
		return null
	if model.has_method("current_life"):
		var model_life: Variant = model.call("current_life")
		if not model_life is int or model_life != life:
			return null
	if life == 0 and not _original_precombat_player_runtime(model, kind):
		return null
	var actor: Object = Handle.new(_world, model, life, kind, stable_order)
	var runtime_id := actor.get_instance_id()
	if runtime_id <= 0 or _actors.has(runtime_id):
		actor.free()
		return null
	_actors[runtime_id] = actor
	return actor

func _original_precombat_player_runtime(model: Object, kind: StringName) -> bool:
	# Original Player._ready precedes begin_combat_transition. Its ObjectID
	# exists while combat_epoch is zero; ActorRef.capture must still reject it.
	# This does not extend Enemy's separately reserved setup-life protocol.
	if kind != &"player" or _world.runtime_map_id != -1 or _world.world_epoch != 0:
		return false
	var source: Script = model.get_script()
	if source == null or source.resource_path != "res://scripts/gameplay/actors/player_actor_model.gd" \
		or not model.has_method("current_life") or model.current_life() != 0 \
		or not model.has_method("runtime_actor_id") or model.get("_runtime_actor_id") != 0:
		return false
	for existing: Object in _actors.values():
		if is_instance_valid(existing) and existing.kind() == &"player": return false
	return true

func capture_actor_identity(actor: Object) -> Dictionary:
	if not _owned() or not is_instance_valid(actor) or _actors.get(actor.get_instance_id()) != actor \
		or not bool(actor.call("is_registered")):
		return {}
	return actor.call("identity")

func resolve_actor_identity(identity: Dictionary, require_alive := true) -> Object:
	if not _owned() or identity.size() != 3 or not identity.get("world") is Dictionary \
		or not matches_world(identity.world) or not identity.get("runtime_id") is int \
		or identity.runtime_id <= 0 or not identity.get("life_generation") is int or identity.life_generation <= 0:
		return null
	var actor: Object = _actors.get(identity.runtime_id)
	if not is_instance_valid(actor) or not bool(actor.call("is_registered")) or actor.call("identity") != identity:
		return null
	if require_alive and not bool(actor.call("can_receive_damage")):
		return null
	return actor

func retain_actor(identity: Dictionary) -> int:
	var actor := resolve_actor_identity(identity, false)
	return retain_runtime_actor(actor.get_instance_id()) if actor != null else 0

func resolve_runtime_actor(runtime_id: int) -> Object:
	if not _owned() or runtime_id <= 0:
		return null
	var actor: Object = _actors.get(runtime_id)
	return actor if is_instance_valid(actor) and bool(actor.call("runtime_object_is_present")) else null

func retain_runtime_actor(runtime_id: int) -> int:
	var actor := resolve_runtime_actor(runtime_id)
	if actor == null or _next_lease <= 0 or not bool(actor.call("retain_lease")):
		return 0
	var token := _next_lease
	_next_lease += 1
	_leases[token] = actor.get_instance_id()
	return token

func release_actor(token: int) -> bool:
	if not _owned() or not _leases.has(token):
		return false
	var runtime_id: int = _leases[token]
	var actor: Object = _actors.get(runtime_id)
	if not is_instance_valid(actor) or not bool(actor.call("release_lease")):
		return false
	_leases.erase(token)
	_destroy_retired(runtime_id)
	return true

func retire_actor(identity: Dictionary) -> bool:
	var actor := resolve_actor_identity(identity, false)
	return retire_runtime_actor(actor.get_instance_id()) if actor != null else false

func retire_runtime_actor(runtime_id: int) -> bool:
	var actor := resolve_runtime_actor(runtime_id)
	if actor == null or not bool(actor.call("begin_retirement")):
		return false
	_destroy_retired(runtime_id)
	return true

func _destroy_retired(runtime_id: int) -> void:
	var actor: Object = _actors.get(runtime_id)
	if is_instance_valid(actor) and bool(actor.call("can_destroy")):
		_actors.erase(runtime_id)
		actor.free()

func remaining_actor_count() -> int:
	return _actors.size() if _owned() else -1

func remaining_lease_count() -> int:
	return _leases.size() if _owned() else -1

func retire_world() -> bool:
	if not _owned():
		return false
	for runtime_id: int in _actors.keys():
		var actor: Object = _actors[runtime_id]
		if bool(actor.call("runtime_object_is_present")):
			actor.call("begin_retirement")
		_destroy_retired(runtime_id)
	return _actors.is_empty() and _leases.is_empty()


# Source Enemy.new() precedes setup's first positive life write. Reserve its
# Object Handle/native body without admitting any ActorRef or storage lease.
var _unconfigured_births: Dictionary = {}
func reserve_unconfigured_actor(model: Object, kind: StringName, stable_order: int) -> Object:
	if not _owned() or _world.is_empty() or model is Node or model is Resource or kind != &"enemy" or stable_order < 0 or not model.has_method("current_life") or model.current_life() != 0: return null
	var actor: Object = Handle.new(_world, model, 0, kind, stable_order)
	if not actor.mark_original_birth_unconfigured():
		actor.free()
		return null
	_unconfigured_births[actor.get_instance_id()] = actor
	return actor
func commit_reserved_actor(actor: Object) -> bool:
	if not _owned() or _unconfigured_births.get(actor.get_instance_id()) != actor or _actors.has(actor.get_instance_id()): return false
	if not actor.commit_original_birth_life(): return false
	_unconfigured_births.erase(actor.get_instance_id())
	_actors[actor.get_instance_id()] = actor
	return true
func discard_reserved_actor(actor: Object) -> bool:
	if not _owned() or _unconfigured_births.get(actor.get_instance_id()) != actor: return false
	_unconfigured_births.erase(actor.get_instance_id())
	actor.free()
	return true
func reserved_birth_count() -> int: return _unconfigured_births.size()

func is_reserved_birth(actor: Object) -> bool: return _owned() and actor != null and _unconfigured_births.get(actor.get_instance_id()) == actor
