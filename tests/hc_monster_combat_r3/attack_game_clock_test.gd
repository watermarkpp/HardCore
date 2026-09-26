extends Node

## HC-MONSTER-COMBAT-R3 W1: the attack presentation consumes the OWNER's
## combat game clock. Engine wall clock is not a production combat time
## source: pause freezes the action, a late draw cannot predate the start,
## and the wall-clock seam only remains for unbound preview fixtures.

var _failures: Array[String] = []


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
		printerr("R3_ATTACK_GAME_CLOCK: ", message)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(24), player, false)
	add_child(enemy)
	enemy.set_physics_process(false)
	assert(enemy.combat_enabled, "fixture: identity 24 must be combat enabled")

	# --- Scene A: late draw after a mid-frame start (review example) ---
	# The action starts at game time 0.49 with duration 0.46; the next draw
	# spans a 0.50 delta and lands at game time 0.50. The remaining time must
	# be duration - age(game 0.50 - start 0.49) = 0.45, NOT 0 and NOT 0.46.
	enemy._combat_action_time_s = 0.49
	enemy._play_attack_animation(0.46)
	_expect(
		enemy.visual._combat_clock_s.is_valid(),
		"production presentation must bind the owner combat clock",
	)
	enemy._combat_action_time_s = 0.50
	enemy.visual._advance_action_timers(0.50)
	var remaining_a: float = enemy.visual._attack_remaining
	_expect(
		absf(remaining_a - 0.45) < 0.005,
		"late draw must consume action age only, expected ~0.45 got %.4f" % remaining_a,
	)
	enemy._combat_action_time_s += 0.46
	enemy.visual._advance_action_timers(0.46)
	_expect(
		enemy.visual._attack_remaining <= 0.0,
		"the same action must finish at its own duration",
	)

	# --- Scene B: engine pause freezes the action; wall clock keeps running ---
	# Advance 0.10 of game time, then pause: draw deltas keep arriving but the
	# game clock does not move. The remaining time must stay 0.36 regardless
	# of how many render deltas pass (the wall clock may run seconds ahead).
	var start_game_time: float = enemy._combat_action_time_s
	enemy._play_attack_animation(0.46)
	enemy._combat_action_time_s += 0.10
	enemy.visual._advance_action_timers(0.10)
	var paused_remaining: float = enemy.visual._attack_remaining
	_expect(
		absf(paused_remaining - 0.36) < 0.005,
		"after 0.10s of game time remaining must be ~0.36, got %.4f" % paused_remaining,
	)
	# Engine pause: physics ticks stop; render _process may still run and a
	# long frame delta arrives (wall clock advanced, game clock did not).
	enemy.visual._advance_action_timers(1.00)
	var frozen_remaining: float = enemy.visual._attack_remaining
	_expect(
		absf(frozen_remaining - 0.36) < 0.005,
		"engine pause must freeze the action at ~0.36, got %.4f" % frozen_remaining,
	)
	# Resume: the action continues from ~0.36, it must not restart.
	enemy._combat_action_time_s += 0.02
	enemy.visual._advance_action_timers(0.02)
	_expect(
		absf(enemy.visual._attack_remaining - 0.34) < 0.005,
		"resume must continue the action at ~0.34, got %.4f" % enemy.visual._attack_remaining,
	)

	# --- Scene C: idempotent re-begin of the SAME logical action ---
	var serial_before: int = enemy._attack_logic_serial
	var visual_serial_before: int = enemy.visual._attack_action_serial
	var accepted: bool = enemy.visual.begin_attack_presentation(
		0.46, enemy._attack_logic_serial, -1, Vector2.INF, enemy._attack_action_start_time_s
	)
	_expect(accepted, "idempotent re-begin must be accepted")
	_expect(
		enemy.visual._attack_action_serial == visual_serial_before,
		"idempotent re-begin must not allocate a new visual serial",
	)
	_expect(
		enemy.visual._attack_action_id == enemy._attack_logic_serial,
		"idempotent re-begin must keep the parent action id",
	)

	# --- Scene D: unbound preview fixture keeps the legacy wall-clock seam ---
	var preview_owner := EnemyActor.new()
	var preview := MonsterVisual.new()
	preview.setup(preview_owner)
	preview_owner.visual = preview
	preview_owner.add_child(preview)
	preview._clock_ms = Callable(self, "_preview_clock")
	preview._start_attack_visual(0.30)
	_preview_ms += 100
	preview._advance_action_timers(0.10)
	_expect(
		absf(preview._attack_remaining - 0.20) < 0.005,
		"unbound preview path must still consume the injected seam, got %.4f" % preview._attack_remaining,
	)
	preview.free()
	preview_owner.free()

	enemy.queue_free()
	player.queue_free()
	if _failures.is_empty():
		print("R3_ATTACK_GAME_CLOCK_PASS")
	get_tree().quit(0 if _failures.is_empty() else 1)


var _preview_ms := 0


func _preview_clock() -> int:
	return _preview_ms
