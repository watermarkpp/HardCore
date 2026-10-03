extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Fixture := preload("res://tests/framework/helpers/journal_backup_fixture.gd")
const Gate := preload("res://tests/framework/helpers/controlled_crash_gate.gd")
const Json := preload("res://tests/framework/helpers/native_producer_gate.gd")
const Codec := preload("res://scripts/items/item_extension_codec.gd")
var proof := Proof.new()
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _ownership(items: Array) -> Dictionary:
	var ids := {}
	for item: Variant in items:
		if item is Dictionary and not item.is_empty():
			for id: String in Codec.ownership_ids(item): ids[id] = int(ids.get(id,0))+1
	return ids
func _run() -> void:
	var handoff: Variant = Json.read_json(OS.get_environment("HARDCORE_CRASH_HANDOFF_PATH"))
	var nonce := OS.get_environment("HARDCORE_CRASH_NONCE")
	var source := OS.get_environment("HARDCORE_R3_CONTENT_SHA256")
	var run := OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID")
	check(Gate.accepts(handoff,nonce,source,run),"this explicitly expected OS-terminated producer owns the cold boundary")
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"isolated production account only")
	if not failures.is_empty(): _finish(); return
	for field: String in ["nonce","source_content_sha256","producer_run_id","producer_invocation_id","armed_sha256","producer_native_status","control_status"]:
		var bad: Dictionary = handoff.duplicate(true); bad[field] = "wrong"
		check(not Gate.accepts(bad,nonce,source,run),"cold refuses mismatched "+field)
	var bad: Dictionary = handoff.duplicate(true); bad.producer_native_exit = 0
	check(not Gate.accepts(bad,nonce,source,run),"normal exit cannot masquerade as this controlled termination")
	check(not Gate.accepts(handoff,nonce,source,handoff.producer_run_id),"live and cold cannot have the same run identity")
	var data: Dictionary = handoff.armed
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"real cold startup gate")
	check(ContentLayers.set_feature_module_enabled(Fixture.Gem.MODULE,true),"explicit fixture permission")
	if not failures.is_empty(): _finish(); return
	PlayerState.set_process(false)
	check(PlayerState.select_character(data.profile_id),"independent process selects the producer's exact profile")
	check(PlayerState._profile_path(data.profile_id) == data.profile_path,"same isolated profile path")
	check(PlayerState._item_transaction_journal == data.durable_journal and PlayerState._item_transaction_journal.epoch == data.epoch,"cold restores the actual durable journal frontier and same healthy epoch")
	check(_ownership(PlayerState.inventory) == _ownership(data.durable_inventory),"cold ownership identities and exact multiplicities match durable primary")
	for id: Variant in _ownership(PlayerState.inventory): check(_ownership(PlayerState.inventory)[id] == 1,"unique owned instance "+str(id))
	check(PlayerState.gold == data.gold and PlayerState.experience == data.xp,"no money or XP drift on recovery")
	if not failures.is_empty(): _finish(); return
	var quote: Dictionary = PlayerState.quote_item_transaction(data.request)
	check(bool(quote.get("success",false)) and bool(quote.get("replay",false)) == (data.phase == "PROMOTING"),"uncommitted intent is eligible once; promoted identity is read-only replay")
	var before: Array = PlayerState.inventory.duplicate(true)
	var completed: int = PlayerState._json_persistence.completed_count
	var bytes := FileAccess.get_file_as_bytes(data.profile_path)
	var pending: Dictionary = PlayerState.commit_item_transaction(quote)
	if data.phase == "PREPARED":
		check(pending.has("job") and PlayerState._json_persistence.pending_count() == 1,"previously uncommitted sequence gets exactly one new writer")
		var duplicate: Dictionary = PlayerState.commit_item_transaction(quote)
		check(duplicate.get("job") == pending.get("job") and PlayerState._json_persistence.pending_count() == 1,"duplicate pending commit shares the sole accepted writer")
		var done := await Fixture.wait_job(self,pending.get("job"))
		check(bool(done.get("success",false)),"one real durable removal finishes after cold")
		PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	else:
		check(bool(pending.get("durable",false)) and not pending.has("job") and PlayerState._json_persistence.pending_count() == 0,"promoted operation cannot open another writer")
		check(PlayerState.inventory == before and PlayerState._json_persistence.completed_count == completed and FileAccess.get_file_as_bytes(data.profile_path) == bytes,"promoted retry changes no inventory/completion/file bytes")
	check(PlayerState._item_transaction_journal.last_sequence == 2,"both boundaries end at the exact once-committed sequence2")
	before = PlayerState.inventory.duplicate(true); bytes = FileAccess.get_file_as_bytes(data.profile_path); completed = PlayerState._json_persistence.completed_count
	check(bool(PlayerState.commit_item_transaction(PlayerState.quote_item_transaction(data.request)).get("durable",false)),"original completed identity remains read-only replayable")
	var changed: Dictionary = data.request.duplicate(true); changed.target_instance_id = "controlled:changed-target"
	check(PlayerState.quote_item_transaction(changed).get("reason") == "operation_identity_conflict","changed contents cannot recycle the completed operation ID")
	check(PlayerState.inventory == before and PlayerState.gold == data.gold and PlayerState.experience == data.xp and PlayerState._json_persistence.pending_count() == 0 and PlayerState._json_persistence.completed_count == completed and FileAccess.get_file_as_bytes(data.profile_path) == bytes,"completed replay and changed request create no second ownership/resource/writer/file change")
	_finish()
func _finish() -> void:
	if not proof.write_receipt("controlled_process_crash_cold_test",proof.records.size(),failures.size()): failures.append("receipt")
	print("CONTROLLED_PROCESS_BOUNDARY_COLD_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",proof.records.size(),str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
