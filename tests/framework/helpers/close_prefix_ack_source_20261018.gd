extends RefCounted
## Exact Native Host/ordinary-mailbox close wake component, not a World fixture.
var _host: Object
var _generation := 0
var _valid := true
var _close_calls := 0
func _init(host: Object, _boot: Dictionary) -> void:
	_host=host
	_generation=int(host.capabilities().bridge_generation)
	_valid=OS.get_thread_caller_id()!=OS.get_main_thread_id()
	var prefix := {"bridge_generation":_generation,"journal_generation":_generation,"through_ordinal":1,"events":[{"ordinal":1,"operation":&"close_wake_actual_label","arguments":["written-before-real-ACK"]}]}
	_valid=_valid and _host.register_published_original_main_prefix(prefix)
func on_inputs(_domain: String, _packets: Array) -> bool: return _valid
func on_phase(phase: String, _frame: Dictionary) -> bool:
	if phase=="PUBLISH": return _host.publish_snapshot({"ready_for_close_without_ACK":true},[])
	return _valid
func close_session() -> bool:
	_close_calls+=1
	var actual: Dictionary=_host.completed_original_main_prefix_receipt()
	return _valid and _close_calls==1 and actual.get("applied")==true and actual.get("through_ordinal")==1
