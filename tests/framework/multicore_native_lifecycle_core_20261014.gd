extends "res://tests/framework/multicore_native_world_core_20261014.gd"

var _dynamic_body := RID()
const INITIAL_DYNAMIC_POSITION := Vector2(-300, -300)

func _init(host: Object, boot: Dictionary) -> void:
	super(host, boot)
	_dynamic_body = _world.call("create_static_body", _identity(), Transform2D(0, INITIAL_DYNAMIC_POSITION),
		[{"type":PhysicsServer2D.SHAPE_RECTANGLE,"data":Vector2(1, 1)}], 0, 0)
	PhysicsServer2D.body_set_mode(_dynamic_body, PhysicsServer2D.BODY_MODE_RIGID)
	PhysicsServer2D.body_set_param(_dynamic_body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
	PhysicsServer2D.body_set_state(_dynamic_body, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2(60, 0))

func _h_first() -> void:
	super()
	_host.call("set_simulation_paused", true)

func _p_first() -> void:
	super()
	var transform: Transform2D = PhysicsServer2D.body_get_state(_dynamic_body, PhysicsServer2D.BODY_STATE_TRANSFORM)
	_check(transform.origin == INITIAL_DYNAMIC_POSITION, "S pause stops original backend integration while keeping P query/timer access")

func on_phase(name: String, frame: Dictionary) -> bool:
	if name == "H_GROUP" and frame.epoch == 2:
		_host.call("set_simulation_paused", false)
	if name == "P_GROUP" and frame.epoch == 2:
		var transform: Transform2D = PhysicsServer2D.body_get_state(_dynamic_body, PhysicsServer2D.BODY_STATE_TRANSFORM)
		_check(transform.origin.x > INITIAL_DYNAMIC_POSITION.x, "S unpause restores native integration on its original H step")
		_check(_world.call("retire_body", _dynamic_body), "lifecycle fixture retires the extra real body before original world teardown")
	return super(name, frame)
