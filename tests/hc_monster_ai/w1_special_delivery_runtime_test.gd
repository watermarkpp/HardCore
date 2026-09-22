extends "res://tests/hc_monster_ai/test_support.gd"

const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const WorldRules := preload("res://scripts/world_spatial_rules.gd")
const ProjectileVisual := preload("res://scripts/monster_ranged_projectile_effect.gd")

var player: PlayerCharacter
var descriptors: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	player = PlayerCharacter.new()
	player.global_position = ground_to_screen(Vector2(24.25, 20.25))
	player.set_meta("runtime_map_id", 11)
	player.set_meta("zone_generation", 3)
	player.max_hp = 100000
	player.current_hp = player.max_hp
	player.defense_min = 0
	player.defense_max = 0
	add_child(player)
	player.set_physics_process(false)
	await get_tree().physics_frame
	# PlayerCharacter._ready() loads the formal runtime stats. Override only
	# after that boundary so the multi-case fixture cannot die between channels.
	player.max_hp = 100000
	player.current_hp = player.max_hp
	# Isolate delivery geometry/status/defense from player random evasion.
	PlayerState.computed_stats["anti_magic_points"] = 0
	await _test_spit_immediate_and_world()
	await _test_spit_status_uses_post_defense_damage()
	await _test_special_accuracy_and_named_fallback_boundaries()
	await _test_line_delay_duplicate_epoch_and_world()
	await _test_mixed_target_tile_atomic()
	await _test_guard_immediate_visual()
	await _test_exact_special_family_actors()
	finish("w1_special_delivery_runtime")


func ground_to_screen(position: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(position)


func screen_to_ground(position: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(position)


func open_context() -> Dictionary:
	return Terrain.build_context(
		11,
		{
			"build_sha256": "d".repeat(64),
			"source": {"runtime_map_id": 11},
			"design": {"design_size": [80, 80]},
			"collision": {"blocked_tiles": []},
		},
		Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
	)


func make_actor(position_ground_gu: Vector2, rule: Dictionary) -> EnemyActor:
	var actor := EnemyActor.new()
	actor.global_position = ground_to_screen(position_ground_gu)
	actor.setup(GameData.get_monster_by_id(64), player, false)
	actor.set_meta("spawn_position", actor.global_position)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 3)
	actor.configure_runtime_map_projection(
		11,
		Callable(self, "ground_to_screen"),
		Callable(self, "screen_to_ground"),
	)
	actor.configure_terrain_navigation_context(open_context())
	actor.attack_delivery_rule = rule
	actor.attack_range_gu = 12.0
	actor.attack_min = 20
	actor.attack_max = 20
	actor.target = player
	actor._retarget_timer = 999.0
	actor.monster_special_delivery_requested.connect(capture_descriptor)
	add_child(actor)
	actor.set_physics_process(false)
	return actor


func make_exact_actor(monster_id_value: int, position_ground_gu: Vector2) -> EnemyActor:
	var actor := EnemyActor.new()
	actor.global_position = ground_to_screen(position_ground_gu)
	actor.setup(GameData.get_monster_by_id(monster_id_value), player, false)
	actor.set_meta("spawn_position", actor.global_position)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 3)
	actor.configure_runtime_map_projection(
		11,
		Callable(self, "ground_to_screen"),
		Callable(self, "screen_to_ground"),
	)
	actor.configure_terrain_navigation_context(open_context())
	actor.target = player
	actor._retarget_timer = 999.0
	actor.monster_special_delivery_requested.connect(capture_descriptor)
	add_child(actor)
	actor.set_physics_process(false)
	return actor


func capture_descriptor(descriptor: Dictionary) -> void:
	descriptors.append(descriptor)


func spit_rule() -> Dictionary:
	return {
		"kind": "directional_spit_map",
		"bodyOnly": true,
		"presentationDelaySeconds": 0.3,
		"footprintPattern": "source_spit_map_5x5",
		"cellSteps": 2,
		"damageChannel": "magic_defense",
		"useAccuracy": true,
		"poisonEnabled": false,
	}


func poison_spit_rule() -> Dictionary:
	var rule := spit_rule()
	rule["poisonEnabled"] = true
	rule["status"] = {
		"poisonKind": "decrease_health",
		"durationSeconds": 30.0,
		"chanceDenominatorOffset": 1,
		"chanceDenominatorStatOwner": "attacker",
		"point": 1,
		"tickDamage": 2,
		"intervalSeconds": 2.5,
	}
	return rule


func line_rule() -> Dictionary:
	return {
		"kind": "line_magic",
		"bodyOnly": true,
		"presentationDelaySeconds": 0.6,
		"footprintPattern": "directional_line_cells",
		"cellSteps": 9,
		"damageChannel": "magic_defense",
		"hitDelaySeconds": 0.6,
		"undeadMultiplier": 1.5,
		"trigger": {"axisExclusiveGu": 6.0},
	}


func guard_rule() -> Dictionary:
	return {
		"kind": "guard_direct_projectile",
		"bodyOnly": true,
		"footprintPattern": "target_cell",
		"damageChannel": "physical_defense",
		"damageTiming": "immediate",
		"obstaclePolicy": "world_fresh_override",
		"presentationKind": "generic_projectile_observer",
		"rangeMetric": "manhattan",
		"viewRangeGu": 12.0,
		"useAccuracy": false,
		"presentationDelay": {
			"baseSeconds": 0.6,
			"perChebyshevGuSeconds": 0.05,
		},
	}


func mixed_rule() -> Dictionary:
	return {
		"kind": "mixed_target_tile",
		"bodyOnly": true,
		"presentationDelaySeconds": 0.2,
		"footprintPattern": "target_cell",
		"damageChannel": "mixed_defense",
		"physicalRatio": 0.5,
		"magicRatio": 0.5,
	}


func _test_spit_immediate_and_world() -> void:
	descriptors.clear()
	player.global_position = ground_to_screen(Vector2(22.25, 20.25))
	var actor := make_actor(Vector2(20.25, 20.25), spit_rule())
	await get_tree().physics_frame
	var hp_before := player.current_hp
	check(
		actor._launch_monster_special_cell_delivery(player, 20),
		"W1-spit-launch",
		"directional spit freezes a real EnemyActor release",
	)
	check(
		player.current_hp < hp_before and actor._pending_attack_time < 0.0,
		"W1-spit-immediate",
		"spit magic resolves immediately through the actor damage owner",
	)
	var snapshot: Dictionary = descriptors[0].get("footprint_snapshot", {})
	check(
		str(snapshot.get("shape_type", "")) == Snapshot.SHAPE_CELL_UNION
		and snapshot.get("geometry_cells_grid_steps", [])
		== [Vector2i(21, 20), Vector2i(22, 20)],
		"W1-spit-snapshot",
		"spit descriptor carries the exact absolute two-cell union",
	)
	var wall := await add_world_wall(Vector2(21.25, 20.25))
	hp_before = player.current_hp
	check(
		actor._launch_monster_special_cell_delivery(player, 20),
		"W1-spit-wall-release",
		"body action may release while a WORLD obstacle is present",
	)
	check(
		player.current_hp == hp_before,
		"W1-spit-wall-damage",
		"fresh WORLD settlement blocks immediate spit damage",
	)
	wall.queue_free()
	actor.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame


func _test_spit_status_uses_post_defense_damage() -> void:
	player.global_position = ground_to_screen(Vector2(22.25, 20.25))
	var actor := make_actor(Vector2(20.25, 20.25), poison_spit_rule())
	actor.anti_poison = 0
	await get_tree().physics_frame
	player._monster_source_poison.clear()
	PlayerState.computed_stats["magic_defense_min"] = 100
	PlayerState.computed_stats["magic_defense_max"] = 100
	check(
		actor._launch_monster_special_cell_delivery(player, 20),
		"W1-spit-status-defense-release",
		"spit release still resolves when MAC absorbs the complete magic amount",
	)
	check(
		int(actor.last_magic_attack_resolution.get("final_damage", -1)) == 0
		and player._monster_source_poison.remaining_seconds == 0.0,
		"W1-spit-status-defense-gate",
		"zero post-MAC damage cannot apply source poison",
	)
	PlayerState.computed_stats["magic_defense_min"] = 0
	PlayerState.computed_stats["magic_defense_max"] = 0
	PlayerState.computed_special_effects["magic_shield"] = {}
	player.current_mp = 100
	var hp_before := player.current_hp
	check(
		actor._launch_monster_special_cell_delivery(player, 20),
		"W1-spit-status-shield-release",
		"spit release resolves through the active MP shield",
	)
	check(
		int(actor.last_magic_attack_resolution.get("final_damage", 0)) > 0
		and int(actor.last_magic_attack_resolution.get("applied_damage", -1)) == 0
		and player.current_hp == hp_before
		and player._monster_source_poison.remaining_seconds > 0.0,
		"W1-spit-status-shield-gate",
		"post-MAC damage applies source poison even when the MP shield absorbs HP damage",
	)
	PlayerState.computed_special_effects.erase("magic_shield")
	player._monster_source_poison.clear()
	actor.queue_free()
	await get_tree().process_frame


func _test_special_accuracy_and_named_fallback_boundaries() -> void:
	player.global_position = ground_to_screen(Vector2(21.0, 20.0))
	var malformed_rule := line_rule()
	malformed_rule.erase("hitDelaySeconds")
	var malformed := make_actor(Vector2(20.0, 20.0), malformed_rule)
	await get_tree().physics_frame
	var hp_before := player.current_hp
	malformed._attack_timer = 0.0
	malformed._physics_process_internal(0.1)
	malformed._update_pending_attack(1.0)
	check(
		player.current_hp == hp_before
		and not malformed._uses_monster_special_cell_delivery(),
		"W1-special-malformed-fail-closed",
		"a malformed named cell delivery cannot fall through to ordinary contact",
	)
	malformed.queue_free()
	await get_tree().process_frame

	var target_magic_rule := {
		"kind": "target_magic",
		"effectId": "monster.target_lightning.v1",
		"damageChannel": "magic_defense",
		"rangeShape": "chebyshev_square",
		"rangePixels": 64.0,
		"hitDelaySeconds": 0.2,
		"activation": {"hpBelowRatio": 0.5, "orAxisBoundaryTiles": 2.0},
	}
	var target_magic := make_actor(Vector2(20.0, 20.0), target_magic_rule)
	await get_tree().physics_frame
	target_magic.current_hp = target_magic.max_hp
	hp_before = player.current_hp
	target_magic._attack_timer = 0.0
	target_magic._physics_process_internal(0.1)
	target_magic._update_pending_attack(1.0)
	check(
		player.current_hp < hp_before,
		"W1-target-magic-contact-fallback",
		"inactive target magic preserves its existing adjacent physical fallback",
	)
	target_magic.queue_free()
	await get_tree().process_frame

	var accuracy_actor := make_actor(Vector2(20.0, 20.0), spit_rule())
	await get_tree().physics_frame
	var previous_test_mode := PlayerState.test_mode
	PlayerState.test_mode = false
	accuracy_actor.accuracy = 0
	check(
		not accuracy_actor._monster_special_accuracy_succeeds(player, {
			"source_accuracy": 0,
		}),
		"W1-special-accuracy-zero",
		"strict source hit-point zero always misses",
	)
	accuracy_actor.accuracy = 1
	PlayerState.computed_stats["agility"] = 1
	check(
		accuracy_actor._monster_special_accuracy_succeeds(player, {
			"source_accuracy": 1,
		}),
		"W1-special-accuracy-strict-lt",
		"roll zero is strictly below source hit-point one",
	)
	PlayerState.test_mode = previous_test_mode
	accuracy_actor.queue_free()
	await get_tree().process_frame


func _test_line_delay_duplicate_epoch_and_world() -> void:
	descriptors.clear()
	player.global_position = ground_to_screen(Vector2(24.25, 20.25))
	var actor := make_actor(Vector2(20.25, 20.25), line_rule())
	await get_tree().physics_frame
	check(actor._uses_monster_special_cell_delivery(), "W1-line-contract", "line rule validates")
	check(
		actor._special_delivery_target_is_live(player),
		"W1-line-target-live",
		"line target is live before release",
	)
	check(
		actor._special_delivery_release_condition_met(Vector2(4.0, 0.0)),
		"W1-line-condition",
		"line source axis condition accepts the target",
	)
	var hp_before := player.current_hp
	check(
		actor._launch_monster_special_cell_delivery(player, 20),
		"W1-line-launch",
		"line magic freezes a real delayed EnemyActor release",
	)
	var first_release := actor._pending_attack_release_record
	check(
		player.current_hp == hp_before and actor._pending_attack_time > 0.0,
		"W1-line-delay",
		"line magic does not settle before the source 600ms delay",
	)
	actor._update_pending_attack(0.61)
	check(
		player.current_hp < hp_before,
		"W1-line-settle",
		"line magic settles after the frozen delay",
	)
	var hp_after_first := player.current_hp
	actor._settle_monster_special_cell_release(first_release)
	check(
		player.current_hp == hp_after_first,
		"W1-line-once",
		"one release cannot settle the same victim twice",
	)
	check(actor._launch_monster_special_cell_delivery(player, 20), "W1-line-epoch-freeze", "second line release freezes")
	var epoch_hp := player.current_hp
	check(player.begin_combat_transition("w1-line-epoch"), "W1-line-epoch-begin", "transition begins")
	check(player.finish_combat_transition("w1-line-epoch"), "W1-line-epoch-ready", "transition returns READY")
	actor._update_pending_attack(0.61)
	check(
		player.current_hp == epoch_hp,
		"W1-line-epoch-settle",
		"old line release cannot cross typed combat_epoch after READY",
	)
	check(actor._launch_monster_special_cell_delivery(player, 20), "W1-line-wall-freeze", "third line release freezes")
	var wall_hp := player.current_hp
	var wall := await add_world_wall(Vector2(22.25, 20.25))
	actor._update_pending_attack(0.61)
	check(
		player.current_hp == wall_hp,
		"W1-line-wall-settle",
		"WORLD added after release blocks delayed line settlement",
	)
	wall.queue_free()
	actor.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame


func _test_guard_immediate_visual() -> void:
	descriptors.clear()
	player.global_position = ground_to_screen(Vector2(25.25, 20.25))
	var actor := make_actor(Vector2(20.25, 20.25), guard_rule())
	await get_tree().physics_frame
	check(actor._uses_monster_special_cell_delivery(), "W1-guard-contract", "guard rule validates")
	check(
		actor._special_delivery_target_is_live(player),
		"W1-guard-target-live",
		"guard target is live before release",
	)
	var hp_before := player.current_hp
	check(
		actor._launch_monster_special_cell_delivery(player, 20),
		"W1-guard-launch",
		"guard direct projectile releases inside Manhattan view range",
	)
	check(
		player.current_hp == hp_before - 20 and actor._pending_attack_time < 0.0,
		"W1-guard-immediate",
		"guard HP is immediate and never owned by the presentation flight",
	)
	check(
		descriptors.size() == 1
		and is_equal_approx(float(descriptors[0].get("presentation_delay_seconds", 0.0)), 0.85),
		"W1-guard-delay",
		"guard presentation retains 0.6 + ChebyshevGU*0.05",
	)
	var visual_count := 0
	for child: Node in get_children():
		if child.get_script() == ProjectileVisual:
			visual_count += 1
	check(
		visual_count == 1,
		"W1-guard-visual",
		"guard reuses exactly one existing presentation-only projectile visual",
	)
	actor.queue_free()
	for child: Node in get_children():
		if child.get_script() == ProjectileVisual:
			child.queue_free()
	await get_tree().process_frame


func _test_mixed_target_tile_atomic() -> void:
	descriptors.clear()
	player.global_position = ground_to_screen(Vector2(21.25, 20.25))
	player.shield_time = 0.0
	player.defense_min = 0
	player.defense_max = 0
	PlayerState.computed_stats["magic_defense_min"] = 0
	PlayerState.computed_stats["magic_defense_max"] = 0
	var actor := make_actor(Vector2(20.25, 20.25), mixed_rule())
	await get_tree().physics_frame
	var hp_before := player.current_hp
	check(
		actor._launch_monster_special_cell_delivery(player, 20),
		"W1-mixed-launch",
		"mixed target-tile delivery freezes a real actor release",
	)
	var resolution := actor.last_magic_attack_resolution
	check(
		player.current_hp == hp_before - 20
		and int(resolution.get("pipeline_input", -1)) == 20
		and int(resolution.get("applied_damage", -1)) == 20,
		"W1-mixed-atomic",
		"physical and magic halves enter one shield/HP transaction",
	)
	check(
		int(resolution.get("physical_damage", -1)) == 10
		and int(resolution.get("magic_damage", -1)) == 10,
		"W1-mixed-components",
		"mixed resolution preserves both post-defense components",
	)
	actor.queue_free()
	await get_tree().process_frame


func _test_exact_special_family_actors() -> void:
	var cases := [
		{"ids": [18, 103, 104, 146, 185], "kind": "directional_spit_map", "target": Vector2(22.25, 20.25)},
		{"ids": [46, 60, 128, 168], "kind": "gas_adjacent", "target": Vector2(21.25, 20.25)},
		{"ids": [79], "kind": "line_magic", "target": Vector2(24.25, 20.25)},
		{"ids": [76, 77, 160, 235, 236, 239], "kind": "mixed_target_tile", "target": Vector2(21.25, 20.25)},
		{"ids": [194], "kind": "guard_direct_projectile", "target": Vector2(25.25, 20.25)},
	]
	var source_ground := Vector2(20.25, 20.25)
	for family_value: Variant in cases:
		var family := family_value as Dictionary
		var expected_kind := str(family.get("kind", ""))
		var target_ground: Vector2 = family.get("target", Vector2.INF)
		for monster_id_value: int in family.get("ids", []):
			descriptors.clear()
			player.global_position = ground_to_screen(target_ground)
			player.current_hp = player.max_hp
			player.current_mp = 1000
			player.control_time = 0.0
			player._monster_source_poison.clear()
			PlayerState.computed_stats["magic_defense_min"] = 0
			PlayerState.computed_stats["magic_defense_max"] = 0
			var actor := make_exact_actor(monster_id_value, source_ground)
			await get_tree().physics_frame
			# Some exact appearances apply their authored foot anchor during _ready().
			# Reassert the formal ground coordinates after that lifecycle boundary.
			actor.global_position = ground_to_screen(source_ground)
			player.global_position = ground_to_screen(target_ground)
			var contract_ok := (
				str(actor.attack_delivery_rule.get("kind", "")) == expected_kind
				and actor._uses_monster_special_cell_delivery()
			)
			check(
				contract_ok,
				"W1-exact-%d-contract" % monster_id_value,
				(
					"exact GameData actor consumes the formal %s contract" % expected_kind
					if contract_ok
					else "rejected rule=%s" % str(actor.attack_delivery_rule)
				),
			)
			if monster_id_value == 194:
				check(
					actor.attack_delivery_rule.get("useAccuracy", null) == false,
					"W1-exact-194-no-accuracy",
					"guard source has no separate speed-point accuracy gate",
				)
			var hp_before := player.current_hp
			var launched := actor._launch_monster_special_cell_delivery(player, 20)
			if expected_kind == "line_magic":
				actor._update_pending_attack(0.61)
			var positive_ok := (
				launched and player.current_hp < hp_before
				and descriptors.size() == 1
				and str(descriptors[0].get("delivery_kind", "")) == expected_kind
			)
			check(
				positive_ok,
				"W1-exact-%d-positive" % monster_id_value,
				(
					"exact actor executes its formal delivery through the shared owner"
					if positive_ok
					else "launch=%s hp=%d/%d descriptors=%d resolution=%s" % [
						launched, player.current_hp, hp_before, descriptors.size(),
						str(_exact_launch_diagnostic(actor, expected_kind)),
					]
				),
			)
			player.current_hp = player.max_hp
			player.control_time = 0.0
			player._monster_source_poison.clear()
			var wall := await add_world_wall((source_ground + target_ground) * 0.5)
			hp_before = player.current_hp
			launched = actor._launch_monster_special_cell_delivery(player, 20)
			if expected_kind == "line_magic":
				actor._update_pending_attack(0.61)
			check(
				launched and player.current_hp == hp_before,
				"W1-exact-%d-world-negative" % monster_id_value,
				"fresh WORLD blocks the exact actor delivery",
			)
			wall.queue_free()
			actor.queue_free()
			for child: Node in get_children():
				if child.get_script() == ProjectileVisual:
					child.queue_free()
			await get_tree().physics_frame
			await get_tree().process_frame


func _exact_launch_diagnostic(actor: EnemyActor, kind: String) -> Dictionary:
	var source_ground := screen_to_ground(actor.global_position)
	var target_ground := screen_to_ground(player.global_position)
	var snapshot := actor._create_monster_special_cell_snapshot(
		kind,
		"diagnostic:%d" % actor.monster_id,
		source_ground,
		target_ground,
	)
	return {
		"combat_enabled": actor.combat_enabled,
		"source_hp": actor.current_hp,
		"target_live": actor._special_delivery_target_is_live(player),
		"condition": actor._special_delivery_release_condition_met(
			target_ground - source_ground
		),
		"snapshot_ok": actor._snapshot_strict_ok(snapshot),
		"victim_count": actor._monster_special_delivery_targets(snapshot, player).size(),
		"resolution": actor.last_magic_attack_resolution,
	}


func add_world_wall(ground_position_gu: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = WorldRules.WORLD_LAYER
	wall.collision_mask = 0
	wall.global_position = ground_to_screen(ground_position_gu)
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	await get_tree().physics_frame
	return wall
