extends Node
const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
const Rune := preload("res://scripts/items/rune_item_rules.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
const Journal := preload("res://scripts/items/item_transaction_journal.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof:=Proof.new()
var checks:=0
var failures: Array[String]=[]
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks+=1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false); PlayerState.set_process(false)
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/rune_composition_registry.json"),"trusted registry resolves a separately registered default-off rune business module")
	var base: Dictionary={}
	for index in range(256):
		var candidate:=Drop.create_instance(GameData.get_item_record({"item_id":85}),"rune-transaction:"+str(index))
		for modifier: Dictionary in candidate.get("modifiers",[]):
			if modifier.stat=="magic_max" and modifier.op=="add" and float(modifier.value)>0: base=candidate; break
		if not base.is_empty(): break
	var gem:=Gem.create_instance("rune-transaction:gem",true)
	var rune:=Rune.create_instance("rune-transaction:rune",true)
	check(not base.is_empty() and not gem.is_empty() and not rune.is_empty(),"actual registered creators supply immutable gear and independently identified gem and rune")
	if not failures.is_empty(): _finish(); return
	var directory: String="user://framework_rune_transaction_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory=directory.path_join("characters"); PlayerState.profile_index_path=directory.path_join("profiles.json")
	PlayerState.shared_warehouse_path=directory.path_join("shared.json"); PlayerState.shared_warehouse_transaction_log_path=directory.path_join("shared.transaction.json")
	PlayerState.active_profile_id="rune-transaction"; PlayerState.character_name="符文事务验收"
	PlayerState._shared_warehouse_initialized=false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory))
	PlayerState.profession="法师"; PlayerState.level=50; PlayerState.learned_skills={"hc.skill.wizard.ice_storm":3}
	PlayerState.inventory=[base,gem,rune]; PlayerState.gold=500; PlayerState.recalculate_stats(false); PlayerState.test_mode=false
	check(PlayerState.save_game(false,false),"original three assets use the actual isolated profile writer")
	var input: Dictionary={"action":"hc.runes.insert","target_instance_id":base.instance_id,"rune_instance_id":rune.instance_id}
	check(not PlayerState.quote_new_item_transaction(input).get("success",false),"rune operation is unavailable before explicit module enablement")
	check(ContentLayers.set_feature_module_enabled(Rune.MODULE,true) and ContentLayers.set_feature_module_enabled(Gem.MODULE,true)
		and ContentLayers.set_feature_module_enabled("hc.ignite",true),"formal module activation enables the three declared source permissions")
	var wrong_field: Dictionary={"action":"hc.runes.insert","target_instance_id":base.instance_id,"gem_instance_id":rune.instance_id}
	check(not PlayerState.quote_new_item_transaction(wrong_field).get("success",false)
		and PlayerState._json_persistence.pending_count()==0,"rune commands refuse the gem field without scheduling a writer")
	var wrong_type:=input.duplicate(true); wrong_type.rune_instance_id=42
	check(not PlayerState.quote_new_item_transaction(wrong_type).get("success",false)
		and PlayerState._json_persistence.pending_count()==0,"rune commands refuse non-string instance identity without scheduling a writer")
	var quote:=PlayerState.quote_new_item_transaction(input)
	check(quote.get("success",false),"real common transaction port admits the correctly identified rune input")
	if not quote.get("success",false): print("RUNE_TRANSACTION_RED_REASON="+str(quote.get("reason"))); _finish(); return
	var before:=PlayerState.inventory.duplicate(true)
	var pending:=PlayerState.commit_item_transaction(quote)
	check(pending.get("pending",false) and PlayerState.inventory==before,"accepted rune stays pending without exposing or consuming assets before durability")
	check(PlayerState.commit_item_transaction(quote).get("job")==pending.get("job") and PlayerState._json_persistence.pending_count()==1,"double submission shares the sole accepted writer")
	var reserved_before: bool=PlayerState._item_transaction_port.record_reserved(rune)
	var destruction:=PlayerState.destroy_inventory_indices([2])
	print("RUNE_RESERVED_DESTRUCTION="+JSON.stringify({"reserved_before":reserved_before,"result":destruction,
		"inventory_unchanged":PlayerState.inventory==before,"writer_finished":pending.job.response.get("finished",false)}))
	check(not destruction.get("success",false) and PlayerState.inventory==before and not pending.job.response.get("finished",false),"actual destruction cannot consume the reserved original rune or complete its pending writer")
	check(destruction.get("reason")=="item_transaction_pending" and PlayerState._json_persistence.pending_count()==1
		and PlayerState._item_transaction_port.record_reserved(rune),"refusal preserves the sole writer and the original rune reservation")
	check(not PlayerState.destroy_inventory_indices([1,2]).get("success",false) and PlayerState.inventory==before
		and not pending.job.response.get("finished",false),"mixed selection containing a reserved rune destroys neither the unrelated gem nor the rune")
	check(not PlayerState.destroy_inventory_indices([0]).get("success",false) and PlayerState.inventory==before
		and not pending.job.response.get("finished",false),"the reserved original equipment is protected at the same pre-drain boundary")
	check(await _wait(pending.get("job")),"real ordered writer returns the durable rune receipt")
	check(Codec.ownership_ids(PlayerState.inventory[0])==[base.instance_id,rune.instance_id] and PlayerState.inventory[2].is_empty(),"durable publication moves the original rune into exactly one owner")
	before=PlayerState.inventory.duplicate(true)
	check(not PlayerState.destroy_inventory_indices([0]).get("success",false) and PlayerState.inventory==before,"actual destruction of a rune-only host cannot lose the original embedded asset")
	check(PlayerState.commit_item_transaction(quote).get("durable",false) and PlayerState._json_persistence.pending_count()==0,"old success replays without another writer")
	check(await _transaction("hc.socketing.insert",base.instance_id,gem.instance_id),"original socket operation remains usable after a rune is embedded")
	check(Codec.ownership_ids(PlayerState.inventory[0])==[base.instance_id,gem.instance_id,rune.instance_id],"socket insertion preserves the independently owned rune namespace")
	check(PlayerState.equip_inventory_index_result(0,"hc.slot.weapon",base.instance_id).get("success",false),"actual production equip compiles the original gear with all three sources")
	var all:=_handles()
	check(all.size()==3,"real compiler retains distinct affix, gem and rune subscriptions to one ignite mechanism")
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	var available_inventory:=PlayerState.inventory.duplicate(true)
	PlayerState.inventory.resize(PlayerState.INVENTORY_CAPACITY)
	for index in PlayerState.inventory.size():
		if not PlayerState.inventory[index] is Dictionary or PlayerState.inventory[index].is_empty():
			PlayerState.inventory[index]={"item_id":88,"name":GameData.get_item_record({"item_id":88}).name,"count":1}
	var full_inventory:=PlayerState.inventory.duplicate(true)
	var full_equipment:=PlayerState.equipment.duplicate(true)
	var no_room:=PlayerState.quote_new_item_transaction({"action":"hc.runes.remove","target_instance_id":base.instance_id,"rune_instance_id":""})
	check(not no_room.get("success",false) and no_room.get("reason")=="inventory_full"
		and PlayerState._json_persistence.pending_count()==0 and PlayerState.inventory==full_inventory
		and PlayerState.equipment==full_equipment,"full inventory refuses rune extraction before consuming ownership or starting a writer")
	PlayerState.inventory=available_inventory
	check(await _transaction("hc.runes.remove",base.instance_id,""),"common writer removes the rune while keeping socket ownership")
	var without_rune:=_handles()
	check(without_rune.size()==2 and _subset(without_rune,all),"removing rune withdraws only its source and keeps the original two handles")
	check(Codec.ownership_ids(PlayerState.equipment["hc.slot.weapon"])==[base.instance_id,gem.instance_id],"rune removal never discards the original gem")
	check(await _transaction("hc.runes.insert",base.instance_id,rune.instance_id) and _handles()==all,"reinserting the exact rune rebuilds all three original source identities")
	check(await _transaction("hc.socketing.remove",base.instance_id,""),"socket removal coexists with an embedded rune")
	check(_handles().size()==2 and _subset(_handles(),all) and Codec.ownership_ids(PlayerState.equipment["hc.slot.weapon"])==[base.instance_id,rune.instance_id],"socket removal preserves rune ownership and contribution")
	check(await _transaction("hc.socketing.insert",base.instance_id,gem.instance_id) and _handles()==all,"returning the original gem restores the exact three logical handles")
	check(Codec.base_record(PlayerState.equipment["hc.slot.weapon"])==base and PlayerState.gold==500,"neither module rerolls the old base or introduces a formal fee")
	check(not Codec.can_release_ownership(PlayerState.equipment["hc.slot.weapon"]),"shared ownership gate refuses discarding either original embedded asset")
	PlayerState._start_item_save(); PlayerState._json_persistence.drain(); PlayerState.load_save()
	check(PlayerState.last_load_result.success and _handles()==all,"production save and reload preserve all three source handles")
	check(PlayerState._validate_extended_item_ownership({"inventory":PlayerState.inventory,"equipment":PlayerState.equipment})
		and Journal.validate_document(PlayerState._prepare_character_save_payload(false)).valid,"both namespaces and new rune operation records share the original aggregate and journal authorities")
	PlayerState.test_mode=true; PlayerState.set_process(true); check(ContentLayers.reload_feature_catalog(),"isolated transaction restores original default-off registry")
	_finish()
func _handles() -> Array:
	var result: Array=[]
	for binding: Dictionary in PlayerState.feature_bundle().get("event_index",{}).get("damage_committed:hc.skill.wizard.ice_storm",[]): result.append(binding.handle)
	result.sort(); return result
func _subset(values: Array,all: Array) -> bool:
	for value: Variant in values:
		if value not in all: return false
	return true
func _transaction(action: String,target: String,input: String) -> bool:
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	var field: String="rune_instance_id" if action.begins_with("hc.runes.") else "gem_instance_id"
	var request: Dictionary={"action":action,"target_instance_id":target}; request[field]=input
	var quote:=PlayerState.quote_new_item_transaction(request)
	var pending:=PlayerState.commit_item_transaction(quote)
	if not pending.get("pending",false): print("RUNE_TRANSACTION_ERROR="+JSON.stringify({"quote":quote,"result":pending})); return false
	return await _wait(pending.job)
func _wait(job: Variant) -> bool:
	if job==null: return false
	var deadline:=Time.get_ticks_msec()+5000
	while not job.response.get("finished",false) and Time.get_ticks_msec()<deadline:
		PlayerState._json_persistence.pump(); await get_tree().process_frame
	return job.response.get("success",false)
func _finish() -> void:
	if not proof.write_receipt("rune_transaction_test",checks,failures.size()): failures.append("receipt")
	print(("FRAMEWORK_RUNE_TRANSACTION_PASS" if failures.is_empty() else "FRAMEWORK_RUNE_TRANSACTION_FAIL")+" checks="+str(checks)+" errors="+str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
