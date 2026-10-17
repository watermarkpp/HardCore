extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Registry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
const ActorRef := preload("res://scripts/features/contracts/actor_ref.gd")
const LINK_PATH := "res://scripts/gameplay/foundation/actor_link.gd"

class Model extends RefCounted:
	var current_hp := 40
	var life := 1
	var level := 20
	func current_life() -> int:
		return life
	func take_damage(amount: int) -> void:
		current_hp = maxi(0, current_hp - amount)
		if current_hp == 0:
			life += 1

var proof := Proof.new()
var failures := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures += 1

func _ready() -> void:
	_run.call_deferred()

func _owner_checks() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var owner := Object.new()
	var registry := Registry.new()
	var world := {"contract_id":registry.WORLD_CONTRACT,"world_runtime_id":owner.get_instance_id(),
		"world_epoch":1,"runtime_map_id":913203,"profile_id":"link_fixture"}
	records.append({"passed":registry.configure_world(world, ""),"label":"S configures one original world identity"})
	var model := Model.new()
	var handle: Object = registry.register_actor(model, 1, &"enemy", 0)
	var link_class: Script = load(LINK_PATH)
	var link: RefCounted = link_class.capture(registry, handle)
	var action: RefCounted = ActorRef.capture_domain(registry, handle)
	records.append({"passed":link != null and action != null and registry.remaining_lease_count() == 2,
		"label":"persistent link and accepted action retain separate leases on the same handle"})
	if link == null or action == null:
		registry.retire_world()
		owner.free()
		return records
	var runtime_id: int = handle.get_instance_id()
	records.append({"passed":runtime_id > 0 and link.runtime_id() == runtime_id and link.borrow_model() == model,
		"label":"link uses the original full positive runtime ObjectID and sole model"})
	var borrowed: Object = link.borrow_model()
	borrowed.take_damage(40)
	records.append({"passed":action.resolve_record(false) == null and link.resolve_record() == handle,
		"label":"death life change rejects old accepted action without erasing persistent object link"})
	records.append({"passed":borrowed.current_hp == 0 and borrowed.level == 20 and borrowed == model,
		"label":"qualified damage post-processing reads the same returned Core after life changes"})
	model.life += 1
	model.current_hp = 40
	records.append({"passed":link.borrow_model() == model and action.resolve_record(false) == null,
		"label":"revival keeps persistent object relationship but cannot revive an old accepted release"})
	handle.set_world_membership(false)
	records.append({"passed":handle.runtime_object_is_present() and not handle.is_inside_world()
		and link.resolve_record() == handle and ActorRef.capture_domain(registry, handle) == null,
		"label":"temporary world exit separates object presence from canonical world qualification"})
	handle.set_world_membership(true)
	var current: RefCounted = ActorRef.capture_domain(registry, handle)
	records.append({"passed":current != null and current.resolve_record() == handle,
		"label":"world reentry qualifies the same current life without changing runtime identity"})
	handle.queue_retirement()
	records.append({"passed":handle.is_queued_for_retirement() and handle.runtime_object_is_present()
		and link.resolve_record() == handle and current.resolve_record(false) == null,
		"label":"queued deletion retains Node-style presence while accepted action qualification closes"})
	handle.begin_retirement()
	records.append({"passed":link.resolve_record() == null and not handle.runtime_object_is_present()
		and borrowed.current_hp == 40,
		"label":"logical deletion ends link resolution; local borrowed data is retained without gameplay qualification"})
	action.dispose_domain()
	current.dispose_domain()
	link.dispose()
	records.append({"passed":registry.remaining_lease_count() == 0 and registry.remaining_actor_count() == 0,
		"label":"final link disposal releases retired storage once on S"})
	link.dispose()
	records.append({"passed":registry.remaining_lease_count() == 0 and link.resolve_record() == null,
		"label":"explicit disposal is idempotent and cannot requalify an actor"})
	owner.free()
	return records

func _run() -> void:
	check(FileAccess.file_exists(LINK_PATH), "persistent runtime ActorLink implementation exists")
	if failures == 0:
		var thread := Thread.new()
		check(thread.start(_owner_checks) == OK, "checks run on a real Godot simulation thread")
		var records: Array = thread.wait_to_finish()
		for record: Dictionary in records:
			check(bool(record.passed), str(record.label))
	var valid := proof.write_receipt("multicore_actor_link_20261014", proof.records.size(), failures)
	print("MULTICORE_ACTOR_LINK_20261014_", "PASS" if valid and failures == 0 else "FAIL")
	get_tree().quit(0 if valid and failures == 0 else 1)
