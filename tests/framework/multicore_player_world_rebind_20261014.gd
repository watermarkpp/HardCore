extends Node

const Registry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
const ActorRef := preload("res://scripts/features/contracts/actor_ref.gd")
const ActorLink := preload("res://scripts/gameplay/foundation/actor_link.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures := 0

class Model extends RefCounted:
	var current_hp := 137
	var level := 40
	func current_life() -> int: return 2

func _record(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures += 1

func _checks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var owner := Object.new()
	var registry := Registry.new()
	var original_world := {"contract_id":registry.WORLD_CONTRACT,"world_runtime_id":owner.get_instance_id(),
		"world_epoch":1,"runtime_map_id":913203,"profile_id":"persistent_player_fixture"}
	registry.configure_world(original_world, "")
	var model := Model.new()
	var player: Object = registry.register_actor(model, 2, &"player", 0)
	var runtime_id: int = player.get_instance_id()
	var method_exists := registry.has_method("rebind_world_with_player")
	result.append({"passed":method_exists,"label":"registry owns explicit canonical persistent-player world transition"})
	if not method_exists:
		registry.retire_world()
		owner.free()
		return result
	var link := ActorLink.capture(registry, player)
	var action := ActorRef.capture_domain(registry, player)
	var replacement := original_world.duplicate()
	replacement.world_epoch = 2
	replacement.runtime_map_id = 910001
	result.append({"passed":not registry.call("rebind_world_with_player", runtime_id, replacement, ""),
		"label":"live world membership cannot be rebound before original transition detachment"})
	player.set_world_membership(false)
	var other: Object = registry.register_actor(Model.new(), 2, &"enemy", 1)
	result.append({"passed":not registry.call("rebind_world_with_player", runtime_id, replacement, ""),
		"label":"other live actors must retire before persistent player moves to the new world"})
	registry.retire_runtime_actor(other.get_instance_id())
	var foreign_profile := replacement.duplicate()
	foreign_profile.profile_id = "another_account"
	result.append({"passed":not registry.call("rebind_world_with_player", runtime_id, foreign_profile, ""),
		"label":"persistent actor rebind cannot transfer an account or reuse the old world epoch"})
	result.append({"passed":not registry.call("rebind_world_with_player", runtime_id, original_world, ""),
		"label":"repeated or old world epoch is rejected without rewriting identity"})
	var rebound: bool = registry.call("rebind_world_with_player", runtime_id, replacement, "")
	result.append({"passed":rebound and link.resolve_record() == player and link.borrow_model() == model
		and player.get_instance_id() == runtime_id and model.current_hp == 137 and model.level == 40,
		"label":"rebind preserves exact actor model HP level runtime ID and existing lease storage"})
	result.append({"passed":action.resolve_record(false) == null and player.identity().world == replacement
		and player.identity().life_generation == 2 and not player.is_inside_world() and player.parent_scope_id() == 0,
		"label":"old accepted action fails while rebinding never invents life or exposes a half-bound native body"})
	player.set_runtime_qualification(owner.get_instance_id(), true, true)
	player.set_world_membership(true)
	var current := ActorRef.capture_domain(registry, player)
	result.append({"passed":current != null and current.resolve_record() == player and registry.capture_world() == replacement,
		"label":"only explicit completed transition reentry admits new-world accepted actions"})
	registry.retire_runtime_actor(runtime_id)
	action.dispose_domain()
	current.dispose_domain()
	link.dispose()
	result.append({"passed":registry.remaining_actor_count() == 0 and registry.remaining_lease_count() == 0,
		"label":"new and old world leases all retire through the same owner"})
	owner.free()
	return result

func _ready() -> void:
	var thread := Thread.new()
	_record(thread.start(_checks) == OK, "persistent-world checks execute on a real simulation owner")
	for record: Dictionary in thread.wait_to_finish(): _record(record.passed, record.label)
	var valid := proof.write_receipt("multicore_player_world_rebind_20261014", proof.records.size(), failures)
	print("MULTICORE_PLAYER_WORLD_REBIND_20261014_", "PASS" if valid and failures == 0 else "FAIL")
	get_tree().quit(0 if valid and failures == 0 else 1)
