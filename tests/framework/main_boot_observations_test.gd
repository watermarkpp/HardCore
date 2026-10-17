extends Node
## Scoped actual Main observation/negative-admission fixture. No stub producer,
## gameplay profile, body, Host startup, generation or resource readiness.
const Observe:=preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
const Config:=preload("res://scripts/gameplay/source/main_original_host_config_provider.gd")
const BootFactory:=preload("res://scripts/gameplay/source/main_original_boot_provider_factory.gd")
const Proof:=preload("res://tests/framework/helpers/check_receipt.gd")
var _proof:=Proof.new()
var failures: Array[String]=[]
func _check(condition: bool,label: String) -> void:
	_proof.record(condition,label)
	if not condition:failures.append(label)
func _ready() -> void:
	var root:=Node2D.new();add_child(root)
	var scope: Dictionary=Observe.node(root)
	_check(not (scope.get("actual_node_id")!=root.get_instance_id() or scope.get("inside_world")!=true),"actual_scope_capture")
	_check(not (scope.get("parent_scope_id")!=get_instance_id() or scope.get("process_frame")!=Engine.get_process_frames() or scope.get("physics_frame")!=Engine.get_physics_frames()),"actual_scope_parent_clock")
	_check(not (scope.has("life_generation")),"invented_source_life_generation")
	var graph: Dictionary=Observe.capture({"actual_position":Vector2(2,3),"scope":scope})
	_check(not (graph.get("success")!=true or graph.get("publication",{}).get("actual_position")!=Vector2(2,3)),"actual_runtime_graph_Vector2")
	_check(ClassDB.class_exists("HardCoreSimulationHost"),"actual_native_Host_exists")
	if not ClassDB.class_exists("HardCoreSimulationHost"):
		root.free();_finish();return
	var host: Object=ClassDB.instantiate("HardCoreSimulationHost")
	var config: RefCounted=Config.new()
	var negative: Dictionary=config.capture_actual_original_source_host_config(host,{"root":root},{})
	_check(not (negative.get("status")!="MISSING" or negative.get("error")!="actual_Host_generation_capacity_policy_producer_required"),"missing_policy_must_reject")
	_check(not (negative.get("actual_observed",{}).get("engine_clock",{}).get("source_process_frame")!=Engine.get_process_frames()),"missing_policy_preserves_actual_observation")
	var missing: Dictionary=BootFactory.create_main(host,root,{})
	_check(not (missing.get("status")!="MISSING" or missing.get("actual_observed",{}).get("required",[]).is_empty()),"missing_producers_must_reject")
	root.free()
	_finish()
func _finish() -> void:
	var written: bool=_proof.write_receipt("main_boot_observations_test",_proof.records.size(),failures.size())
	print("MAIN_BOOT_OBSERVATIONS_","PASS" if written and failures.is_empty() else "FAIL", " failures=",failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
