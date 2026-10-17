extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Model := preload("res://scripts/gameplay/profile/profile_model.gd")
var proof := Proof.new()
var failures := 0
class DrainBoundary:
	extends "res://scripts/gameplay/profile/profile_model.gd"
	var replace_inventory: Array = []
	var replace_equipment: Dictionary = {}
	var barriers := 0
	func _before_state_transaction(_include_world := false) -> void:
		barriers+=1
		if not replace_inventory.is_empty(): inventory=replace_inventory.duplicate(true)
		if not replace_equipment.is_empty(): equipment=replace_equipment.duplicate(true)
func check(ok: bool,label: String) -> void:
	proof.record(ok,label)
	if not ok: failures+=1;print("ITEM_SELECTION_FAIL ",label)
func selected(container: String,slot: Variant,record: Dictionary) -> Dictionary:
	return {"contract_id":"hardcore.profile.item_selection.v1","profile_id":"component-p","session_id":99,"container":container,"slot":slot,"record":record.duplicate(true)}
func _ready() -> void:
	var model := DrainBoundary.new()
	model.active_profile_id="component-p";model.test_mode=true
	var gear := {"item_id":"hc.item.fixture","instance_id":"selected-uid","count":1,"affixes":[{"id":"power","value":17}]}
	var other := gear.duplicate(true);other.instance_id="replacement-uid"
	check(model.has_method("_selected_item_matches"),"actual Profile Model supplies post-barrier selection verification")
	if model.has_method("_selected_item_matches"):
		model.inventory=[gear.duplicate(true)]
		var witness := selected("inventory",0,gear)
		check(model.call("_selected_item_matches","inventory",0,witness),"unchanged complete original equipment matches")
		gear.affixes[0].value=18
		check(model.call("_selected_item_matches","inventory",0,witness),"captured nested affix is detached from original source dictionary")
		model.inventory[0].affixes[0].value=19
		check(not model.call("_selected_item_matches","inventory",0,witness),"same UID with changed nested attributes rejects")
		model.inventory=[witness.record.duplicate(true),witness.record.duplicate(true)]
		check(not model.call("_selected_item_matches","inventory",0,witness),"duplicate UID rejects rather than selecting first match")
		model.inventory=[witness.record.duplicate(true)]
		var foreign := witness.duplicate(true);foreign.profile_id="another-profile"
		check(not model.call("_selected_item_matches","inventory",0,foreign),"foreign profile selection rejects")
		foreign=witness.duplicate(true);foreign.container="warehouse"
		check(not model.call("_selected_item_matches","inventory",0,foreign),"foreign container rejects")
		foreign=witness.duplicate(true);foreign.slot=1
		check(not model.call("_selected_item_matches","inventory",0,foreign),"foreign slot rejects")
		var potion := {"item_id":"hc.item.920014","count":3}
		model.inventory=[potion.duplicate(true)];var stack := selected("inventory",0,potion)
		check(model.call("_selected_item_matches","inventory",0,stack),"UID-less fungible record matches by full value")
		model.inventory[0].count=2
		check(not model.call("_selected_item_matches","inventory",0,stack),"UID-less changed stack count rejects")
		# Adapter only changes state at the original barrier. All operations below
		# are the production Model methods, not replacement transaction algorithms.
		model.inventory=[witness.record.duplicate(true)];model.replace_inventory=[other]
		var result: Dictionary=model.call("destroy_inventory_indices",[0],[witness])
		check(result.get("reason")=="selection_changed" and model.inventory==[other],"discard validates after actual original barrier and preserves replacement")
		model.inventory=[witness.record.duplicate(true)]
		result=model.call("equip_inventory_index_result",0,"hc.slot.weapon","selected-uid",witness)
		check(result.get("reason")=="selection_changed" and model.inventory==[other],"equip carries UID and witness through inner original barrier")
		model.inventory=[witness.record.duplicate(true)]
		result=model.call("use_inventory_index_result",0,false,witness)
		check(result.get("reason")=="selection_changed" and model.inventory==[other],"use validates after original barrier before effect or consumption")
		model.equipment={"hc.slot.weapon":witness.record.duplicate(true)};model.replace_equipment={"hc.slot.weapon":other}
		var equipped := selected("equipment","hc.slot.weapon",witness.record)
		result=model.call("unequip_to_inventory_slot","hc.slot.weapon",0,"selected-uid",equipped)
		check(result.get("reason")=="selection_changed" and model.equipment["hc.slot.weapon"]==other,"unequip validates inside original barrier and preserves replacement")
		model.inventory=[witness.record.duplicate(true)]
		result=model.call("deposit_to_warehouse_batch",[0],[0],false,[witness])
		check(result.get("reason")=="selection_changed" and model.inventory==[other],"warehouse deposit validates after barrier and initialization")
		check(result.get("contract_id")==model.WAREHOUSE_TRANSFER_CONTRACT_ID and result.get("operation")=="deposit" and result.get("requested")==1 and result.get("remaining")==1 and result.get("completed_source_indices")==[],"stale warehouse deposit retains original complete result schema")
		model.warehouse_inventory=[other]
		result=model.call("withdraw_from_warehouse_batch",[0],false,[selected("warehouse",0,witness.record)])
		check(result.get("reason")=="selection_changed" and model.warehouse_inventory==[other],"warehouse withdrawal preserves replacement on stale selection")
		check(result.get("contract_id")==model.WAREHOUSE_TRANSFER_CONTRACT_ID and result.get("operation")=="withdraw" and result.get("requested")==1 and result.get("remaining")==1 and result.get("completed_warehouse_slots")==[],"stale warehouse withdrawal retains original complete result schema")
		model.inventory=[witness.record.duplicate(true)]
		result=model.call("_learn_skill_result","hc.skill.wizard.fireball",0,false,witness)
		check(result.get("reason")=="selection_changed","skill book rejects after original barrier before progression or fallback to a second book")
		model.inventory=[witness.record.duplicate(true)]
		result=model.call("_use_weapon_repair_oil_item_result",0,false,false,witness)
		check(result.get("reason")=="selection_changed","repair oil rejects before weapon mutation")
		model.inventory=[witness.record.duplicate(true)]
		var rng := RandomNumberGenerator.new();rng.seed=1873;var prior_state := rng.state
		result=model.call("use_blessing_oil_inventory_index",0,rng,false,witness)
		check(result.get("reason")=="selection_changed" and rng.state==prior_state,"stale blessing oil rejects before consuming original RNG")
		model.inventory=[witness.record.duplicate(true)]
		result=model.call("use_blessing_oil_inventory_index_with_rolls",0,0,0,-1,false,witness,rng)
		check(result.get("reason")=="selection_changed" and rng.state==prior_state,"inner blessing barrier rejects before deferred RNG or item consumption")
		model.inventory=[witness.record.duplicate(true)]
		check(not model.call("_consume_inventory_index",0,1,false,witness) and model.inventory==[other],"inner consumable barrier preserves replacement")
		check(model.barriers>=6,"actual operations crossed their original barrier before rejection")
	model=null
	proof.write_receipt("profile_item_selection_20261018",proof.records.size(),failures)
	print("PROFILE_ITEM_SELECTION_", "PASS" if failures==0 else "FAIL", " checks=",proof.records.size()," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
