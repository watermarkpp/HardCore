extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("Q0A_SELF_CASE4_PASS")
	# Intentionally never quit: the runner must time out and FAIL despite PASS.
	while true:
		await get_tree().process_frame
