extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Inputs := preload("res://scripts/features/contracts/published_monster_inputs.gd")
const Bound := preload("res://scripts/features/adapters/world_target_bound.gd")
var proof := Proof.new()
var failures := 0
func check(ok: bool, label: String) -> void:
	proof.record(ok,label)
	if not ok: failures+=1; print("SOURCE_MONSTER_BIRTH_INPUTS_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _source(publication: Dictionary) -> Array:
	var rows: Array=[]
	var bound: RefCounted=Bound.new()
	rows.append([bound.configure_owner_inputs(publication),"actual nonMain owner imports original Main monster records"])
	for epoch: int in [1,2]:
		bound.sync_world({"component_world_epoch":epoch})
		rows.append([bound.get("_inputs").is_empty(),"new world clears only the compiled input selection"])
		for id: int in publication.inputs:
			var selected: RefCounted=bound._capture_inputs(id)
			rows.append([selected!=null and selected.view()==publication.inputs[id],"owner lookup keeps original published record "+str(id)])
			var cached: RefCounted=bound.get("_inputs").get(id)
			rows.append([cached!=null and is_same(selected,cached),"owner lookup installs same input in birth plan "+str(id)])
			if cached==null: continue
			rows.append([bound.declare_base("slot:"+str(id),id,Vector2(id,0),60.0,{"respawn_enabled":false}),"original base descriptor admitted "+str(id)])
		rows.append([bound._capture_inputs(987654321)==null and not bound.get("_inputs").has(987654321),"unknown ID remains rejected without a cache entry"])
		var sealed: bool=bound.seal()
		rows.append([sealed,"real birth plan seals after owner lookups"])
		if sealed:
			for id: int in publication.inputs:
				rows.append([bound.admit_base(id,Vector2(id,0),60.0,{"spawn_slot_id":"slot:"+str(id),"respawn_enabled":false}).get("accepted")==true,"sealed plan reads same published input "+str(id)])
	return rows
func _run() -> void:
	var publication: Dictionary={"contract_id":"world.monster_inputs.publication.v1","inputs":{}}
	for id: int in [18,19]:
		var record: RefCounted=Inputs.capture(id,EnemyActor._attack_range_policy_record_for_id(id),EnemyActor._movement_authority_record_for_id(id))
		check(record!=null,"actual Main captures production monster "+str(id))
		if record!=null: publication.inputs[id]=record.view()
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary=graph.capture(publication,true,false)
	check(captured.get("success")==true,"Native captures publication as immutable plain values")
	var worker:=Thread.new()
	check(worker.start(Callable(self,"_source").bind(captured.value))==OK,"actual separate owner starts")
	while worker.is_alive(): await get_tree().process_frame
	var rows: Array=worker.wait_to_finish()
	for row: Array in rows: check(row[0],row[1])
	proof.write_receipt("source_monster_birth_inputs_20261017",proof.records.size(),failures)
	if failures==0: print("SOURCE_MONSTER_BIRTH_INPUTS_PASS")
	get_tree().quit(0 if failures==0 else 1)
