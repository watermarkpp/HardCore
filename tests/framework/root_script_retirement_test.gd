extends Node

## Separates loading Root's real dependency graph from world startup.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Root := preload("res://scripts/game_root.gd")
@export var construct_root := false
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(not PlayerState.test_mode and OS.get_environment("APPDATA").replace("\\", "/").contains("/.godot/runtime_appdata/"),
		"Root dependency characterization owns isolated data")
	var loaded_root: Script = Root
	check(loaded_root.can_instantiate(), "the real Root dependency graph loads without world initialization")
	if construct_root:
		var game: Node = Root.new()
		var watched := {"root":weakref(game), "world":weakref(game._world_context), "clock":weakref(game._time_domains)}
		check(not game.is_inside_tree() and game._streaming_coordinator == null and game._feature_effect_runtime == null,
			"constructor does not create a world streaming or feature runtime")
		game.free()
		game = null
		var retired := true
		for owner: String in watched:
			retired = retired and watched[owner].get_ref() == null
		check(retired, "unentered Root and its context owners release without startup or reset")
	for frame in 4:
		await get_tree().process_frame
	var scene_id := "root_constructor_retirement_test" if construct_root else "root_script_retirement_test"
	var written := proof.write_receipt(scene_id, proof.records.size(), failures.size())
	print("ROOT_DEPENDENCY_RETIREMENT_", "PASS" if written and failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
