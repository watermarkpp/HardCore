extends Node

## Direct real-Godot numeric/transport test. This is not a complete WorldCore,
## crowd AI replay, active physics, deadline performance or device acceptance.
const Policy := preload("res://scripts/monster_ai_package/policy.gd")
const Crowd := preload("res://scripts/gameplay/enemy/enemy_owner_crowd_position.gd")
const GU := preload("res://scripts/ground_unit_space.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _thread := Thread.new()
var _result: Dictionary = {}

func _ready() -> void:
	_thread.start(_run_numeric)
	while _thread.is_alive():
		await get_tree().process_frame
	_result = _thread.wait_to_finish()
	print("CROWD_NUMERIC_RECEIPT " + JSON.stringify(_result))
	var proof := Proof.new()
	for entry: Dictionary in _result.get("check_records", []): proof.record(entry.passed, entry.name)
	var clean: bool = _result.get("failures", 1) == 0
	var written: bool = proof.write_receipt("multicore_crowd_numeric_20261014", int(_result.get("checks", 0)), int(_result.get("failures", 1)))
	print("MULTICORE_CROWD_NUMERIC_20261014_", "PASS" if clean and written else "FAIL")
	get_tree().quit(0 if clean and written else 1)

func _check(state: Dictionary, value: bool, name: String) -> void:
	state.checks += 1
	state.check_records.append({"passed":value,"name":name})
	if not value:
		state.failures += 1
		state.failed_names.append(name)

func _run_numeric() -> Dictionary:
	var state := {"scope":"actual_Godot_math_and_native_pool_direct", "checks":0, "failures":0, "failed_names":[], "receipts":[], "check_records":[]}
	if not ClassDB.class_exists("HardCoreCrowdGeometry"):
		_check(state, false, "native_crowd_class_MISSING")
		return state
	var native: RefCounted = ClassDB.instantiate("HardCoreCrowdGeometry")
	_check(state, native.configure_owner(64, 32, 4, GU.EPSILON_GU), "native_S_configure")
	var oracle: RefCounted = Crowd.new()
	var world := {"contract_id":"hardcore.execution.world_context.v1", "world_runtime_id":1, "world_epoch":1, "runtime_map_id":913203, "profile_id":"kernel_unit_fixture"}
	var scope := {"world_context":world, "world_generation":1, "map_instance_identity":"kernel_unit_map_instance", "geometry_generation":1}
	var directions := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1,1), Vector2(-1,1), Vector2(-1,-1), Vector2(1,-1)]
	var handles: Array[Object] = []
	for count: int in [10, 30, 40]:
		var peers: Array = []
		for i: int in count:
			# These are real positive ObjectIDs held until native tasks retire.
			# They are numeric unit fixtures, not production ActorRegistry IDs.
			var handle := Object.new()
			handles.append(handle)
			peers.append({"runtime_id":handle.get_instance_id(),"life":1,"pose_revision":1,"radius_revision":1,"map":913203,
				"position":Vector2(float(i%7-3)*0.37,float(i/7-2)*0.33),"radius":0.25+float(i%3)*0.003,"margin":0.0037,
				"world_context":world,"map_instance_identity":scope.map_instance_identity})
		var queries: Array = []
		var origin := Vector2(0.17,-0.08)
		for direction: Vector2 in directions:
			queries.append({"kind":0,"a":origin,"b":origin+direction,"own_radius":0.25,"own_margin":0.0})
			queries.append({"kind":1,"a":origin+direction,"b":origin+direction,"own_radius":0.25,"own_margin":0.0})
			queries.append({"kind":2,"a":origin,"b":direction,"own_radius":0.25,"own_margin":0.0037})
		var receipt: Dictionary = native.prepare(queries, peers, scope, count, count, Time.get_ticks_usec()+10000000)
		state.receipts.append(receipt)
		_check(state, bool(receipt.get("success",false)) and int(receipt.get("worker_kernel_calls",0)) == queries.size(), "real_pool_geometry_"+str(count))
		_check(state, int(receipt.get("worker_thread_count",0)) > 0 and int(receipt.get("serial_kernel_calls",-1)) == 0, "W_performed_geometry_"+str(count))
		for direction: Vector2 in directions:
			var end := origin+direction
			for peer: Dictionary in peers:
				var c: Vector2 = peer.position
				var row: Dictionary = native.motion_row(origin,end,c,0.25,peer.radius,peer,scope)
				_check(state, row.crossed == Policy.core_crossed(origin,end,c,0.25,peer.radius), "motion_reference_"+str(count))
				var radius: float = maxf(0.0,0.25+peer.radius)
				_check(state, native.destination_row(end,c,0.25,peer.radius,peer,scope) == (not end.distance_squared_to(c)>=radius*radius-Policy.EPS), "destination_reference_"+str(count))
				var effective: float = 0.25+peer.radius+0.0037+peer.margin
				var limit: float = native.contact_limit(origin,direction,c,effective,peer,scope)
				for extent: float in [1.0,0.91,0.3,0.0]:
					_check(state, minf(extent,limit) == oracle._free_ray_extent(origin,direction,c,effective,extent), "ray_reference_"+str(count))
		# Same bucket motion: membership is deliberately unchanged.
		var moved: Dictionary = peers[0].duplicate(true)
		moved.position = origin+Vector2(0.1,0.0)
		moved.pose_revision += 1
		var repaired: Dictionary = native.motion_row(origin,origin+Vector2.RIGHT,moved.position,0.25,moved.radius,moved,scope)
		_check(state, repaired.crossed == Policy.core_crossed(origin,origin+Vector2.RIGHT,moved.position,0.25,moved.radius), "same_bucket_repair")
		# Birth was absent from frozen input; it must still block in its original
		# S candidate slot. Retirement/rebirth invalidates life even same geometry.
		var born := moved.duplicate(true)
		var born_handle := Object.new()
		handles.append(born_handle)
		born.runtime_id = born_handle.get_instance_id()
		born.life = 2
		var born_row: Dictionary = native.motion_row(origin,origin+Vector2.RIGHT,born.position,0.25,born.radius,born,scope)
		_check(state, born_row.crossed, "new_peer_does_not_bypass_original_earlier_direction")
		var changed_radius := moved.duplicate(true)
		changed_radius.radius = 0.4
		changed_radius.radius_revision += 1
		_check(state, native.destination_row(origin,changed_radius.position,0.25,changed_radius.radius,changed_radius,scope), "radius_repair")
		var rebound_scope := scope.duplicate(true)
		rebound_scope.world_context.world_epoch += 1
		rebound_scope.map_instance_identity = "new_actual_map_instance"
		var rebound_peer := moved.duplicate(true)
		rebound_peer.world_context = rebound_scope.world_context
		rebound_peer.map_instance_identity = rebound_scope.map_instance_identity
		var rebound: Dictionary = native.motion_row(origin,origin+Vector2.RIGHT,moved.position,0.25,moved.radius,rebound_peer,rebound_scope)
		_check(state, rebound.crossed, "same_map_world_instance_repair")
		var late: Dictionary = native.prepare(queries,peers,scope,count+100,count+100,1)
		_check(state, late.success and late.status == "FAIL" and late.deadline_missed, "late_accepted_work_is_retired_and_remains_FAIL")
		_check(state, native.diagnostics().in_flight == 0, "accepted_inputs_retired_before_owner_return")
	_check(state, native.close_owner(), "S_close")
	for handle: Object in handles:
		handle.free()
	return state
