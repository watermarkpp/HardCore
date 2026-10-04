extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/child_admission_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
var game: Node
var runtime: RefCounted
var first: EnemyActor
var survivor: EnemyActor
var death_binding: Dictionary
var heal_binding: Dictionary
var reentry_calls := 0
var reentry_served := -1

func _ready() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1; proof.record(ok,label)
	if not ok: errors.append(label)

func _fresh_runtime() -> void:
	runtime=Runtime.new()
	check(runtime.configure(game._world_context,game._time_domains,game._combat_runtime)
		and runtime.configure_child_executor(Callable(game,"_execute_feature_child_action")),"same Root installs the real child executor")
	runtime.require_reservations=true; game._feature_effect_runtime=runtime

func _root_batch(label: String,bindings: Array,count: int,survivor_amount := 1) -> RefCounted:
	var ticket: RefCounted=runtime.reserve_action("hc.skill.wizard.ice_storm",bindings,85,label,85)
	check(ticket!=null,"full finite root promise "+label)
	if ticket==null: return null
	var made: Dictionary=Batch.create(game._world_context,label,"hc.skill.wizard.ice_storm",bindings,
		{"profile_id":PlayerState.active_profile_id},game._time_domains.simulation_usec(),ticket,null,ticket.chain_context(label))
	check(made.success and made.batch.begin_base_scope(),"accepted batch opens only after receiving its ticket "+label)
	if not made.success: return null
	var batch: RefCounted=made.batch
	first.take_damage(20,game.player,{"source_class":"direct","damage_channel":"magic_defense","feature_damage_batch":batch})
	for i in range(count-1):
		survivor.take_damage(survivor_amount,game.player,{"source_class":"direct","damage_channel":"magic_defense","feature_damage_batch":batch})
	check(batch.facts().size()==count and batch.finish_base_scope() and runtime.submit_batch(batch),"actual HP facts transfer once "+label)
	batch.finish_production()
	return batch

func _prepare_first(label: String) -> void:
	if is_instance_valid(first): first.queue_free(); await get_tree().process_frame
	first=game._spawn_enemy(GameData.get_monster_by_id(19),
		game._canonical_ground_gu_to_screen_px(Vector2(40.5,13.5)),false,-1.0,
		{"respawn_enabled":false,"spawn_slot_id":"test:formal_skill:chain_guard:19"})
	check(first!=null,"same declared first slot supplies a replacement life "+label)
	if first!=null:
		first.set_physics_process(false); first.max_hp=1000; first.current_hp=20
		first.direct_spell_anti_magic_points=0; first.direct_spell_magic_defense_min=0
		first.direct_spell_magic_defense_max=0; first.direct_spell_stats_valid=true

func _settle() -> void:
	for i in range(240):
		runtime.pump()
		if runtime.pending_count()==0 and runtime.child_count()==0: return
		await get_tree().process_frame
	check(false,"finite child work settles")

func _on_stats(_hp: int,_maximum: int) -> void:
	if reentry_calls>0: return
	reentry_calls+=1
	reentry_served=runtime.pump()

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	check(PlayerState.set_profession_identity("hc.profession.wizard"),"stable wizard identity")
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/child_chain_guard_registry.json"),"formal default-off mixed registry")
	if not errors.is_empty(): _finish(); return
	game=Root.new(); add_child(game)
	var deadline:=Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"real mapped world reaches READY")
	if not game.gameplay_input_is_enabled(): game.queue_free(); _finish(); return
	first=await Fixture.prepare_target(self,game,game.player,19,"chain_guard")
	survivor=game._spawn_enemy(GameData.get_monster_by_id(64),
		game._canonical_ground_gu_to_screen_px(Vector2(43.1,13.5)),false,-1.0,
		{"respawn_enabled":false,"spawn_slot_id":"test:chain_guard:survivor"})
	var extra: EnemyActor=game._spawn_enemy(GameData.get_monster_by_id(64),
		game._canonical_ground_gu_to_screen_px(Vector2(53.5,13.5)),false,-1.0,
		{"respawn_enabled":false,"spawn_slot_id":"test:chain_guard:extra"})
	check(extra!=null,"the third declared factory slot is real rather than a fabricated receiver limit")
	check(first!=null and survivor!=null and game.feature_world_capacity_bound().maximum_receivers==85,"real factory has the same 85-slot bound")
	if first==null or survivor==null: game.queue_free(); _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	for actor: EnemyActor in [first,survivor]:
		actor.max_hp=100000; actor.current_hp=100000
		actor.direct_spell_anti_magic_points=0; actor.direct_spell_magic_defense_min=0
		actor.direct_spell_magic_defense_max=0; actor.direct_spell_stats_valid=true
	first.current_hp=20
	check(ContentLayers.set_feature_module_enabled("hc.validation.child_chain_guard",true),"READY publishes mixed trusted sources")
	var all_bindings: Array=PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	for binding: Dictionary in all_bindings:
		if binding.definition.handler_id=="hc.lifesteal.v1": heal_binding=binding
		elif binding.definition.handler_id=="hc.death_burst.v1": death_binding=binding
	check(not heal_binding.is_empty() and not death_binding.is_empty(),"both qualified bindings come from the actual bundle")
	if heal_binding.is_empty() or death_binding.is_empty(): game.queue_free(); _finish(); return
	_fresh_runtime()
	var held: Array[RefCounted]=[]
	var root_batch:=_root_batch("guard:partial",[death_binding],85)
	if root_batch==null: game.queue_free(); _finish(); return
	for i in range(94):
		var ticket: RefCounted=runtime.reserve_action("hc.skill.wizard.ice_storm",[heal_binding],85,"guard:held:"+str(i),85)
		if ticket!=null: held.append(ticket)
	check(held.size()==94,"94 legitimate zero-state producers coexist with the admitted chain")
	var total_before: int=runtime.pending_count()+int(runtime.reservation_snapshot().facts)
	check(total_before==8160,"initial facts plus resident promises total exactly 8160")
	for i in range(53): runtime._dispatch_one_fact()
	var partial: Dictionary=runtime.reservation_snapshot()
	check(runtime.pending_count()==32 and int(partial.facts)+runtime.pending_count()==8160,
		"each consumed fact remains charged to its live root before the entire branch finishes")
	var competing: RefCounted=runtime.reserve_action("hc.skill.wizard.ice_storm",[heal_binding],85,"guard:competing",85)
	check(competing==null,"competing 85-fact producer is rejected before any resource/HP change")
	for i in range(32): runtime._dispatch_one_fact()
	check(int(runtime.reservation_snapshot().facts)+runtime.pending_count()<=Runtime.MAX_PENDING_FACTS,
		"final branch completion cannot raise total commitments above existing capacity")
	var hp_before: int=survivor.current_hp
	await _settle()
	check(survivor.current_hp==hp_before-10 and runtime.metrics().child_actions==1 and runtime.errors.is_empty(),
		"the admitted child still commits and transfers its full fact after partial drain and competition")
	if competing!=null: competing.close()
	for ticket: RefCounted in held: ticket.close()
	check(not runtime.has_work() and runtime.reservation_snapshot().actions==0,"all first-case owners explicitly retire")

	await _prepare_first("reentry"); _fresh_runtime()
	game.player.current_hp=50; game.player.stats_changed.connect(_on_stats)
	root_batch=_root_batch("guard:reentry",[heal_binding,death_binding],2)
	if root_batch!=null: await _settle()
	game.player.stats_changed.disconnect(_on_stats)
	check(reentry_calls==1 and reentry_served==0,"real Player healing notification attempts reentry once without running a second consumer")
	check(runtime.metrics().child_actions==1 and runtime.errors.is_empty(),"outer death subscription retains its root until all synchronous consumers return")
	check(not runtime.has_work() and runtime.reservation_snapshot().receipts==0,"reentry leaves no root/branch/receipt work")

	await _prepare_first("submit_retirement"); _fresh_runtime()
	game.child_results.clear(); game.clear_before_child_submit=true
	root_batch=_root_batch("guard:retirement",[death_binding],1)
	hp_before=survivor.current_hp
	if root_batch!=null: await _settle()
	check(game.clear_count==1 and survivor.current_hp==hp_before-10,"explicit retirement occurs after actual child HP capture without rolling HP back")
	check(game.child_results.size()==1 and not game.child_results[0].success,
		"Root reports the actual failed transfer/retired owner instead of falsely successful child execution")
	check(runtime.metrics().child_actions==0 and not runtime.has_work(),"retired child is never counted as successful delivery")

	await _prepare_first("sibling_production"); _fresh_runtime()
	survivor.current_hp=40
	extra.max_hp=1000; extra.current_hp=1000
	extra.direct_spell_anti_magic_points=0; extra.direct_spell_magic_defense_min=0
	extra.direct_spell_magic_defense_max=0; extra.direct_spell_stats_valid=true
	extra.set_combat_position(game._canonical_ground_gu_to_screen_px(Vector2(45.7,13.5)),&"test_guard_later_receiver")
	game.child_results.clear(); game.reenter_before_child_submit=true
	root_batch=_root_batch("guard:sibling_production",[death_binding],2,40)
	if root_batch!=null: await _settle()
	check(game.child_reentry_calls==1 and game.child_reentry_served==0 and game.maximum_producing_branches==1,
		"unsealed real child production cannot start a second queued sibling through synchronous pump")
	check(game.child_results.size()==2 and game.child_results[0].success and game.child_results[0].batch_outcome=="empty"
		and game.child_results[1].success and game.child_results[1].batch_outcome=="transferred",
		"a legitimate empty release and a transferred sibling have distinct accurate successful terminal outcomes")
	check(extra.current_hp==980 and runtime.metrics().child_actions==2 and runtime.errors.is_empty(),
		"both owned siblings execute in order and their real HP/consumer results complete once")
	check(not runtime.has_work() and runtime.reservation_snapshot().receipts==0,"sibling production releases the full chain only after terminal consumption")
	game.queue_free(); await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(),"world retirement restores the original registry")
	_finish()

func _finish() -> void:
	var written:=proof.write_receipt("feature_child_chain_admission_test",checks,errors.size())
	print("FEATURE_CHILD_CHAIN_ADMISSION_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",checks," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
