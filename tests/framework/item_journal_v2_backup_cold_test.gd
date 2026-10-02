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
	var expected: Variant = Gate.read_json("res://outputs/test_logs/framework/item_journal_v2_backup_seed_expected.json")
	check(Gate.accepts(expected,"item_journal_v2_backup_seed_test"),"this native successful producer owns the corrupt-primary/old-v2 inputs")
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\","/").contains("/.godot/runtime_appdata/"),"owned isolated account and production persistence only")
	if not failures.is_empty(): _finish(); return
	PlayerState.begin_startup_save_upgrade()
	var startup_ok := PlayerState.finish_startup_save_upgrade()
	check(startup_ok,"real startup migration gate: "+str(PlayerState.startup_save_upgrade_result))
	check(ContentLayers.set_feature_module_enabled(Fixture.Gem.MODULE,true),"explicit default-off module activation")
	if not failures.is_empty(): _finish(); return
	PlayerState.set_process(false)
	var cases: Array = []
	for data: Dictionary in expected.cases:
		check(PlayerState.select_character(data.profile_id),"actual cold selection recovers the requested owned profile")
		var result := await Fixture.probe(self,data)
		if not result.is_empty(): cases.append(result)
	if failures.is_empty():
		var outgoing := {"cases":cases,"producer_run_id":OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"invocation_id":OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),"source_content_sha256":OS.get_environment("HARDCORE_R3_CONTENT_SHA256")}
		check(Fixture.write("res://outputs/test_logs/framework/item_journal_v2_backup_cold_expected.json",JSON.stringify(outgoing).to_utf8_buffer()),"complete owned handoff written")
	_finish()
func _finish() -> void:
	if not proof.write_receipt("item_journal_v2_backup_cold_test",proof.records.size(),failures.size()): failures.append("receipt")
	print("item_journal_v2_backup_cold_test_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",proof.records.size(),str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
