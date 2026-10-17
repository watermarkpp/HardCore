extends Node
## Actual button -> original code/cover -> production Main producer. This
## fixed-engine checkpoint proves the guarded pre-admission failure only.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
var _launcher: Control
var _model: RefCounted
var _profile := ""
var _clicked := false
var _deadline := 0
var _finishing := false
var _resident: PackedScene
func check(ok: bool, label: String) -> void:
	_proof.record(ok,label)
	if not ok: _failed += 1; print("CHARACTER_SOURCE_ENTRY_FAILED ",label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	check(OS.get_user_data_dir().replace("\\","/").contains("/.godot/runtime_appdata/"),"original save APIs are isolated from real user data")
	if _failed > 0: _finish(); return
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	var base: String = "user://character_source_entry_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = base.path_join("characters")
	PlayerState.profile_index_path = base.path_join("profiles.json")
	PlayerState.shared_warehouse_path = base.path_join("warehouse.json")
	PlayerState.shared_warehouse_transaction_log_path = base.path_join("warehouse.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory)) == OK,"new isolated save directory")
	PlayerState.test_mode = false
	var error: String = PlayerState.create_character("Entry115")
	check(error.is_empty(),"actual original create transaction: "+error)
	if not error.is_empty(): _finish(); return
	_profile = PlayerState.active_profile_id; _model = PlayerState.get("_model")
	check(PlayerState.select_character(_profile),"original saved Profile is selected before launch")
	_resident = load("res://scenes/main.tscn")
	_launcher = load("res://scenes/character_select.tscn").instantiate()
	_launcher.force_launch_preload_for_test = true
	get_tree().root.add_child(_launcher); get_tree().current_scene = _launcher
	_deadline = Time.get_ticks_usec()+26000000
func _process(_delta: float) -> void:
	if _launcher == null or _finishing: return
	if not _clicked:
		_clicked = true; _launcher.enter_button.pressed.emit()
	var receipt: Dictionary = _launcher.get("_source_startup_receipt")
	if receipt.get("unstarted_retirement",{}).get("success") == true:
		_finishing = true
		check(receipt.get("details",{}).get("missing") == [{"capability":"source_application_loading_cps","status":"MISSING"}],"prepared actual Native channel reports the precise World capability boundary")
		check(receipt.get("error") == "actual_Source_application_execution_contracts_required" and receipt.get("handled") == false,"real production entry reaches exact missing capability before any World admission: "+str(receipt))
		check(_launcher.get("_source_startup_producer") == null,"Native-proven unstarted producer is retired before retry")
		check(PlayerState.get("_source_domain_gate") == null and PlayerState.get("_model") == _model and PlayerState.active_profile_id == _profile,"same original Profile authority survives production launch rejection")
		check(get_tree().current_scene == _launcher and not _launcher.get("_launch_in_progress") and not _launcher.launch_loading_overlay.visible,"actual original UI restores only after unstarted retirement")
		check(not get_tree().root.has_meta(&"hardcore_original_main_boot_application"),"sole real application entry is uninstalled after Native abort")
		for name: String in ["HardCoreSourceMainLifecycle","HardCoreMainSessionTransport","HardCoreOriginalCloseProcessFrame"]:
			check(get_tree().root.get_node_or_null(NodePath(name)) == null,"actual lifecycle listener released:"+name)
		for node: Node in get_tree().root.get_children():
			check(node.get_script() != preload("res://scripts/game_root.gd"),"no second or fallback GameRoot was instantiated")
		_finish.call_deferred()
	elif Time.get_ticks_usec() > _deadline:
		_finishing = true; check(false,"production entry bounded completion: "+str(receipt)); _finish.call_deferred()
func _finish() -> void:
	set_process(false)
	if is_instance_valid(_launcher):
		if get_tree().current_scene == _launcher: get_tree().current_scene = null
		_launcher.queue_free()
		await _launcher.tree_exited
		await get_tree().process_frame # Original tree deletion and Lease PREDELETE.
		_launcher = null
	# The real launch code owner still owes its original retirement FIFO after
	# a before-Source failure. Let that actual owner drain while frames run.
	var idle := preload("res://scripts/gameplay/source/main_source_admission.gd").new()
	idle.set("_legacy_resources",ContentLayers._feature_resources())
	var deadline: int = Time.get_ticks_usec()+5000000
	while idle.capture_original_resource_idle_state().get("success") != true and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
	check(idle.capture_original_resource_idle_state().get("success") == true,"actual original code retirement FIFO drains before quitting")
	PlayerState.get("_model").close_profile() # Original writer barrier, no test-mode persistence bypass.
	var written: bool = _proof.write_receipt("character_source_launch_entry_20261016",_proof.records.size(),_failed)
	print("CHARACTER_SOURCE_LAUNCH_ENTRY_20261016_","PASS" if written and _failed == 0 else "FAIL")
	get_tree().quit(0 if written and _failed == 0 else 1)
