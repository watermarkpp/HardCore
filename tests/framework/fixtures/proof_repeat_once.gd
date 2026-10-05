extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

func _ready() -> void:
	PlayerState.test_mode = true
	var path := "user://runner-repeat-once-" + OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID")
	var proof := Proof.new()
	proof.record(not FileAccess.file_exists(path), "one successful producer per invocation; second attempt deliberately fails")
	var marker := FileAccess.open(path, FileAccess.WRITE)
	if marker != null:
		marker.store_string("owned runner fixture")
		marker.close()
	proof.write_receipt("proof_repeat_once", 1, 0 if proof.records[0].passed else 1)
	# Text and native zero intentionally cannot grant a failed second receipt.
	print("FRAMEWORK_REPEAT_ONCE_PASS")
	get_tree().quit(0)
