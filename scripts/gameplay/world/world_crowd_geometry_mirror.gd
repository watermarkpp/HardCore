extends RefCounted

## Transport-only mirror, written at the existing authoritative pose commit.
## It performs no spatial query, actor eligibility or position getter.
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _rows: Dictionary = {}
var _order: Array[int] = []
var _generation := 1

func _init(world: RefCounted) -> void: _world = weakref(world)
func owner_thread_id() -> int: return _owner

func commit(handle: Object, view: Dictionary, margin: float, map_identity: int) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	if handle == null or map_identity <= 0 or not is_finite(margin) or margin < 0.0: return false
	var identity: Dictionary = handle.identity()
	var id := handle.get_instance_id()
	if id <= 0 or not view.get("position_ground_gu") is Vector2 or not view.position_ground_gu.is_finite() or not view.get("combat_radius_gu") is float: return false
	var radius: float = view.combat_radius_gu
	if not is_finite(radius) or radius < 0.0: return false
	var old: Dictionary = _rows.get(id, {})
	var life: int = identity.life_generation
	var world: Dictionary = identity.world
	var changed: bool = old.is_empty() or old.life != life or old.map != world.runtime_map_id or old.world_context != world or old.map_instance_identity != map_identity
	var pose_revision := int(view.pose_revision)
	var radius_revision := int(old.get("radius_revision", 0))
	if changed or old.get("radius") != radius or old.get("margin") != margin: radius_revision += 1
	if old.is_empty(): _order.append(id)
	_generation += 1
	_rows[id] = {"runtime_id": id, "life": life, "pose_revision": pose_revision,
		"radius_revision": radius_revision, "map": int(world.runtime_map_id),
		"position": view.position_ground_gu, "radius": radius, "margin": margin,
		"world_context": world, "map_instance_identity": map_identity}
	return true

func remove(runtime_id: int) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	if _rows.erase(runtime_id):
		_order.erase(runtime_id)
		_generation += 1

func _scope(map_id: int) -> Dictionary:
	var world: RefCounted = _world.get_ref()
	return {"world_context": world.current_world_identity(),
		"world_generation": world.world_clock_generation(),
		"map_instance_identity": world.runtime_map_instance_identity(map_id),
		"geometry_generation": _generation}

func freeze(map_id: int) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	var scope := _scope(map_id)
	if int(scope.map_instance_identity) <= 0:
		_world.get_ref().fault("crowd_map_identity_absent", {"map": map_id})
		return {"ok": false}
	var peers: Array[Dictionary] = []
	for id: int in _order:
		var row: Dictionary = _rows[id]
		if int(row.map) != map_id or row.world_context != scope.world_context: continue
		var copy := row.duplicate(false)
		copy["scope"] = scope
		copy.make_read_only()
		peers.append(copy)
	scope.make_read_only()
	peers.make_read_only()
	return {"ok": true, "scope": scope, "geometry_generation": _generation, "peers": peers}

func stamp(runtime_id: int) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	if not _rows.has(runtime_id):
		_world.get_ref().fault("crowd_pose_mirror_missing", {"runtime_id": runtime_id})
		return {"ok": false}
	var row: Dictionary = _rows[runtime_id].duplicate(false)
	var current: Dictionary = _world.get_ref().current_world_identity()
	# A retained old actor/readset is stale. Never relabel its original row as
	# a current-world stamp, including a later visit to the same numeric map.
	if row.world_context != current or int(row.map) != int(current.runtime_map_id): return {"ok":false}
	row["scope"] = _scope(int(row.map))
	row["ok"] = true
	row.make_read_only()
	return row
