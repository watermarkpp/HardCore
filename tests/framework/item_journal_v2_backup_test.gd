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
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"owned isolated account and production persistence only")
	if not failures.is_empty(): _finish(); return
	PlayerState.begin_startup_save_upgrade()
	check(PlayerState.finish_startup_save_upgrade(),"real startup migration gate")
	check(ContentLayers.set_feature_module_enabled(Fixture.Gem.MODULE,true),"explicit default-off module activation")
	if not failures.is_empty(): _finish(); return
	for pair: Array in [[1,2],[65,130]]:
		var data := await Fixture.create_case(self,pair[0],pair[1],true)
		if data.is_empty(): _finish(); return
		Fixture.corrupt(self,data)
		PlayerState.load_save()
		var continued := await Fixture.probe(self,data)
		if not continued.is_empty():
			await _recovery_failure_and_repeat(continued)
			check(Fixture.write(data.path+".bak",data.bytes) and DirAccess.remove_absolute(ProjectSettings.globalize_path(data.path)) == OK,"only this fixture's primary is removed for a separate missing-v2-primary case")
			PlayerState.load_save()
			await Fixture.probe(self,data)
	_finish()
func _recovery_failure_and_repeat(data: Dictionary) -> void:
	var path: String = data.path
	var checkpoint := FileAccess.get_file_as_bytes(path)
	# Both checkpoint+1 operations removed the gem. Its exact ownership is
	# obtained from the preserved result; remove requests intentionally omit it.
	var gem_id: String = PlayerState._item_transaction_journal.entries.back().gem_instance_id
	var quote: Dictionary = PlayerState.quote_new_item_transaction({"action":"hc.socketing.insert","target_instance_id":data.new_request.target_instance_id,"gem_instance_id":gem_id})
	var pending: Dictionary = PlayerState.commit_item_transaction(quote)
	check(bool((await Fixture.wait_job(self,pending.get("job"))).get("success",false)),"v3 stream has another real completed command before repeated recovery")
	PlayerState._start_item_save(); PlayerState._json_persistence.drain()
	check(Fixture.write(path+".bak",checkpoint) and Fixture.write(path,"{owned-v3-primary".to_utf8_buffer()),"owned v3 rollback inputs prepared")
	var before: Array = PlayerState.inventory.duplicate(true)
	var primary := FileAccess.get_file_as_bytes(path)
	var absolute_temp := ProjectSettings.globalize_path(path+".tmp")
	check(DirAccess.make_dir_absolute(absolute_temp) == OK,"owned empty directory injects temporary-file open failure")
	PlayerState.load_save()
	check(not bool(PlayerState.last_load_result.get("success",false)) and PlayerState.last_load_result.get("reason") == "backup_restore_temp_open_failed","failed recovery cannot publish an in-memory-only epoch")
	check(PlayerState.inventory == before and FileAccess.get_file_as_bytes(path) == primary and FileAccess.get_file_as_bytes(path+".bak") == checkpoint and not PlayerState.save_game(false,false,false),"failed promotion preserves both owned inputs and locks ordinary writes")
	check(DirAccess.remove_absolute(absolute_temp) == OK,"only the test-owned empty fault directory is removed")
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success",false)) and PlayerState._item_transaction_journal.epoch != data.epoch,"actual v3 backup recovery rotates epoch again after the write barrier is available")
	var completed: int = PlayerState._json_persistence.completed_count
	var current: Array = PlayerState.inventory.duplicate(true)
	check(PlayerState.quote_item_transaction(quote.request).get("reason") == "item_operation_epoch_mismatch","previous v3 producer cannot replay a lost completed operation")
	check(PlayerState.inventory == current and PlayerState._json_persistence.pending_count() == 0 and PlayerState._json_persistence.completed_count == completed,"repeated recovery refusal creates no writer or ownership delta")
	check(bool(PlayerState.commit_item_transaction(PlayerState.quote_item_transaction(data.new_request)).get("durable",false)),"preserved prior-epoch result remains a read-only replay after v3 recovery")
	check(PlayerState.save_game(true,true,true),"successful recovery clears the failed-restore write lock through the existing loader")

	check(Fixture.write(path+".bak",checkpoint) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,"owned missing-v3-primary case retains the original valid checkpoint")
	PlayerState.load_save()
	check(bool(PlayerState.last_load_result.get("success",false)) and PlayerState._item_transaction_journal.epoch != data.epoch and FileAccess.file_exists(path),"missing v3 primary restores through durable fresh-epoch promotion")
	var restored_before: Array = PlayerState.inventory.duplicate(true)
	var stale: Dictionary = PlayerState.commit_item_transaction(quote)
	check(not bool(stale.get("success",false)) and not stale.has("job") and PlayerState.inventory == restored_before and PlayerState._json_persistence.pending_count() == 0,"missing-primary recovery also rejects the original cached lost v3 command without a writer")

func _finish() -> void:
	if not proof.write_receipt("item_journal_v2_backup_test",proof.records.size(),failures.size()): failures.append("receipt")
	print("item_journal_v2_backup_test_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",proof.records.size(),str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
