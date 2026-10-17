extends "res://tests/framework/helpers/numeric_shape_source_core_20261015.gd"
## Reuse the real S-owned World/fixture lifetime, not a mock query provider.
func _init(host: Object, boot: Dictionary) -> void: super(host,boot)
func _point_case(label: String, point: Vector2, raw_count: int, picked_count: int, compare_order := false, canvas_id := 0) -> void:
	_check(OS.get_thread_caller_id()==_owner,"real Source owner: "+label)
	var query := PhysicsPointQueryParameters2D.new()
	query.position=point;query.canvas_instance_id=canvas_id;query.collide_with_areas=true
	var direct: PhysicsDirectSpaceState2D=PhysicsServer2D.space_get_direct_state(_world.state().space_rid)
	var original: Array[Dictionary]=direct.intersect_point(query,64)
	_check(original.size()==raw_count,"actual original raw point count: "+label)
	var result: Dictionary=_world.intersect_original_pick_point(point,canvas_id)
	_check(result.get("ok")==true and result.get("limit")==64 and result.get("hits",[]).size()==picked_count,"real Native original pick filter and64 limit: "+label)
	var numeric: Array=result.get("hits",[])
	for index: int in numeric.size():
		var hit: Dictionary=numeric[index]
		_check(hit.size()==3 and hit.get("collider_id") is int and hit.collider_id>0 and hit.get("rid") is RID and hit.get("shape") is int and not hit.has("collider"),"numeric identity/RID/shape only: "+label)
		if compare_order:
			_check(index<original.size() and hit.collider_id==original[index].collider_id and hit.rid==original[index].rid and hit.shape==original[index].shape,"same original backend hit order: "+label)
	# Original reference queries still resolve their actual S fixture Objects
	# after numeric scope exits: the engine default was not globally disabled.
	var after: Array[Dictionary]=direct.intersect_point(query,64)
	_check(after.size()==original.size(),"numeric scope preserves following original query: "+label)
	for hit: Dictionary in after:
		_check(hit.collider in _identities and hit.collider.get_instance_id()==hit.collider_id,"following default query retains actual Source collider Object: "+label)
	_comparisons+=1
	_empty_cases+=1 if numeric.is_empty() else 0
	_blocked_cases+=0 if numeric.is_empty() else 1
func _run_queries() -> void:
	_point_case("original body default not pickable",Vector2.ZERO,1,0)
	_check(_world.set_body_pickable(_bodies[0],true),"real owned circle body pickable enabled")
	_point_case("circle enabled",Vector2.ZERO,1,1,true)
	_point_case("far empty",Vector2(200,200),0,0,true)
	_point_case("rectangle default not pickable",Vector2(40,0),1,0)
	_check(_world.set_body_pickable(_bodies[1],true),"real owned rectangle body pickable enabled")
	_point_case("rectangle enabled",Vector2(40,0),1,1,true)
	_point_case("different actual canvas token",Vector2.ZERO,0,0,true,_identities[0].get_instance_id())
	_check(_world.set_body_pickable(_bodies[0],false),"actual owned body pickable removed")
	_point_case("pickable removed again",Vector2.ZERO,1,0)
	_check(_world.set_body_pickable(_bodies[0],true) and _world.set_body_shape_disabled(_bodies[0],0,true),"actual pickable collision shape disabled")
	_point_case("disabled actual shape",Vector2.ZERO,0,0,true)
	# Re-enabled shape broadphase visibility belongs to the next actual physics
	# service. Do not force another sync or assert an immediate original hit.
	_check(_world.set_body_shape_disabled(_bodies[0],0,false),"actual owned shape restored without an invented physics step")
	for index: int in 65:
		var body: RID=_world.create_static_body(_identity(),Transform2D(0,Vector2(500,500)),[{"type":PhysicsServer2D.SHAPE_CIRCLE,"data":8.0}],1,1)
		_check(body.is_valid() and _world.set_body_pickable(body,true),"actual dense owned body "+str(index))
		_bodies.append(body)
	_point_case("original64 shape cap with65 real bodies",Vector2(500,500),64,64,true)
	_check(_world.state().body_count==67 and _comparisons==9 and _empty_cases>0 and _blocked_cases>0,"real body authority and all9 point-query scenarios preserved")
	_done=true
