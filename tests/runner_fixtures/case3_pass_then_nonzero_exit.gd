extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("Q0A_SELF_CASE3_PASS")
	await get_tree().process_frame
	get_tree().quit(7)
