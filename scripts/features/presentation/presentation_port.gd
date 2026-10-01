extends RefCounted

const Cue := preload("res://scripts/features/presentation/ignite_cue.gd")
const CUE_ID := "hc.cue.ignite.v1"
var _world: RefCounted
var _supported := true
var _nodes: Dictionary = {}
var events: Array[Dictionary] = []
func configure(world: RefCounted, supported: bool = true) -> void:
	_world = world; _supported = supported
func start(handle: String, target: RefCounted, command: Dictionary) -> bool:
	if command.get("cue_id") != CUE_ID or command.get("cue_policy") != "optional_procedural" or _nodes.has(handle): return false
	_record("start",handle)
	if not _supported: return false
	var actor: Node = target.resolve()
	if actor == null: return false
	var cue := Cue.new()
	cue.effect_handle = handle; cue.actor_ref = target; cue.strength = int(command.raw_per_tick)
	actor.add_child(cue)
	_nodes[handle] = weakref(cue)
	return true
func refresh(handle: String, strength: int) -> void:
	_record("refresh",handle)
	if not _nodes.has(handle): return
	var cue: Node2D = _nodes[handle].get_ref() as Node2D
	if is_instance_valid(cue): cue.strength = strength; cue.queue_redraw()
func stop(handle: String) -> void:
	_record("stop",handle)
	if not _nodes.has(handle): return
	var cue: Node = _nodes[handle].get_ref() as Node
	if is_instance_valid(cue) and not cue.is_queued_for_deletion(): cue.queue_free()
	_nodes.erase(handle)
func clear() -> void:
	for handle: String in _nodes.keys(): stop(handle)
func node_count() -> int:
	var count := 0
	for reference: WeakRef in _nodes.values():
		var cue: Node = reference.get_ref() as Node
		if is_instance_valid(cue) and not cue.is_queued_for_deletion(): count += 1
	return count
func _record(kind: String, handle: String) -> void:
	# Bounded structural telemetry; it never owns effects or changes damage.
	if events.size() >= 256: events.pop_front()
	var event := {"kind":kind,"effect_handle":handle}
	event.make_read_only(); events.append(event)
