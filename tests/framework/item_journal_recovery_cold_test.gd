extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Gate := preload("res://tests/framework/helpers/native_producer_gate.gd")
const Journal := preload("res://scripts/items/item_transaction_journal.gd")
const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(not PlayerState.test_mode,"independent native process uses real persistence")
	var expected: Variant = Gate.read_json("res://outputs/test_logs/framework/item_journal_recovery_expected.json")
	check(Gate.accepts(expected,"item_journal_recovery_test"),"successful live producer is confirmed by this runner invocation before cold selection")
	if not failures.is_empty(): _finish(); return
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade() and PlayerState.select_character(expected.profile_id),"actual independent startup and profile load recover the sequenced journal")
	PlayerState.set_process(false)
	var journal: Dictionary = PlayerState._item_transaction_journal
	check(Journal.validate_document({"profile_id":expected.profile_id,Journal.FIELD:journal}).valid and journal.get("epoch") == expected.epoch and journal.get("retired_through") == expected.retired_through and journal.get("last_sequence") == expected.last_sequence,"cold aggregate recovers the exact durable epoch, contiguous frontier and recent results")
	check(journal.get("legacy_entries") == expected.legacy,"all 64 original opaque outcomes survive independent cold recovery")
	var before: Array = PlayerState.inventory.duplicate(true)
	check(PlayerState.quote_item_transaction(expected.first_request).get("reason") == "item_operation_retired","old retired identity remains terminal across process restart before module activation")
	check(bool(PlayerState.commit_item_transaction(PlayerState.quote_item_transaction(expected.last_request)).get("durable",false)),"recent exact outcome replays after restart without another writer job")
	check(bool(PlayerState.commit_item_transaction(PlayerState.quote_item_transaction(expected.legacy_request)).get("durable",false)),"legacy exact outcome replays after restart without another writer job")
	check(PlayerState.inventory == before and PlayerState._json_persistence.pending_count() == 0,"all replay/refusal paths preserve current item ownership and perform no writes")
	check(ContentLayers.set_feature_module_enabled(Gem.MODULE,true),"new transaction explicitly enables the original default-off module")
	var quote: Dictionary = PlayerState.quote_new_item_transaction({"action":"hc.socketing.insert","target_instance_id":expected.target_instance_id,"gem_instance_id":expected.gem_instance_id})
	check(bool(quote.get("success",false)) and quote.get("request",{}).get("operation_id") == Journal.sequence_id(expected.epoch,131),"independent process issues the next original epoch serial rather than recycling a retired identity")
	var pending: Dictionary = PlayerState.commit_item_transaction(quote)
	var response := await _wait(pending.get("job"))
	check(bool(response.get("success",false)) and int(PlayerState._item_transaction_journal.get("last_sequence",0)) == 131,"the next real ownership operation commits after independent recovery")
	var owned: Array[String] = []
	for item: Dictionary in PlayerState.inventory: owned.append_array(Codec.ownership_ids(item))
	check(owned.count(expected.target_instance_id) == 1 and owned.count(expected.gem_instance_id) == 1,"cold continuation preserves one exact gear and one original gem")
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	check(PlayerState._json_persistence.pending_count() == 0 and PlayerState._world_json_persistence.pending_count() == 0,"cold continuation consumes every actual persistence receipt")
	_finish()
func _wait(job: Variant) -> Dictionary:
	if job == null: return {"success":false}
	var deadline := Time.get_ticks_msec()+5000
	while not bool(job.response.get("finished",false)) and Time.get_ticks_msec()<deadline:
		PlayerState._json_persistence.pump(); await get_tree().process_frame
	return job.response
func _finish() -> void:
	if not proof.write_receipt("item_journal_recovery_cold_test",checks,failures.size()): failures.append("receipt")
	print("ITEM_JOURNAL_RECOVERY_COLD_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
