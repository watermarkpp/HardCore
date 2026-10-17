extends RefCounted
## Real Source journal and actual Main/Native ACKs. This fixture's terminal
## permission tests only Native transport closure, never production World exit.
const Journal := preload("res://scripts/gameplay/world/world_original_event_journal.gd")
var _host: Object
var _journal: RefCounted
var _checks: Array[Dictionary] = []
var _stage := 0
var _valid := true
func _check(ok: bool, label: String) -> void:
	_checks.append({"pass":ok,"label":label}); _valid = _valid and ok
func fault(code: String, _details: Dictionary) -> void: _check(false,"actual journal fault: "+code)
func _init(host: Object, _boot: Dictionary) -> void:
	_host=host
	_check(OS.get_thread_caller_id()!=OS.get_main_thread_id(),"journal executes on the actual Native Source thread")
	var generation: int=int(host.capabilities().bridge_generation)
	_journal=Journal.new(self,generation,generation)
	_check(_journal.append({"operation":&"actual_delivery_label","arguments":["published-1"]}),"actual Source journal appends event one")
	var first: Dictionary=_journal.freeze_prefix()
	_check(_journal.register_normal_publication(first) and host.register_published_original_main_prefix(first),"actual first immutable journal prefix reaches Native")
	_check(_journal.append({"operation":&"actual_delivery_label","arguments":["published-2"]}),"actual Source journal appends event two before first ACK")
	var second: Dictionary=_journal.freeze_prefix()
	_check(second.events.size()==2 and second.events[0]==first.events[0],"second publication contains genuine already-published overlap")
	_check(_journal.register_normal_publication(second) and host.register_published_original_main_prefix(second),"actual overlapping journal prefix reaches Native before first ACK")
func on_inputs(_domain: String, _packets: Array) -> bool: return true
func on_phase(phase: String, _frame: Dictionary) -> bool:
	if phase!="PUBLISH": return true
	var receipt: Dictionary=_host.completed_original_main_prefix_receipt()
	if _stage==0 and receipt.get("through_ordinal")==1:
		_check(_journal.consume_normal_receipt(receipt),"first genuine Main ACK prunes only event one")
		_check(_journal.applied_ordinal()==1 and _journal.freeze_prefix().events.size()==1,"Source first watermark precedes second Main ACK")
		_stage=1
	elif _stage==1 and receipt.get("through_ordinal")==2:
		_check(_journal.consume_normal_receipt(receipt),"second genuine ACK accepts its registered historical overlap")
		_check(_journal.applied_ordinal()==2 and not _journal.has_pending(),"every original event is retired exactly once")
		_check(not _journal.consume_normal_receipt({"bridge_generation":-1,"journal_generation":1,"through_ordinal":2,"applied":true}),"foreign generation never advances the journal")
		_check(not _journal.consume_normal_receipt({"bridge_generation":receipt.bridge_generation,"journal_generation":receipt.journal_generation,"through_ordinal":3,"applied":true}),"unpublished later ACK is rejected")
		_stage=2
	return _host.publish_snapshot({"ready_to_close":_stage==2,"first_ack_consumed":_stage>=1,"source_valid":_valid,"checks":_checks},[])
func close_session() -> bool: return _stage==2
