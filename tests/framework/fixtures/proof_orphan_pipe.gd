extends Node
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

func _ready() -> void:
	PlayerState.test_mode = true
	var proof := Proof.new()
	# Real bounded child: it survives a successful engine exit and inherits pipes.
	# Forty seconds self-terminates even when the deliberately broken runner fails.
	var child := OS.create_process("/bin/sh", ["-c", "sleep 40 & wait"])
	proof.record(child > 0, "real owned subprocess started")
	proof.write_receipt("proof_orphan_pipe", 1, 0 if child > 0 else 1)
	print("FRAMEWORK_ORPHAN_PIPE_PASS child=%d" % child)
	get_tree().quit(0)
