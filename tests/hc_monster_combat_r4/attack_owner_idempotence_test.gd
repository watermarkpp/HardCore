extends Node

## REVIEW FIXTURE ONLY. Godot NOT_RUN here. Repeating the SAME owner-side
## presentation request must neither resubmit start audio nor re-arm a phase.

class AudioProbeEnemy:
	extends EnemyActor
	var emitted: Array[String] = []
	func _emit_monster_audio(event: String, _allow_death := false, _overrides: Dictionary = {}) -> bool:
		emitted.append(event)
		return true

func _ready() -> void:
	var enemy := AudioProbeEnemy.new()
	enemy.combat_enabled = true
	var visual := MonsterVisual.new()
	visual.setup(enemy)
	enemy.visual = visual
	enemy.add_child(visual)
	enemy._play_attack_animation(0.46)
	var serial: int = enemy._attack_logic_serial
	# Observe one legitimate phase within the clip before retrying the same ID.
	enemy._advance_combat_action_clock(0.30)
	enemy._audio_observe_visual_state()
	var count_before := enemy.emitted.size()
	var age_before: float = visual.attack_action_age_seconds()
	enemy._play_attack_animation(0.46, serial)
	enemy._audio_observe_visual_state()
	var count_after := enemy.emitted.size()
	var same_serial := enemy._attack_logic_serial == serial
	var same_age := is_equal_approx(visual.attack_action_age_seconds(), age_before)
	var messages := enemy.emitted.duplicate()
	enemy.free()
	if count_before < 2 or count_after != count_before or not same_serial or not same_age:
		printerr("R4_OWNER_IDEMPOTENCE: before=%d after=%d serial_ok=%s age_ok=%s events=%s" % [count_before, count_after, same_serial, same_age, messages])
		get_tree().quit(1)
		return
	print("R4_ATTACK_OWNER_IDEMPOTENCE_PASS")
	get_tree().quit(0)
