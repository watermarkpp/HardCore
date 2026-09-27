extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# The engine lifetime stays below the explicit 30-second runner budget.
	# Waiting to confirm a completed process must not turn it into a timeout.
	while Time.get_ticks_msec() < 29400:
		await get_tree().process_frame
	print("RUNNER_BEFORE_DEADLINE_PASS engine_ms=", Time.get_ticks_msec())
	get_tree().quit(0)
