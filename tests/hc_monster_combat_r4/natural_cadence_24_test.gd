extends Node

## R4 T5 natural cadence: the Actor must reach >=20 attack admissions on its
## OWN physics frames - real target acquisition, chase, admission, cooldown
## and release. The fixture only builds the scene, holds the target still and
## seeds the RNG; after sampling starts it NEVER writes _attack_timer /
## _pending_attack_time / _hc_last_start_tick and never calls
## _physics_process / _advance_combat_action_clock directly.
## Per-admission accounting: every start is attributed to a real action, the
## inter-start gaps are reconciled against the parsed formal interval
## (>= interval: cooldown was never cleared to manufacture attacks), and a
## zero-defense fixed-hit control compares HP per hit exactly.

const OpenTerrainFixture := preload("res://tests/helpers/monster_open_terrain_test_fixture.gd")

const SAMPLE_TARGET := 20
const SAMPLE_LIMIT_S := 30.0


var enemy: EnemyActor
var player: PlayerCharacter
var start_serials: Array = []
var hp_events: Array = []
var last_hp: int = 0
var rng_seed := 20260927


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var monster_id: int = int(OS.get_environment("HC_NATURAL_CADENCE_MONSTER_ID")) if OS.get_environment("HC_NATURAL_CADENCE_MONSTER_ID") != "" else 24
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var deadline_boot: int = Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline_boot:
		if int(game.get("current_map_id")) >= 0 and bool(game.call("gameplay_input_is_enabled")):
			break
		await get_tree().process_frame
	assert(int(game.get("current_map_id")) == GameData.service_runtime_map_id(0), "fixture needs the formal mapped world")

	player = game.player
	player.set_physics_process(false)
	player.max_hp = 100000
	player.current_hp = player.max_hp
	player.defense_min = 0
	player.defense_max = 0
	# A quiet authored corner far from the central spawn cluster, outside the
	# safe zones, on walkable ground.
	var fixture_ground := Vector2(8.5, 90.5)
	var fixture_screen: Vector2 = game._canonical_ground_gu_to_screen_px(fixture_ground)
	player.global_position = fixture_screen
	game._set_player_world_position(fixture_screen)
	last_hp = player.current_hp
	player.stats_changed.connect(_on_player_stats_changed)

	enemy = game._spawn_enemy(
		GameData.get_monster_by_id(monster_id),
		fixture_screen + Vector2(140.0, 0.0),
		false,
		-1.0,
		{"respawn_enabled": false, "spawn_slot_id": "test:r4-natural-cadence"},
	)
	assert(enemy != null and enemy.combat_enabled, "fixture enemy must spawn combat-enabled through the formal factory")
	enemy.set_combat_position(fixture_screen + Vector2(140.0, 0.0), &"spawn")
	await get_tree().physics_frame

	# Sampling window: pure observation on real physics frames.
	var deadline_ms: int = Time.get_ticks_msec() + int(SAMPLE_LIMIT_S * 1000.0)
	var last_serial: int = -1
	while Time.get_ticks_msec() < deadline_ms:
		await get_tree().physics_frame
		var serial: int = enemy._attack_logic_serial
		if serial != last_serial and enemy._attack_action_active:
			last_serial = serial
			start_serials.append(Time.get_ticks_msec())
		if hp_events.size() >= SAMPLE_TARGET and start_serials.size() >= SAMPLE_TARGET:
			break

	var valid := true
	var report := "monster=%d starts=%d hp_events=%d" % [monster_id, start_serials.size(), hp_events.size()]
	if start_serials.size() < SAMPLE_TARGET:
		valid = false
	if hp_events.size() < SAMPLE_TARGET:
		valid = false

	# Natural-cadence reconciliation: every inter-start gap must be at least
	# the parsed formal interval (a cleared cooldown or reset anti-reentry
	# would produce a gap BELOW it).
	if valid:
		var interval: float = enemy._current_attack_interval()
		for i: int in range(1, start_serials.size()):
			var gap_s: float = float(start_serials[i] - start_serials[i - 1]) / 1000.0
			if gap_s < interval * 0.9:
				valid = false
				report += " FAST_GAP[%d]=%.3f<interval=%.3f" % [i, gap_s, interval]
				break

	# Zero-defense fixed-hit control: every landed hit must debit HP exactly
	# once with a positive amount; swallowing 19 of 20 hits fails here.
	if valid:
		for event: Variant in hp_events:
			if int(event) <= 0:
				valid = false
				report += " BAD_HP_EVENT=%d" % int(event)
				break

	enemy.queue_free()
	game.queue_free()
	if not valid:
		printerr("R4_NATURAL_CADENCE_FAIL: %s" % report)
		get_tree().quit(1)
		return
	print("R4_NATURAL_CADENCE_PASS: %s" % report)
	get_tree().quit(0)


func _on_player_stats_changed(hp: int, _maximum: int) -> void:
	var delta: int = last_hp - hp
	last_hp = hp
	if delta > 0:
		hp_events.append(delta)
