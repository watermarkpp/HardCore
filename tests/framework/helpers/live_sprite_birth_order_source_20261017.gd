extends "res://tests/framework/helpers/multicore_binding_fifo_core_20261015.gd"
## Protocol component: real Source visual producer, coordinator, Native FIFO,
## checked physical Main renderer, BindingFact and cleanup; not full World.
const Ports := preload("res://scripts/gameplay/enemy/enemy_owner_streaming_visual_ports.gd")
var _birth_ports: RefCounted
var _birth_events: Array[Dictionary] = []
func _capture_birth_event(event: Dictionary) -> bool:
	_birth_events.append(event.duplicate(true))
	return true
func setup_case() -> void:
	if case_index != 0:
		super.setup_case()
		return
	case_mode = case_modes[case_index]
	completion_fired = false
	var id: int = registry.handle.get_instance_id()
	_birth_ports = Ports.new()
	var catalogue := {"appearances":{},"source_profiles":{},"direction_offsets":{},"ground_contact":{},"manual_alignment":{},"overhead":{}}
	record(_birth_ports.configure_owner(catalogue,session._resource_failure) and _birth_ports.configure_streaming_bindings(primitives,coordinator) and _birth_ports.configure_original_journal(_capture_birth_event),"actual Source ports bind the real configured coordinator and primitives")
	_birth_ports.emit_visual(id,&"visual_configure_actor_y_sort",["visual_root"])
	_birth_ports.emit_visual(id,&"visual_position",[Vector2(0,4)])
	_birth_ports.emit_visual(id,&"visual_visible",[false])
	_birth_ports.emit_visual(id,&"visual_create_body_sprite",[])
	_birth_ports.emit_visual(id,&"sprite_region",[Rect2(0,0,64,64)])
	_birth_ports.emit_visual(id,&"sprite_position",[Vector2(-32,-56)])
	var operations: Array = []
	for event: Dictionary in _birth_events: operations.append(event.operation)
	var creation: int = operations.find(&"visual_create_body_sprite")
	var region: int = operations.find(&"sprite_region")
	var position_index: int = operations.find(&"sprite_position")
	var ordered: bool = creation >= 0 and creation < region and region < position_index
	record(ordered,"LIVE producer emits actual Sprite construction before its dependent region and position")
	record(not primitives.has_binding_fact(id),"unexecuted Source command is not manufactured into a BindingFact")
	var rows: Array = coordinator.get("_live_bindings")
	record(rows.size()==2 and rows[0].op==&"bind_or_clear" and rows[0].args==[id,&"visual_visible",[false]],"original visibility mutation retains its exact first FIFO position")
	record(rows.size()==2 and rows[1].op==&"observe_binding" and rows[1].args==[id],"Sprite journal construction is followed by real observation, never a second creation")
	if ordered:
		for event: Dictionary in _birth_events:
			record(session.original_event_journal().append({"kind":"enemy_visual","event":event}),"exact produced Sprite birth event enters sole real journal:"+str(event.operation))
	else:
		# RED only: this diagnostic batch has NOT been accepted by Native.
		# Do not feed known-invalid dependent writes into a permanent claim.
		# Retain original FIFO baseline so all genuine native ownership closes.
		record(false,"RED producer batch withheld before Native acceptance; original binding baseline cleans up")
	coordinator._visual_subscriptions[id] = {"resource_key":"actual_fixture_profile","world_generation":1}
	record(coordinator.request_live_visual_activation(id,profile,true),"actual activation retains its no-fact cursor until Main observation")
	record(coordinator._live_bindings.size()==3 and coordinator._live_bindings[2].get("await_initial_binding")==true,"no initial binding readiness is invented while Native has not executed")
