extends "res://tests/device_lab_runtime_test.gd"


# Reuse the existing Device Lab layout assertions unchanged. This entry covers
# only layout guards/competing application/real panel checkpoint rollback;
# it does not claim the unrelated legacy character roster fixture passes.
func _run() -> void:
	await _test_external_profile_guards()
	await _test_transaction_rollback()
	await _test_ui_checkpoint_rollback()
	print("DEVICE_LAB_LAYOUT_REGRESSION_PASS external_guards competing_transaction checkpoint_rollback")
	get_tree().quit(0)
