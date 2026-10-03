extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Fixture := preload("res://tests/framework/helpers/journal_backup_fixture.gd")
const Codec := preload("res://scripts/items/item_extension_codec.gd")
var proof := Proof.new()
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var nonce := OS.get_environment("HARDCORE_CRASH_NONCE")
	var phase := OS.get_environment("HARDCORE_CRASH_PHASE")
	var armed_path := OS.get_environment("HARDCORE_CRASH_ARMED_PATH").replace("\\","/")
	var owned := ProjectSettings.globalize_path("res://outputs/framework_v2/critical_98f09_followup/crash_runs/").replace("\\","/")
	check(nonce.length() == 32 and nonce.is_valid_hex_number(false) and phase in ["PREPARED","PROMOTING"] and armed_path.begins_with(owned+nonce+"/") and not FileAccess.file_exists(armed_path),"explicit fresh owned control identity and armed path")
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"isolated production persistence, no real account")
	if not failures.is_empty(): _finish(); return
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"real startup gate")
	check(ContentLayers.set_feature_module_enabled(Fixture.Gem.MODULE,true),"explicit default-off socket module")
	if not failures.is_empty(): _finish(); return
	var data := await Fixture.create_case(self,1,1)
	if data.is_empty() or not failures.is_empty(): _finish(); return
	var before: Array = PlayerState.inventory.duplicate(true)
	var prior: Dictionary = PlayerState._item_transaction_journal.duplicate(true)
	var quote: Dictionary = PlayerState.quote_new_item_transaction({"action":"hc.socketing.remove","target_instance_id":data.target,"gem_instance_id":""})
	check(bool(quote.get("success",false)) and not bool(quote.get("replay",false)),"one actual next sequence accepted by production rules")
	var pending: Dictionary = PlayerState.commit_item_transaction(quote)
	check(pending.has("job") and PlayerState._json_persistence.pending_count() == 1,"one sole production writer owns the removal")
	if not failures.is_empty(): _finish(); return
	var job: Variant = pending.job
	var service: Variant = PlayerState._json_persistence
	var deadline := Time.get_ticks_msec()+5000
	while not service._queue.is_empty() and str(service._queue[0].phase) != phase and Time.get_ticks_msec()<deadline:
		service.pump(true)
		await get_tree().process_frame
	check(service._queue.size() == 1 and str(service._queue[0].phase) == phase,"actual requested production phase reached before timeout")
	if not failures.is_empty(): _finish(); return
	if phase == "PROMOTING":
		var completed: Dictionary = job.stage_result(true)
		check(bool(completed.get("finished",false)) and bool(completed.get("result",{}).get("success",false)),"promotion worker finished and joined without consuming its domain callback")
	check(not bool(job.response.get("finished",false)) and PlayerState.inventory == before and PlayerState._item_transaction_journal == prior,"domain receipt remains unconsumed and memory retains sequence1")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(data.path))
	check(disk is Dictionary and disk.get(Fixture.Journal.FIELD,{}).get("last_sequence") == (1 if phase == "PREPARED" else 2),"formal primary has exactly the boundary's durable sequence")
	var decoded: Dictionary = Codec.decode_document(disk if disk is Dictionary else {})
	check(decoded.get("status") == Codec.KNOWN_VALID,"durable ownership graph decodes through the production codec")
	if not failures.is_empty(): _finish(); return
	var armed := {"schema_version":1,"stage_observation":"ARMED","nonce":nonce,"phase":phase,"pid":OS.get_process_id(),"scene_id":"controlled_process_crash_test","producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"producer_invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256"),"profile_id":data.profile_id,"profile_path":data.path,"profile_absolute_path":ProjectSettings.globalize_path(data.path),"request":quote.request,"epoch":prior.epoch,"durable_journal":disk[Fixture.Journal.FIELD],"durable_inventory":decoded.document.inventory,"gold":PlayerState.gold,"xp":PlayerState.experience,"primary_sha256":FileAccess.get_sha256(data.path),"count":proof.records.size(),"failed":failures.size(),"checks":proof.records}
	check(Fixture.write(armed_path,JSON.stringify(armed).to_utf8_buffer()),"owned armed observation written")
	if not failures.is_empty(): _finish(); return
	print("CONTROLLED_PROCESS_CRASH_ARMED nonce="+nonce+" phase="+phase+" pid="+str(OS.get_process_id()))
	# Remain at this test-owned boundary. PlayerState processing was disabled by
	# the existing fixture; no completion/next writer is pumped before OS termination.
func _finish() -> void:
	proof.write_receipt("controlled_process_crash_test",proof.records.size(),failures.size())
	print("CONTROLLED_PROCESS_CRASH_FAIL "+str(failures))
	get_tree().quit(1)
