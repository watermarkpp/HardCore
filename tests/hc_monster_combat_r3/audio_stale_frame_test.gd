extends Node

# NOT_RUN by the reviewer. A focused stale-frame counterexample, not an
# end-to-end audio test. No audio service is required: R2 consumes the wrong
# phase before attempting delivery to the service.
func _ready() -> void:
	var enemy := EnemyActor.new()
	var visual := MonsterVisual.new()
	visual.setup(enemy)
	enemy.visual = visual
	enemy.add_child(visual) # Attach ownership even though neither enters the tree.
	# Last DRAW belonged to A. B starts between renders; R2 does not clear the
	# old current_state/current_frame on begin_attack_presentation.
	visual.current_state = "attack"
	visual.current_frame = 4
	visual.begin_attack_presentation(0.46, 2, 1000, Vector2.RIGHT)
	enemy.combat_enabled = true
	enemy._audio_attack_sequence = 2
	enemy._audio_attack_start_accepted = true
	enemy._audio_attack_frame_sequence = -1
	enemy._audio_attack_frame_ready = false
	enemy._audio_attack_presented_seen = false
	enemy._audio_observe_visual_state()
	var consumed_fresh_b_from_old_a := enemy._audio_attack_frame_sequence == 2
	enemy.free()
	if consumed_fresh_b_from_old_a:
		printerr("R3_AUDIO_STALE_FRAME: B consumed attack_frame from A before B advanced")
	else:
		print("HC_MCR3_AUDIO_STALE_FRAME_PASS")
	get_tree().quit(1 if consumed_fresh_b_from_old_a else 0)
