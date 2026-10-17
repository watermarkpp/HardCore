extends "res://tests/framework/persistent_profile_process_20261015.gd"
## Same actual Native S/writer fixture; tests a real Main refusal at live exit.
func _init() -> void:
	reject_main_after_completed_writer = true
