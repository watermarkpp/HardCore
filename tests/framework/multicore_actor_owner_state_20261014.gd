extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const ENEMY_PATH := "res://scripts/gameplay/actors/enemy_combat_action_state.gd"
const PLAYER_PATH := "res://scripts/gameplay/actors/player_combat_action_state.gd"
var proof := Proof.new()
var errors: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(FileAccess.file_exists(ENEMY_PATH), "enemy owner action state exists outside Node")
	check(FileAccess.file_exists(PLAYER_PATH), "player accepted action state exists outside Node")
	if not FileAccess.file_exists(ENEMY_PATH) or not FileAccess.file_exists(PLAYER_PATH):
		_finish()
		return
	var enemy: Object = load(ENEMY_PATH).new()
	check(not enemy is Node and not enemy.timeline is Node, "enemy action owner and timeline require no SceneTree")
	enemy.time_s = 0.50
	check(enemy.allocate_attack(0.46, 3, 8, 1234) == 1, "attack allocates original monotonic serial")
	check(enemy.action_start_time_s == 0.5 and enemy.action_duration_s == 0.46 and enemy.action_source_life == 3 and enemy.action_generation == 8 and enemy.logic_started_at_ms == 1234, "attack freezes original life generation and diagnostic wall stamp")
	check(not enemy.advance_clock(0.45) and enemy.action_active, "owner clock does not close before logical end")
	check(enemy.advance_clock(0.02) and not enemy.action_active, "crossing end closes once and returns completion effect")
	check(not enemy.advance_clock(0.10), "completed action cannot emit completion twice")
	enemy.struck_paused_time_s = 0.125
	check(enemy.movement_time_ms() == int(maxf(0.0, enemy.time_s - 0.125) * 1000.0), "movement projection excludes only actual struck time")
	enemy.struck_paused_time_s = 99.0
	check(enemy.movement_time_ms() == 0, "movement projection retains original zero floor")

	var player: Object = load(PLAYER_PATH).new()
	check(not player is Node, "player action rule instance has no Node")
	var action: int = player.begin_action("skill", 41)
	check(action == 1 and player.pending_action_epoch == 41 and player.pending_action_active and not player.pending_action_committed, "accepted action captures epoch before release")
	check(not player.commit_action(action + 1, false) and not player.commit_action(action, true), "foreign or dead release cannot commit")
	player.action_timer = 0.05
	player.queued_struck_reaction = true
	player.advance_before_reaction(0.10)
	check(player.pending_action_active and not player.queued_reaction_ready(), "uncommitted accepted release survives expired body timer")
	check(player.commit_action(action, false), "accepted release commits once live")
	player.advance_before_reaction(0.0)
	check(not player.pending_action_active and player.queued_reaction_ready(), "committed expired action finishes before queued struck admission")
	player.start_queued_struck_reaction(0.20)
	player.attack_timer = 1.0
	player.skill_cooldowns["skill"] = 1.0
	player.advance_cooldowns(0.10, true)
	check(is_equal_approx(player.attack_timer, 0.90) and is_equal_approx(player.struck_cooldown_pause_remaining, 0.20), "newly started reaction does not retroactively pause current cooldown interval")
	player.advance_cooldowns(0.30, false)
	check(is_equal_approx(player.attack_timer, 0.80) and is_equal_approx(float(player.skill_cooldowns.skill), 0.80) and player.struck_cooldown_pause_remaining == 0.0, "existing hit pauses exact authored portion and spends remaining cooldown time")
	player.skill_cooldowns["expired"] = 0.001
	player.advance_cooldowns(0.002, false)
	check(not player.skill_cooldowns.has("expired") and player.skill_cooldown_remaining_ms("missing") == 0, "expired cooldowns erase and missing cooldown remains zero")
	player.struck_protection_remaining = 0.0000005
	player.advance_before_reaction(0.0)
	check(player.struck_protection_remaining == 0.0, "original exact-boundary tolerance is preserved")
	var frozen: Dictionary = player.action_snapshot()
	player.begin_action("attack", 42)
	player.finish_action(action)
	check(player.pending_action_active and int(frozen.action_id) == action and int(frozen.epoch) == 41, "stale finish cannot retire newer action and snapshot preserves original values")
	_finish()

func _finish() -> void:
	proof.write_receipt("multicore_actor_owner_state_20261014", proof.records.size(), errors.size())
	if errors.is_empty():
		print("MULTICORE_ACTOR_OWNER_STATE_20261014_PASS")
	else:
		for message: String in errors:
			printerr(message)
	get_tree().quit(0 if errors.is_empty() else 1)
