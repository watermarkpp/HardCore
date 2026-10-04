extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Actor := preload("res://scripts/features/contracts/actor_ref.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []

func _ready() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1; proof.record(ok,label)
	if not ok: errors.append(label)

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	var game:=Root.new(); add_child(game)
	var deadline:=Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"production mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for enemy: Node in get_tree().get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	var position: Vector2=game._canonical_ground_gu_to_screen_px(Vector2(40.5,13.5))
	var context: Dictionary={"respawn_enabled":false,"spawn_slot_id":"test:birth_slot_identity:19"}
	var initial: Dictionary=game.feature_world_capacity_bound()
	var first: EnemyActor=game._spawn_enemy(GameData.get_monster_by_id(19),position,false,-1.0,context)
	check(first!=null and first.can_receive_damage(),"first actual life occupies its stable base factory slot")
	if first==null: game.queue_free(); _finish(); return
	first.set_physics_process(false)
	var bound: Dictionary=game.feature_world_capacity_bound()
	check(bound.proved and int(bound.maximum_receivers)==int(initial.maximum_receivers)+1,
		"the base slot contributes exactly one legal receiver to the original world proof")
	var serial: int=game._runtime_spawn_serial
	var actors_before: int=get_tree().get_nodes_in_group("enemies").size()
	var original_hp: int=first.current_hp
	var duplicate: EnemyActor=game._spawn_enemy(GameData.get_monster_by_id(19),position,false,-1.0,context)
	check(duplicate==null,"a still-live base slot cannot materialize a second receiver without another declared allowance")
	check(game._runtime_spawn_serial==serial and get_tree().get_nodes_in_group("enemies").size()==actors_before,
		"duplicate rejection precedes actor allocation, registration and birth serial changes")
	check(first.current_hp==original_hp and first.can_receive_damage() and game.feature_world_capacity_bound()==bound,
		"the original receiver and frozen declared world bound remain intact")
	if duplicate!=null: duplicate.queue_free(); await get_tree().process_frame
	var old_ref: RefCounted=Actor.capture(game._world_context,first)
	first.take_damage(first.current_hp,game.player,{"source_class":"direct","damage_channel":"magic_defense"})
	check(first.current_hp==0 and not first.is_queued_for_deletion() and first.collision_layer==0,
		"real fatal HP immediately removes collision while the old body still awaits its deferred death")
	serial=game._runtime_spawn_serial
	var premature: EnemyActor=game._spawn_enemy(GameData.get_monster_by_id(19),position,false,-1.0,context)
	check(premature==null and game._runtime_spawn_serial==serial,
		"a not-yet-retired body cannot share its base slot with a replacement during deferred death or revival")
	if premature!=null: premature.queue_free()
	first.queue_free()
	var replacement: EnemyActor=game._spawn_enemy(GameData.get_monster_by_id(19),position,false,-1.0,context)
	check(replacement!=null and old_ref.resolve(false)==null,
		"queued retirement revokes the old life immediately while a legal replacement uses the same slot")
	check(game.feature_world_capacity_bound()==bound,"replacement does not grow or erase the accepted factory allowance")
	if replacement!=null:
		replacement.set_physics_process(false)
		check(replacement.get_instance_id()!=int(old_ref.identity().runtime_id),"replacement has a distinct actual actor identity")
	game.queue_free(); await get_tree().process_frame
	_finish()

func _finish() -> void:
	var written:=proof.write_receipt("feature_birth_slot_identity_test",checks,errors.size())
	print("FEATURE_BIRTH_SLOT_IDENTITY_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",checks," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
