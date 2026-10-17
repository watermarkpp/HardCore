extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")

func _ready() -> void:
	var proof := Proof.new()
	var port: RefCounted = PlayerState._model._runtime_port
	for initial_seed: int in [1, 987654321, 9223372036854775807]:
		seed(initial_seed)
		var expected := [randi(), randi_range(1000, 9999), randi()]
		seed(initial_seed)
		var actual := [port.global_randi(), port.global_randi_range(1000, 9999), randi()]
		proof.record(actual == expected, "same global stream and next draw seed=" + str(initial_seed))
	var valid: bool = proof.write_receipt("profile_global_rng_continuity_20261014", proof.records.size(), 0)
	print("PROFILE_GLOBAL_RNG_CONTINUITY_20261014_", "PASS" if valid else "FAIL")
	get_tree().quit(0 if valid else 1)
