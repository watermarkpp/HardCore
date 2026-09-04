extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_tree().quit(0)
