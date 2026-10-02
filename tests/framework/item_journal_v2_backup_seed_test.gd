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
	var cases: Array = []
	for pair: Array in [[1,2],[65,130]]:
		var data := await Fixture.create_case(self,pair[0],pair[1])
		if data.is_empty(): _finish(); return
		cases.append(data)
	# All profile changes and writers finish before corrupting the owned files.
	for data: Dictionary in cases:
		Fixture.corrupt(self,data); data.erase("bytes")
	if failures.is_empty():
		var expected := {"cases":cases,"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256")}
		check(Fixture.write("res://outputs/test_logs/framework/item_journal_v2_backup_seed_expected.json",JSON.stringify(expected).to_utf8_buffer()),"complete owned handoff written")
	_finish()
func _finish() -> void:
	if not proof.write_receipt("item_journal_v2_backup_seed_test",proof.records.size(),failures.size()): failures.append("receipt")
	print("item_journal_v2_backup_seed_test_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",proof.records.size(),str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
