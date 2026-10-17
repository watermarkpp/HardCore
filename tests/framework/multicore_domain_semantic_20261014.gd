extends Node

## Parse the actual promoted dependency graph without instantiating another
## gameplay state or claiming runtime/physics/performance acceptance.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures := 0

func _scripts(path: String, found: Array[String]) -> void:
	var files := DirAccess.get_files_at(path)
	files.sort()
	for filename: String in files:
		if filename.ends_with(".gd"): found.append(path.path_join(filename))
	var directories := DirAccess.get_directories_at(path)
	directories.sort()
	for directory: String in directories: _scripts(path.path_join(directory), found)

func _ready() -> void:
	var paths: Array[String] = ["res://scripts/enemy.gd", "res://scripts/game_root.gd"]
	_scripts("res://scripts/gameplay", paths)
	for resource_owner_script: String in ["feature_resource_owner_factory", "feature_resource_owner_coordinator", "feature_resource_owner_primitives", "feature_resource_main_primitives", "feature_resource_main_facade", "feature_resource_main_shader_acquisition", "feature_resource_reference"]:
		paths.append("res://scripts/features/runtime/" + resource_owner_script + ".gd")
	for path: String in paths:
		var script: Script = load(path) as Script
		var valid: bool = script != null and script.can_instantiate()
		proof.record(valid, "Godot semantic resolution " + path)
		if not valid: failures += 1
	var valid := proof.write_receipt("multicore_domain_semantic_20261014", paths.size(), failures)
	print("MULTICORE_DOMAIN_SEMANTIC_", "PASS" if valid and failures == 0 else "FAIL", " scripts=", paths.size())
	get_tree().quit(0 if valid and failures == 0 else 1)
