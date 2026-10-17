extends Node
## Real production Profile creation/selection in the runner's isolated userdir.
## Captures genuine detached original Root identity; no full-world claim.
const App := preload("res://scripts/gameplay/source/main_boot_application.gd")
const Router := preload("res://scripts/gameplay/source/main_root_checkpoint_router.gd")
const Attachment := preload("res://scripts/gameplay/world/world_main_root_attachment.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failed += 1
func _ready() -> void:
	var user_dir: String = OS.get_user_data_dir().replace("\\","/")
	check(user_dir.contains("/.godot/runtime_appdata/"),"all profile I/O is inside the official isolated runtime directory")
	if _failed > 0: _finish(); return
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var isolated: String = "user://main_premap_%d" % Time.get_ticks_usec()
	PlayerState.profile_directory = isolated.path_join("characters")
	PlayerState.profile_index_path = isolated.path_join("profiles.json")
	PlayerState.shared_warehouse_path = isolated.path_join("warehouse.json")
	PlayerState.shared_warehouse_transaction_log_path = isolated.path_join("warehouse.transaction.json")
	PlayerState._shared_warehouse_initialized = false
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlayerState.profile_directory)) == OK,"actual isolated character directory created")
	PlayerState.test_mode = false
	var creation: String = PlayerState.create_character("BootTrace115")
	check(creation.is_empty(),"original character transaction creates its own canonical storage identity: " + creation)
	if not creation.is_empty(): PlayerState.test_mode = true; _finish(); return
	var profile_id: String = PlayerState.active_profile_id
	check(not profile_id.is_empty() and PlayerState.select_character(profile_id),"original select_character loads the real newly persisted profile")
	check(PlayerState.last_load_result.get("success") == true,"actual production loader completed before Main identity capture")
	var profile_path: String = PlayerState._profile_path(profile_id)
	var before: Dictionary = {}
	for path: String in [profile_path,PlayerState.profile_index_path,PlayerState.shared_warehouse_path]:
		check(FileAccess.file_exists(path),"original writer emitted isolated document: " + path.get_file())
		if FileAccess.file_exists(path): before[path] = FileAccess.get_sha256(path)
	var root: Node2D = load("res://scenes/main.tscn").instantiate()
	var ctor_api: Script = Attachment
	var ctor: Dictionary = {}
	for method: Dictionary in ctor_api.get_script_method_list():
		if method.name == &"capture_original_constructor_before_tree_entry": ctor = ctor_api.call("capture_original_constructor_before_tree_entry",root)
	check(ctor.get("success") == true,"actual attachment captures original constructor values before Main tree entry")
	if ctor.get("success") == true:
		check(ctor.original_root_id == root.get_instance_id() and ctor.original_source_sha256 == root.get_script().get_source_code().sha256_text(),"constructor publication is bound to the actual original root and Script")
		check(not root.is_inside_tree() and ctor.source_fields.get("constructor_values") is Dictionary,"constructor capture neither enters the tree nor erases the original typed/sentinel codec")
		var original_rng: RandomNumberGenerator = root.get("_rng")
		check(ctor.world_random.seed == original_rng.seed and ctor.world_random.state == original_rng.state,"snapshot reads the genuine constructor RNG without randomize/draw")
	check(root.get("current_map_id") == -1 and root.get("_zone_generation") == 0,"genuine original constructor remains before first map arrival")
	var captured: Dictionary = App.inspect_original_root_identity(root,PlayerState)
	check(captured.get("success") == true and captured.get("phase") == "PRE_MAP","selected original Root has a legitimate pre-map capture rather than guessed target activation")
	var identity: Dictionary = captured.get("world",{})
	var router := Router.new()
	check(bool(router.call("_valid_world",identity)),"actual Main checkpoint accepts the same selected pre-map constructor identity")
	var other_negative: Dictionary = identity.duplicate(true)
	other_negative.runtime_map_id = -2
	check(not bool(router.call("_valid_world",other_negative)),"checkpoint does not admit an undefined negative map")
	other_negative.runtime_map_id = -1
	other_negative.world_epoch = 1
	check(not bool(router.call("_valid_world",other_negative)),"checkpoint does not reopen a retired generation as initial pre-map")
	check(identity.size() == 5 and identity.get("world_runtime_id") == root.get_instance_id() and identity.get("world_epoch") == 0 and identity.get("runtime_map_id") == -1 and identity.get("profile_id") == profile_id,"all five identity fields come from actual Root and selected Profile")
	check(not identity.is_empty() and identity.is_read_only(),"actual pre-map identity is immutable across the Main/Source boundary")
	var rejected_root: Node2D = load("res://scenes/main.tscn").instantiate()
	rejected_root.set("current_map_id",-2)
	check(App.inspect_original_root_identity(rejected_root,PlayerState).get("success") != true,"undefined negative map sentinel is not admitted")
	rejected_root.set("current_map_id",-1); rejected_root.set("_zone_generation",1)
	check(App.inspect_original_root_identity(rejected_root,PlayerState).get("success") != true,"retired/noninitial generation cannot re-enter pre-map state")
	rejected_root.free()
	PlayerState.active_profile_id = ""
	check(App.inspect_original_root_identity(root,PlayerState).get("success") != true,"pre-map capture cannot create an unselected gameplay session")
	PlayerState.active_profile_id = profile_id
	check(root.get("current_map_id") == -1 and root.get("_zone_generation") == 0,"capture does not write map or generation")
	for path: String in before:
		check(FileAccess.get_sha256(path) == before[path],"identity capture did not rewrite isolated saved document: " + path.get_file())
	root.free()
	PlayerState.test_mode = true
	_finish()
func _finish() -> void:
	var written: bool = _proof.write_receipt("main_premap_capture_20261015",_proof.records.size(),_failed)
	print("MAIN_PREMAP_CAPTURE_20261015_", "PASS" if written and _failed == 0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed == 0 else 1)
