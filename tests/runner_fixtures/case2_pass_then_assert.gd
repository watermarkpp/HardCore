extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("Q0A_SELF_CASE2_PASS")
	await get_tree().process_frame
	assert(false, "Q0A_SELF_CASE2 forced assertion failure")
