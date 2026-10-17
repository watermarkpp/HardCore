extends Node

const Registry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
const ActorRef := preload("res://scripts/features/contracts/actor_ref.gd")
const ActorLink := preload("res://scripts/gameplay/foundation/actor_link.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures := 0

class Model extends RefCounted:
	var current_hp := 20
	func current_life() -> int: return 1

func _record(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures += 1

func _owner_checks() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var owner := Object.new()
	var parent := Object.new()
	var registry := Registry.new()
	var world := {"contract_id":registry.WORLD_CONTRACT,"world_runtime_id":owner.get_instance_id(),
		"world_epoch":1,"runtime_map_id":913203,"profile_id":"scope_fixture"}
	var configured := registry.configure_world(world, "")
	var model := Model.new()
	var handle: Object = registry.register_actor(model, 1, &"enemy", 0)
	var available := configured and handle != null and handle.has_method("set_parent_scope_id") and handle.has_method("set_processing_qualification")
	records.append({"passed":available,"label":"canonical actor has independent parent and processing qualification"})
	if not available:
		registry.retire_world()
		parent.free()
		owner.free()
		return records
	var identity: Dictionary = handle.identity()
	var process_available := handle.has_method("is_processing") and handle.has_method("set_process_processing_enabled")
	records.append({"passed":process_available,"label":"ordinary process enabled has its own source qualification"})
	if process_available:
		handle.call("set_process_processing_enabled", false)
		records.append({"passed":not handle.call("is_processing") and handle.can_process() and handle.is_physics_processing_enabled(),
			"label":"ordinary processing disabled does not disable physics or can-process"})
		handle.call("set_process_processing_enabled", true)
		handle.set_processing_qualification(false, false)
		records.append({"passed":handle.call("is_processing") and not handle.can_process() and not handle.is_physics_processing_enabled(),
			"label":"pause and physics flags do not substitute for original ordinary process flag"})
		handle.set_processing_qualification(true, true)
	var action := ActorRef.capture_domain(registry, handle)
	var link := ActorLink.capture(registry, handle)
	records.append({"passed":handle.set_parent_scope_id(owner.get_instance_id()),"label":"parent scope binds the existing owner identity"})
	var view: Dictionary = handle.runtime_actor_view()
	records.append({"passed":view.parent_scope_id == owner.get_instance_id() and view.can_process and view.physics_processing_enabled,
		"label":"owner publishes exact original parent and independent processing fields"})
	handle.set_parent_scope_id(parent.get_instance_id())
	records.append({"passed":handle.parent_scope_id() != view.parent_scope_id and handle.identity() == identity and action.resolve_record() == handle,
		"label":"same-world reparent changes original extra scope without inventing a world or life generation"})
	handle.set_processing_qualification(false, true)
	records.append({"passed":not handle.can_process() and handle.is_physics_processing_enabled() and link.borrow_model() == model,
		"label":"can-process and physics enabled remain separate from object presence and sole HP"})
	handle.set_processing_qualification(true, false)
	records.append({"passed":handle.can_process() and not handle.is_physics_processing_enabled() and action.resolve_record() == handle,
		"label":"consumer checks original processing flag; ActorRef schema and general qualification remain unchanged"})
	handle.set_world_membership(false)
	records.append({"passed":not handle.can_process() and handle.parent_scope_id() == 0 and link.borrow_model() == model,
		"label":"temporary world exit removes current parent/process qualification while preserving persistent object link"})
	handle.set_world_membership(true)
	handle.set_parent_scope_id(parent.get_instance_id())
	handle.queue_retirement()
	view = handle.runtime_actor_view()
	records.append({"passed":view.inside_world and view.queued_for_retirement and link.resolve_record() == handle and action.resolve_record(false) == null,
		"label":"queued retirement is independently visible before final object retirement"})
	registry.retire_runtime_actor(handle.get_instance_id())
	action.dispose_domain()
	link.dispose()
	records.append({"passed":registry.remaining_actor_count() == 0 and registry.remaining_lease_count() == 0,
		"label":"qualification fields do not create another lifetime or retained actor store"})
	parent.free()
	owner.free()
	return records

func _ready() -> void:
	var thread := Thread.new()
	_record(thread.start(_owner_checks) == OK, "scope checks execute on a real owner thread")
	for record: Dictionary in thread.wait_to_finish(): _record(record.passed, record.label)
	var valid := proof.write_receipt("multicore_actor_scope_20261014", proof.records.size(), failures)
	print("MULTICORE_ACTOR_SCOPE_20261014_", "PASS" if valid and failures == 0 else "FAIL")
	get_tree().quit(0 if valid and failures == 0 else 1)
