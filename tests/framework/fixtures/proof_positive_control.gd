extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
func _ready() -> void:
	PlayerState.test_mode = true
	var proof := Proof.new()
	proof.record(Engine.get_version_info().major == 4, "real running engine major")
	var valid := proof.write_receipt("proof_positive_control", 1, 0)
	print("FRAMEWORK_POSITIVE_CONTROL_PASS checks=1" if valid else "FRAMEWORK_POSITIVE_CONTROL_FAIL")
	get_tree().quit(0 if valid else 1)
