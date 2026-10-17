extends RefCounted

## Real Host-owned S component. Bodies carry the production positive ObjectID
## contract. Only the test model is RefCounted; no body Object or query crosses M.
var _host: Object
var _world: Object
var _owner := OS.get_thread_caller_id()
var _identities: Array[Object] = []
var _bodies: Array[RID] = []
var _area := RID()
var _area_shape := RID()
var _query_circle := RID()
var _query_rectangle := RID()
var _query: PhysicsShapeQueryParameters2D
var _checks: Array[Dictionary] = []
var _done := false
var _closed := false
var _empty_cases := 0
var _blocked_cases := 0
var _comparisons := 0

func _check(value: bool, label: String) -> void: _checks.append({"pass":value,"label":label})
func _identity() -> int:
	var identity := Object.new()
	_identities.append(identity)
	_check(identity.get_instance_id() > 0,"actual Source Object preserves production full positive canonical ID")
	return identity.get_instance_id()

func _init(host: Object, boot: Dictionary) -> void:
	_host = host
	_check(_owner != OS.get_main_thread_id(),"test model born on actual Native Host S thread")
	_world = ClassDB.instantiate("HardCoreSimulationWorld2D")
	_check(_world.initialize(boot.area),"same actual singleton backend and Native space initialized on S")
	_bodies.append(_world.create_static_body(_identity(),Transform2D(0,Vector2.ZERO),[{"type":PhysicsServer2D.SHAPE_CIRCLE,"data":8.0}],1,1))
	_bodies.append(_world.create_static_body(_identity(),Transform2D(0,Vector2(40,0)),[{"type":PhysicsServer2D.SHAPE_RECTANGLE,"data":Vector2(8,12)}],4,1))
	_check(_bodies[0].is_valid() and _bodies[1].is_valid(),"circle and rectangle are real NativeWorld-owned static bodies")
	# Real optional area exercises collide_with_areas independently of bodies.
	# Its RID/shape and canonical Object are owned and freed by this same S model.
	_area_shape = PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(_area_shape,5.0)
	_area = PhysicsServer2D.area_create()
	PhysicsServer2D.area_attach_object_instance_id(_area,_identity())
	PhysicsServer2D.area_set_collision_layer(_area,16)
	PhysicsServer2D.area_set_collision_mask(_area,0)
	PhysicsServer2D.area_add_shape(_area,_area_shape)
	PhysicsServer2D.area_set_transform(_area,Transform2D(0,Vector2(80,0)))
	PhysicsServer2D.area_set_space(_area,_world.state().space_rid)
	_query_circle = PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(_query_circle,6.0)
	_query_rectangle = PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(_query_rectangle,Vector2(3,5))
	_query = PhysicsShapeQueryParameters2D.new()
	_check(_area.is_valid() and _query_circle.is_valid() and _query_rectangle.is_valid(),"all extra query/area RIDs are real and remain on S")

func _query_facts() -> Dictionary:
	return {"shape_rid":_query.shape_rid,"transform":_query.transform,"motion":_query.motion,"margin":_query.margin,"mask":_query.collision_mask,"bodies":_query.collide_with_bodies,"areas":_query.collide_with_areas,"exclude":_query.exclude.duplicate(),"query_id":_query.get_instance_id()}
func _compare(label: String, center: Vector2, shape: RID, mask: int, margin: float=0.0, bodies: bool=true, areas: bool=false, excluded: Array[RID]=[], motion: Vector2=Vector2.ZERO, rotation: float=0.0, expected_empty: Variant=null) -> void:
	_check(OS.get_thread_caller_id() == _owner,"same S owner for "+label)
	_query.shape_rid = shape
	_query.transform = Transform2D(rotation,center)
	_query.motion = motion
	_query.margin = margin
	_query.collision_mask = mask
	_query.collide_with_bodies = bodies
	_query.collide_with_areas = areas
	_query.exclude = excluded
	var facts := _query_facts()
	var space: RID = _world.state().space_rid
	var direct: PhysicsDirectSpaceState2D = PhysicsServer2D.space_get_direct_state(space)
	_check(direct != null,"actual same-space direct state for "+label)
	if direct == null: return
	# Reference resolves only this fixture's actual S-owned identities. No Main
	# Node, model or published Object enters either query. Maximum remains one.
	var reference: Array[Dictionary] = direct.intersect_shape(_query,1)
	_check(reference.size() <= 1,"reference maximum one for "+label)
	for hit: Dictionary in reference:
		_check(hit.collider in _identities and hit.collider_id == hit.collider.get_instance_id(),"reference ObjectDB resolves exact same S-owned identity for "+label)
	var original_empty := reference.is_empty()
	var numeric: Dictionary = _world.intersect_shape_empty(_query)
	_check(numeric.get("ok") == true and numeric.get("empty") is bool and numeric.empty == original_empty,"exact original/native emptiness for "+label)
	_check(numeric.size() == 2 and not numeric.has("collider"),"numeric result contains no ObjectDB collider for "+label)
	_check(_query_facts() == facts,"same reusable query/all parameters unchanged for "+label)
	var reference_after: Array[Dictionary] = direct.intersect_shape(_query,1)
	_check(reference_after.is_empty() == original_empty,"reference remains exact after numeric query for "+label)
	for hit: Dictionary in reference_after:
		_check(hit.collider in _identities and hit.collider_id == hit.collider.get_instance_id(),"numeric call did not mutate reference ObjectDB resolution policy for "+label)
	if expected_empty is bool: _check(original_empty == expected_empty,"real geometry expected empty/blocked for "+label)
	_empty_cases += 1 if original_empty else 0
	_blocked_cases += 0 if original_empty else 1
	_comparisons += 1

func _run_queries() -> void:
	_compare("circle interior",Vector2.ZERO,_query_circle,1,0,true,false,[],Vector2.ZERO,0,false)
	_compare("far empty",Vector2(200,200),_query_circle,1,0,true,false,[],Vector2.ZERO,0,true)
	_compare("circle mask filtered",Vector2.ZERO,_query_circle,4,0,true,false,[],Vector2.ZERO,0,true)
	_compare("bodies disabled",Vector2.ZERO,_query_circle,1,0,false,false,[],Vector2.ZERO,0,true)
	_compare("circle exclusion",Vector2.ZERO,_query_circle,1,0,true,false,[_bodies[0]],Vector2.ZERO,0,true)
	_compare("circle all owned exclusions",Vector2.ZERO,_query_circle,5,0,true,false,_bodies,Vector2.ZERO,0,true)
	_compare("circle tangent",Vector2(14,0),_query_circle,1)
	_compare("circle tangent inward",Vector2(13.96875,0),_query_circle,1)
	_compare("circle tangent outward",Vector2(14.03125,0),_query_circle,1)
	_compare("circle positive margin",Vector2(14.125,0),_query_circle,1,0.25)
	_compare("circle swept motion",Vector2(-20,0),_query_circle,1,0,true,false,[],Vector2(40,0))
	_compare("rectangle body interior",Vector2(40,0),_query_circle,4,0,true,false,[],Vector2.ZERO,0,false)
	_compare("rectangle tangent",Vector2(54,0),_query_circle,4)
	_compare("rectangle tangent inward",Vector2(53.96875,0),_query_circle,4)
	_compare("rectangle tangent outward",Vector2(54.03125,0),_query_circle,4)
	_compare("rectangle positive margin",Vector2(54.125,0),_query_circle,4,0.25)
	_compare("rectangle query interior",Vector2(40,0),_query_rectangle,4,0,true,false,[],Vector2.ZERO,0,false)
	_compare("rectangle query rotated",Vector2(49,0),_query_rectangle,4,0.35,true,false,[],Vector2.ZERO,PI/4.0)
	_compare("rectangle query motion",Vector2(20,0),_query_rectangle,4,0.35,true,false,[],Vector2(30,0),PI/8.0)
	_compare("real area enabled",Vector2(80,0),_query_circle,16,0,false,true,[],Vector2.ZERO,0,false)
	_compare("real area disabled",Vector2(80,0),_query_circle,16,0,false,false,[],Vector2.ZERO,0,true)
	_compare("real area mask filtered",Vector2(80,0),_query_circle,1,0,false,true,[],Vector2.ZERO,0,true)
	_compare("area and bodies flags together",Vector2(80,0),_query_circle,21,0,true,true,[],Vector2.ZERO,0,false)
	# Reuse the exact query/RID after actual source shape radius changes.
	PhysicsServer2D.shape_set_data(_query_circle,1.0)
	_compare("same RID radius1 empty",Vector2(11,0),_query_circle,1,0,true,false,[],Vector2.ZERO,0,true)
	PhysicsServer2D.shape_set_data(_query_circle,6.0)
	_compare("same RID radius6 blocked",Vector2(11,0),_query_circle,1,0,true,false,[],Vector2.ZERO,0,false)
	_compare("reused rectangle after circle",Vector2(40,0),_query_rectangle,4,0,true,false,[],Vector2.ZERO,0,false)
	_check(_comparisons == 26 and _empty_cases > 0 and _blocked_cases > 0,"full26case matrix includes actual empty and blocked results")
	_check(_world.state().body_count == 2,"query neither creates nor retires Native body authority")
	_done = true

func on_phase(phase: String, frame: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner: return false
	if phase == "P_GROUP" and not _done and frame.epoch >= 1: _run_queries()
	if phase == "PUBLISH": return _host.publish_snapshot({"done":_done,"owner":_owner,"comparisons":_comparisons,"empty_cases":_empty_cases,"blocked_cases":_blocked_cases,"checks":_checks},[])
	return true
func on_inputs(_domain: String, _packets: Array) -> bool: return OS.get_thread_caller_id() == _owner
func close_session() -> bool:
	if OS.get_thread_caller_id() != _owner: return false
	if _closed: return true
	# Cleanup actual source RIDs before retiring their space. All identity Objects
	# remain held until every attached body/area has actually gone.
	_query = null
	if _area.is_valid(): PhysicsServer2D.area_set_space(_area,RID()); PhysicsServer2D.free_rid(_area); _area = RID()
	for shape: RID in [_area_shape,_query_circle,_query_rectangle]:
		if shape.is_valid(): PhysicsServer2D.free_rid(shape)
	_area_shape = RID(); _query_circle = RID(); _query_rectangle = RID()
	if _world != null:
		if not _world.close(): return false
		_world = null
	_bodies.clear()
	for identity: Object in _identities: identity.free()
	_identities.clear(); _closed = true; _host = null
	return true
