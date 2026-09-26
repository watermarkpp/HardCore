extends Node

## HC-MONSTER-COMBAT-R2 T1 (R2-05): the three large named/boss identities
## verified by the review (238, 239 and 76) must sustain 20 consecutive
## attack starts: every swing binds the next parent-action serial, every
## presentation starts, and the presentation ring drains back to empty
## between swings (no backlog growth, no dropped swings).


const LARGE_IDS: Array = [238, 239, 76]
const SWINGS_PER_ID := 20


var _fake_ms := 0


func _clock() -> int:
	return _fake_ms


func _ready() -> void:
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)

	for monster_id: int in LARGE_IDS:
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(monster_id), player, false)
		enemy.global_position = Vector2.ZERO
		enemy.set_meta("spawn_position", Vector2.ZERO)
		enemy.set_meta("safe_zones", [])
		add_child(enemy)
		enemy.set_physics_process(false)
		# The R2 logic clock consumes the action's own age against the injected
		# monotonic clock; the test advances the clock between swings.
		enemy.visual._clock_ms = Callable(self, "_clock")
		assert(
			enemy.combat_enabled and not enemy.has_meta("body_policy_rejected"),
			"fixture: large identity %d must be body-accepted" % monster_id
		)
		var first_serial: int = enemy._attack_logic_serial
		for swing in SWINGS_PER_ID:
			enemy._play_attack_animation(0.46)
			assert(
				enemy.visual._attack_remaining > 0.0,
				"large identity %d swing %d must present" % [monster_id, swing]
			)
			assert(
				enemy._attack_logic_serial == first_serial + swing + 1,
				"large identity %d swing %d must bind the next serial"
					% [monster_id, swing]
			)
			assert(
				enemy._audio_attack_sequence == enemy._attack_logic_serial,
				"large identity %d swing %d must bind the audio stream"
					% [monster_id, swing]
			)
			_fake_ms += 500
			enemy.visual._advance_action_timers(0.5)
			assert(
				enemy.visual._attack_remaining == 0.0,
				"large identity %d swing %d must finish before the next swing"
					% [monster_id, swing]
			)
			assert(
				enemy.visual._presentation_count == 0,
				"large identity %d must not grow a presentation backlog" % monster_id
			)
		enemy.queue_free()

	player.queue_free()
	print("HC_MCR2_LARGE_BODY_SWINGS_PASS")
	get_tree().quit()
