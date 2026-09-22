extends Node2D

## R2-W6 persistent-status (poison) lifecycle counterexamples.
##
## Matrix row: strong poison expires -> weak poison takes over; old poison is
## never retained forever; pause / map-transition / death-revival boundaries;
## large delta. Two production poison lanes exist and must agree at the death
## boundary:
##   - legacy lane (player.poison_time / poison_damage, fed by monster poison
##     attacks via apply_poison),
##   - monster-source lane (player._monster_source_poison, cleared at death).
## Part 1 is the red-green pair: the legacy lane historically survived
## complete_death_revival while the monster lane was cleared.

const MonsterSourcePoisonState := preload(
	"res://scripts/monster_source_poison_state.gd"
)

var failures: Array[String] = []
var checks := 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("STATUS_EFFECT_LIFECYCLE: " + label)


class StruckVisualFixture:
	extends MonsterVisual
	func _ready() -> void:
		set_process(false)


class PoisonEnemyFixture:
	extends EnemyActor
	func _ready() -> void:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		_initialize_spawn_facing_once()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("战士")
	_poison_state_unit_pins()
	_enemy_lane_pins()
	await _player_lane_pins()
	if failures.is_empty():
		print("STATUS_EFFECT_LIFECYCLE_PASS checks=", checks)
		get_tree().quit(0)
	else:
		print(
			"STATUS_EFFECT_LIFECYCLE_FAILED count=%d" % failures.size()
		)
		get_tree().quit(1)


func _poison_state_unit_pins() -> void:
	# Strong poison active, weak re-applied: damage takes the maximum and the
	# duration refreshes (poison never stacks; it takes the highest).
	var state := MonsterSourcePoisonState.new()
	check(state.apply(10, 2.0, 1.0), "strong poison accepted")
	check(state.apply(2, 5.0, 1.0), "weak re-application accepted")
	check(
		state.tick_damage == 10,
		"active strong poison keeps the higher damage"
	)
	check(
		is_equal_approx(state.remaining_seconds, 5.0),
		"re-application refreshes the duration"
	)
	# Weak takeover after the strong poison fully expired.
	var takeover := MonsterSourcePoisonState.new()
	check(takeover.apply(10, 2.0, 1.0), "takeover: strong accepted")
	check(takeover.advance(2.0) == 2, "takeover: strong poison ticks out")
	check(
		takeover.remaining_seconds <= 0.0, "takeover: strong poison expired"
	)
	check(takeover.apply(2, 5.0, 1.0), "takeover: weak accepted after expiry")
	check(
		takeover.tick_damage == 2,
		"expired strong poison must not ride on the weak poison"
	)
	check(
		is_equal_approx(takeover.remaining_seconds, 5.0),
		"takeover: weak poison owns the fresh duration"
	)
	# Old poison is never retained forever.
	var expire := MonsterSourcePoisonState.new()
	expire.apply(3, 2.5, 1.0)
	expire.advance(100.0)
	check(
		expire.remaining_seconds <= 0.0 and expire.tick_damage == 0
		or expire.remaining_seconds <= 0.0,
		"long advance expires the poison"
	)
	check(expire.advance(1.0) == 0, "expired poison no longer ticks")
	# Large delta stays bounded by the remaining duration.
	var bounded := MonsterSourcePoisonState.new()
	bounded.apply(3, 2.5, 1.0)
	var ticks := bounded.advance(10.0)
	check(
		ticks == 2 and is_equal_approx(bounded.remaining_seconds, 0.0),
		"large delta ticks at most the remaining duration (%d)" % ticks
	)
	check(
		is_equal_approx(bounded.elapsed_seconds, 0.5),
		"large delta keeps the tick phase bounded"
	)
	# Invalid applications are rejected.
	var invalid := MonsterSourcePoisonState.new()
	check(not invalid.apply(0, 5.0, 1.0), "zero damage rejected")
	check(not invalid.apply(3, -1.0, 1.0), "negative seconds rejected")
	check(not invalid.apply(3, INF, 1.0), "infinite seconds rejected")
	check(not invalid.apply(3, 5.0, 0.0), "zero interval rejected")


func _enemy_lane_pins() -> void:
	var enemy := PoisonEnemyFixture.new()
	add_child(enemy)
	enemy.current_hp = 100
	enemy.max_hp = 100
	# Strong then weak on the same actor: damage max, duration refresh.
	enemy.apply_poison(10, 2.0, 1.0)
	enemy.apply_poison(2, 5.0, 1.0)
	check(
		enemy.poison_damage == 10,
		"enemy lane keeps the higher poison damage"
	)
	check(
		is_equal_approx(enemy.poison_time, 5.0),
		"enemy lane refreshes the poison duration"
	)
	# Old poison is never retained forever; large delta stays bounded.
	enemy.apply_poison(3, 2.5, 1.0)
	enemy._update_status_effects(10.0)
	check(
		enemy.poison_time <= 0.0,
		"enemy lane: large delta expires the poison"
	)
	check(
		enemy.poison_damage == 0,
		"enemy lane: expired poison clears its damage"
	)
	check(
		enemy.current_hp > 0,
		"enemy lane: tick burst stays bounded by the remaining duration"
	)
	enemy.free()


func _player_lane_pins() -> void:
	var player := PlayerCharacter.new()
	add_child(player)
	player.defense_min = 0
	player.defense_max = 0
	player.defense_buff = 0

	# Both poison lanes active (30s, far beyond this test).
	player.apply_poison(7, 30.0)
	check(
		player.poison_time > 0.0 and player.poison_damage == 7,
		"legacy lane applied"
	)
	check(
		player.apply_monster_poison(5, 30.0, 1.0),
		"monster-source lane applied"
	)
	check(
		player._monster_source_poison.remaining_seconds > 0.0,
		"monster-source lane is active before death"
	)

	# Map-transition pause freezes both lanes without clearing them. Real
	# frames drive _process, so the freeze is verified end to end.
	player.begin_combat_transition("status_lifecycle_probe")
	var legacy_before := player.poison_time
	var monster_before := player._monster_source_poison.remaining_seconds
	for _frame in 3:
		await get_tree().process_frame
	check(
		is_equal_approx(player.poison_time, legacy_before),
		"transition freezes the legacy poison lane"
	)
	check(
		is_equal_approx(
			player._monster_source_poison.remaining_seconds, monster_before
		),
		"transition freezes the monster-source lane"
	)
	player._combat_transition_token = ""

	# Death boundary: the monster-source lane is already cleared at death.
	player.current_hp = 1
	player.take_damage(1, false)
	check(player._dead, "formal death boundary reached")
	check(
		player._monster_source_poison.remaining_seconds <= 0.0,
		"monster-source lane is cleared at death"
	)
	# RED-GREEN: the legacy lane must not survive the revival boundary either.
	player.complete_death_revival()
	check(not player._dead, "revival completes")
	check(
		player.poison_time <= 0.0,
		"legacy poison must not survive formal death (got %.2fs)" %
		player.poison_time
	)
	check(
		player.poison_damage == 0,
		"legacy poison damage must be cleared at death"
	)
	player.free()
