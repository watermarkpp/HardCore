extends Node

## HC-MONSTER-COMBAT-R1 Task 1 (F01) counterexamples.
## A production attack transaction enters through EnemyActor._play_attack_animation().
## Under the old strict presentation FIFO the attack could be queued behind a
## struck backlog or silently dropped on overflow while the attack sound and
## damage still executed. The critical arbitration contract
## (hardcore.monster.combat_presentation.r1) requires the attack presentation
## to start at its logic moment and never be dropped by struck backlog.


func _make_enemy() -> EnemyActor:
	# Procedural-fallback actor (no authored art needed) with a real MonsterVisual.
	var enemy := EnemyActor.new()
	enemy.monster_id = 24
	enemy.monster_data = {"monster_id": 24}
	enemy.display_name = "测试占位怪"
	var visual := MonsterVisual.new()
	visual.setup(enemy)
	enemy.visual = visual
	return enemy


func _ready() -> void:
	# Scenario 1: a playing struck must yield to the critical attack.
	var s1 := _make_enemy()
	s1.visual._hit_remaining = 0.2
	s1._play_attack_animation(0.46)
	assert(
		s1.visual._attack_remaining > 0.0,
		"F01: a critical attack must start instead of queueing behind a struck"
	)
	s1.free()

	# Scenario 2: a full presentation backlog must not silently drop the attack.
	var s2 := _make_enemy()
	for i in MonsterVisual.PRESENTATION_QUEUE_CAPACITY:
		s2.visual.queue_struck(50)
	assert(
		s2.visual._presentation_count == MonsterVisual.PRESENTATION_QUEUE_CAPACITY,
		"fixture: backlog is full"
	)
	s2._play_attack_animation(0.46)
	assert(
		s2.visual._attack_remaining > 0.0,
		"F01: queue overflow must not drop a critical attack (sound and damage ran without a body)"
	)
	# The struck backlog collapses into bounded feedback (at most one item).
	assert(
		s2.visual._presentation_count <= 1,
		"F01: waiting pure struck feedback must merge into bounded feedback"
	)
	s2.free()

	# Scenario 3 (frozen rule): death still suppresses attack presentations.
	var s3 := _make_enemy()
	s3.visual._death_remaining = 1.0
	s3._play_attack_animation(0.46)
	assert(
		s3.visual._attack_remaining == 0.0,
		"death must keep suppressing attack presentations"
	)
	s3.free()
	print("HC_MCR1_ATTACK_PRESENTATION_BACKLOG_PASS")
	get_tree().quit()
