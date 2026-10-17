extends Node
const Proof:=preload("res://tests/framework/helpers/check_receipt.gd")
const Audit:=preload("res://tests/framework/helpers/source_save_roundtrip_assertions_20261017.gd")
const Catalog:=preload("res://scripts/gameplay/source/profile_original_command_catalog.gd")
var proof:=Proof.new()
var failed:=0
func check(ok: bool,label: String) -> void:
	proof.record(ok,label)
	if not ok:failed+=1;print("SOURCE_SAVE_ASSERTIONS_FAIL ",label)
func _ready() -> void:
	check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"actual isolated data root")
	var fixture: Script=load("res://tests/framework/source_save_roundtrip_20261017.gd")
	check(fixture!=null and fixture.can_instantiate(),"actual full Source integration fixture parser; not executed")
	for method: String in Catalog.ARITIES:
		for count: int in range(0,7):
			check(Catalog.accepts(method,count)==(count in Catalog.ARITIES[method]),"official unique arity catalog "+method+"/"+str(count))
	for method: String in ["__unknown__","deposit_to_warehouse","withdraw_from_warehouse","_model"]:check(not Catalog.accepts(method,0),"unknown/unadmitted direct mutation rejects "+method)
	check(Catalog.accepts("transfer_warehouse_prepared",2) and Catalog.accepts("transfer_warehouse_prepared",3) and not Catalog.accepts("transfer_warehouse_prepared",1),"formal prepared transfer default and explicit target arities")
	check(Audit.equal(4,4.0) and not Audit.equal(4,4.0000001) and not Audit.equal(4,4.9) and not Audit.equal(NAN,NAN),"exact JSON int normalization without tolerance/truncation")
	var gear: Dictionary={"item_id":"hc.item.known","instance_id":"actual-equipment","count":1,"affixes":[{"id":"power","value":17}],"durability_raw":8123,"mystery":{"rolled":19}}
	var a: Dictionary={"inventory":[],"equipment":{"hc.slot.helmet":gear},"warehouse_inventory":[]}
	var b: Dictionary={"inventory":[],"equipment":{"hc.slot.helmet":{}},"warehouse_inventory":[gear.duplicate(true)]}
	check(Audit.equal(Audit.ownership(a),Audit.ownership(b)),"complete property and UID ownership survives relocation")
	b.warehouse_inventory[0].affixes[0].value=18
	check(not Audit.equal(Audit.ownership(a),Audit.ownership(b)),"nested affix corruption rejected")
	b.warehouse_inventory=[gear.duplicate(true)];b.inventory=[gear.duplicate(true)]
	check(Audit.ownership(b).has_duplicate_instances and not Audit.equal(Audit.ownership(a),Audit.ownership(b)),"actual duplicate UID and quantity rejected")
	b.inventory=[];b.warehouse_inventory[0].count=2
	check(not Audit.equal(Audit.ownership(a),Audit.ownership(b)),"count multiplication rejected")
	b.warehouse_inventory=[]
	check(not Audit.equal(Audit.ownership(a),Audit.ownership(b)),"item loss rejected")
	b.warehouse_inventory=[gear.duplicate(true)];b.warehouse_inventory[0].count=0.5
	check(not Audit.ownership(b).valid,"fractional stack count rejected")
	var receipt: Dictionary={"contract_id":"hardcore.profile.ui.command_receipt.v1","method":"save_game","profile_id":"p","post_profile_id":"p","owner_session_id":7,"profile_model_id":-9223372000000000000,"command_id":1,"command_sha256":"0".repeat(64),"result":true,"profile_view":{"fields":{"active_profile_id":"p"}}}
	var reply: Dictionary={"success":true,"receipt":receipt,"result":true}
	check(Audit.command_matches(reply,"save_game","p",7,-9223372000000000000,0),"plain schema unit accepts actual RefCounted signed witness; not Native receipt proof")
	for field: String in ["method","profile_id","post_profile_id","owner_session_id","profile_model_id","command_id","command_sha256"]:
		var changed: Dictionary=reply.duplicate(true);changed.receipt[field]=0 if receipt[field] is int else "foreign"
		check(not Audit.command_matches(changed,"save_game","p",7,-9223372000000000000,0),"command receipt foreign/gap/replay boundary "+field)
	var rng: Dictionary={"seed":-8123456789012345678,"state":-9123456789012345678,"increment":1442695040888963407}
	check(bytes_to_var(var_to_bytes(rng))==rng,"cross-process binary witness preserves signed64 RNG seed/state exactly")
	var ok: bool=proof.write_receipt("source_save_assertions_20261017",proof.records.size(),failed)
	print("SOURCE_SAVE_ASSERTIONS_20261017_","PASS" if ok else "FAIL"," checks=",proof.records.size()," failures=",failed," ACTUAL_SOURCE_ROUNDTRIP=NOT_RUN")
	get_tree().quit(0 if ok else 1)
