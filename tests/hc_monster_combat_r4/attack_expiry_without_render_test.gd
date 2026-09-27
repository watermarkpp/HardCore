extends Node

## REVIEW FIXTURE ONLY. Authored for the pinned R3 source; Godot NOT_RUN here.
## An expired action cannot expose an active identity/strike phase merely
## because the rendering process has not refreshed its cached remaining time.

class AudioProbeEnemy:
	extends EnemyActor
	var emitted: Array[String] = []
	func _emit_monster_audio(event: String, _allow_death := false, _overrides: Dictionary = {}) -> bool:
		emitted.append(event)
		return true

func _ready() -> void:
	var enemy := AudioProbeEnemy.new()
	# Keep the test independent from assets: this exercises the real owner /
	# MonsterVisual clock and observer, not a map or animation-load fixture.
	enemy.combat_enabled = true
	var visual := MonsterVisual.new()
	visual.setup(enemy)
	enemy.visual = visual
	enemy.add_child(visual)
	enemy._play_attack_animation(0.46)
	var serial: int = enemy._attack_logic_serial
	assert(serial > 0)
	enemy._advance_combat_action_clock(0.60)
	# Deliberately do NOT call visual._advance_action_timers(): several physics
	# steps may occur before the next drawing update. Reads must be logical.
	var exposed_id: int = visual.current_attack_action_id()
	var phase_reached: bool = visual.attack_frame_phase_reached()
	enemy._audio_observe_visual_state()
	var strike_count := enemy.emitted.count("attack_frame")
	enemy.free()
	if exposed_id != -1 or phase_reached or strike_count != 0:
		printerr("R4_ATTACK_EXPIRY: expired action id=%d phase=%s strike_count=%d" % [exposed_id, phase_reached, strike_count])
		get_tree().quit(1)
		return
	print("R4_ATTACK_EXPIRY_WITHOUT_RENDER_PASS")
	get_tree().quit(0)
