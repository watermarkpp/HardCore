extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Registry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
const ActorRef := preload("res://scripts/features/contracts/actor_ref.gd")
const WorldContext := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan_contract.gd")

class HealthModel extends RefCounted:
	var current_hp := 40
	func can_receive_damage() -> bool:
		return current_hp > 0

class LifeModel extends HealthModel:
	var life := 0
	func current_life() -> int:
		return life

var proof := Proof.new()
var failures := 0

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures += 1

func _ready() -> void:
	_run.call_deferred()

func _identity_on_simulation_thread() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var owner := Object.new()
	var registry := Registry.new()
	var world := {"contract_id":registry.WORLD_CONTRACT,"world_runtime_id":owner.get_instance_id(),
		"world_epoch":3,"runtime_map_id":913203,"profile_id":"identity_fixture"}
	results.append({"passed":registry.configure_world(world, ""),"label":"S configures the existing complete world schema"})
	var core := HealthModel.new()
	var actor: Object = registry.register_actor(core, 7, &"enemy", 2)
	results.append({"passed":actor != null and actor.get_instance_id() > 0 and not actor is RefCounted,
		"label":"canonical actor uses positive full ObjectID without RefCounted sign bit"})
	if actor == null:
		owner.free()
		return results
	var identity: Dictionary = actor.identity()
	results.append({"passed":identity.size() == 3 and identity.keys().has("world") and identity.keys().has("runtime_id") and identity.keys().has("life_generation"),
		"label":"ActorRef v1 fields are unchanged"})
	var context := WorldContext.new()
	results.append({"passed":context.configure_domain(registry) and context.capture_world() == world and context.matches_profile({"profile_id":"identity_fixture","world_clock_generation":""}),
		"label":"world/profile views delegate to the same registry"})
	var ref: RefCounted = ActorRef.capture_domain(registry, actor)
	results.append({"passed":ref != null and ref.resolve_record() == actor and registry.remaining_lease_count() == 1,
		"label":"domain ActorRef retains an explicit S-owned lease"})
	results.append({"passed":actor.set_pose(Vector2(120, 80), Vector2(2, 4), 0.5) and actor.actor_view().pose_revision == 1,
		"label":"pose transaction advances the read-set revision"})
	core.current_hp = 0
	results.append({"passed":ref.resolve_record() == null and ref.resolve_record(false) == actor,
		"label":"live HP gate reads the one model while historical life may resolve"})
	core.current_hp = 40
	var old_identity := identity
	results.append({"passed":actor.replace_life(8) and registry.resolve_actor_identity(old_identity, false) == null,
		"label":"old life cannot resolve a revived actor"})
	var replacement: RefCounted = ActorRef.capture_domain(registry, actor)
	results.append({"passed":replacement != null and registry.retire_actor(replacement.identity()) and registry.remaining_actor_count() == 1 and replacement.resolve_record(false) == null,
		"label":"retirement immediately removes gameplay qualification and retains leased storage"})
	ref.dispose_domain()
	results.append({"passed":registry.remaining_actor_count() == 1,"label":"one remaining lease protects the retired object"})
	replacement.dispose_domain()
	results.append({"passed":registry.remaining_actor_count() == 0 and registry.remaining_lease_count() == 0,
		"label":"final lease releases the object on S"})
	var automatic_actor: Object = registry.register_actor(core, 1, &"enemy", 3)
	var automatic_ref: RefCounted = ActorRef.capture_domain(registry, automatic_actor)
	registry.retire_actor(automatic_ref.identity())
	automatic_ref = null
	results.append({"passed":registry.remaining_actor_count() == 0 and registry.remaining_lease_count() == 0,
		"label":"RefCounted finalization retires its outstanding lease directly on S"})
	var life_core := LifeModel.new()
	var zero_actor: Object = registry.register_actor(life_core, 1, &"player", 0)
	results.append({"passed":zero_actor == null,"label":"pre-admission player life zero is preserved and cannot be replaced by a handle counter"})
	if zero_actor != null: registry.retire_actor(zero_actor.identity())
	life_core.life = 1 # The formal world admission has executed the original transition.
	var mismatch: Object = registry.register_actor(life_core, 2, &"player", 0)
	results.append({"passed":mismatch == null,"label":"registration refuses disagreement with the model's existing life authority"})
	if mismatch != null: registry.retire_actor(mismatch.identity())
	var life_actor: Object = registry.register_actor(life_core, 1, &"player", 0)
	var life_ref: RefCounted = ActorRef.capture_domain(registry, life_actor)
	life_core.life = 2
	results.append({"passed":life_actor.identity().life_generation == 2 and life_ref.resolve_record(false) == null,
		"label":"one model life mutation updates live identity and invalidates historical references without a second counter"})
	results.append({"passed":not life_actor.replace_life(3),"label":"a model-owned life cannot also be advanced through the handle"})
	registry.retire_actor(life_actor.identity())
	life_ref.dispose_domain()
	results.append({"passed":OS.get_thread_caller_id() != OS.get_main_thread_id() and registry.retire_world(),
		"label":"actual Godot Thread constructs and retires the Node-free identity domain"})
	owner.free()
	return results

static func _projection(value: Vector2) -> Vector2:
	return value * 0.025

static func _screen(value: Vector2) -> Vector2:
	return value * 40.0

func _run() -> void:
	var thread := Thread.new()
	check(thread.start(_identity_on_simulation_thread) == OK, "Godot simulation thread starts")
	var result: Array = thread.wait_to_finish()
	for record: Dictionary in result:
		check(bool(record.passed), str(record.label))
	var target := Node2D.new()
	target.position = Vector2(120, 80)
	var context := {"runtime_map_id":-1,"fallback_target_actor":target,"player_actor":target,
		"target_combat_radius_gu":0.5,"player_combat_radius_gu":0.5,
		"screen_to_ground_position_px":Callable(get_script(), "_projection"),
		"ground_gu_to_screen_position_px":Callable(get_script(), "_screen")}
	var domain := context.duplicate()
	domain.erase("fallback_target_actor")
	domain.erase("player_actor")
	domain["target_actor_view"] = {"runtime_id":target.get_instance_id(),"position_screen_px":target.position}
	domain["player_actor_view"] = domain.target_actor_view
	for skill: String in ["wizard.lightning", "taoist.poison", "wizard.magic_shield", "taoist.invisibility"]:
		var legacy: Dictionary = Plan.build_release_snapshot(skill, "identity-view", {}, context)
		var detached: Dictionary = Plan.build_release_snapshot(skill, "identity-view", {}, domain)
		check(not legacy.is_empty() and legacy == detached, "same canonical snapshot for legacy/domain actor view: " + skill)
	domain["target_actor_view"] = {"runtime_id":-1,"position_screen_px":target.position}
	domain["fallback_target_actor"] = target
	check(Plan.build_release_snapshot("wizard.lightning", "invalid-view", {}, domain).is_empty(),
		"invalid explicit domain identity cannot fall back to a live Node")
	target.free()
	var receipt_ok: bool = proof.write_receipt("multicore_identity_plan_view_20261014", proof.records.size(), failures)
	print("MULTICORE_IDENTITY_PLAN_VIEW_20261014_", "PASS" if failures == 0 and receipt_ok else "FAIL")
	get_tree().quit(0 if failures == 0 and receipt_ok else 1)
