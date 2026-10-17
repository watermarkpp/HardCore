extends Node

const Core := preload("multicore_feature_domain_core_20261014.gd")
const WorldCore := preload("res://scripts/gameplay/world/world_simulation_core.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _host: Object
var _boot: Dictionary
var _tick := 0
var _deadline := 0
var _failures := 0
func _check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failures += 1
func _ready() -> void:
	_boot = WorldCore.publish_feature_domain_test_bootstrap()
	_check(not _boot.is_empty(),"actual Main feature declarations/resource pins and pure boot publication")
	if _boot.is_empty():
		_finish()
		return
	_host = ClassDB.instantiate("HardCoreSimulationHost")
	_check(_host.call("start",Core,_boot,{"physics_hz":60,"max_epochs_per_turn":8,"timer_capacity":128,"input_capacity":128,"event_capacity":4096}),
		"genuine Host.start S world/profile/actors/feature factory; no clock fixture")
	_deadline = Time.get_ticks_usec()+10000000
func _process(_delta: float) -> void:
	if _host == null: return
	var packet: Dictionary = _host.call("acquire_presentation",_tick+1,4096)
	if not packet.is_empty():
		_tick = packet.tick
		if not WorldCore.consume_feature_domain_test_presentation(packet):
			_check(false,"actual Main cue/audio/resource bridge rejects the reliable feature packet")
			_finish()
			return
		_host.call("ack_events",packet.through_ordinal)
		var frame: Dictionary = packet.frame
		if frame.get("done",false):
			for row: Dictionary in frame.checks: _check(row.pass,row.label)
			_finish()
			return
	if Time.get_ticks_usec()>_deadline:
		_check(false,"real feature domain reaches terminal verification within ten wall seconds")
		_finish()
func _finish() -> void:
	set_process(false)
	if _host != null:
		_check(_host.call("close_and_join"),"S feature states/branches/leases drain before physical world/Host close")
		_host = null
	if not _boot.is_empty(): _check(WorldCore.release_feature_domain_test_bootstrap(_boot),"Main resource/catalog publication retires only after real host quiescence")
	_proof.write_receipt("multicore_feature_domain_20261014",_proof.records.size(),_failures)
	print("MULTICORE_FEATURE_DOMAIN_20261014_", "PASS" if _failures==0 else "FAIL")
	get_tree().quit(0 if _failures==0 else 1)
