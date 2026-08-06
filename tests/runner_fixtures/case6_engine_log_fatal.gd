extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("Q0A_SELF_CASE6_PASS")
	push_error("Q0A_SELF_CASE6_ENGINE_LOG_FATAL")
	await get_tree().process_frame
	get_tree().quit(0)
