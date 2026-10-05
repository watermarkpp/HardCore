extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("RUNNER_AFTER_DEADLINE_PASS")
	# A marker cannot authorize additional engine execution past 30 seconds.
	while Time.get_ticks_msec() < 30600:
		await get_tree().process_frame
	get_tree().quit(0)
