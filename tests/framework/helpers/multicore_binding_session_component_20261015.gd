extends "res://scripts/gameplay/source/source_session.gd"

# Protocol-component construction only: real Session ticket/settlement methods,
# real Native Host, real ledger and journal. Does NOT exercise application
# initialize()/Loading-pin admission, WorldCore or production actor birth.
class Sink extends RefCounted:
	var faults: Array[Dictionary] = []
	func record_fatal_source_fault(code: String, details: Dictionary) -> void:
		faults.append({"code":code,"details":details})
	func resource_failure(reason: String) -> void:
		faults.append({"code":"resource_failure","details":{"reason":reason}})
	func deny_cold() -> bool: return false

class Access extends RefCounted:
	var owner: int = OS.get_thread_caller_id()
	func owner_thread_id() -> int: return owner
	func capture(value: Object) -> WeakRef: return weakref(value)
	func resolve(value: WeakRef) -> Object: return value.get_ref()
	func present(value: Object) -> bool: return is_instance_valid(value) and value.runtime_object_is_present()
	func queued(value: Object) -> bool: return value.is_queued_for_retirement()
	func inside(value: Object) -> bool: return value.is_inside_world()
	func can_process(value: Object) -> bool: return value.can_process()
	func process_enabled(value: Object) -> bool: return value.process_enabled()
	func physics_enabled(value: Object) -> bool: return value.physics_enabled()

var actual_native_backpressure := 0
var fixture_sink := Sink.new()
var fixture_access := Access.new()
func install_component(host: Object, session_id: int, generation: int, settings: Dictionary) -> bool:
	if _host != null or OS.get_thread_caller_id() == OS.get_main_thread_id(): return false
	_host = host
	_id = session_id
	_services = {"failure":fixture_sink}
	_clock = SessionClock.new(self, host, settings)
	_journal = Journal.new(self, generation, generation)
	_budget = SessionBudget.new()
	if not _budget.configure_owner({"Engine":_clock,"Time":_clock,"ProjectSettings":_clock,"phase":_clock}, fixture_access): return false
	if not _budget.configure_resource_continuations(fixture_sink.resource_failure): return false
	if not _budget.configure_session(_id, fixture_sink.deny_cold): return false
	# Ample test allowance separates protocol from PC speed; no production
	# setting is changed. Targeted tests change allowance only as fixture input.
	_budget.configure_for_tests(2000000, _clock.get_process_frames, _clock.get_ticks_usec)
	_loading_transport = PrefixTransport.new(self, host)
	_transport = Transport.new(self, host, _loading_transport)
	_phase = "LIVE" # Explicit test state, NOT proof of real Loading admission.
	return true

func component_transport() -> RefCounted: return _transport
func component_clock() -> RefCounted: return _clock
func component_tickets_empty() -> bool:
	return _live_tickets.is_empty() and _live_consumers.is_empty() and _budget.live_obligations() == 0

func submit_live_resource(request: Dictionary, category: String, lane: int, reserved_usec: int, consumer_key := "feature") -> Dictionary:
	var actual: Dictionary = super.submit_live_resource(request, category, lane, reserved_usec, consumer_key)
	if actual.get("status") == "BACKPRESSURE" and not actual.has("error"): actual_native_backpressure += 1
	if actual.get("status") not in ["PENDING", "BUSY", "BACKPRESSURE"]:
		print("BINDING_COMPONENT_ACTUAL_ADMISSION ", {"actual":actual,"operation":request.op,"prefix":request.main_prefix,"faults":_faults})
	return actual
