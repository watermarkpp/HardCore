extends Node

const Gate := preload("res://tests/framework/helpers/native_producer_gate.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Codec := preload("res://scripts/items/item_extension_codec.gd")
const Gem := preload("res://scripts/items/socket_gem_rules.gd")
const Rune := preload("res://scripts/items/rune_item_rules.gd")
const EXPECTED := "res://outputs/test_logs/framework/rune_source_composition_expected.json"
var proof := Proof.new()
var checks := 0
var errors: Array[String]=[]

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks+=1
	if not value: errors.append(label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(not PlayerState.test_mode,"independent cold process starts with actual persistence")
	var expected: Variant=JSON.parse_string(FileAccess.get_file_as_string(EXPECTED)) if FileAccess.file_exists(EXPECTED) else null
	check(expected is Dictionary,"successful live composition supplies an explicit owned handoff")
	if not expected is Dictionary: _finish(); return
	var valid:=Gate.accepts(expected,"rune_source_composition_test")
	check(valid,"expectation binds this invocation's native exit-zero complete live producer")
	if not valid: _finish(); return
	check(expected.producer_run_id!=OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"),"cold restoration has a different native execution identity")
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/rune_composition_registry.json")
		and ContentLayers.set_feature_module_enabled(Gem.MODULE,true) and ContentLayers.set_feature_module_enabled(Rune.MODULE,true) and ContentLayers.set_feature_module_enabled("hc.ignite",true),
		"fresh process resolves the same registered sources through the production configuration")
	PlayerState.profile_directory=expected.profile_directory; PlayerState.profile_index_path=expected.profile_index_path
	PlayerState.shared_warehouse_path=expected.shared_warehouse_path
	PlayerState.shared_warehouse_transaction_log_path=expected.shared_warehouse_transaction_log_path
	PlayerState.active_profile_id=expected.profile_id; PlayerState._shared_warehouse_initialized=false
	PlayerState.test_mode=false; PlayerState.load_save()
	check(PlayerState.last_load_result.success,"real cold loader restores the producer's isolated durable profile")
	var gear: Dictionary=PlayerState.equipment.get("hc.slot.weapon",{})
	var encoded:=Codec.encode_runtime(gear)
	var expected_encoded:=Codec.encode_runtime(expected.gear)
	if gear!=expected.gear:
		var type_differences: Array=[]
		for key: String in expected.gear:
			if typeof(expected.gear[key])!=typeof(gear.get(key)): type_differences.append({"field":key,"expected_type":typeof(expected.gear[key]),"actual_type":typeof(gear.get(key))})
		type_differences.append({"field":"extension.format_version","expected_type":typeof(expected.gear[Codec.RUNTIME_EXTENSION].format_version),"actual_type":typeof(gear[Codec.RUNTIME_EXTENSION].format_version)})
		print("SOURCE_COMPOSITION_COLD_TYPES="+JSON.stringify(type_differences))
	# Persistence owns JSON wire values. Compare every field after the same
	# JSON boundary used by the transaction guard, not parser float/int tags.
	check(encoded.status==Codec.KNOWN_VALID and expected_encoded.status==Codec.KNOWN_VALID
		and JSON.parse_string(JSON.stringify(encoded.item))==JSON.parse_string(JSON.stringify(expected_encoded.item)),
		"cold equipment keeps the complete validated persisted wire content exactly")
	check(Codec.ownership_ids(gear)==[expected.gear.instance_id,expected.gem_instance_id,expected.rune_instance_id],"cold gear owns the same original gem and rune exactly once")
	check(PlayerState._validate_extended_item_ownership({"inventory":PlayerState.inventory,"equipment":PlayerState.equipment}),"cold aggregate has no second accessible copy of either embedded asset")
	var handles: Array=[]
	for binding: Dictionary in PlayerState.feature_bundle().get("event_index",{}).get("damage_committed:hc.skill.wizard.ice_storm",[]): handles.append(binding.handle)
	handles.sort()
	check(handles.size()==3 and handles==expected.source_handles,"cold compiler reconstructs the three exact affix, gem and rune provenance handles")
	var inventory_before:=PlayerState.inventory.duplicate(true); var equipment_before:=PlayerState.equipment.duplicate(true)
	var replay:=PlayerState.commit_item_transaction(PlayerState.quote_item_transaction(expected.last_request))
	check(replay.get("durable",false) and not replay.get("pending",false) and PlayerState._json_persistence.pending_count()==0,
		"cold retry of the original insertion returns the recorded outcome without a new writer")
	check(PlayerState.inventory==inventory_before and PlayerState.equipment==equipment_before,"cold gem replay preserves all three sources and both original assets")
	var rune_replay:=PlayerState.commit_item_transaction(PlayerState.quote_item_transaction(expected.last_rune_request))
	check(rune_replay.get("durable",false) and not rune_replay.get("pending",false)
		and PlayerState._json_persistence.pending_count()==0,"cold retry of the original rune operation also reuses the persisted journal result without a writer")
	check(PlayerState.inventory==inventory_before and PlayerState.equipment==equipment_before,
		"cold rune replay preserves the original rune, gem and equipment exactly once")
	_finish()

func _finish() -> void:
	if not proof.write_receipt("rune_source_composition_cold_test",checks,errors.size()): errors.append("receipt")
	print(("FRAMEWORK_RUNE_SOURCE_COMPOSITION_COLD_PASS" if errors.is_empty() else "FRAMEWORK_RUNE_SOURCE_COMPOSITION_COLD_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
