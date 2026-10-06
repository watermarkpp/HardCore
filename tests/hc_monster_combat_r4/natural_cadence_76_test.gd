extends "res://tests/hc_monster_combat_r4/natural_cadence_base.gd"


func _init() -> void:
	monster_id_under_test = 76
	# Identity 76's real cadence is ~2.5s per full start->settlement cycle,
	# so the default 48s sample budget finishes 19 of the required 20 cycles
	# and the deadline cuts the twentieth. Same approved-90s treatment as
	# identity 24 (runner allowlist already contains this scene); the
	# expected start/settlement counts stay at 20.
	approved_process_window_seconds = 90
