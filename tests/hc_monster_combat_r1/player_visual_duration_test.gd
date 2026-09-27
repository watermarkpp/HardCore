extends Node

## HC-MONSTER-COMBAT-R1 Task 1 (F04) counterexample.
## A new player action must own its own duration; it must not inherit the
## maximum duration of any historical action (e.g. a finished 0.8s death).
const VisualScript = preload("res://scripts/player_visual.gd")


func _ready() -> void:
	var visual: Node2D = VisualScript.new()
	visual._action_name = "idle"
	visual._action_remaining = 0.0
	visual._action_duration = 0.8  # A finished long action left this behind.
	visual.play_action("attack", 0.51)
	assert(
		is_equal_approx(visual._action_remaining, 0.51),
		"A new action must own its remaining clock"
	)
	assert(
		is_equal_approx(visual._action_duration, 0.51),
		"A new action must not inherit historical maximum duration"
	)
	visual.free()
	print("HC_MCR1_PLAYER_VISUAL_DURATION_PASS")
	get_tree().quit()
