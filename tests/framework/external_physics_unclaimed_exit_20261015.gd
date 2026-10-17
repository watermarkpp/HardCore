extends Node
## Real startup/menu quit before any Source starts. Native process exit is the
## essential assertion: a scene PASS alone does not prove backend finalization.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
func _ready() -> void:
	var proof := Proof.new()
	proof.record(ProjectSettings.get_setting("physics/2d/external_owner_mode",false)==true,"actual external-owner backend initialized for startup/menu")
	var host: Object = ClassDB.instantiate("HardCoreSimulationHost")
	proof.record(host.status().get("running")==false,"no Source thread or physics handoff has been started")
	var written: bool = proof.write_receipt("external_physics_unclaimed_exit_20261015",proof.records.size(),0)
	print("EXTERNAL_PHYSICS_UNCLAIMED_EXIT_20261015_","PASS" if written else "FAIL")
	get_tree().quit(0 if written else 1)
