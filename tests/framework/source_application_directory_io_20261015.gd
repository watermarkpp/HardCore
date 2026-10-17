extends Node
## Root proof wrapper over the real canonical Main directory leaf.
## No profile selection, Host, real save write, or fake resource publication.
const MainLeaf := preload("res://scripts/gameplay/world/world_source_application_main.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var _proof := Proof.new()
var _failed := 0
func check(value: bool, label: String) -> void:
	_proof.record(value,label)
	if not value: _failed += 1
func _ready() -> void:
	var original_model: RefCounted = PlayerState.get("_model")
	var profile_id: String = original_model.get("active_profile_id")
	check(OS.get_thread_caller_id() == OS.get_main_thread_id() and Gate.write_allowed(),"actual canonical Main compiler barrier")
	var registry: String = ContentLayers.FEATURE_REGISTRY
	check(FileAccess.file_exists(registry),"actual production module registry exists")
	var prepared: Dictionary = MainLeaf.prepare_original_directory(registry)
	check(prepared.get("success") == true,"new Main leaf executes original complete directory compiler")
	check(prepared.get("candidate") is Dictionary and prepared.get("authority") is Dictionary,"original catalog and authority result shape")
	check(prepared.get("bindings") is Array and prepared.get("enabled") is Array,"original bindings and enabled module list retained")
	var bad: Dictionary = MainLeaf.prepare_original_directory("user://source_application_test_untrusted_registry.json")
	check(bad.get("success") != true and bad.get("errors") is Array and not bad.errors.is_empty(),"untrusted registry rejected with real original errors")
	check(is_same(PlayerState.get("_model"),original_model) and original_model.get("active_profile_id") == profile_id,"directory preparation does not adopt another Profile or character")
	check(Gate.write_allowed(),"directory reader returns without acquiring permanent catalog writer")
	var written: bool = _proof.write_receipt("source_application_directory_io_20261015",_proof.records.size(),_failed)
	print("SOURCE_APPLICATION_DIRECTORY_IO_20261015_", "PASS" if written and _failed == 0 else "FAIL", " checks=",_proof.records.size()," failures=",_failed)
	get_tree().quit(0 if written and _failed == 0 else 1)
