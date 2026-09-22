extends Node

## AIA-2-R1 real-game ordinary-attack release regressions (README 7.7 rows).
## One script, three runner entries selected by `scenario`:
##   taps          - rapid taps during cooldown, release, observe >= 12 s
##   kill_release  - single hold kills a monster through the real damage
##                   pipeline, release, observe >= 12 s
##   kill_retarget - monster dies while still holding with a live neighbour
##                   nearby, hold keeps attacking it, release, observe >= 12 s
## Action starts are judged by PlayerCharacter._combat_action_sequence, never
## by queue length. No engine timers, cooldowns, damage or input gates are
## modified; the scene runs the real mapped world and real melee pipeline.

const Fixture := preload("res://tests/helpers/formal_world_skill_fixture.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

const OBSERVE_FRAMES := 720  # 12 s at the default 60 Hz physics tick
const MONSTER_ID := 43  # canonical test monster used by mobile_targeting_test

@export var scenario: String = "taps"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	match scenario:
		"taps":
			await _run_taps(game)
		"kill_release":
			await _run_kill_release(game)
		"kill_retarget":
			await _run_kill_retarget(game)
		_:
			assert(false, "unknown scenario: %s" % scenario)
	get_tree().quit(0)


## Scenario A: rapid taps land while the first swing is busy. Busy taps are
## dropped, never queued; after the final release no attack action may start
## for at least 12 s while the already-started swing finishes naturally.
func _run_taps(game: Node) -> void:
	var target: EnemyActor = await Fixture.prepare_target(
		self, game, game.player, MONSTER_ID, "aia2_taps"
	)
	assert(target.current_hp > 0, "taps fixture target must be alive")
	var sequence_base: int = game.player._combat_action_sequence
	_tap(game)
	await get_tree().process_frame
	assert(
		game.player._combat_action_sequence == sequence_base + 1,
		"首次点按没有立即开始一次普通攻击动作"
	)
	for _tap_index in range(6):
		_tap(game)
	assert(game._queued_mobile_attacks == 0, "忙时快速点按不得排队积欠")
	assert(game._active_mobile_attack_tokens.is_empty(), "快速点按后不得残留按住归属")
	assert(
		game.player._combat_action_sequence == sequence_base + 1,
		"冷却内的快速点按不得新开普通攻击动作"
	)
	var sequence_after_taps: int = game.player._combat_action_sequence
	await _wait_physics_frames(OBSERVE_FRAMES)
	assert(
		game.player._combat_action_sequence == sequence_after_taps,
		"快速点按松手后12秒内新开了普通攻击动作"
	)
	assert(game.player._attack_action_timer == 0.0, "已开始的一刀没有自然收尾")
	assert(game.player._attack_timer == 0.0, "冷却没有自然走完")
	print(
		"AIA2_TAPS_RELEASE_PASS sequence=", game.player._combat_action_sequence,
		" observed_seconds=", OBSERVE_FRAMES / 60.0
	)


## Scenario B: one continuous hold kills the monster through the real windup
## and melee damage pipeline. While still holding, the frame loop must keep
## starting swings (open-field swing semantics stay intact). After release,
## no attack action may start for at least 12 s.
func _run_kill_release(game: Node) -> void:
	var target: EnemyActor = await Fixture.prepare_target(
		self, game, game.player, MONSTER_ID, "aia2_kill"
	)
	target.max_hp = 1
	target.current_hp = 1
	var sequence_base: int = game.player._combat_action_sequence
	_press(game)
	assert(
		game.player._combat_action_sequence == sequence_base + 1,
		"长按首刀没有立即开始普通攻击动作"
	)
	var killed := await _wait_for_kill(game, target, 120)
	assert(killed, "长按首刀没有通过真实伤害管线击杀怪物")
	var sequence_at_kill: int = game.player._combat_action_sequence
	var continued := await _wait_for_sequence(game, sequence_at_kill + 1, 150)
	assert(continued, "怪死后仍按住时帧循环没有继续攻击（被错误断开）")
	_release(game)
	var sequence_after_release: int = game.player._combat_action_sequence
	await _wait_physics_frames(OBSERVE_FRAMES)
	assert(
		game.player._combat_action_sequence == sequence_after_release,
		"击杀后松手12秒内新开了普通攻击动作"
	)
	assert(game.player._attack_action_timer == 0.0, "松手后已开始的动作没有自然收尾")
	print(
		"AIA2_HOLD_KILL_RELEASE_PASS sequence=", game.player._combat_action_sequence,
		" observed_seconds=", OBSERVE_FRAMES / 60.0
	)


## Scenario C: the monster dies while the pointer is still genuinely held and
## a second live monster stands nearby. Holding must keep attacking and lock a
## legal live target; a later release must stop new actions for >= 12 s.
func _run_kill_retarget(game: Node) -> void:
	var first_target: EnemyActor = await Fixture.prepare_target(
		self, game, game.player, MONSTER_ID, "aia2_retarget_a"
	)
	first_target.max_hp = 1
	first_target.current_hp = 1
	var neighbour_ground: Vector2 = Fixture.FIXTURE_GROUND_POSITION + Vector2(4.0, 0.0)
	var neighbour: EnemyActor = game._spawn_enemy(
		GameData.get_monster_by_id(MONSTER_ID),
		game._canonical_ground_gu_to_screen_px(neighbour_ground),
		false,
		-1.0,
		{"respawn_enabled": false, "spawn_slot_id": "test:aia2_retarget_b"},
	)
	assert(neighbour != null, "邻居活怪夹具必须通过正式刷新事务生成")
	neighbour.max_hp = 9999
	neighbour.current_hp = 9999
	neighbour.control_time = 60.0
	neighbour.set_physics_process(false)
	await get_tree().process_frame
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			neighbour_ground, game._active_safe_zones
		),
		"邻居活怪夹具不得落在安全区内"
	)
	assert(
		game._combat_target_world_clear(neighbour, game.player.global_position, true),
		"邻居活怪与角色之间必须存在合法WORLD路径"
	)
	var sequence_base: int = game.player._combat_action_sequence
	_press(game)
	assert(
		game.player._combat_action_sequence == sequence_base + 1,
		"长按首刀没有立即开始普通攻击动作"
	)
	var killed := await _wait_for_kill(game, first_target, 120)
	assert(killed, "长按首刀没有通过真实伤害管线击杀怪物")
	var sequence_at_kill: int = game.player._combat_action_sequence
	var continued := await _wait_for_sequence(game, sequence_at_kill + 1, 150)
	assert(continued, "怪死后仍按住时帧循环没有继续攻击")
	assert(
		is_instance_valid(game.locked_target) and game.locked_target.current_hp > 0,
		"怪死后持续按住没有锁到合法活目标"
	)
	assert(game.locked_target == neighbour, "自动选敌没有选中旁边的合法活怪")
	_release(game)
	var sequence_after_release: int = game.player._combat_action_sequence
	await _wait_physics_frames(OBSERVE_FRAMES)
	assert(
		game.player._combat_action_sequence == sequence_after_release,
		"换目标场景松手后12秒内新开了普通攻击动作"
	)
	assert(game.player._attack_action_timer == 0.0, "松手后已开始的动作没有自然收尾")
	assert(neighbour.current_hp > 0, "邻居活怪在观察期内意外死亡")
	print(
		"AIA2_HOLD_KILL_RETARGET_PASS sequence=", game.player._combat_action_sequence,
		" observed_seconds=", OBSERVE_FRAMES / 60.0
	)


## One physical tap: real ScreenTouch press+release through the button's
## _gui_input, so button and root ledgers both run the production path.
func _tap(game: Node, index: int = 1) -> void:
	_press(game, index)
	_release(game, index)


func _press(game: Node, index: int = 1) -> void:
	var press := InputEventScreenTouch.new()
	press.index = index
	press.pressed = true
	press.position = (game.hud.attack_button as Control).size * 0.5
	(game.hud.attack_button as Control)._gui_input(press)


func _release(game: Node, index: int = 1) -> void:
	var release := InputEventScreenTouch.new()
	release.index = index
	release.pressed = false
	release.position = (game.hud.attack_button as Control).size * 0.5
	(game.hud.attack_button as Control)._gui_input(release)


func _wait_physics_frames(frames: int) -> void:
	for _frame in range(frames):
		await get_tree().physics_frame


func _wait_for_sequence(game: Node, target_sequence: int, max_frames: int) -> bool:
	for _frame in range(max_frames):
		await get_tree().physics_frame
		if game.player._combat_action_sequence >= target_sequence:
			return true
	return false


func _wait_for_kill(game: Node, target: EnemyActor, max_frames: int) -> bool:
	for _frame in range(max_frames):
		await get_tree().physics_frame
		if not is_instance_valid(target) or target.current_hp <= 0:
			return true
	return false
