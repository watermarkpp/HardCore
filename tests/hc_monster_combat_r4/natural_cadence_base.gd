extends Node

## R4 T5 shared natural-cadence base (C task): per-action, per-release,
## per-damage attribution on real physics frames. The fixture never writes
## _attack_timer / _pending_attack_time / _hc_last_start_tick and never calls
## _physics_process / _advance_combat_action_clock. Diagnostics read ONLY
## production state (_last_hc_release_record, _hc_starts/_hc_settlements,
## _current_attack_interval, parent_start_game_time_s) - no second damage
## owner, no extra per-frame admission or world queries.

const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const DamageLedgerObserverScript := preload("res://scripts/damage_ledger_observer.gd")
const VerifierScript := preload("res://tests/hc_monster_combat_r4/damage_attribution_verifier.gd")

const SAMPLE_TARGET := 20
const BOOT_BUDGET_S := 8.0
## Total scene budget stays within the 60s heavy-scene cap: boot (8) +
## sampling (48) + evidence write + cleanup <= 60. Boot typically takes
## ~2s, so the full 48s sampling window is available in practice.
const SAMPLE_BUDGET_S := 48.0
const FOREIGN_DAMAGE := 7

## Subclasses pin these; the formal per-identity scenes must NOT be
## overridable through the environment (review section 6).
var monster_id_under_test := 0
var chase_mode := false

var game: Node
var player: PlayerCharacter
var enemy: EnemyActor
var sampled_frames := 0
var position_changes := 0
var last_position := Vector2.INF
var min_target_distance_px := INF
var start_events: Array = []
var last_release_seq := 0
var hp_events: Array = []
var foreign_events: Array = [] # legacy cursor, unused by v4 ledger
var last_hp := 0
var boot_ok := false
var spawn_ok := false
var safe_zone_hit := false
var initial_ground_distance_gu := 0.0
var effective_intervals: Array = []


func _ready() -> void:
	_run.call_deferred()


func _expected_monster_id() -> int:
	return monster_id_under_test


## R4 T5-P3: attribution comes from the DamageLedgerObserver real-write
## ledger via the shared verifier. The stats_changed listener only tracks
## the HP cursor for evidence totals; it never attributes by itself.


func _run() -> void:
	var run_started_ms := Time.get_ticks_msec()
	var failures: Array = []
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var boot_deadline := run_started_ms + int(BOOT_BUDGET_S * 1000.0)
	while Time.get_ticks_msec() < boot_deadline:
		if int(game.get("current_map_id")) >= 0 and bool(game.call("gameplay_input_is_enabled")):
			break
		await get_tree().process_frame
	boot_ok = int(game.get("current_map_id")) == GameData.service_runtime_map_id(0) and bool(game.call("gameplay_input_is_enabled"))
	if not boot_ok:
		failures.append("world_not_ready")

	player = game.player
	player.set_physics_process(false)
	player.max_hp = 100000
	player.current_hp = player.max_hp
	player.defense_min = 0
	player.defense_max = 0
	var fixture_ground := Vector2(40.5, 13.5)
	safe_zone_hit = WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(fixture_ground, game._active_safe_zones)
	if safe_zone_hit:
		failures.append("fixture_inside_safe_zone")
	var fixture_screen: Vector2 = game._canonical_ground_gu_to_screen_px(fixture_ground)
	player.global_position = fixture_screen
	game._set_player_world_position(fixture_screen)
	last_hp = player.current_hp

	# Stationary mode: spawn within admission reach. Chase mode: spawn
	# OUTSIDE the 1.5GU center-admission reach and require real movement.
	var spawn_offset_px := 30.0 if not chase_mode else 200.0
	enemy = game._spawn_enemy(
		GameData.get_monster_by_id(_expected_monster_id()),
		fixture_screen + Vector2(spawn_offset_px, 0.0),
		false,
		-1.0,
		{"respawn_enabled": false, "spawn_slot_id": "test:r4-natural-cadence"},
	)
	spawn_ok = enemy != null and enemy.combat_enabled and not bool(enemy.get_meta("body_policy_rejected", false))
	if not spawn_ok:
		failures.append("spawn_failed")
	if enemy != null and enemy.monster_id != _expected_monster_id():
		failures.append("identity_mismatch spawned=%d expected=%d" % [enemy.monster_id, _expected_monster_id()])
	var index_runtime_id := -1
	if spawn_ok:
		index_runtime_id = enemy.spatial_actor_runtime_id
		last_position = enemy.global_position
		initial_ground_distance_gu = _ground_distance_gu(enemy.global_position, player.global_position)
		if chase_mode and initial_ground_distance_gu <= 1.5:
			failures.append("chase_fixture_not_out_of_range gu=%.3f" % initial_ground_distance_gu)
		await get_tree().physics_frame

	# --- Sampling window (bounded; evidence is written before cleanup) ---
	# R4 T5-P3: attribution consumes the REAL ledger from the victim's HP
	# write site (DamageLedgerObserver), resolved by delivery identity - no
	# time-window correlation, no roll clipping, no inference.
	DamageLedgerObserverScript.recording_enabled = true
	DamageLedgerObserverScript.reset()
	var sample_deadline := run_started_ms + int((BOOT_BUDGET_S + SAMPLE_BUDGET_S) * 1000.0)
	var next_foreign_ms := Time.get_ticks_msec() + (3000 if chase_mode else 9000)
	while Time.get_ticks_msec() < sample_deadline:
		await get_tree().physics_frame
		sampled_frames += 1
		if not is_instance_valid(enemy):
			break
		var record: Dictionary = enemy._last_hc_release_record
		var seq: int = int(record.get("seq", 0))
		if seq != last_release_seq and seq > 0:
			last_release_seq = seq
			start_events.append({
				"seq": seq,
				"release_id": str(record.get("release_id", "")),
				"parent_action_id": int(record.get("parent_action_id", -1)),
				"parent_start_game_time_s": float(record.get("parent_start_game_time_s", -1.0)),
				"parent_duration_s": float(record.get("parent_duration_s", -1.0)),
				"source_life": int(record.get("source_life", -1)),
				"target_id": int(record.get("target_id", 0)),
				"target_life": int(record.get("target_life", -1)),
				"map_id": int(record.get("map_id", -1)),
				"generation": int(record.get("generation", -1)),
				"damage": int(record.get("damage", 0)),
				"effective_interval_s": enemy._current_attack_interval(),
				"physics_tick": Engine.get_physics_frames(),
			})
		var pos: Vector2 = enemy.global_position
		if pos.distance_to(last_position) > 0.01:
			position_changes += 1
			last_position = pos
		if is_instance_valid(player):
			var distance: float = pos.distance_to(player.global_position)
			if distance < min_target_distance_px:
				min_target_distance_px = distance
		# Bounded foreign-damage perturbation from a legal external source:
		# the injection carries NO delivery identity, so its debits land as
		# UNKNOWN in the raw ledger - reported as such, never attributed to
		# the under test and never relabeled as wild sources.
		if Time.get_ticks_msec() >= next_foreign_ms:
			next_foreign_ms = Time.get_ticks_msec() + 11000
			player.take_damage(FOREIGN_DAMAGE)
		var target_count := 1 if chase_mode else SAMPLE_TARGET
		if start_events.size() >= target_count:
			break

	# --- Assertions ---
	var snapshot: Dictionary = enemy.hc_package_policy_snapshot() if is_instance_valid(enemy) else {}
	var target_count := 1 if chase_mode else SAMPLE_TARGET
	var under_test_id := enemy.get_instance_id() if is_instance_valid(enemy) else -1
	var ledger := VerifierScript.verdict(
		DamageLedgerObserverScript.events,
		DamageLedgerObserverScript.terminal_events,
		under_test_id,
	)
	var audit := VerifierScript.audit_releases(
		start_events,
		DamageLedgerObserverScript.events,
		DamageLedgerObserverScript.terminal_events,
		under_test_id,
	)
	hp_events = ledger["under_test_mutations"]
	if start_events.size() < target_count:
		failures.append("insufficient_starts=%d" % start_events.size())
	if hp_events.size() < target_count:
		failures.append("insufficient_attributed_hits=%d" % hp_events.size())
	var settlements: int = int(snapshot.get("settlements", 0))
	if not chase_mode and settlements < SAMPLE_TARGET:
		failures.append("insufficient_settlements=%d" % settlements)
	# Every dispatched release needs a REAL terminal (applied mutation, real
	# miss or real rejection); duplicates are reported, never deduplicated.
	for f: Variant in audit["failures"]:
		failures.append(str(f))
	# UNKNOWN debits (the test injector and any unattributed writer) are
	# reported as UNKNOWN - never relabeled as wild sources or under-test.
	if not chase_mode and ledger["unknown_mutations"].is_empty():
		failures.append("foreign_perturbation_missing")
	for event: Variant in ledger["unknown_mutations"]:
		printerr("R4_LEDGER_UNKNOWN_MUTATION: %s" % [str(event)])
	# Cadence from the production game clock: the gap between consecutive
	# parent_start_game_time_s values must be >= the effective interval at the
	# earlier start, minus physical-tick quantization (one frame); strike
	# deferrals (struck lock) only ever LENGTHEN gaps and are recorded.
	for i: int in range(1, start_events.size()):
		var gap: float = float(start_events[i]["parent_start_game_time_s"]) - float(start_events[i - 1]["parent_start_game_time_s"])
		var interval: float = float(start_events[i - 1]["effective_interval_s"])
		if gap < interval - (1.0 / 60.0):
			failures.append("fast_gap[%d]=%.4f<interval=%.4f" % [i, gap, interval])
	if chase_mode:
		var moved_gu := initial_ground_distance_gu - _ground_distance_gu(enemy.global_position, player.global_position) if is_instance_valid(enemy) else 0.0
		if position_changes < 10:
			failures.append("chase_no_movement changes=%d" % position_changes)
		if moved_gu <= 0.0:
			failures.append("chase_no_closure gu=%.3f" % moved_gu)
		# The chase must bring the actor into admission reach: the minimum
		# observed distance must be far below the out-of-range start.
		if min_target_distance_px >= 120.0:
			failures.append("chase_never_reached min_px=%.1f" % min_target_distance_px)

	# --- Same-structure per-run JSON for PASS and FAIL ---
	# Review section 2 vocabulary:
	# observed_records   - every buffered HP debit line (raw observations)
	# unique_admissions  - deduplicated under-test admissions (start_events)
	# unique_releases    - deduplicated release transactions (= admissions,
	#                      one release record per admission in production)
	# terminal_results   - per settled release: HIT (frame reconciled with
	#                      the damage roll) or amounts mismatch listed
	# actual_hp_debits   - under-test debits: count and total amount
	# foreign_hp_debits  - injected foreign debits, separate ledger
	# other_source_debits- world-sourced debits (wild monsters, DOTs):
	#                      recorded, never attributed to the under test
	var total_under_test_amount := 0
	for event: Variant in hp_events:
		total_under_test_amount += int(event.get("actual_hp_delta", 0))
	var foreign_mutations: Array = ledger["foreign_mutations"]
	var foreign_amount := int(ledger["foreign_amount"])
	var unknown_mutations: Array = ledger["unknown_mutations"]
	var raw_events: Array = DamageLedgerObserverScript.events
	var raw_amount := 0
	for event: Variant in raw_events:
		if not event.get("suppressed", false):
			raw_amount += int(event.get("actual_hp_delta", 0))
	var evidence := {
		"schema": "r4_natural_cadence_v4_real_write_ledger",
		"expected_monster_id": _expected_monster_id(),
		"chase_mode": chase_mode,
		"git_head": "see delivery manifest; runner JSON carries git_head",
		"world_ready": boot_ok,
		"fixture_safe_zone_hit": safe_zone_hit,
		"spawn_ok": spawn_ok,
		"spawned_monster_id": enemy.monster_id if is_instance_valid(enemy) else -1,
		"index_runtime_id": index_runtime_id,
		"initial_ground_distance_gu": initial_ground_distance_gu,
		"sampled_physics_frames": sampled_frames,
		"enemy_position_changes": position_changes,
		"min_target_distance_px": min_target_distance_px,
		"hc_starts_total": int(snapshot.get("starts", 0)),
		"hc_settlements_total": settlements,
		"observed_records": raw_events.size(),
		"raw_total_amount": raw_amount,
		"unique_admissions": start_events.size(),
		"unique_releases": start_events.size(),
		"actual_hp_debits": {"count": hp_events.size(), "total_amount": total_under_test_amount},
		"foreign_hp_debits": {"count": foreign_mutations.size(), "total_amount": foreign_amount},
		"unknown_mutations": {"count": unknown_mutations.size(), "note": "identity-less debits (test injector / unattributed writers), never relabeled"},
		"under_test_starts_recorded": start_events.size(),
		"attributed_hp_events": hp_events.size(),
		"starts": start_events,
		"attributed_hp": hp_events,
		"foreign_detail": foreign_mutations,
		"unknown_detail": unknown_mutations,
		"terminal_events": DamageLedgerObserverScript.terminal_events,
		"audit_failures": audit["failures"],
		"raw_events": raw_events,
		"failures": failures,
	}
	var out_path := "res://outputs/test_logs/r4_cadence_%d%s.json" % [_expected_monster_id(), "_chase" if chase_mode else ""]
	FileAccess.open(out_path, FileAccess.WRITE).store_string(JSON.stringify(evidence, "  "))

	# Quit directly: synchronously tearing down the whole formal world inside
	# the scene budget cost more time than the 60s cap leaves after the 56s
	# sampling plan, so the process exit is left to the runner.
	if not failures.is_empty():
		printerr("R4_NATURAL_CADENCE_FAIL: monster=%d %s evidence=%s" % [_expected_monster_id(), str(failures), out_path])
		get_tree().quit(1)
		return
	print("R4_NATURAL_CADENCE_PASS: monster=%d starts=%d attributed=%d settlements=%d foreign=%d evidence=%s" % [
		_expected_monster_id(), start_events.size(), hp_events.size(), settlements, ledger["foreign_mutations"].size(), out_path,
	])
	get_tree().quit(0)


func _ground_distance_gu(from_screen: Vector2, to_screen: Vector2) -> float:
	var a: Vector2 = game._canonical_screen_px_to_ground_gu(from_screen)
	var b: Vector2 = game._canonical_screen_px_to_ground_gu(to_screen)
	return a.distance_to(b)
