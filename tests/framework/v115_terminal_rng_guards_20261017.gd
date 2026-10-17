extends Node
## Negative boundaries on the real linked Native Host; never simulates a
## completed Source session. Actual positive return belongs to full-world exit.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures := 0
func check(value: bool, label: String) -> void:
	proof.record(value,label)
	if not value: failures += 1; print("TERMINAL_RNG_GUARD_FAIL ",label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"actual isolated userdata")
	var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
	check(host != null,"actual Native Host")
	var capable: bool = host.has_method("capture_original_terminal_gameplay_random") and host.has_method("restore_original_terminal_gameplay_random")
	check(capable,"actual linked terminal RNG capture and restore")
	check(host.status().get("main_channels_prepared") == false,"negative capture boundary genuinely precedes Main channel preparation")
	if capable:
		var oracle := RandomNumberGenerator.new()
		oracle.seed = 19020261017
		seed(19020261017)
		var empty: Dictionary = host.restore_original_terminal_gameplay_random({})
		check(empty.get("success") == false and empty.get("error") == "actual_joined_Source_and_nine_Main_owner_return_required","unstarted Host cannot restore Main global RNG")
		check(randi() == oracle.randi(),"rejected empty restore preserves actual Main random stream")
		var foreign: Dictionary = host.restore_original_terminal_gameplay_random({"contract_id":"hardcore.profile.global_random.return.v1","host_object_id":host.get_instance_id()})
		check(foreign == empty,"partial self-labelled token cannot replace actual Source terminal proof")
		check(randi() == oracle.randi(),"rejected foreign restore consumes no global draw")
		var random: Object = ClassDB.instantiate("HardCoreGameplayGlobalRandom")
		var captured: Dictionary = host.capture_original_terminal_gameplay_random(random,{"bridge_generation":1,"journal_generation":1,"event_ordinal":1})
		check(captured.get("success") == false and captured.get("error") == "actual_closing_production_Source_required","Main cannot manufacture Source capture or a terminal ordinal")
		check(randi() == oracle.randi(),"rejected Source capture preserves actual Main global random stream")
		check(host.restore_original_terminal_gameplay_random({}) == empty,"invalid repeat remains rejected")
		check(randi() == oracle.randi(),"invalid repeat does not reseed or rewind Main")
	check(host.status().get("original_terminal_gameplay_random_restored") == false and host.status().get("started") == false,"all negative calls retain unstarted and unrestored state")
	var valid: bool = proof.write_receipt("v115_terminal_rng_guards_20261017",proof.records.size(),failures)
	print("V115_TERMINAL_RNG_GUARDS_20261017_", "PASS" if valid else "FAIL", " checks=",proof.records.size()," failures=",failures)
	get_tree().quit(0 if valid else 1)
