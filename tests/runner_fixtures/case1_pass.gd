extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("Q0A_SELF_CASE1_PASS")
	get_tree().quit(0)
