extends Node
## Archived PC corpus on the actual pre-binding Main Profile owner.
## Full-world Source/Android/device acceptance is deliberately a separate gate.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Audit := preload("res://tests/framework/helpers/v115_savedata_warehouse_source_20261017.gd")
const BASE := "res://outputs/v115_multicore/save_warehouse_parallel_20261017"
var proof := Proof.new()
var failed := 0
var report: Dictionary = {"scope":"actual_Main_prebinding_ProfileModel_old_PC_corpus","profiles":[],"warehouse_transfers":[]}
func check(ok: bool,label: String) -> bool:
	proof.record(ok,label)
	if not ok: failed += 1; print("SAVEDATA_WAREHOUSE_FAILED ",label)
	return ok
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	if not check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"real userdata is isolated inside snapshot"): _finish(); return
	var corpus: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE.path_join("CORPUS.json")))
	check(corpus.archive_sha256 == "d32b185ad5752ea240f310c01e61e93d0a0761fc738b26be3f8c6cd6656245ef","exact original read-only PC ZIP provenance")
	check(corpus.profiles.size() == 13,"all thirteen archived stored profiles selected without filtering")
	PlayerState.set_process(false)
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var root := "user://archived_roundtrip_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("character_profiles.json")
	PlayerState.shared_warehouse_path = root.path_join("shared_warehouse.json")
	PlayerState.shared_warehouse_transaction_log_path = root.path_join("shared_warehouse.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	for relative: String in corpus.files:
		var source: String = BASE.path_join("corpus").path_join(relative)
		var target: String = root.path_join(relative)
		check(FileAccess.get_sha256(source) == corpus.files[relative],"immutable corpus SHA "+relative)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
		var file := FileAccess.open(target,FileAccess.WRITE)
		if not check(file != null,"isolated copy opens "+relative): _finish(); return
		file.store_buffer(FileAccess.get_file_as_bytes(source)); file.close()
		check(FileAccess.get_sha256(target) == corpus.files[relative],"exact copy before official migration "+relative)
	PlayerState.test_mode = false
	PlayerState.begin_startup_save_upgrade()
	if not check(PlayerState.finish_startup_save_upgrade(),"official complete startup migration "+str(PlayerState.startup_save_upgrade_result)): _finish(); return
	var archive := root.path_join("save_upgrades/framework_identity_v1/original")
	for relative: String in corpus.files:
		check(FileAccess.get_sha256(archive.path_join(relative)) == corpus.files[relative],"migration preserves original archived bytes "+relative)
	for relative: String in corpus.profiles:
		var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE.path_join("corpus").path_join(relative)))
		var id: String = str(original.profile_id)
		if not check(PlayerState.select_character(id),"formal old-profile selection "+id+" "+str(PlayerState.last_load_result)): continue
		var before: Dictionary = Audit.snapshot(PlayerState)
		var own: Dictionary = Audit.ownership(PlayerState)
		check(not own.has_duplicate_instances,"loaded inventory/equipment/warehouse unique instance ownership "+id)
		check(PlayerState.level == int(original.level) and PlayerState.experience == int(original.experience) and PlayerState.gold == int(original.gold),"original level/XP/money retained "+id)
		var old_items: Array = original.get("inventory",[]).duplicate(true)
		old_items.append_array(original.get("equipment",{}).values())
		var original_count := 0
		var original_item_counts: Dictionary = {}
		for item: Variant in old_items:
			if not item is Dictionary or item.is_empty(): continue
			original_count += int(item.get("count",1))
			var canonical_id: String = GameData.item_entity_id(item)
			check(not canonical_id.is_empty() and canonical_id.begins_with("hc."),"legacy item resolves through official stable registry "+id+":"+str(item.get("name","")))
			original_item_counts[canonical_id] = int(original_item_counts.get(canonical_id,0))+int(item.get("count",1))
			var item_id: String = str(item.get("instance_id",""))
			if item_id.is_empty(): continue
			if not check(own.instances.has(item_id),"original stable instance retained "+item_id): continue
			for attribute: String in item:
				if attribute == "name": continue # formal migration replaces legacy name identity.
				check(own.instances[item_id].get(attribute) == item[attribute],"original complete item attribute retained "+item_id+":"+attribute)
		var runtime_profile_count := 0
		var runtime_item_counts: Dictionary = {}
		for item: Variant in before.inventory + before.equipment.values():
			if item is Dictionary and not item.is_empty():
				runtime_profile_count += int(item.get("count",1))
				var canonical_id: String = GameData.item_entity_id(item)
				runtime_item_counts[canonical_id] = int(runtime_item_counts.get(canonical_id,0))+int(item.get("count",1))
		check(original_item_counts == runtime_item_counts,"every original stable item identity and per-item quantity retained "+id)
		check(original_count == runtime_profile_count,"original total item quantities retained "+id)
		var skill_ids: Script = load("res://scripts/skills/skill_data_loader.gd")
		var old_skills: Dictionary = original.get("skill_progression",{}).get("skills",{})
		var expected_ranks: Dictionary = {}
		if original.has("skill_progression"):
			for old_id: String in old_skills:
				var stable: String = skill_ids.entity_skill_id(old_id)
				expected_ranks[stable] = int(old_skills[old_id].get("base_rank",old_skills[old_id].get("rank",0)))
		else:
			for old_name: String in original.get("learned_skills",{}):
				var stable: String = skill_ids.entity_skill_id(old_name)
				expected_ranks[stable] = int(original.learned_skills[old_name])
		var actual_ranks: Dictionary = {}
		for stable: String in before.skill_progression.skills:
			var skill: Dictionary = before.skill_progression.skills[stable]
			actual_ranks[stable] = int(skill.get("base_rank",skill.get("rank",0)))
		check(expected_ranks == actual_ranks,"all historical learned skill stable IDs and ranks preserved through formal migration "+id)

		if not check(PlayerState.save_game(false,false,false),"actual ordered profile writer saves loaded old profile "+id): continue
		PlayerState._shared_warehouse_initialized = false
		PlayerState.load_save()
		check(bool(PlayerState.last_load_result.get("success",false)) and Audit.equal(Audit.snapshot(PlayerState),before),"complete profile/equipment/bag/warehouse/skills equality after disk reload "+id)
		report.profiles.append({"id":id,"original_sha256":corpus.files[relative],"snapshot":before,"ownership":own})
	# Every profile gets a separate physical account clone of the migrated base.
	# A wizard's legal medicine deposits never contaminate another case.
	for case_index: int in report.profiles.size():
		var row: Dictionary = report.profiles[case_index]
		var case_root: String = root+"_case_%02d" % case_index
		if not _copy_directory(root,case_root): continue
		PlayerState.active_profile_id = ""
		PlayerState.profile_directory = case_root.path_join("characters")
		PlayerState.profile_index_path = case_root.path_join("character_profiles.json")
		PlayerState.shared_warehouse_path = case_root.path_join("shared_warehouse.json")
		PlayerState.shared_warehouse_transaction_log_path = case_root.path_join("shared_warehouse.transaction.json")
		PlayerState._shared_warehouse_initialized = false
		if not check(PlayerState.select_character(row.id),"independent physical account clone selects old profile "+row.id): continue
		check(Audit.equal(Audit.snapshot(PlayerState),row.snapshot),"per-profile independent baseline equals original loaded snapshot "+row.id)
		var transfer: Dictionary = _roundtrip(row.id)
		row.case_root = ProjectSettings.globalize_path(case_root)
		row.final_snapshot = Audit.snapshot(PlayerState)
		row.transfer = transfer
		if not transfer.is_empty(): report.warehouse_transfers.append(transfer)

	check(report.warehouse_transfers.size() == 9,"all nine archived equipped test profiles perform real equipment warehouse transactions")
	var model: RefCounted = PlayerState.get("_model")
	check(model._json_persistence.pending_count() == 0 and model._world_json_persistence.pending_count() == 0,"all actual persistence receipts drained")
	report.user_root = ProjectSettings.globalize_path(root)
	PlayerState.active_profile_id = ""
	_finish()
func _roundtrip(id: String) -> Dictionary:
	var initial: Dictionary = Audit.snapshot(PlayerState)
	var conserved: Dictionary = Audit.ownership(PlayerState)
	var selected_slot := ""
	for slot: String in ["hc.slot.helmet","hc.slot.necklace","hc.slot.ring_left","hc.slot.weapon"]:
		if PlayerState.equipment[slot] is Dictionary and not PlayerState.equipment[slot].is_empty(): selected_slot = slot; break
	if selected_slot.is_empty(): return {}
	var gear: Dictionary = PlayerState.equipment[selected_slot].duplicate(true)
	var instance: String = str(gear.get("instance_id",""))
	if not check(not instance.is_empty() and gear.has("item_id"),"warehouse equipment uses existing stable item and instance IDs "+id): return {}
	var preparation: Array = []
	var model: RefCounted = PlayerState.get("_model")
	var original_preview: Dictionary = model._build_receive_result_for_record(gear,PlayerState.inventory)
	if not bool(original_preview.get("success",false)):
		check(str(original_preview.get("reason","")) == "overweight","original overweight refusal retains formal reason "+id+" "+str(original_preview))
		var indices: Array = []
		var slots: Array = []
		for index: int in PlayerState.inventory.size():
			if PlayerState.inventory[index] is Dictionary and not PlayerState.inventory[index].is_empty():
				indices.append(index); slots.append(20+index)
		var prepared: Dictionary = PlayerState.deposit_to_warehouse_batch(indices,slots)
		check(bool(prepared.get("success",false)) and bool(prepared.get("complete",false)),"official medicine deposit frees real bag weight without removing any item "+id+" "+str(prepared))
		check(Audit.equal(Audit.ownership(PlayerState),conserved),"preparatory medicine deposit conserves every item attribute/count "+id)
		preparation.append({"original_unequip_preview":original_preview,"medicine_deposit":prepared,"snapshot":Audit.snapshot(PlayerState)})
	var free_bag := PlayerState.inventory.size()
	var unequipped: Dictionary = PlayerState.unequip_to_inventory_slot(selected_slot,free_bag,instance)
	if not check(bool(unequipped.get("success",false)),"official unequip into bag "+id+" "+str(unequipped)): return {}
	check(Audit.equal(PlayerState.inventory[free_bag],gear),"unequip preserves every equipment attribute "+id)
	var deposited: Dictionary = PlayerState.deposit_to_warehouse(free_bag,0)
	if not check(bool(deposited.get("success",false)) and int(deposited.get("transferred",0)) == 1,"actual two-file warehouse deposit commit "+id+" "+str(deposited)): return {}
	check(Audit.find_instance(PlayerState.inventory,instance) == -1 and Audit.equal(PlayerState.warehouse_inventory[0],gear),"warehouse is nonempty and uniquely owns the entire real item "+id)
	check(Audit.equal(Audit.ownership(PlayerState),conserved),"deposit conserves all items, IDs, full attributes and counts "+id)
	check(PlayerState.save_game(false,false,false),"actual save after warehouse deposit "+id)
	var deposited_snapshot: Dictionary = Audit.snapshot(PlayerState)
	PlayerState._shared_warehouse_initialized = false
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success",false)) and Audit.equal(Audit.snapshot(PlayerState),deposited_snapshot),"nonempty equipment warehouse survives actual reload "+id)
	var withdrawn: Dictionary = PlayerState.withdraw_from_warehouse(0)
	if not check(bool(withdrawn.get("success",false)) and int(withdrawn.get("transferred",0)) == 1,"actual warehouse withdraw commit "+id+" "+str(withdrawn)): return {}
	var bag_slot: int = Audit.find_instance(PlayerState.inventory,instance)
	check(bag_slot >= 0 and Audit.equal(PlayerState.inventory[bag_slot],gear) and Audit.find_instance(PlayerState.warehouse_inventory,instance) == -1,"withdraw retains exact item and clears warehouse ownership "+id)
	if bag_slot < 0: return {}
	var equipped: Dictionary = PlayerState.equip_inventory_index_result(bag_slot,selected_slot,instance)
	check(bool(equipped.get("success",false)),"official equip returns original item to original slot "+id+" "+str(equipped))
	check(Audit.equal(Audit.ownership(PlayerState),conserved),"final ownership proves no duplication or loss "+id)
	check(PlayerState.save_game(false,false,false),"actual final save "+id)
	PlayerState._shared_warehouse_initialized = false
	PlayerState.load_save()
	# Container arrays may retain official empty trailing slots. Compare occupied
	# records and equipped slots exactly, with progression and quantity conservation.
	var final: Dictionary = Audit.snapshot(PlayerState)
	check(Audit.equal(Audit.progression(PlayerState),_progression(initial)) and Audit.equal(final.equipment,initial.equipment) and Audit.equal(Audit.ownership(PlayerState),conserved),"final reload restores all progression, equipment and aggregate ownership "+id)
	return {"profile_id":id,"slot":selected_slot,"preparation":preparation,"item":gear,"deposit":deposited,"withdraw":withdrawn,"deposited_snapshot":deposited_snapshot,"final_snapshot":final}
func _copy_directory(source: String,target: String) -> bool:
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target)) == OK,"independent account directory "+target.get_file()): return false
	for name: String in DirAccess.get_files_at(source):
		var origin: String = source.path_join(name)
		var destination: String = target.path_join(name)
		if not check(DirAccess.copy_absolute(ProjectSettings.globalize_path(origin),ProjectSettings.globalize_path(destination)) == OK and FileAccess.get_sha256(origin) == FileAccess.get_sha256(destination),"independent account byte copy "+target.get_file()+"/"+name): return false
	for name: String in DirAccess.get_directories_at(source):
		if not _copy_directory(source.path_join(name),target.path_join(name)): return false
	return true
func _progression(value: Dictionary) -> Dictionary:
	var out: Dictionary = value.duplicate(true)
	for key: String in ["inventory","equipment","warehouse_inventory"]: out.erase(key)
	return out
func _finish() -> void:
	report.status = "PASS" if failed == 0 else "FAIL"
	report.check_count = proof.records.size(); report.failures = failed
	report.source_content_sha256 = OS.get_environment("HARDCORE_R3_CONTENT_SHA256")
	var file := FileAccess.open(BASE.path_join("roundtrip_detail.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"  ")); file.close()
	var valid: bool = proof.write_receipt("v115_savedata_warehouse_roundtrip_20261017",proof.records.size(),failed)
	print("V115_SAVEDATA_WAREHOUSE_ROUNDTRIP_20261017_", "PASS" if valid else "FAIL", " checks=",proof.records.size()," failures=",failed)
	get_tree().quit(0 if valid else 1)
