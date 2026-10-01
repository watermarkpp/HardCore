extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
func _ready() -> void:
	PlayerState.test_mode = true
	var proof := Proof.new()
	# Exact unused test-owned probe only. The controller restores its original
	# bytes after the fingerprint wrapper records this deliberate mismatch.
	var marker := FileAccess.open("res://tests/framework/fixtures/source_mutation_marker.gd", FileAccess.READ_WRITE)
	proof.record(marker != null, "exact test-owned source probe opens")
	if marker != null:
		marker.seek_end()
		marker.store_string("\n# FRAMEWORK_SOURCE_MUTATED\n")
		marker.close()
	var valid := proof.write_receipt("proof_source_changed", 1, 0)
	print("FRAMEWORK_SOURCE_CHANGED_PASS checks=1" if valid else "FRAMEWORK_SOURCE_CHANGED_FAIL")
	get_tree().quit(0 if valid else 1)
