extends Node

## HC-MONSTER-COMBAT-R2 T3 (R2-02) logic-clock counterexample, written only
## against the version-stable direct primitive so it parses AND runs on both
## the R1 and the R2 code: start a fresh 0.46 s attack via
## `_start_attack_visual`, then advance one 0.50 s render delta that SPANS the
## attack start (the review's case: previous draw t=0, attack starts t=0.49,
## next draw t=0.50). The R1 render-delta countdown zeroed the fresh attack
## although it had aged only ~0.01 s; the R2 logic clock keeps ~0.45 s.


func _make_enemy() -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.monster_id = 24
	enemy.monster_data = {"monster_id": 24}
	enemy.display_name = "测试占位怪"
	var visual := MonsterVisual.new()
	visual.setup(enemy)
	enemy.visual = visual
	return enemy


func _ready() -> void:
	var enemy := _make_enemy()
	var visual: MonsterVisual = enemy.visual
	visual._start_attack_visual(0.46)
	assert(visual._attack_remaining > 0.40, "fixture: the fresh attack owns its duration")
	visual._advance_action_timers(0.50)
	assert(
		visual._attack_remaining > 0.40,
		(
			"one spanning render delta must not consume a fresh attack's whole "
			+ "duration (aged ~0.01 s of 0.46 s; got %f)"
		)
			% visual._attack_remaining
	)
	enemy.free()
	print("HC_MCR2_ATTACK_CLOCK_PASS")
	get_tree().quit()
