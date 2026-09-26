extends Node

## HC-MONSTER-COMBAT-R3 W2 (R3-03): one facing authority per delivery phase.
## While an attack action owns the body, the body row, the swing overlay and
## the combat-facing tracker all share the commit-facing frozen at the commit
## tick. A live target turn during the action must not split them, and the
## freeze must expire with the action's logical window.

var _failures: Array[String] = []

const GroundUnit := preload("res://scripts/ground_unit_space.gd")


func _expect(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
		printerr("R3_ATTACK_FACING_FREEZE: ", message)


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _screen_to_ground(screen_px: Vector2) -> Vector2:
	return GroundUnit.screen_delta_px_to_ground_delta_gu(screen_px)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)

	# --- Scene A: the body row stays on the commit facing mid-action ---
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(76), player, false)
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.facing = Vector2.RIGHT
	enemy._play_attack_animation(0.46)
	enemy.visual._update_animation_frame(0.0)
	var commit_direction: int = enemy.visual.current_direction
	_expect(
		enemy._attack_action_active,
		"the committed action must own the active-action flag",
	)
	_expect(
		is_equal_approx(enemy._attack_action_start_time_s, enemy._combat_action_time_s),
		"the action start must be the combat clock at commit",
	)
	# The actor (target line) turns mid-action.
	enemy.facing = Vector2.DOWN
	enemy.visual._update_animation_frame(0.01)
	_expect(
		enemy.visual.current_state == "attack",
		"fixture: the action must own the body",
	)
	_expect(
		enemy.visual.current_direction == commit_direction,
		"the body row must stay frozen on the commit facing mid-action",
	)
	_expect(
		enemy.visual._attack_facing_at_commit == Vector2.RIGHT,
		"the overlay and the body must share one commit facing",
	)

	# --- Scene B: the freeze expires with the action's logical window ---
	enemy._advance_combat_action_clock(0.50)
	_expect(
		not enemy._attack_action_active,
		"the active-action flag must close on the combat clock",
	)
	enemy.visual._advance_action_timers(0.50)
	enemy.visual._update_animation_frame(0.01)
	_expect(
		enemy.visual.current_state != "attack",
		"fixture: the action must have expired",
	)
	_expect(
		enemy.visual.current_direction == enemy.visual._direction_row(Vector2.DOWN),
		"after the action the body follows the actor facing again",
	)
	enemy.queue_free()

	# --- Scene C: the boss combat-facing tracker keeps live-turning the LOGIC
	# layer while the freeze stays overlay-only (R3 W7 correction of R3-03:
	# "冻结朝向只给 overlay（身体仍读 actor.facing）" - corpse_king_boss_test's
	# "bosses keep facing the player while pursuing/attacking" is the standing
	# authority; the attack ROW stays on the commit facing, the actor.facing
	# property keeps following the target).
	var boss := EnemyActor.new()
	boss.setup(GameData.get_monster_by_id(76), player, false)
	boss.configure_runtime_map_projection(
		9001,
		Callable(self, "_ground_to_screen"),
		Callable(self, "_screen_to_ground")
	)
	boss.global_position = _ground_to_screen(Vector2(16.5, 16.5))
	add_child(boss)
	boss.set_physics_process(false)
	player.global_position = _ground_to_screen(Vector2(16.5, 18.5))
	boss.target = player
	boss.facing = Vector2.RIGHT
	boss._attack_action_active = true
	boss._hc_finalize_boss_facing()
	_expect(
		boss.facing != Vector2.RIGHT,
		"the boss combat-facing tracker keeps live-turning the logic layer even mid-action",
	)
	boss._attack_action_active = false
	boss._hc_finalize_boss_facing()
	_expect(
		boss.facing != Vector2.RIGHT,
		"outside the action window the tracker still follows the target",
	)
	boss.queue_free()
	player.queue_free()

	if _failures.is_empty():
		print("R3_ATTACK_FACING_FREEZE_PASS")
	get_tree().quit(0 if _failures.is_empty() else 1)
