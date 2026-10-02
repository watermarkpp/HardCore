extends RefCounted

const Journal := preload("res://scripts/items/item_transaction_journal.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")

static func write(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes); file.flush(); var okay := file.get_error() == OK; file.close(); return okay

static func wait_job(host: Node, job: Variant) -> Dictionary:
	if job == null: return {"success":false}
	var deadline := Time.get_ticks_msec()+5000
	while not bool(job.response.get("finished",false)) and Time.get_ticks_msec()<deadline:
		PlayerState._json_persistence.pump(); await host.get_tree().process_frame
	return job.response

static func create_case(host: Node, checkpoint: int, total: int, retain_callback := false) -> Dictionary:
	var label := str(total)+"->"+str(checkpoint)
	host.check(PlayerState.create_character("事务回退"+str(total),"hc.profession.warrior").is_empty(),label+": actual profile creation")
	PlayerState.set_process(false)
	var base := Drop.create_instance(GameData.get_item_record({"item_id":80}),"rollback:"+str(total)+":gear")
	var gem := Gem.create_instance("rollback:"+str(total)+":gem",true)
	PlayerState.inventory = [base,gem]
	host.check(PlayerState.save_game(true,true,true),label+": actual initial save")
	var data := {"profile_id":PlayerState.active_profile_id,"path":PlayerState._profile_path(PlayerState.active_profile_id),
		"checkpoint":checkpoint,"total":total,"target":base.instance_id,"gem":gem.instance_id}
	var count := 0
	for sequence in range(1,total+1):
		var request := {"action":"hc.socketing.insert" if sequence%2 == 1 else "hc.socketing.remove",
			"target_instance_id":base.instance_id,"gem_instance_id":gem.instance_id if sequence%2 == 1 else ""}
		var quote: Dictionary = PlayerState.quote_new_item_transaction(request)
		var pending: Dictionary = PlayerState.commit_item_transaction(quote)
		var held: Dictionary = PlayerState._item_transaction_port._active if retain_callback and sequence == checkpoint+1 else {}
		var done := await wait_job(host,pending.get("job"))
		if not held.is_empty():
			data["old_plan"] = held; data["old_receipt"] = done.duplicate(true)
		if not bool(done.get("success",false)):
			host.check(false,label+": actual transaction "+str(sequence)+" failed "+str(done)); return {}
		PlayerState._start_item_save(); PlayerState._json_persistence.drain()
		count += 1
		if sequence == checkpoint:
			data["bytes"] = FileAccess.get_file_as_bytes(data.path)
			data["retained_request"] = quote.request.duplicate(true)
			data["checkpoint_journal"] = PlayerState._item_transaction_journal.duplicate(true)
		if sequence == checkpoint+1: data["old_quote"] = quote.duplicate(true)
	host.check(count == total and PlayerState._json_persistence.pending_count() == 0,label+": all real transactions and receipts complete")
	data["epoch"] = PlayerState._item_transaction_journal.epoch
	host.check(PlayerState._item_transaction_journal.contract_id == Journal.SEQUENCE_CONTRACT and int(PlayerState._item_transaction_journal.retired_through) == maxi(0,total-64),label+": healthy v2 stream reaches its real frontier")
	return data

static func corrupt(host: Node, data: Dictionary) -> void:
	host.check(write(data.path+".bak",data.bytes) and write(data.path,"{broken-owned-primary".to_utf8_buffer()),str(data.total)+": owned v2 checkpoint and corrupt primary installed")

static func probe(host: Node, data: Dictionary) -> Dictionary:
	var label := str(data.total)+"->"+str(data.checkpoint)
	var journal: Dictionary = PlayerState._item_transaction_journal.duplicate(true)
	host.check(bool(PlayerState.last_load_result.get("success",false)) and int(journal.get("last_sequence",0)) == int(data.checkpoint),label+": actual loader restores the older sequenced ownership checkpoint: "+str(PlayerState.last_load_result))
	if not bool(PlayerState.last_load_result.get("success",false)): return {}
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data.path))
	host.check(journal.get("epoch") != data.epoch and disk.get(Journal.FIELD) == journal,label+": old producer epoch is closed durably with the restored inventory before accepting commands")
	host.check(journal.get("entries") == data.checkpoint_journal.entries and journal.get("legacy_entries") == data.checkpoint_journal.legacy_entries,label+": every retained old outcome is preserved exactly")
	var before: Array = PlayerState.inventory.duplicate(true)
	var gold: int = PlayerState.gold
	var xp: int = PlayerState.experience
	var bytes := FileAccess.get_file_as_bytes(data.path)
	var completed: int = PlayerState._json_persistence.completed_count
	var stale: Dictionary = PlayerState.quote_item_transaction(data.old_quote.request)
	host.check(not bool(stale.get("success",false)) and stale.get("reason") == "item_operation_epoch_mismatch",label+": original lost completed ID is refused before rules or inputs")
	var changed: Dictionary = data.old_quote.request.duplicate(true); changed.target_instance_id = "changed:target"
	var conflict: Dictionary = PlayerState.quote_item_transaction(changed)
	host.check(not bool(conflict.get("success",false)) and conflict.get("reason") == "item_operation_epoch_mismatch",label+": changing request contents cannot recycle the old ID")
	var result: Dictionary = PlayerState.commit_item_transaction(stale)
	host.check(not bool(result.get("success",false)) and not result.has("job") and PlayerState._json_persistence.pending_count() == 0,label+": old complete quote cannot create another writer")
	if result.has("job"): await wait_job(host,result.job)
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	host.check(PlayerState.inventory == before and PlayerState.gold == gold and PlayerState.experience == xp and PlayerState._item_transaction_journal == journal and FileAccess.get_file_as_bytes(data.path) == bytes and PlayerState._json_persistence.completed_count == completed,label+": refusals cause zero ownership/resource/journal/file/completion changes")
	if journal.get("epoch") == data.epoch: return {}
	var replay: Dictionary = PlayerState.quote_item_transaction(data.retained_request)
	host.check(bool(replay.get("replay",false)) and bool(PlayerState.commit_item_transaction(replay).get("durable",false)),label+": retained old result is read-only replayable")
	changed = data.retained_request.duplicate(true); changed.target_instance_id = "changed:target"
	host.check(PlayerState.quote_item_transaction(changed).get("reason") == "operation_identity_conflict",label+": retained ID still detects changed request")
	var fresh_request: Dictionary = data.old_quote.request.duplicate(true); fresh_request.erase("operation_id")
	var fresh: Dictionary = PlayerState.quote_new_item_transaction(fresh_request)
	host.check(bool(fresh.get("success",false)) and fresh.get("request",{}).get("operation_id") == Journal.sequence_id(journal.epoch,int(data.checkpoint)+1),label+": new user intent has a distinct durable epoch and next logical serial")
	var pending: Dictionary = PlayerState.commit_item_transaction(fresh)
	if data.has("old_plan"):
		var live_before: Array = PlayerState.inventory.duplicate(true)
		PlayerState._item_transaction_port._complete(data.old_receipt,data.old_plan)
		host.check(PlayerState.inventory == live_before and PlayerState._item_transaction_port._active.get("job") == pending.get("job"),label+": retained pre-recovery callback cannot publish or clear the newly accepted writer")
	var done := await wait_job(host,pending.get("job"))
	host.check(bool(done.get("success",false)),label+": actual sole writer continues the recovered stream")
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	host.check(Journal.validate_document({"profile_id":data.profile_id,Journal.FIELD:PlayerState._item_transaction_journal}).valid and PlayerState._item_transaction_journal.entries.size() <= 64,label+": mixed retained history remains validated and bounded")
	return {"profile_id":data.profile_id,"path":data.path,"epoch":PlayerState._item_transaction_journal.epoch,"last_sequence":PlayerState._item_transaction_journal.last_sequence,"old_request":data.old_quote.request,"new_request":fresh.request}
