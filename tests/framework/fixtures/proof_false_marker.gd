extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
func _ready() -> void:
	PlayerState.test_mode = true
	var proof := Proof.new()
	proof.record(false, "intentional false assertion")
	proof.write_receipt("proof_false_marker", 1, 0)
	print("FRAMEWORK_FALSE_MARKER_PASS checks=1")
	get_tree().quit(0)
