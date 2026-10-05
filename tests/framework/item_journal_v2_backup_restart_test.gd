extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Fixture := preload("res://tests/framework/helpers/journal_backup_fixture.gd")
const Gate := preload("res://tests/framework/helpers/native_producer_gate.gd")
var proof := Proof.new()
var failures: Array[String] = []
func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: failures.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var expected: Variant = Gate.read_json("res://outputs/test_logs/framework/item_journal_v2_backup_cold_expected.json")
	check(Gate.accepts(expected,"item_journal_v2_backup_cold_test"),"this native successful cold producer owns the recovered epochs")
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"owned isolated account and production persistence only")
	if not failures.is_empty(): _finish(); return
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"real startup migration gate")
	check(ContentLayers.set_feature_module_enabled(Fixture.Gem.MODULE,true),"explicit default-off module activation")
	if not failures.is_empty(): _finish(); return
	PlayerState.set_process(false)
	for data: Dictionary in expected.cases:
		check(PlayerState.select_character(data.profile_id),"independent restart loads recovered profile")
		var journal: Dictionary = PlayerState._item_transaction_journal
		check(journal.get("epoch") == data.epoch and journal.get("last_sequence") == data.last_sequence,"recovery epoch is durable rather than a temporary issuer cache")
		var before: Array = PlayerState.inventory.duplicate(true)
		var completed: int = PlayerState._json_persistence.completed_count
		var bytes := FileAccess.get_file_as_bytes(data.path)
		check(PlayerState.quote_item_transaction(data.old_request).get("reason") == "item_operation_epoch_mismatch","old missing result never regains eligibility across another restart")
		check(bool(PlayerState.commit_item_transaction(PlayerState.quote_item_transaction(data.new_request)).get("durable",false)),"new epoch completed result stays exactly replayable")
		check(PlayerState.inventory == before and PlayerState._json_persistence.pending_count() == 0 and PlayerState._json_persistence.completed_count == completed and FileAccess.get_file_as_bytes(data.path) == bytes,"restart replay/refusal creates no writer and changes no resources or file")
	_finish()
func _finish() -> void:
	if not proof.write_receipt("item_journal_v2_backup_restart_test",proof.records.size(),failures.size()): failures.append("receipt")
	print("item_journal_v2_backup_restart_test_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",proof.records.size(),str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
