extends RefCounted

const Cue := preload("res://scripts/features/presentation/ignite_cue.gd")
const Definitions := preload("res://scripts/features/presentation/cue_definitions.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
var _world: RefCounted
var _supported := true
var _nodes: Dictionary = {}
var _audio_handles: Dictionary = {}
var events: Array[Dictionary] = []
func configure(world: RefCounted, supported: bool = true) -> void:
	_world = world; _supported = supported
func start(handle: String, target: RefCounted, command: Dictionary, resources: RefCounted = null) -> bool:
	var definition := Definitions.definition(str(command.get("cue_id", "")))
	if definition.is_empty() or command.get("cue_policy") != definition.policy or _nodes.has(handle): return false
	var requirements := Definitions.requirements(command.cue_id)
	if not requirements.success: return false
	if not requirements.paths.is_empty():
		if resources == null or resources.get_script() != Lease: return false
		for path: String in requirements.paths:
			if resources.resource_at(path) == null: return false
	_record("start",handle)
	# Optional decoration may be suppressed. A required readability cue still
	# creates its actual CanvasItem, including in CPU-only headless validation.
	if not _supported and definition.policy == "optional_procedural": return false
	var actor: Node = target.resolve()
	if actor == null: return false
	var owner: Node = _world.current_world_owner()
	var audio: Node = owner.get("_audio_runtime_service") if not requirements.records.is_empty() and owner != null else null
	if not requirements.records.is_empty() and (not is_instance_valid(audio) or not audio.has_method("play_prepared_event")): return false
	var cue := Cue.new()
	cue.effect_handle = handle; cue.actor_ref = target; cue.strength = int(command.raw_per_tick)
	if not requirements.paths.is_empty(): cue.resource_lease = resources
	# Tree-entry notifications may synchronously retire or replace this onset.
	# Publish ownership before attaching, then qualify it again before audio.
	_nodes[handle] = weakref(cue)
	actor.add_child(cue)
	if not is_instance_valid(cue) or not _nodes.has(handle) \
		or not is_same(_nodes[handle].get_ref(), cue) or cue.is_queued_for_deletion():
		return true
	for record: Dictionary in requirements.records:
		var request: Dictionary = audio.play_prepared_event(record.origin.event_id,resources.resource_at(record.path),
			{"feature_effect_handle":handle,"audio_owner_key":handle,"release_id":str(cue.get_instance_id())})
		if request.get("status") == "played":
			# Playback notification can synchronously retire this effect. The
			# returned request belongs to the old onset, never a replacement cue.
			if not _nodes.has(handle) or not is_same(_nodes[handle].get_ref(),cue) or cue.is_queued_for_deletion():
				if is_instance_valid(audio): audio.stop_prepared_event(request)
				return true
			_audio_handles[handle] = {"service":weakref(audio),"request":request}
	return true
func refresh(handle: String, strength: int) -> void:
	_record("refresh",handle)
	if not _nodes.has(handle): return
	var cue: Node2D = _nodes[handle].get_ref() as Node2D
	if is_instance_valid(cue): cue.strength = strength; cue.queue_redraw()
func stop(handle: String) -> void:
	_record("stop",handle)
	if _audio_handles.has(handle):
		var value: Dictionary = _audio_handles[handle]
		var audio: Node = value.service.get_ref()
		if is_instance_valid(audio): audio.stop_prepared_event(value.request)
		_audio_handles.erase(handle)
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
