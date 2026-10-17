extends RefCounted

## Actual S native static-body adapter. Identity allocation and retirement ledger
## are required WorldCore services. This class stores only body RID ownership;
## there is no independent actor identity, HP, physics space or frame authority.
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var _native: Object
var _world_ref: WeakRef
var _world: Object:
	get:
		return _world_ref.get_ref() if _world_ref != null else null
	set(value):
		_world_ref = weakref(value) if value != null else null
var _bodies: Dictionary = {}
var _retiring: Dictionary = {}
var _gothic_ids: Array[int] = []
var _gothic_entries: Array = []
var _gothic_generation := -1

func owner_thread_id() -> int:
	return _owner_thread

func configure_owner(native_world: Object, world: Object) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread:
		return false
	if native_world == null or native_world is Node or native_world is Resource or not native_world.is_class("HardCoreSimulationWorld2D"):
		push_error("Environment bodies require actual native S simulation world")
		return false
	for method: String in ["state", "create_static_body", "retire_body"]:
		if not native_world.has_method(method):
			return false
	if world == null or world is Node or world is Resource or not world.has_method("owner_thread_id") or world.owner_thread_id() != _owner_thread:
		return false
	for method: String in ["fault", "allocate_environment_body_id", "enqueue_environment_body_retirement"]:
		if not world.has_method(method):
			return false
	var state: Dictionary = native_world.state()
	if not bool(state.get("ok", false)) or int(state.get("owner_thread", -1)) != _owner_thread:
		world.fault("environment_native_owner_mismatch", state)
		return false
	_native = native_world
	_world = world
	_configured = true
	return true

func create_environment_static_body(transform: Transform2D, shapes: Array[Dictionary], layer: int, mask: int, metadata: Dictionary) -> Dictionary:
	if not _configured or OS.get_thread_caller_id() != _owner_thread:
		return {"ok": false, "created": false}
	var id: int = _world.allocate_environment_body_id(metadata)
	if id <= 0 or _bodies.has(id):
		_world.fault("environment_body_identity_rejected", {"id": id, "metadata": metadata})
		return {"ok": false, "created": false}
	var body: RID = _native.create_static_body(id, transform, shapes, layer, mask)
	if not body.is_valid():
		_world.fault("environment_native_static_creation_rejected", {"id": id, "metadata": metadata})
		return {"ok": false, "created": false}
	_bodies[id] = {"rid": body, "metadata": metadata}
	return {"ok": true, "created": true, "id": id}

func retire_environment_static_body(id: int) -> bool:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or not _bodies.has(id) or _retiring.has(id):
		return false
	if not _world.enqueue_environment_body_retirement(id):
		_world.fault("environment_retirement_ledger_rejected", {"id": id})
		return false
	_retiring[id] = true
	return true

func retire_original_map_environment() -> bool:
	if not _configured or OS.get_thread_caller_id() != _owner_thread: return false
	# Queue the same actual bodies for the original delete checkpoint. Do not
	# step/sync/flush physics, free actor bodies, or close this persistent adapter.
	for id: int in _bodies:
		if not _retiring.has(id) and not retire_environment_static_body(id): return false
	_gothic_ids.clear(); _gothic_entries.clear(); _gothic_generation = -1
	return true

## WorldCore calls this once at the original queued-deletion checkpoint. No
## flush/step/sync/timer or cancellation delay is created by this adapter.
func commit_environment_body_retirement(id: int) -> bool:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or not _retiring.has(id) or not _bodies.has(id):
		return false
	var body: RID = _bodies[id].rid
	if not _native.retire_body(body):
		_world.fault("environment_native_retirement_rejected", {"id": id})
		return false
	_retiring.erase(id)
	_bodies.erase(id)
	return true

## Called at original GothicBichCampBuilder.build prop/collision registration
## positions after Main has published its exact sprite-qualified collision list.
func register_gothic_environment_bodies(entries: Array, generation: int) -> bool:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or not _gothic_ids.is_empty():
		return false
	for entry: Dictionary in entries:
		var position: Vector2 = entry.get("position", Vector2.ZERO)
		var definition: Dictionary = entry.get("definition", {})
		var shape: Dictionary
		if str(definition.get("type", "")) == "circle":
			shape = {"type": PhysicsServer2D.SHAPE_CIRCLE, "data": float(definition.get("radius", 16.0))}
		else:
			var raw: Variant = definition.get("size", [32, 20])
			var size := Vector2.ZERO
			if raw is Array and raw.size() >= 2:
				size = Vector2(float(raw[0]), float(raw[1]))
			shape = {"type": PhysicsServer2D.SHAPE_RECTANGLE, "data": size * 0.5}
		var shapes: Array[Dictionary] = [shape]
		var result := create_environment_static_body(Transform2D(0.0, position), shapes, 1, 0,
			{"gothic_bich_camp": true, "generation": generation})
		if not result.ok:
			return false
		_gothic_ids.append(result.id)
	_gothic_entries = entries.duplicate(true)
	_gothic_generation = generation
	return true

func ensure_gothic_environment_bodies(entries: Array, generation: int) -> Dictionary:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or generation != _gothic_generation or entries != _gothic_entries or _gothic_ids.is_empty():
		_world.fault("environment_gothic_bodies_not_registered_at_prop_stage", {"generation": generation})
		return {"ok": false, "created": false}
	# Original _build_gothic_camp_collisions returns the first already-built body.
	return {"ok": true, "created": false, "id": _gothic_ids[0]}

func close_at_original_boundary() -> bool:
	if not _configured or OS.get_thread_caller_id() != _owner_thread or not _retiring.is_empty():
		return false
	for id: int in _bodies:
		if not _native.retire_body(_bodies[id].rid):
			_world.fault("environment_native_close_retirement_rejected", {"id": id})
			return false
	_bodies.clear()
	_gothic_ids.clear()
	_gothic_entries.clear()
	_gothic_generation = -1
	_configured = false
	return true
