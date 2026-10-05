extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://tests/framework/fixtures/lease_probe_root.gd")
const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
const Rune := preload("res://scripts/items/rune_item_rules.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
const SKILL := "hc.skill.wizard.ice_storm"
const CHAIN := "hc.validation.mixed_delivery_chain"
const HEAL := "hc.validation.lifesteal"
const REGISTRY := "res://assets/data/features/validation/mixed_delivery_registry.json"
const AUDIO := "res://assets/audio/sfx/client/10332__M33-3.wav"
@export var fatal_initial_hit := false
var proof := Proof.new()
var errors: Array[String] = []
var rows: Array[Dictionary] = []
var audio_rows: Array[Dictionary] = []
var _audio_game: Node
var _audio_resources: RefCounted

func _ready() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: errors.append(label)

func _run() -> void:
	for mask in range(8):
		if not await _case(mask): break
	PlayerState.test_mode=true; PlayerState.set_process(true)
	check(ContentLayers.reload_feature_catalog(),"all controlled worlds retire before restoring the formal default registry")
	var scene: String="feature_mixed_child_resource_test" if fatal_initial_hit else "feature_mixed_delivery_test"
	var trace:=FileAccess.open("res://outputs/test_logs/framework/"+scene+".trace.json",FileAccess.WRITE)
	check(trace!=null,"bounded eight-case evidence has an owned output file")
	if trace!=null:
		trace.store_string(JSON.stringify({"run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),
			"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
			"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),
			"scope":"eight controlled real item/writer/Root combinations; simulation steps are test-owned; no natural or device claim",
			"fatal_initial_hit":fatal_initial_hit,"rows":rows},"  "))
		trace.flush(); check(trace.get_error()==OK,"bounded combination trace writes without ignoring I/O failure"); trace.close()
	check(rows.size()==8,"all eight generated gem/rune/healing selections complete")
	var written:=proof.write_receipt(scene,proof.records.size(),errors.size())
	print("FEATURE_MIXED_DELIVERY_",("PASS" if written and errors.is_empty() else "FAIL")," scene=",scene," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)

func _case(mask: int) -> bool:
	var prefix: String="mask="+str(mask)+" "
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	check(PlayerState.set_profession_identity("hc.profession.wizard"),prefix+"registered profession")
	PlayerState.level=50; PlayerState.learned_skills={SKILL:3}; PlayerState.recalculate_stats(false)
	var loaded: bool=await ContentLayers.reload_feature_catalog_async(REGISTRY)
	check(loaded,prefix+"formal async preparation closes base and child sound dependencies")
	if not loaded: return false
	for id: String in [Gem.MODULE,Rune.MODULE,CHAIN]:
		var activated: bool=await ContentLayers.set_feature_module_enabled_async(id,true)
		check(activated,prefix+"formal resource-ready activation before item operations: "+id)
		if not activated: print("MIXED_ACTIVATION_REJECT ",JSON.stringify({"id":id,"errors":ContentLayers.feature_load_errors})); return false
	var healing: bool=(mask & 4)!=0
	if healing: check(await ContentLayers.set_feature_module_enabled_async(HEAL,true),prefix+"independent healing contribution activates with the same ready resource closure")
	var base: Dictionary={}
	for attempt in range(256):
		var candidate:=Drop.create_instance(GameData.get_item_record({"item_id":85}),"mixed-delivery:"+str(mask)+":"+str(attempt))
		for modifier: Dictionary in candidate.get("modifiers",[]):
			if modifier.stat=="magic_max" and modifier.op=="add" and float(modifier.value)>0: base=candidate; break
		if not base.is_empty(): break
	check(not base.is_empty() and GameData.validate_item_drop_instance(base),prefix+"formal v3 drop provides a validated affix")
	if base.is_empty(): return false
	var original: Dictionary=base.duplicate(true)
	# The persisted JSON boundary represents numeric values as floats. Compare
	# every exact serialized field, including the immutable authored modifiers.
	var original_wire: Dictionary=JSON.parse_string(JSON.stringify(original))
	var gem: Dictionary=Gem.create_instance("mixed-delivery:gem:"+str(mask),true)
	var rune: Dictionary=Rune.create_instance("mixed-delivery:rune:"+str(mask),true)
	var directory: String="user://framework_mixed_delivery_"+OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")+"_"+str(mask)
	PlayerState.profile_directory=directory.path_join("characters"); PlayerState.profile_index_path=directory.path_join("profiles.json")
	PlayerState.shared_warehouse_path=directory.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path=directory.path_join("shared.transaction.json")
	PlayerState.active_profile_id="mixed-delivery"; PlayerState.character_name="混合来源验收"
	PlayerState._shared_warehouse_initialized=false; PlayerState.set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.inventory=[base]
	if (mask & 1)!=0: PlayerState.inventory.append(gem)
	if (mask & 2)!=0: PlayerState.inventory.append(rune)
	PlayerState.test_mode=false
	check(PlayerState.save_game(false,false),prefix+"production writer stores original isolated inputs")
	if (mask & 1)!=0: check(await _transaction("hc.socketing.insert",base.instance_id,gem.instance_id),prefix+"gem transfers through the original durable transaction port")
	if (mask & 2)!=0: check(await _transaction("hc.runes.insert",base.instance_id,rune.instance_id),prefix+"rune transfers through the original durable transaction port")
	check(PlayerState.equip_inventory_index_result(0,"hc.slot.weapon",base.instance_id).get("success",false),prefix+"original equip publishes the composed sources")
	PlayerState._start_item_save(); PlayerState._json_persistence.drain(); PlayerState.load_save()
	var source_count: int=1+(1 if (mask & 1)!=0 else 0)+(1 if (mask & 2)!=0 else 0)
	var handles: Array=[]
	for binding: Dictionary in PlayerState.feature_bundle().event_index.get("damage_committed:"+SKILL,[]):
		if binding.definition.mechanic_id=="hc.ignite.ice_storm": handles.append(binding.handle)
	check(PlayerState.last_load_result.success and handles.size()==source_count and _unique(handles),prefix+"durable load restores exact distinct affix/gem/rune provenance")
	var loaded_base: Dictionary=Codec.base_record(PlayerState.equipment["hc.slot.weapon"])
	if JSON.parse_string(JSON.stringify(loaded_base))!=original_wire:
		var differences: Dictionary={}
		var keys: Array=original.keys()
		for key: String in loaded_base:
			if key not in keys: keys.append(key)
		for key: String in keys:
			if original.get(key)!=loaded_base.get(key): differences[key]={"before":original.get(key),"after":loaded_base.get(key)}
		var types: Dictionary={}
		for key: String in keys:
			if typeof(original.get(key))!=typeof(loaded_base.get(key)):
				types[key]={"before":typeof(original.get(key)),"after":typeof(loaded_base.get(key))}
		print("MIXED_BASE_DIFFERENCE ",JSON.stringify({"mask":mask,"differences":differences,"top_level_types":types,
			"exact_json_values":JSON.parse_string(JSON.stringify(original))==JSON.parse_string(JSON.stringify(loaded_base))}))
	check(JSON.parse_string(JSON.stringify(loaded_base))==original_wire and GameData.validate_item_drop_instance(loaded_base)
		and Codec.ownership_ids(PlayerState.equipment["hc.slot.weapon"]).size()==source_count,
		prefix+"embedding preserves historical modifiers and unique asset ownership")
	var game:=Root.new(); add_child(game)
	var deadline:=Time.get_ticks_msec()+20000
	while not game.gameplay_input_is_enabled() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.gameplay_input_is_enabled(),prefix+"mapped production world reaches READY")
	if not game.gameplay_input_is_enabled(): await _retire(game); return false
	var descriptors: Array[Dictionary] = [
		{"id": 19, "ground": Fixture.FIXTURE_GROUND_POSITION, "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:formal_skill:mixed_delivery:19"}},
		{"id": 19, "ground": Vector2(43.1,13.5), "respawn": -1.0, "context": {"respawn_enabled": false, "spawn_slot_id": "test:mixed_delivery:later"}},
	]
	var published_targets := await Fixture.prepare_published_target_set(self, game, game.player, descriptors, "mixed_delivery")
	var target: EnemyActor = published_targets[0]
	check(target!=null,prefix+"sole Root factory creates the initial receiver")
	if target==null: await _retire(game); return false
	var later: EnemyActor = published_targets[1]
	check(later!=null,prefix+"declared child receiver starts outside the direct footprint")
	if later==null: await _retire(game); return false
	game.set_process(false); game.set_physics_process(false); game.player.set_physics_process(false)
	for actor: Node in get_tree().get_nodes_in_group("enemies"): actor.set_physics_process(false)
	var initial_hp: int=20 if fatal_initial_hit else 10000
	_prepare(target,initial_hp); _prepare(later,10000)
	game.player.current_hp=50; game.player.current_mp=100
	game._skill_cast_target=target; game._set_magic_locked_target(target,true)
	_audio_game=game; audio_rows=[]; game._audio_runtime_service.event_started.connect(_observe_audio)
	var lease: RefCounted=game._capture_action_configuration(SKILL)
	check(lease!=null and lease.event_bindings_for(SKILL).size()==source_count+2+(1 if healing else 0),prefix+"one immutable action captures the complete mixed binding set")
	if lease==null: await _retire(game); return false
	_audio_resources=lease.resource_lease()
	check(_audio_resources!=null and _audio_resources.resource_at(AUDIO) is AudioStream,prefix+"accepted resource closure contains the actual child sound")
	if _audio_resources==null: await _retire(game); return false
	var resource_owner: WeakRef=weakref(_audio_resources)
	var accepted: bool=game.player.request_skill(SKILL,target.get_instance_id(),lease)
	check(accepted and lease.is_accepted() and lease.effect_reservation()!=null,prefix+"real windup reserves complete world and per-target derived capacity")
	if not accepted: _audio_resources=null; await _retire(game); return false
	for id: String in ["hc.ignite",CHAIN,HEAL,Gem.MODULE,Rune.MODULE,"hc.ignite_cue_assets"]:
		if ContentLayers.feature_configuration().enabled_modules.has(id): check(ContentLayers.set_feature_module_enabled(id,false),prefix+"withdraw future source "+id)
	check(PlayerState.feature_bundle().event_index.is_empty(),prefix+"withdrawal removes future work while retaining accepted obligations")
	# Keep the formal equipped profile's release-time primary-stat authority.
	deadline=Time.get_ticks_msec()+3000
	while game.observed_releases==0 and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	check(game.observed_releases==1 and game.observed_execution.get("accepted",false),prefix+"real SceneTreeTimer releases exactly once through the sole planner")
	var loss: int=initial_hp-target.current_hp
	check(loss>0 and (not fatal_initial_hit or loss==initial_hp) and later.current_hp==10000,prefix+"base commit uses actual loss and does not pre-execute the child")
	var runtime: RefCounted=game._feature_effect_runtime
	var old_rng: int=game._rng.state; var player_rng: int=game.player._rng.state; var mp: int=game.player.current_mp
	check(await _pump(runtime),prefix+"production consumer completes base and finite child facts")
	var states: int=1 if fatal_initial_hit else source_count+1
	var child_loss: int=10000-later.current_hp
	check(runtime.active_count()==states and runtime.presentation().node_count()==states,prefix+"every surviving declared source has one actual native cue")
	check(runtime.metrics().child_actions==(1 if fatal_initial_hit else 0)
		and (not fatal_initial_hit or child_loss==loss),prefix+"finite child uses committed loss exactly once and existing Root geometry")
	if fatal_initial_hit: check(target.current_hp==0 and target.collision_layer==0 and target.collision_mask==0,prefix+"fatal base commit immediately removes collision")
	var gain: int=floori(float(loss)*0.25) if healing else 0
	check(game.player.current_hp==50+gain and runtime.metrics().healing_commands==(1 if healing else 0),prefix+"direct healing uses actual loss once without child feedback")
	check(not audio_rows.is_empty() and _audio_rows_valid(),prefix+"existing audio service consumes the exact accepted stream for native cues")
	_audio_resources=null; lease=null
	var raw: int=roundi(float(child_loss if fatal_initial_hit else loss)*0.05)
	for tick in range(1,5):
		game._time_domains.advance_simulation(1.0)
		check(await _pump(runtime),prefix+"original period work completes at tick "+str(tick))
		var hp: int=later.current_hp if fatal_initial_hit else target.current_hp
		check(hp==10000-(child_loss if fatal_initial_hit else loss)-states*tick*raw,prefix+"all original periodic sources deliver unchanged damage at tick "+str(tick))
		check(game.player.current_hp==50+gain,prefix+"periodic work cannot recursively heal at tick "+str(tick))
	check(runtime.metrics().ticks==4*states and runtime.metrics().child_actions==(1 if fatal_initial_hit else 0),prefix+"complete delivery counts retain the authored finite bounds")
	var empty:=true
	for count: int in runtime.reservation_snapshot().values(): empty=empty and count==0
	check(empty and not runtime.has_work() and runtime.errors.is_empty() and runtime.presentation().node_count()==0,prefix+"all promises states heaps receipts and cues terminate")
	await get_tree().process_frame
	check(resource_owner.get_ref()==null,prefix+"last accepted state and native cue release their prepared resource owner")
	check(game._rng.state==old_rng and game.player._rng.state==player_rng and game.player.current_mp==mp,prefix+"derived work preserves old RNG and player resource charges")
	rows.append({"mask":mask,"source_handles":handles,"base_loss":loss,"child_loss":child_loss,"healing":gain,
		"ticks":runtime.metrics().ticks,"child_actions":runtime.metrics().child_actions,"audio":audio_rows.duplicate(true)})
	await _retire(game)
	return true

func _prepare(target: EnemyActor,hp: int) -> void:
	target.set_physics_process(false); target.max_hp=10000; target.current_hp=hp
	target.direct_spell_anti_magic_points=0; target.direct_spell_magic_defense_min=0
	target.direct_spell_magic_defense_max=0; target.direct_spell_stats_valid=true

func _transaction(action: String,target: String,embedded: String) -> bool:
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	var request: Dictionary={"action":action,"target_instance_id":target}
	request["rune_instance_id" if action.begins_with("hc.runes.") else "gem_instance_id"]=embedded
	var quote: Dictionary=PlayerState.quote_new_item_transaction(request)
	var result: Dictionary=PlayerState.commit_item_transaction(quote)
	var job: Variant=result.get("job")
	if job==null: print("MIXED_TRANSACTION_REJECT ",JSON.stringify({"quote":quote,"result":result})); return false
	var deadline:=Time.get_ticks_msec()+5000
	while not job.response.get("finished",false) and Time.get_ticks_msec()<deadline:
		PlayerState._json_persistence.pump(); await get_tree().process_frame
	return job.response.get("success",false)

func _pump(runtime: RefCounted) -> bool:
	for frame in range(200):
		runtime.pump()
		if runtime.pending_count()==0 and runtime.child_count()==0 and not runtime.has_due(): return true
		await get_tree().process_frame
	return false

func _observe_audio(event: Dictionary) -> void:
	if not event.context.has("feature_effect_handle"): return
	var player: AudioStreamPlayer=_audio_game._audio_runtime_service._event_players[int(event.pool_index)]
	audio_rows.append({"handle":event.context.feature_effect_handle,"request_serial":event.request_serial,"path":event.runtime_path,
		"exact_stream":_audio_resources!=null and is_same(player.stream,_audio_resources.resource_at(AUDIO))})

func _audio_rows_valid() -> bool:
	for row: Dictionary in audio_rows:
		if row.path!=AUDIO or not row.exact_stream: return false
	return true

func _unique(values: Array) -> bool:
	var seen: Dictionary={}
	for value: Variant in values:
		if seen.has(value): return false
		seen[value]=true
	return true

func _retire(game: Node) -> void:
	_audio_resources=null; _audio_game=null
	game.queue_free(); await get_tree().process_frame
