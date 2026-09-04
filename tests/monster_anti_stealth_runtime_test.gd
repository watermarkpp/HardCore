extends Node2D

## The 21CQ detail attribute "反隐身" is a live monster perception rule.
## This test drives the production EnemyActor physics path with canonical IDs:
## ID 38 (半兽勇士, anti_stealth=true) and ID 64 (沃玛战士,
## anti_stealth=false).  It intentionally uses the same PlayerCharacter and
## the same distance for both actors so the only changed input is the
## canonical anti-stealth projection.

const EnemyActorScript := preload("res://scripts/enemy.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const ANTI_STEALTH_MONSTER_ID := 38
const NORMAL_MONSTER_ID := 64
const TEST_DISTANCE_GU := 4.0
const STEALTH_SUPPRESSION_DISTANCE_GU := 35.0 / 32.0
const POSITION_EPSILON_PX := 0.001
const MOVEMENT_DELTA_EPSILON_GU := 0.000001


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = false
	PlayerState.reset_progress()

	var player := PlayerCharacter.new()
	player.name = "AntiStealthRuntimePlayer"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	add_child(player)
	await get_tree().process_frame
	player.max_hp = 1000
	player.current_hp = player.max_hp
	player.defense_min = 0
	player.defense_max = 0

	var enemy_start := Vector2.ZERO
	var target_position := GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
		Vector2(TEST_DISTANCE_GU, 0.0)
	)
	player.global_position = target_position
	player.apply_stealth(60.0)
	assert(player.is_stealthed(), "test target must be stealth-visible to EnemyActor")
	assert(
		TEST_DISTANCE_GU > STEALTH_SUPPRESSION_DISTANCE_GU,
		"test distance must remain in the existing stealth suppression range",
	)

	# Same hidden target and same distance: an ordinary monster must remain in
	# the existing suppression branch, without starting a pursuit step or
	# dealing damage.
	var ordinary := await _make_enemy(NORMAL_MONSTER_ID, player, enemy_start)
	var ordinary_hp_before := player.current_hp
	_force_cadence_ready(ordinary)
	ordinary._physics_process(1.0 / 60.0)
	assert(not ordinary.anti_stealth, "ID 64 canonical projection unexpectedly has anti-stealth")
	assert(ordinary.target == player, "ordinary monster lost its canonical target")
	assert(
		ordinary.global_position.distance_to(enemy_start) <= POSITION_EPSILON_PX,
		"ordinary monster tracked a hidden target outside the existing stealth threshold",
	)
	assert(
		not ordinary._movement_step_active,
		"ordinary monster opened a pursuit step through stealth suppression",
	)
	assert(ordinary.velocity == Vector2.ZERO, "ordinary monster did not stop for stealth")
	assert(
		ordinary.actual_ground_motion_gu.length() <= MOVEMENT_DELTA_EPSILON_GU,
		"ordinary monster reported movement while stealth-suppressed",
	)
	assert(player.current_hp == ordinary_hp_before, "ordinary monster damaged a hidden target from suppression range")
	ordinary.queue_free()
	await get_tree().process_frame

	# The same hidden target at the same distance must remain actionable for a
	# canonical anti-stealth monster.  Force only the existing cadence clock
	# ready; the actor still enters _physics_process, requests a normal pursuit
	# step, and advances it through the production movement executor.
	var anti_stealth := await _make_enemy(ANTI_STEALTH_MONSTER_ID, player, enemy_start)
	var anti_hp_before := player.current_hp
	_force_cadence_ready(anti_stealth)
	anti_stealth._physics_process(1.0 / 60.0)
	assert(anti_stealth.anti_stealth, "ID 38 canonical projection lost anti-stealth")
	assert(anti_stealth.target == player, "anti-stealth monster lost its canonical target")
	assert(
		anti_stealth.global_position.distance_to(enemy_start) > POSITION_EPSILON_PX,
		"anti-stealth monster did not continue along the production pursuit path",
	)
	assert(
		anti_stealth._movement_step_active,
		"anti-stealth monster did not retain its active production pursuit step",
	)
	assert(
		anti_stealth.actual_ground_motion_gu.length() > MOVEMENT_DELTA_EPSILON_GU,
		"anti-stealth monster produced no observable tracking movement",
	)
	assert(
		player.current_hp == anti_hp_before,
		"anti-stealth tracking unexpectedly changed the target HP before engagement",
	)
	anti_stealth.queue_free()
	await get_tree().process_frame

	# With stealth removed, both canonical actors must use the same ordinary
	# target/engagement path and continue tracking from this same distance.
	player.stealth_time = 0.0
	player.break_stealth()
	assert(not player.is_stealthed(), "non-stealth control target is still hidden")

	var ordinary_visible := await _make_enemy(NORMAL_MONSTER_ID, player, enemy_start)
	_force_cadence_ready(ordinary_visible)
	ordinary_visible._physics_process(1.0 / 60.0)
	assert(
		ordinary_visible.global_position.distance_to(enemy_start) > POSITION_EPSILON_PX,
		"ordinary monster did not pursue the visible target",
	)
	assert(
		ordinary_visible._movement_step_active,
		"ordinary monster visible-target path did not start the production pursuit step",
	)
	ordinary_visible.queue_free()
	await get_tree().process_frame

	var anti_visible := await _make_enemy(ANTI_STEALTH_MONSTER_ID, player, enemy_start)
	_force_cadence_ready(anti_visible)
	anti_visible._physics_process(1.0 / 60.0)
	assert(
		anti_visible.global_position.distance_to(enemy_start) > POSITION_EPSILON_PX,
		"anti-stealth monster did not pursue the visible target",
	)
	assert(
		anti_visible._movement_step_active,
		"anti-stealth visible-target path did not start the production pursuit step",
	)
	anti_visible.queue_free()
	player.queue_free()
	await get_tree().process_frame

	PlayerState.test_mode = previous_test_mode
	print(
		"MONSTER_ANTI_STEALTH_RUNTIME_PASS "
		+ "canonical_ids=38,64 hidden_same_distance=1 "
		+ "normal_suppressed=1 anti_stealth_pursued=1 visible_parity=1"
	)
	get_tree().quit(0)


func _make_enemy(
	monster_id: int,
	player: PlayerCharacter,
	position_px: Vector2,
) -> EnemyActor:
	var enemy := EnemyActorScript.new()
	enemy.name = "AntiStealthProbe_%d" % monster_id
	enemy.global_position = position_px
	enemy.setup(GameData.get_monster_by_id(monster_id), player, false)
	enemy.environment_blocker = self
	enemy.set_meta("spawn_position", position_px)
	enemy.set_meta("safe_zones", [])
	enemy.set_physics_process(false)
	add_child(enemy)
	await get_tree().physics_frame
	# The test positions both actors at the same canonical footpoint.  The
	# target is four GU away, so setup's overlap safety correction is not active.
	enemy.set_combat_position(position_px, &"test_setup")
	enemy._attack_timer = 999.0
	enemy._pending_attack_time = -1.0
	enemy._pending_attack_target = null
	enemy._pending_attack_damage = 0
	enemy._pending_attack_release_record = {}
	# M02A setup keeps the current target null. After the fixture has established
	# its final Ground-GU positions, explicitly drive the production first-search
	# API without changing the runtime retarget cadence.
	enemy.target = null
	enemy._threat_table.clear()
	enemy._retarget_timer = 0.0
	enemy._retarget(0.0)
	assert(enemy.target == player, "fixture failed explicit first target acquisition")
	return enemy


func _force_cadence_ready(enemy: EnemyActor) -> void:
	var cadence = enemy._movement_cadence
	assert(cadence != null, "canonical enemy must own a movement cadence")
	var now_ms := Time.get_ticks_msec()
	cadence.walk_wait_locked = false
	cadence.walk_tick_ms = now_ms - cadence.walk_interval_ms - 1
	cadence.walk_wait_tick_ms = now_ms
	cadence.last_evaluated_ms = now_ms - 1


func is_environment_point_blocked(_world_px: Vector2) -> bool:
	return false
