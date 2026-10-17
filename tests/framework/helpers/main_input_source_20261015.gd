extends "res://tests/framework/helpers/premap_context_source_20261015.gd"
const InputOwner := preload("res://scripts/gameplay/world/world_owner_input.gd")
var _input_owner: RefCounted
var _processes := 0
func _init(host: Object,boot: Dictionary) -> void:
	super(host,boot)
	var input := InputOwner.new(self)
	_input_owner = input
	_check(input.accept(boot.packets[0]),"real Source input owner consumes actual Main initial values")
	_check(not input.has_button_lifecycle_owner(),"actual pre-HUD initial packet has no invented button owner")
	_check(input.accept(boot.packets[1]),"real Source owner consumes next detached Main event snapshot")
	_check(input.has_button_lifecycle_owner() and input.has_button_lifecycle_snapshot(),"Source observes the actual original button presence and snapshot")
	_check(not input.button_owns_lifecycle_input(1,0,&"touch"),"Source does not invent a token absent from real original button ownership")
	_check(not input.accept(boot.packets[1]),"real Source input owner rejects replay independently")
	_check(input.accept(boot.packets[2]),"next actual Main packet still reaches Source after rejected replay")
	_check(input.keyboard_movement_vector() == boot.packets[2].keyboard_movement,"actual runtime Vector2 survives the Native codec")
func current_clock_frame() -> Dictionary: return _host.current_clock_frame()
func current_world_identity() -> Dictionary: return _world
func on_phase(phase: String,frame: Dictionary) -> bool:
	if phase == "P_INPUT":
		var exists: bool = _input_owner.has_method("begin_original_process_boundary")
		_check(exists,"actual Source input owns an edge boundary instead of repeating Main just_pressed indefinitely")
		if exists: _check(_input_owner.begin_original_process_boundary(frame),"input edge boundary uses the current genuine Native P_INPUT frame")
	if phase == "P_GROUP":
		_processes += 1
		var expected: bool = _processes == 1
		_check(_input_owner.is_action_just_pressed(&"interact") == expected,"actual Main edge is visible only in its first Source process: %d" % _processes)
		_check(_input_owner.is_action_just_pressed(&"interact") == expected,"multiple queries within the same Source process see the same edge: %d" % _processes)
	if phase == "PUBLISH": return _host.publish_snapshot({"done":_processes>=2,"checks":_checks,"world":_world},[])
	return super(phase,frame)
