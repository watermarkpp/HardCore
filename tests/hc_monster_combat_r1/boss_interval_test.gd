extends Node

## HC-MONSTER-COMBAT-R1 Task 1 (F02) counterexamples.
## A boss without an explicit boss_rule must not inherit hidden legacy
## timing (1.15s / 0.78s) or implicit skill/phase capabilities.
const EnemyScript = preload("res://scripts/enemy.gd")


func _ready() -> void:
	var enemy := EnemyScript.new()
	enemy.is_boss = true
	enemy.boss_rule = {}
	enemy._boss_phase_two = false
	enemy._attack_interval = 1.5
	assert(
		is_equal_approx(enemy._current_attack_interval(), 1.5),
		"Missing boss rule must not replace the configured base interval"
	)
	enemy._boss_phase_two = true
	assert(
		is_equal_approx(enemy._current_attack_interval(), 1.5),
		"Missing boss rule must not apply a hidden phase-two interval"
	)
	assert(
		enemy._boss_skill_enabled == false,
		"Boss skill capability must default to off without an explicit rule"
	)
	assert(
		enemy._boss_phase_enabled == false,
		"Boss phase mechanics must default to off without an explicit rule"
	)
	enemy.free()
	print("HC_MCR1_BOSS_INTERVAL_PASS")
	get_tree().quit()
