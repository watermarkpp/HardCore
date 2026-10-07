extends RefCounted

const Cue := preload("res://scripts/features/presentation/ignite_cue.gd")
const Definitions := preload("res://scripts/features/presentation/cue_definitions.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const CUE_ID := &"hc_feature_cue_id"
const ONSET := &"hc_feature_cue_onset"
var _world: RefCounted
var _supported := true
var _nodes: Dictionary = {}
var _audio_handles: Dictionary = {}
var events: Array[Dictionary] = []

func configure(world: RefCounted, supported: bool = true) -> void:
	_world = world; _supported = supported

func _prepare(target: RefCounted, command: Dictionary, resources: RefCounted) -> Dictionary:
	var definition := Definitions.definition(str(command.get("cue_id", "")))
	if definition.is_empty() or command.get("cue_policy") != definition.policy: return {}
	var requirements := Definitions.requirements(command.cue_id)
	if not requirements.success: return {}
	if not requirements.paths.is_empty():
		if resources == null or resources.get_script() != Lease: return {}
		for path: String in requirements.paths:
			if resources.resource_at(path) == null: return {}
	var actor: Node = target.resolve() if target != null else null
	if actor == null: return {}
	var owner: Node = _world.current_world_owner() if _world != null else null
	var audio: Node = owner.get("_audio_runtime_service") if not requirements.records.is_empty() and owner != null else null
	if not requirements.records.is_empty() and (not is_instance_valid(audio) or not audio.has_method("play_prepared_event")): return {}
	return {"definition":definition, "requirements":requirements, "actor":actor, "audio":audio}

func _current(handle: String, cue: Node, onset: RefCounted) -> bool:
	return is_instance_valid(cue) and not cue.is_queued_for_deletion() and _nodes.has(handle) \
		and is_same(_nodes[handle].get_ref(), cue) and is_same(cue.get_meta(ONSET, null), onset)

func _play_onset(handle: String, cue: Node, onset: RefCounted, prepared: Dictionary, resources: RefCounted) -> void:
	var audio: Node = prepared.audio
	for record: Dictionary in prepared.requirements.records:
		if not _current(handle, cue, onset): return
		var request: Dictionary = audio.play_prepared_event(record.origin.event_id, resources.resource_at(record.path),
			{"feature_effect_handle":handle, "audio_owner_key":handle, "release_id":str(onset.get_instance_id())})
		if request.get("status") == "played":
			# The physical cue can be reused for a new accepted incarnation during
			# a synchronous notification. Identity of this onset must also match.
			if not _current(handle, cue, onset):
				if is_instance_valid(audio): audio.stop_prepared_event(request)
				return
			_audio_handles[handle] = {"service":weakref(audio), "request":request}

func start(handle: String, target: RefCounted, command: Dictionary, resources: RefCounted = null) -> bool:
	if _nodes.has(handle): return false
	var prepared := _prepare(target, command, resources)
	if prepared.is_empty(): return false
	_record("start", handle)
	if not _supported and prepared.definition.policy == "optional_procedural": return false
	var cue := Cue.new()
	var onset := RefCounted.new()
	cue.effect_handle = handle; cue.actor_ref = target; cue.strength = int(command.raw_per_tick)
	cue.resource_lease = resources if not prepared.requirements.paths.is_empty() else null
	cue.set_meta(CUE_ID, command.cue_id); cue.set_meta(ONSET, onset)
	# Tree-entry observers may retire or replace this onset synchronously.
	_nodes[handle] = weakref(cue)
	prepared.actor.add_child(cue)
	if not _current(handle, cue, onset): return true
	_play_onset(handle, cue, onset, prepared, resources)
	return true

func replace(handle: String, target: RefCounted, command: Dictionary, resources: RefCounted = null) -> bool:
	# Validate new accepted presentation before touching the old owner. This
	# consumes no resource request/get and never changes logical HP or timing.
	var prepared := _prepare(target, command, resources)
	if prepared.is_empty(): return false
	if not _supported and prepared.definition.policy == "optional_procedural":
		stop(handle)
		return false
	var cue: Node2D = _nodes[handle].get_ref() as Node2D if _nodes.has(handle) else null
	if not is_instance_valid(cue) or cue.is_queued_for_deletion():
		stop(handle)
		return start(handle, target, command, resources)
	var same_cue: bool = cue.get_meta(CUE_ID, "") == command.cue_id
	cue.actor_ref = target
	cue.resource_lease = resources if not prepared.requirements.paths.is_empty() else null
	if same_cue:
		# Preserve the original no-repeat sound policy for an unchanged cue,
		# while releasing the obsolete lease held by the previous state owner.
		refresh(handle, int(command.raw_per_tick))
		return true
	var old_audio: Dictionary = _audio_handles.get(handle, {})
	_audio_handles.erase(handle)
	var onset := RefCounted.new()
	cue.set_meta(CUE_ID, command.cue_id); cue.set_meta(ONSET, onset)
	cue.strength = int(command.raw_per_tick); cue.queue_redraw()
	_record("replace", handle)
	if not old_audio.is_empty():
		var old_service: Node = old_audio.service.get_ref()
		if is_instance_valid(old_service): old_service.stop_prepared_event(old_audio.request)
	if not _current(handle, cue, onset): return true
	_play_onset(handle, cue, onset, prepared, resources)
	return true

func refresh(handle: String, strength: int) -> void:
	_record("refresh", handle)
	if not _nodes.has(handle): return
	var cue: Node2D = _nodes[handle].get_ref() as Node2D
	if is_instance_valid(cue): cue.strength = strength; cue.queue_redraw()

func stop(handle: String) -> void:
	_record("stop", handle)
	var audio_owner: Dictionary = _audio_handles.get(handle, {})
	var cue: Node = _nodes[handle].get_ref() as Node if _nodes.has(handle) else null
	# Detach ownership before any external/native callback. A replacement
	# registered during retirement must not be erased by this old continuation.
	_audio_handles.erase(handle); _nodes.erase(handle)
	if not audio_owner.is_empty():
		var audio: Node = audio_owner.service.get_ref()
		if is_instance_valid(audio): audio.stop_prepared_event(audio_owner.request)
	if is_instance_valid(cue) and not cue.is_queued_for_deletion(): cue.queue_free()

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
	var event := {"kind":kind, "effect_handle":handle}
	event.make_read_only(); events.append(event)
