extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const LIFE_METADATA := "metadata:hc_combat_life_epoch"
const LIFE_PLAYER := "property:combat_epoch"
var _world: RefCounted
var _actor := WeakRef.new()
var _identity: Dictionary = {}
var _life_authority := ""

static func capture(world: RefCounted, actor: Node, life_authority: String = LIFE_METADATA) -> RefCounted:
	if world == null or not is_instance_valid(actor) or actor.is_queued_for_deletion() or not actor.is_inside_tree() \
		or life_authority not in [LIFE_METADATA,LIFE_PLAYER]:
		return null
	var owner: Node = world.current_world_owner()
	if owner == null or not owner.is_ancestor_of(actor):
		return null
	var world_identity: Dictionary = world.capture_world()
	if world_identity.is_empty():
		return null
	var life := int(actor.get_meta("hc_combat_life_epoch", 0)) if life_authority == LIFE_METADATA else int(actor.get("combat_epoch"))
	if life <= 0:
		return null
	var result := new()
	result._world = world
	result._actor = weakref(actor)
	result._life_authority = life_authority
	result._identity = Graph.capture({"world":world_identity,"runtime_id":actor.get_instance_id(),"life_generation":life}).value
	return result

func identity() -> Dictionary:
	return _identity

func resolve(require_alive := true) -> Node:
	if _identity.is_empty() or _world == null or not _world.matches_world(_identity.world):
		return null
	var actor: Node = _actor.get_ref() as Node
	if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not actor.is_inside_tree():
		return null
	var owner: Node = _world.current_world_owner()
	if owner == null or not owner.is_ancestor_of(actor):
		return null
	var life := int(actor.get_meta("hc_combat_life_epoch", 0)) if _life_authority == LIFE_METADATA else int(actor.get("combat_epoch"))
	if actor.get_instance_id() != int(_identity.runtime_id) or life != int(_identity.life_generation):
		return null
	if require_alive and (int(actor.get("current_hp")) <= 0 \
		or (actor.has_method("can_receive_damage") and not bool(actor.call("can_receive_damage")))):
		return null
	return actor
