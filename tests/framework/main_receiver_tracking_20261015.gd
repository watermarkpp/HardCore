extends Node
## Actual loaded original receiver scripts and readonly callback invocation.
## Does not assert that a Source session or UI command migration is complete.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SOURCES: Array[String] = ["res://scripts/startup_loading.gd","res://scripts/character_select.gd","res://scripts/game_data.gd","res://scripts/layers/runtime/content_layer_registry.gd","res://scripts/layers/runtime/game_mode_service.gd","res://scripts/layers/runtime/domain_runtime_services.gd","res://scripts/layers/runtime/runtime_service_facade.gd","res://scripts/equipment_character_preview.gd","res://scripts/device_lab_runtime.gd","res://scripts/hud.gd","res://scripts/inventory_panel.gd","res://scripts/enhancement_panel.gd","res://scripts/item_detail_presenter.gd","res://scripts/quest_panel.gd","res://scripts/shop_panel.gd","res://scripts/skill_panel.gd","res://scripts/warehouse_panel.gd"]
var _proof := Proof.new()
var _failed := 0
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failed += 1
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var original: RefCounted = PlayerState.get("_model")
	var level: int = original.level
	for path: String in SOURCES:
		var code: Script = load(path)
		check(code!=null,"actual receiver Script loads: "+path)
		if code==null: continue
		var has_ledger := false
		for prop: Dictionary in code.get_script_property_list():
			if prop.name == &"_original_main_callback_ledger": has_ledger = true
		check(has_ledger,"actual original receiver exposes callback-depth ledger: "+path)
		var method_names: Dictionary = {}
		for method: Dictionary in code.get_script_method_list(): method_names[String(method.name)] = true
		if method_names.has("_ready"): check(method_names.has("_original_source_"+path.get_file().get_basename()+"__ready"),"real ready wrapper retains original body: "+path)
	if GameData.has_method("_original_source_game_data_item_usage_summary"):
		var item_name := ""
		for item: Dictionary in GameData.item_catalog:
			if not String(item.get("name","")).is_empty(): item_name=String(item.name);break
		check(not item_name.is_empty(),"readonly call uses a genuine loaded item")
		var direct: Dictionary = GameData.call("_original_source_game_data_item_usage_summary",item_name,level)
		var wrapped: Dictionary = GameData.item_usage_summary(item_name,level)
		check(direct == wrapped,"wrapper returns the exact original readonly result")
		var ledger: Dictionary=GameData.get("_original_main_callback_ledger")
		check(ledger.get("item_usage_summary",-1)==0,"real callback entry returned and closed its depth")
		check(ledger.get("_ready",-1)==0,"actual autoload ready callback returned before test")
	else: check(false,"real GameData readonly callback has retained source implementation")
	if _failed == 0:
		var panel: Control = load("res://scripts/enhancement_panel.gd").new()
		add_child(panel)
		var depths: Dictionary = panel.get("_original_main_callback_ledger")
		check(depths.get("_ready",-1)==0,"real derived/base ready returns through two distinct retained methods")
		check(panel.get("forge_button") != null and panel.get("forge_slots").size() == 9,"real derived forge construction completes after real InventoryPanel base ready")
		panel.refresh()
		check(depths.get("refresh",0)==0,"real inherited refresh closes without recursive dispatch")
		panel.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		check(not is_instance_valid(panel),"real composed panel retires through ordinary delete queue")
	check(PlayerState.get("_model")==original and original.level==level,"callback proof test leaves actual Profile owner/state unchanged")
	var written: bool=_proof.write_receipt("main_receiver_tracking_20261015",_proof.records.size(),_failed)
	print("MAIN_RECEIVER_TRACKING_20261015_", "PASS" if written and _failed==0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed==0 else 1)
