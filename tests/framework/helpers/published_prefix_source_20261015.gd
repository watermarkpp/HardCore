extends RefCounted
## Actual Source on the existing Host; no second producer queue or Main objects.
var _host: Object
var _generation := 0
var _next := 0
var _registered := false
var _closed := false
var _valid := true
var _pumps := 0
func _init(host: Object, _boot: Dictionary) -> void:
	_host=host
	_generation=int(host.capabilities().bridge_generation)
	_valid=OS.get_thread_caller_id()!=OS.get_main_thread_id()
	_register_next()
func _register_next() -> void:
	var events: Array=[]
	if _next>0: events.append({"ordinal":_next,"operation":&"actual_delivery_label","arguments":["published-"+str(_next)]})
	var prefix: Dictionary={"bridge_generation":_generation,"journal_generation":_generation,"through_ordinal":_next,"events":events}
	var accepted: bool=_host.register_published_original_main_prefix(prefix)
	var repeated: bool=_host.register_published_original_main_prefix(prefix)
	_valid=_valid and accepted and repeated
	_registered=accepted
func on_inputs(_domain: String, _packets: Array) -> bool: return _valid
func on_phase(phase: String, _frame: Dictionary) -> bool:
	if phase!= "PUBLISH": return _valid
	_pumps+=1
	var receipt: Dictionary=_host.completed_original_main_prefix_receipt()
	if not receipt.is_empty() and receipt.get("applied")==true and int(receipt.through_ordinal)==_next:
		_registered=false
		if _next<2:
			_next+=1
			_register_next()
		else: _closed=true
	return _host.publish_snapshot({"ready_to_close":_closed,"source_valid":_valid,"source_ack":int(receipt.get("through_ordinal",-1)),"pumps":_pumps},[])
func close_session() -> bool:
	var receipt: Dictionary=_host.completed_original_main_prefix_receipt()
	return _valid and _closed and receipt.get("applied")==true and int(receipt.through_ordinal)==2
