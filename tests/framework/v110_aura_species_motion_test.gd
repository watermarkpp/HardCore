extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Fixture := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Budget := preload("res://scripts/monster_ai_package/decision_budget.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Spatial := preload("res://scripts/runtime_combat_spatial_index.gd")
@export var scene_id := "v110_aura_species_motion_test"
@export var monster_ids: Array[int] = []
@export var require_mobile_ordinary := false
const IDS := [18, 238, 19, 21, 24, 26, 28, 34, 43, 47, 64, 66, 81, 110, 112, 118, 129, 132, 170, 46]
const HELD_IDS := [41, 59, 78, 123, 161, 190]
var current_map_id := 1
var _zone_generation := 1
var proof := Proof.new()
var actors: Array[EnemyActor] = []
var players: Array[PlayerCharacter] = []
var rows: Array[Dictionary] = []
var index := Spatial.new()

func _ready() -> void:
	await get_tree().process_frame
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	proof.record(GameData.is_loaded(), "canonical data loaded")
	var authority: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/monster_runtime_authority_v1.json"))
	var policy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/monster_targeting_classification_override_v1.json"))
	proof.record(bool(policy.get("preserve", {}).get("data_hold_missing_targeting", false)), "authored user halo policy preserves missing targeting holds")
	var observed_holds: Array[int] = []
	for record: Dictionary in authority.records:
		if int(record.monster_id) in HELD_IDS:
			proof.record(record.targeting.acquisition_status == "DATA_HOLD" and record.targeting.view_range_cells == null,
				"held variant %d remains missing original targeting authority" % int(record.monster_id))
			observed_holds.append(int(record.monster_id))
	proof.record(observed_holds == HELD_IDS, "six exact held variant identities remain explicit negative cases")

	# Real actors, source authority, movement owner and natural physics callbacks.
	# Open terrain is a component fixture, not a claim about all authored maps.
	var selected_ids: Array = IDS if monster_ids.is_empty() else monster_ids
	for ordinal: int in selected_ids.size():
		var monster_id: int = selected_ids[ordinal]
		var ground := Vector2(6.0 + 15.0 * (ordinal % 5), 6.0 + 15.0 * (ordinal / 5))
		var victim := Fixture.player(self, ground + Vector2(4.5, 0.0))
		players.append(victim)
		var data: Dictionary = GameData.get_monster_by_id(monster_id)
		var actor := EnemyActor.new()
		actor.setup(data, victim, str(data.get("classification", "")) == "boss")
		if require_mobile_ordinary:
			proof.record(actor._source176_ordinary_melee() and not actor.is_boss and not actor.stationary, "authority matrix ID %d enters the affected mobile ordinary path" % monster_id)
		if actor.dormant:
			# Zuma stone wake has its own retained range; exercise pursuit inside it.
			victim.global_position = Fixture.to_screen(ground + Vector2(2.0, 0.0))
		actor.configure_runtime_map_projection(1, Callable(Fixture.GU, "ground_delta_gu_to_screen_delta_px"), Callable(Fixture.GU, "screen_delta_px_to_ground_delta_gu"))
		actor.configure_terrain_navigation_context(Fixture.open_context())
		actor.global_position = Fixture.to_screen(ground)
		actor.set_meta("spawn_position", actor.global_position)
		actor.set_meta("safe_zones", [])
		actor.set_meta("zone_generation", 1)
		actor.configure_spatial_index(index, actor.get_instance_id())
		index.register(actor.get_instance_id(), 1, ground, actor.combat_radius_gu, ordinal + 1, actor, Callable(actor, "spatial_index_position"))
		add_child(actor)
		actors.append(actor)
		proof.record(not is_instance_valid(actor.target), "ID %d starts cold without damage or target injection" % monster_id)
		var acquired := actor.request_passive_target_wakeup(victim, 1, 1)
		if monster_id in HELD_IDS:
			# Existing authored policy explicitly preserves missing targeting holds.
			# Do not invent Race/range values merely because movement is allowed.
			proof.record(not acquired and not is_instance_valid(actor.target), "held variant ID %d refuses autonomous acquisition" % monster_id)
		else:
			proof.record(acquired and actor.target == victim, "ID %d accepts legal aura event" % monster_id)
		rows.append({"monster_id": monster_id, "classification": data.get("classification"),
			"delivery": actor.attack_delivery_rule.get("kind", ""), "ordinary": actor._source176_ordinary_melee(),
			"source_interval_ms": actor.service_move_interval_ms, "owner_interval_ms": actor._owner_decision_interval_ms,
			"start_ground": [ground.x, ground.y], "start_clock": actor._combat_action_time_s,
			"max_motion_gu": 0.0, "first_motion_ms": -1.0, "first_source_grant_ms": -1.0,
			"source_grants": 0, "source_grants_while_owner_deferred": 0, "last_source_serial": actor._source176_decision_serial,
			"last_action_serial": actor._attack_logic_serial, "action_started": false, "reason_counts": {}})
	for frame: int in 300:
		await get_tree().physics_frame
		for ordinal: int in actors.size():
			var actor := actors[ordinal]
			var row: Dictionary = rows[ordinal]
			var start := Vector2(float(row.start_ground[0]), float(row.start_ground[1]))
			var moved := actor.spatial_index_position().distance_to(start)
			var elapsed_ms: float = (actor._combat_action_time_s - float(row.start_clock)) * 1000.0
			row.max_motion_gu = maxf(float(row.max_motion_gu), moved)
			if moved > 0.02 and float(row.first_motion_ms) < 0.0: row.first_motion_ms = elapsed_ms
			if actor._attack_logic_serial != int(row.last_action_serial): row.action_started = true
			if actor._source176_decision_serial != int(row.last_source_serial):
				row.source_grants = int(row.source_grants) + 1
				row.last_source_serial = actor._source176_decision_serial
				if float(row.first_source_grant_ms) < 0.0: row.first_source_grant_ms = elapsed_ms
				if not actor._movement_step_active and not actor._hc_pursuit_session and actor._owner_decision_granted_physics_tick != actor._source176_decision_tick:
					row.source_grants_while_owner_deferred = int(row.source_grants_while_owner_deferred) + 1
			var counts: Dictionary = row.reason_counts
			counts[actor._hc_last_reason] = int(counts.get(actor._hc_last_reason, 0)) + 1
	var moving := 0
	for ordinal: int in actors.size():
		var actor := actors[ordinal]
		var row: Dictionary = rows[ordinal]
		row.target_retained = actor.target == players[ordinal]
		row.observed = actor._hc_observed
		row.pursuit_session = actor._hc_pursuit_session
		row.movement_rejected = actor._movement_authority_failed_closed
		if int(row.monster_id) in HELD_IDS:
			row.expected_acquisition_hold = true
			proof.record(not is_instance_valid(actor.target) and not actor._hc_pursuit_session,
				"held variant ID %d has no unauthorized pursuit session" % int(row.monster_id))
			proof.record(actor._source176_pursuit_permission.is_empty(),
				"held variant ID %d retains no invented source permission" % int(row.monster_id))
			continue
		var progressed: bool = float(row.max_motion_gu) > 0.02 or (not bool(row.ordinary) and bool(row.action_started))
		if progressed: moving += 1
		proof.record(progressed, "ID %d actually pursues or executes its source-specific attack" % int(row.monster_id))
		if bool(row.ordinary):
			proof.record(float(row.first_motion_ms) >= 0.0 and float(row.first_motion_ms) <= float(row.source_interval_ms) + 1000.0,
				"ID %d first pursuit cannot lose movement permits behind optional owner windows" % int(row.monster_id))
		actor._owner_optional_budget_end()
	var observations := {"scope": "real EnemyActor downstream aura handoff in open component terrain; no manual physics ticks, no source/grant edits", "motion_results": rows, "moving_actors": moving, "physics_frames": 300,
		"source_binding": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"), "budget": Budget.pursuit_process_snapshot(), "frame_budget": FrameBudget.snapshot()}
	var output := FileAccess.open("res://outputs/test_logs/framework/" + scene_id + ".observations.json", FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(observations, "  ")); output.close()
	var failed := 0
	for record: Dictionary in proof.records:
		if not bool(record.passed): failed += 1
	var ok: bool = proof.write_receipt(scene_id, proof.records.size(), failed)
	print("V110_AURA_SPECIES_MOTION_%s checks=%d moving=%d/%d" % ["PASS" if ok else "FAIL", proof.records.size(), moving, actors.size()])
	for actor: EnemyActor in actors: index.unregister(actor.spatial_actor_runtime_id)
	get_tree().quit(0 if ok else 1)
