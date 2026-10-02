extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Journal := preload("res://scripts/items/item_transaction_journal.gd")
const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
const Drop := preload("res://scripts/item_drop_instance_rules.gd")
const EXPECTED := "res://outputs/test_logs/framework/item_journal_recovery_expected.json"
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"real persistence uses the runner's prelaunch isolated account")
	if not failures.is_empty(): _finish(); return
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"actual startup upgrade gate completes")
	check(PlayerState.create_character("事务序列验证","hc.profession.warrior").is_empty(),"actual profile service creates the owned character")
	PlayerState.set_process(false)
	var profile: String = PlayerState.active_profile_id
	var base := Drop.create_instance(GameData.get_item_record({"item_id":80}),"journal:gear")
	var gem := Gem.create_instance("journal:gem",true)
	PlayerState.inventory = [base,gem]
	# A valid legacy document fixture represents unretirable opaque history.
	# The following 130 sequenced operations themselves use real commits.
	var legacy := {}
	var legacy_request := {"operation_id":"legacy:1","action":"hc.socketing.insert","target_instance_id":"historical:gear","gem_instance_id":"historical:gem"}
	for index in 64:
		var entry := {"operation_id":"legacy:"+str(index+1),"action":legacy_request.action,
			"target_instance_id":legacy_request.target_instance_id,"gem_instance_id":legacy_request.gem_instance_id,
			"request_digest":JSON.stringify([profile,legacy_request.action,legacy_request.target_instance_id,legacy_request.gem_instance_id]).sha256_text(),"rules_revision":"legacy-rules".sha256_text()}
		legacy = Journal.appended(legacy,profile,entry)
	PlayerState._item_transaction_journal = legacy.duplicate(true)
	check(PlayerState.save_game(true,true,true),"sole writer persists valid full v1 history and test-owned inputs")
	check(ContentLayers.set_feature_module_enabled(Gem.MODULE,true),"default-off fixture enabled through its real module service")
	if not failures.is_empty(): _finish(); return
	var first_quote := {}
	var last_quote := {}
	var first_plan := {}
	var first_receipt := {}
	var completed := 0
	for sequence in range(1,131):
		var request := {"action":"hc.socketing.insert" if sequence%2 == 1 else "hc.socketing.remove",
			"target_instance_id":base.instance_id,"gem_instance_id":gem.instance_id if sequence%2 == 1 else ""}
		var quote: Dictionary = PlayerState.quote_new_item_transaction(request)
		if not bool(quote.get("success",false)): check(false,"real next quote "+str(sequence)+": "+str(quote)); break
		if sequence == 1:
			first_quote = quote
			check(quote.request.has("operation_id") and quote.has("request_digest") and quote.has("protocol_epoch"),"issued identity crosses the strict plain-String boundary with a complete quote, never a partial success")
		last_quote = quote
		var pending: Dictionary = PlayerState.commit_item_transaction(quote)
		if not bool(pending.get("pending",false)):
			print("ITEM_JOURNAL_QUOTE_FAILURE_TRACE "+JSON.stringify({"original":quote,"refreshed":PlayerState.quote_item_transaction(quote.request),"response":pending}))
			check(false,"real commit "+str(sequence)+": "+str(pending)); break
		if sequence == 1:
			first_plan = PlayerState._item_transaction_port._active
			check(PlayerState.commit_item_transaction(quote).get("job") == pending.job,"duplicate click owns one pending writer job")
		if sequence == 65:
			var owned_before: Array = PlayerState.inventory.duplicate(true)
			PlayerState._item_transaction_port._complete(first_receipt,first_plan)
			check(PlayerState.inventory == owned_before and PlayerState._item_transaction_port._active.job == pending.job,"delayed old callback cannot publish or clear another accepted writer job at the retirement boundary")
		var response := await _wait(pending.get("job"))
		if not bool(response.get("success",false)): check(false,"durable receipt "+str(sequence)+": "+str(response.get("reason"))); break
		if sequence == 1: first_receipt = response.duplicate(true)
		completed += 1
		PlayerState._start_item_save(); PlayerState._json_persistence.drain()
		if sequence in [64,65,130]:
			var current: Dictionary = PlayerState._item_transaction_journal
			check(current.entries.size() == mini(sequence,64) and int(current.retired_through) == maxi(0,sequence-64) and current.legacy_entries == legacy.entries,"actual durable sequence boundary "+str(sequence)+" retains its bounded recent window and all opaque history")
	check(completed == 130,"all 130 real ownership transactions complete beyond journal64 without losing a gem")
	if completed != 130: _finish(); return
	var journal: Dictionary = PlayerState._item_transaction_journal.duplicate(true)
	var snapshot: Array = PlayerState.inventory.duplicate(true)
	var retired: Dictionary = PlayerState.quote_item_transaction(first_quote.request)
	check(not bool(retired.success) and retired.reason == "item_operation_retired","old sequence is explicitly retired and can never consume again")
	var conflict: Dictionary = first_quote.request.duplicate(true); conflict.target_instance_id = "different:target"
	check(PlayerState.quote_item_transaction(conflict).get("reason") == "item_operation_retired","changing a retired request cannot reopen its old identity")
	check(bool(PlayerState.commit_item_transaction(last_quote).get("durable",false)),"retained recent result still replays its exact durable outcome")
	check(bool(PlayerState.commit_item_transaction(PlayerState.quote_item_transaction(legacy_request)).get("durable",false)),"v1 opaque result remains exactly replayable after sequenced retirement")
	await get_tree().create_timer(0.01).timeout
	PlayerState._item_transaction_port._complete(first_receipt,first_plan)
	check(PlayerState.inventory == snapshot and PlayerState._item_transaction_journal == journal,"terminal old callback cannot roll back inventory or durable retirement watermark")
	check(_owned(base.instance_id,gem.instance_id),"one gear and original gem remain singly owned after all insert/remove cycles")
	# A new sequence that fails before promotion must leave the old frontier and
	# inputs intact. The same issued quote may be retried after explicit re-enable.
	var retry_quote: Dictionary = PlayerState.quote_new_item_transaction({"action":"hc.socketing.insert","target_instance_id":base.instance_id,"gem_instance_id":gem.instance_id})
	var pending: Dictionary = PlayerState.commit_item_transaction(retry_quote)
	check(bool(pending.get("pending",false)),"next sequence enters the actual writer before a controlled prepromotion cancellation")
	var bytes_before := FileAccess.get_file_as_bytes(PlayerState._profile_path(profile))
	ContentLayers.set_feature_module_enabled(Gem.MODULE,false)
	var cancelled := await _wait(pending.get("job"))
	check(not bool(cancelled.get("success",false)) and PlayerState.inventory == snapshot and PlayerState._item_transaction_journal == journal and FileAccess.get_file_as_bytes(PlayerState._profile_path(profile)) == bytes_before,"prepromotion failure does not advance frontier or mutate owned inputs/primary bytes")
	ContentLayers.set_feature_module_enabled(Gem.MODULE,true)
	check(PlayerState.quote_item_transaction(retry_quote.request) == retry_quote,"uncommitted next serial remains retryable after its producer regains permission")
	check(PlayerState.save_game(true,true,true),"final ordinary checkpoint uses the existing character writer")
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,"all owned writer jobs and callbacks drain before cold handoff")
	if failures.is_empty():
		var expected := {"profile_id":profile,"epoch":journal.epoch,"last_sequence":130,"retired_through":66,
			"first_request":first_quote.request,"last_request":last_quote.request,"legacy_request":legacy_request,
			"target_instance_id":base.instance_id,"gem_instance_id":gem.instance_id,"legacy":legacy.entries,
			"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256")}
		var file := FileAccess.open(EXPECTED,FileAccess.WRITE)
		check(file != null,"successful live producer opens its cold handoff expectation")
		if file != null:
			file.store_string(JSON.stringify(expected)); file.flush(); check(file.get_error() == OK,"complete cold expectation reaches its test-owned file"); file.close()
	_finish()
func _owned(target: String,gem: String) -> bool:
	var ids: Array[String] = []
	for record: Dictionary in PlayerState.inventory: ids.append_array(Codec.ownership_ids(record))
	return ids.count(target) == 1 and ids.count(gem) == 1 and PlayerState._validate_extended_item_ownership({"inventory":PlayerState.inventory})
func _wait(job: Variant) -> Dictionary:
	if job == null: return {"success":false}
	var deadline := Time.get_ticks_msec()+5000
	while not bool(job.response.get("finished",false)) and Time.get_ticks_msec()<deadline:
		PlayerState._json_persistence.pump(); await get_tree().process_frame
	return job.response
func _finish() -> void:
	if not proof.write_receipt("item_journal_recovery_test",checks,failures.size()): failures.append("receipt")
	print("ITEM_JOURNAL_RECOVERY_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
