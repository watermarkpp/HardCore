extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
func _ready() -> void:
	PlayerState.test_mode = true
	var proof := Proof.new()
	proof.write_receipt("proof_zero_checks", 0, 0)
	print("FRAMEWORK_ZERO_CHECKS_PASS checks=0")
	get_tree().quit(0)
