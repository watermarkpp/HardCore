extends Node
const Source := preload("res://tests/framework/helpers/premap_context_source_20261015.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failures := 0
var _host: Object
var _root: Node2D
var _world: Dictionary
var _tick := 0
var _closing := false
var _deadline := 0
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failures += 1
func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_root = scene.instantiate()
	check(_root.get("current_map_id") == -1 and _root.get("_zone_generation") == 0,"actual detached original GameRoot begins before any map")
	# Explicit protocol fixture profile namespace, not a loaded-save receipt.
	_world = {"contract_id":"hardcore.execution.world_context.v1","world_runtime_id":_root.get_instance_id(),"world_epoch":_root.get("_zone_generation"),"runtime_map_id":_root.get("current_map_id"),"profile_id":"premap_protocol_fixture"}
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	var config := {"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":16,"input_capacity":16,"event_capacity":16,"bridge_generation":115123,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"primitive_request_capacity":65536,"primitive_result_capacity":65536,"source_deferred_max_pages":int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))*256}
	var started: bool = _host.start_clock_fixture(Source,{"world_identity":_world},config)
	check(started,"actual Native Host Source fixture starts without global external-owner override")
	if not started:
		_host = null
		_finish()
		return
	_deadline = Time.get_ticks_usec()+5000000
func _process(_delta: float) -> void:
	if _host == null: return
	var packet: Dictionary = _host.acquire_presentation(_tick+1,16)
	if not packet.is_empty():
		_tick = int(packet.tick)
		_host.ack_events(int(packet.through_ordinal))
		if packet.frame.get("done") == true and not _closing:
			for row: Dictionary in packet.frame.checks: check(row.pass,row.label)
			check(packet.frame.world == _world,"actual Source returns the unchanged pre-map context")
			_closing = true
			_host.request_close()
	if _closing and _host.status().get("join_complete") == true:
		check(_host.close_and_join(),"real Source joins before original Main template release")
		check(str(_host.status().get("fault","")).is_empty(),"protocol refusal paths do not corrupt Host state")
		_host = null
		_finish()
	elif Time.get_ticks_usec() > _deadline and not _closing:
		check(false,"actual pre-map protocol fixture reaches its bounded endpoint")
		_closing = true
		_host.request_close()
func _finish() -> void:
	if is_instance_valid(_root):
		check(_root.get("current_map_id") == -1 and _root.get("_zone_generation") == 0,"Source component never mutates Main map identity")
		_root.free()
	var written: bool = _proof.write_receipt("premap_context_20261015",_proof.records.size(),_failures)
	print("PREMAP_CONTEXT_20261015_", "PASS" if written and _failures == 0 else "FAIL", " checks=",_proof.records.size()," failures=",_failures)
	get_tree().quit(0 if written and _failures == 0 else 1)
