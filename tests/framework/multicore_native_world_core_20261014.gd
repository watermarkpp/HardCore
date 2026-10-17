extends RefCounted

var _host: Object
var _world: Object
var _actor: Object
var _other: Object
var _wall := RID()
var _identities: Array[Object] = []
var _checks: Array[Dictionary] = []
var _closed := false
var _done := false
var _owner := 0
var _points := PackedVector2Array()

func _check(value: bool, label: String) -> void:
	_checks.append({"pass":value,"label":label})

func _identity() -> int:
	# Canonical positive Object IDs, held and freed exclusively by S. These
	# fixture handles have no Nodes or model/HP state.
	var handle := Object.new()
	_identities.append(handle)
	return handle.get_instance_id()

func _config(position: Vector2, layer: int, mask: int) -> Dictionary:
	return {"position_screen_px":position,"footprint_points":_points,
		"collision_layer":layer,"collision_mask":mask,"motion_mode":1,"max_slides":6,"safe_margin":0.35}

func _init(host: Object, boot: Dictionary) -> void:
	_host = host
	_owner = OS.get_thread_caller_id()
	_points = boot.points
	_world = ClassDB.instantiate("HardCoreSimulationWorld2D")
	_check(_world.call("initialize", boot.area), "world initializes exact published default-area numbers on existing singleton")
	_actor = _world.call("create_actor", _identity(), _config(Vector2.ZERO, 2, 5))
	_other = _world.call("create_actor", _identity(), _config(Vector2(0, 100), 4, 7))
	_wall = _world.call("create_static_body", _identity(), Transform2D(0, Vector2(40, 0)),
		[{"type":PhysicsServer2D.SHAPE_RECTANGLE,"data":Vector2(2, 50)}], 1, 1)
	_check(_actor != null and _other != null and _wall.is_valid(), "two canonical actors and real static wall own original native RIDs")
	_check(_actor.call("get_canonical_id") == _identities[0].get_instance_id(), "collider identity binds original handle instead of RefCounted model ID")
	_check(is_equal_approx(float(_actor.call("safe_margin")), 0.35) and _actor.call("state").max_slides == 6, "floating player settings preserve source safe margin and max slides")

func _h_first() -> void:
	var start: Vector2 = _actor.call("position_screen_px")
	var tested: Dictionary = _actor.call("collide_motion", Vector2(100, 0), true, 0.35, false)
	_check(tested.ok and tested.collided and tested.collider_rid == _wall, "real RID motion query collides with world-layer wall")
	_check(tested.collider_id == _identities[2].get_instance_id(), "motion result preserves canonical collider ID")
	_check(_actor.call("position_screen_px") == start and _world.call("state").pending_transforms == 0, "test_only never changes logical transform or notification queue")
	_check((tested.travel + tested.remainder).is_equal_approx(Vector2(100, 0)), "original motion result retains travel plus remainder")
	var moved: Dictionary = _actor.call("collide_motion", Vector2(100, 0), false, 0.35, false)
	_check(moved.ok and moved.collided and _actor.call("position_screen_px").x > 0 and _actor.call("position_screen_px").x < 40, "move_and_collide applies shared correction and clips displacement")
	_actor.call("set_position_screen_px", Vector2(4, 0))
	_actor.call("set_position_screen_px", Vector2(5, 0))
	_other.call("set_position_screen_px", Vector2(2, 100))
	_actor.call("set_position_screen_px", Vector2(6, 0))
	_check(_world.call("state").pending_transforms == 2, "repeated logical writes deduplicate by original insertion order")
	_check(_world.call("flush_transforms", "fixture_original_force_update_transform"), "explicit source-mapped flush submits queued transforms")
	var flush: Dictionary = _world.call("state")
	_check(flush.pending_transforms == 0 and flush.last_flush_identities == PackedInt64Array([_identities[0].get_instance_id(), _identities[1].get_instance_id()]), "flush order remains first actor then second actor")
	_check(_world.call("set_collision_exception", _actor.call("get_body_rid"), _wall, true), "collision exceptions enter the original body pair filter")
	var excepted: Dictionary = _actor.call("collide_motion", Vector2(100, 0), true, 0.35, false)
	_check(excepted.ok and not excepted.collided, "actual motion honors registered exception")
	_world.call("set_collision_exception", _actor.call("get_body_rid"), _wall, false)
	_world.call("set_body_shape_disabled", _wall, 0, true)
	var disabled: Dictionary = _actor.call("collide_motion", Vector2(100, 0), true, 0.35, false)
	_check(disabled.ok and not disabled.collided, "disabled original shape no longer collides")
	_world.call("set_body_shape_disabled", _wall, 0, false)
	_actor.call("set_position_screen_px", Vector2(35, 0))
	var recovery_start: Vector2 = _actor.call("position_screen_px")
	var recovery: Dictionary = _actor.call("collide_motion", Vector2.ZERO, false, 0.35, true)
	_check(recovery.ok and recovery.collided and not recovery.travel.is_zero_approx(), "zero-motion recovery remains a real solver call with nonzero separation")
	_check(_actor.call("position_screen_px").is_equal_approx(recovery_start + recovery.travel), "zero recovery updates same authoritative controller pose")
	_actor.call("set_position_screen_px", Vector2(20, 0))
	_actor.call("set_velocity_screen_px_per_sec", Vector2(100, 50))
	var slid: Dictionary = _actor.call("slide", 0.25)
	_check(slid.ok and slid.collided and slid.slide_collisions.size() > 0 and slid.on_wall, "shared floating slide reports original wall flags and ordered collisions")
	_check(slid.position_screen_px.y > 0 and slid.position_screen_px.x < 40, "explicit delta floating slide preserves accepted tangential travel")
	_check(_actor.call("stop_velocity") and _actor.call("velocity_screen_px_per_sec") == Vector2.ZERO, "stop edits the shared motion state used by model pose reads")
	_world.call("flush_transforms", "fixture_H_tail_pre_step")

func _p_first() -> void:
	var ray: Dictionary = _world.call("intersect_ray", Vector2(0, -20), Vector2(100, -20), 1)
	_check(ray.ok and ray.collided and ray.rid == _wall and ray.collider_id == _identities[2].get_instance_id(), "original P-phase numeric ray retains RID and canonical identity after actual step")
	var direct: PhysicsDirectSpaceState2D = PhysicsServer2D.space_get_direct_state(_world.call("state").space_rid)
	var parameters := PhysicsRayQueryParameters2D.create(Vector2(0, -20), Vector2(100, -20), 1)
	var original := direct.intersect_ray(parameters)
	_check(original.collider == _identities[2] and original.collider_id == ray.collider_id and original.rid == ray.rid and original.position == ray.position and original.normal == ray.normal and original.shape == ray.shape, "numeric ray matches original exact same-loop geometry and identity; original resolves only fixture S handle")
	var excluded: Dictionary = _world.call("intersect_ray", Vector2(0, -20), Vector2(100, -20), 1, [_wall])
	_check(excluded.ok and not excluded.collided, "numeric ray uses original exclude list")
	var inside: Dictionary = _world.call("intersect_ray", Vector2(40, 0), Vector2(100, 0), 1, [], true, false, true)
	_check(inside.ok and inside.collided and inside.position == Vector2(40, 0) and inside.normal == Vector2.ZERO, "ray hit_from_inside retains original zero-normal branch")
	var p_motion: Dictionary = _actor.call("collide_motion", Vector2.ZERO, true, 0.35, true)
	_check(p_motion.ok, "P timer/release phase supports original live body motion queries")
	_world.call("flush_transforms", "fixture_P_timer_original_flush")

func on_phase(name: String, frame: Dictionary) -> bool:
	if name == "H_GROUP" and frame.epoch == 1: _h_first()
	if name == "P_GROUP" and frame.epoch == 1: _p_first()
	if name == "H_GROUP" and frame.epoch == 2:
		# Native kinematic transform integration occurred during preceding step.
		_actor.call("set_position_screen_px", Vector2(-100, -100))
		_other.call("set_position_screen_px", Vector2(-120, -100))
		_world.call("flush_transforms", "fixture_second_H_tail")
	if name == "P_GROUP" and frame.epoch == 2:
		var peer: Dictionary = _other.call("collide_motion", Vector2(100, 0), true, 0.35, false)
		_check(peer.ok and peer.collided and peer.collider_id == _identities[0].get_instance_id(), "enemy mask seven sees player layer two after integrated kinematic pose")
		_world.call("set_body_collision_filters", _other.call("get_body_rid"), 0, 1)
		var ghost: Dictionary = _other.call("collide_motion", Vector2(100, 0), true, 0.35, false)
		_check(ghost.ok and not ghost.collided, "explicit existing ghost mask filters actor while preserving world collision")
		_other.call("set_position_screen_px", Vector2(-140, -100))
		_check(_world.call("retire_actor", _identities[1].get_instance_id()), "actor retirement removes pending adapter before freeing its RID and shape")
		_other = null
		_check(_world.call("state").pending_transforms == 0 and _world.call("state").body_count == 2, "retirement leaves no stale transform pointer or body registration")
		_check(_world.call("retire_body", _wall), "static retirement frees attached shape through same owner")
		_check(_world.call("close"), "full world retirement frees remaining actor and space on S")
		_closed = true
		_actor = null
		_world = null
		_done = true
	if name == "PUBLISH":
		return _host.call("publish_snapshot", {"done":_done,"owner":_owner,"checks":_checks}, [])
	return OS.get_thread_caller_id() == _owner

func on_inputs(_domain: String, _packets: Array) -> bool:
	return OS.get_thread_caller_id() == _owner

func close_session() -> bool:
	if _world != null and not _closed:
		_closed = _world.call("close")
	_actor = null
	_other = null
	_world = null
	for handle: Object in _identities: handle.free()
	_identities.clear()
	_host = null
	return _closed and OS.get_thread_caller_id() == _owner
