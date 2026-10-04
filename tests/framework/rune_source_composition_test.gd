extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
const Rune := preload("res://scripts/items/rune_item_rules.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
const SKILL := "hc.skill.wizard.ice_storm"
const EXPECTED := "res://outputs/test_logs/framework/rune_source_composition_expected.json"
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
var _last_item_request: Dictionary={}
var _last_rune_request: Dictionary={}

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)
func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.profession = "法师"; PlayerState.level = 50
	PlayerState.learned_skills = {SKILL:3}; PlayerState.recalculate_stats(false)
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/rune_composition_registry.json"),
		"trusted registry accepts the independently registered affix, embedded gem and rune sources")
	if not errors.is_empty():
		print("SOURCE_COMPOSITION_PUBLICATION_ERRORS="+JSON.stringify(ContentLayers.feature_load_errors)); _finish(); return
	var published: Dictionary = ContentLayers.feature_configuration()
	check(published.enabled_modules.is_empty(),"composition stays default-off before explicit fixture activation")
	check(not ContentLayers.reload_feature_catalog("res://assets/data/features/validation/source_composition_unknown_registry.json")
		and ContentLayers.feature_configuration()==published,"unknown affix identity rejects the whole candidate and preserves the published catalog")
	check(ContentLayers.set_feature_module_enabled(Gem.MODULE,true) and ContentLayers.set_feature_module_enabled(Rune.MODULE,true) and ContentLayers.set_feature_module_enabled("hc.ignite",true),
		"gem and rune business permissions and existing ignite activate through the formal configuration boundary")
	var base: Dictionary = {}
	for index in range(256):
		var candidate := Drop.create_instance(GameData.get_item_record({"item_id":85}),"source-composition:"+str(index))
		for modifier: Dictionary in candidate.get("modifiers",[]):
			if modifier.stat=="magic_max" and modifier.op=="add" and float(modifier.value)>0: base=candidate; break
		if not base.is_empty(): break
	check(not base.is_empty() and GameData.validate_item_drop_instance(base),"real immutable v3 drop generation supplies a validated positive magic affix")
	if base.is_empty(): _finish(); return
	var original_base := base.duplicate(true)
	var gem := Gem.create_instance("source-composition:gem",true)
	var rune := Rune.create_instance("source-composition:rune",true)
	var directory := "user://framework_source_composition_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = directory.path_join("characters")
	PlayerState.profile_index_path = directory.path_join("profiles.json")
	PlayerState.shared_warehouse_path = directory.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = directory.path_join("shared.transaction.json")
	PlayerState.active_profile_id = "source-composition"; PlayerState.character_name = "来源组合验收"
	PlayerState._shared_warehouse_initialized = false; PlayerState.set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.inventory = [base,gem,rune]; PlayerState.test_mode = false
	check(PlayerState.save_game(false,false),"production writer persists isolated real equipment and original gem and rune inputs")
	check(await _transaction("hc.socketing.insert",base.instance_id,gem.instance_id),"formal durable insertion gives the original gem one equipment owner")
	check(await _transaction("hc.runes.insert",base.instance_id,rune.instance_id),"the separate rune module durably owns its original asset beside the original gem")
	check(PlayerState.equip_inventory_index_result(0,"hc.slot.weapon",base.instance_id).get("success",false),"production equip compiles the actual affix and embedded sources")
	check(_handles().size()==3,"exactly three independent sources subscribe to the same ignite mechanism")
	var first_handles := _handles()
	if first_handles.size()!=3: _finish(); return
	check(first_handles[0]!=first_handles[1] and first_handles[1]!=first_handles[2] and first_handles[0]!=first_handles[2],"affix, gem and rune have distinct stable provenance handles")
	check(await _transaction("hc.socketing.remove",base.instance_id,""),"formal removal returns the original gem through the single writer")
	check(_handles().size()==2,"removing the gem withdraws its ignite contribution and preserves the real affix and rune")
	check(Codec.base_record(PlayerState.equipment["hc.slot.weapon"])==original_base,"socket removal does not reroll or edit historical v3 modifiers")
	check(await _transaction("hc.socketing.insert",base.instance_id,gem.instance_id),"a new issued operation reinserts the same uniquely owned gem")
	check(_handles()==first_handles,"reinsert reconstructs the same three logical source identities")
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	check(PlayerState._json_persistence.pending_count()==0,"accepted item receipts and ordinary save fully drain")
	PlayerState.load_save()
	check(PlayerState.last_load_result.success and _handles()==first_handles,"production reload rebuilds identical source provenance from the durable original items")
	check(Codec.ownership_ids(PlayerState.equipment["hc.slot.weapon"])==[base.instance_id,gem.instance_id,rune.instance_id]
		and PlayerState._validate_extended_item_ownership({"inventory":PlayerState.inventory,"equipment":PlayerState.equipment}),"saved and loaded composition has no duplicated embedded asset")
	var game := Root.new(); add_child(game)
	var deadline := Time.get_ticks_msec()+15000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),"real production world reaches READY with the composed equipment")
	if not game.gameplay_input_is_enabled(): game.queue_free(); await get_tree().process_frame; _finish(); return
	var target := await Fixture.prepare_target(self,game,game.player,19,"source_composition")
	check(target!=null,"actual mapped geometry supplies the receiver")
	if target==null: game.queue_free(); await get_tree().process_frame; _finish(); return
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	target.max_hp=10000; target.current_hp=10000; target.direct_spell_anti_magic_points=0
	target.direct_spell_magic_defense_min=0; target.direct_spell_magic_defense_max=0; target.direct_spell_stats_valid=true
	game.player.current_mp=100; game._skill_cast_target=target; game._set_magic_locked_target(target,true)
	var lease: RefCounted = game._capture_action_configuration(SKILL)
	check(lease!=null and lease.event_bindings_for(SKILL).size()==3,"real action captures all three formal contributions in one immutable lease")
	if lease==null: game.queue_free(); await get_tree().process_frame; _finish(); return
	check(game.player.request_skill(SKILL,target.get_instance_id(),lease) and lease.effect_reservation()!=null,"real windup accepts capacity for all three derived states")
	deadline=Time.get_ticks_msec()+3000
	while game.observed_releases==0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases==1 and is_same(game.observed_configuration,lease),"composed sources still use one actual release and planner")
	var loss: int = 10000-target.current_hp
	var runtime: RefCounted = game._feature_effect_runtime
	var root_rng: int=game._rng.state; var player_rng: int=game.player._rng.state
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count()==0: break
		await get_tree().process_frame
	check(loss>0 and runtime.active_count()==3,"one committed base hit starts three separately owned ignite states")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false) and _handles().is_empty(),"formal withdrawal removes future subscriptions without cancelling accepted states")
	for second in range(1,5):
		game._time_domains.advance_simulation(float(second*1000000-game._time_domains.simulation_usec())/1000000.0)
		for iteration in range(120):
			runtime.pump()
			if not runtime.has_due(): break
			await get_tree().process_frame
		check(target.current_hp==10000-loss-3*second*roundi(float(loss)*0.05),"three original source states each deliver their unchanged periodic damage at tick "+str(second))
	check(game._rng.state==root_rng and game.player._rng.state==player_rng,"source composition does not consume legacy combat random streams")
	check(runtime.errors.is_empty() and not runtime.has_work(),"composed producers, receipts and persistent states reach their terminal boundary")
	game.queue_free(); await get_tree().process_frame
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	if errors.is_empty():
		var expected: Dictionary={"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
			"profile_id":PlayerState.active_profile_id,"profile_directory":PlayerState.profile_directory,
			"profile_index_path":PlayerState.profile_index_path,"shared_warehouse_path":PlayerState.shared_warehouse_path,
			"shared_warehouse_transaction_log_path":PlayerState.shared_warehouse_transaction_log_path,
			"gear":PlayerState.equipment["hc.slot.weapon"],"gem_instance_id":gem.instance_id,"rune_instance_id":rune.instance_id,
			"source_handles":first_handles,"last_request":_last_item_request,"last_rune_request":_last_rune_request}
		var file:=FileAccess.open(EXPECTED,FileAccess.WRITE)
		check(file!=null,"this producer can write its owned cold expectation")
		if file!=null:
			file.store_string(JSON.stringify(expected)); file.flush()
			check(file.get_error()==OK,"complete cold expectation is written without ignoring I/O failure")
			file.close()
	PlayerState.test_mode=true; PlayerState.set_process(true)
	check(ContentLayers.reload_feature_catalog(),"retired world restores the original default-off registry")
	_finish()

func _handles() -> Array:
	var handles: Array=[]
	for binding: Dictionary in PlayerState.feature_bundle().get("event_index",{}).get("damage_committed:"+SKILL,[]): handles.append(binding.handle)
	handles.sort(); return handles

func _transaction(action: String,target: String,gem: String) -> bool:
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	var request: Dictionary={"action":action,"target_instance_id":target}
	request["rune_instance_id" if action.begins_with("hc.runes.") else "gem_instance_id"]=gem
	var quote: Dictionary=PlayerState.quote_new_item_transaction(request)
	if quote.get("success",false):
		_last_item_request=quote.request.duplicate(true)
		if action.begins_with("hc.runes."): _last_rune_request=quote.request.duplicate(true)
	var pending: Dictionary=PlayerState.commit_item_transaction(quote)
	var job: Variant=pending.get("job")
	if job==null: print("SOURCE_COMPOSITION_TRANSACTION="+JSON.stringify({"quote":quote,"pending":pending})); return false
	var deadline=Time.get_ticks_msec()+5000
	while not job.response.get("finished",false) and Time.get_ticks_msec()<deadline:
		PlayerState._json_persistence.pump(); await get_tree().process_frame
	return job.response.get("success",false)

func _finish() -> void:
	if not proof.write_receipt("rune_source_composition_test",checks,errors.size()): errors.append("receipt")
	print(("FRAMEWORK_RUNE_SOURCE_COMPOSITION_PASS" if errors.is_empty() else "FRAMEWORK_RUNE_SOURCE_COMPOSITION_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
