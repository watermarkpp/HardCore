extends "res://tests/hc_monster_ai/test_support.gd"

const GU := preload("res://scripts/ground_unit_space.gd")
const Terrain := preload("res://scripts/monster_terrain_navigation_policy.gd")
const Index := preload("res://scripts/runtime_combat_spatial_index.gd")

var index := Index.new()
var player: PlayerCharacter
var serial := 0


func ground_to_screen(position: Vector2) -> Vector2:
	return GU.ground_delta_gu_to_screen_delta_px(position)


func screen_to_ground(position: Vector2) -> Vector2:
	return GU.screen_delta_px_to_ground_delta_gu(position)


func open_context() -> Dictionary:
	return {
		"valid": true,
		"contract_id": Terrain.CONTRACT_ID,
		"runtime_map_id": 1,
		"build_sha256": "b".repeat(64),
		"coordinate_contract_id": Terrain.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		"design_size": Vector2i(80,80),
		"blocked_cells": {},
	}


func make_enemy(position: Vector2) -> EnemyActor:
	var actor := EnemyActor.new()
	actor.setup(GameData.get_monster_by_id(64),player,false)
	actor.global_position = ground_to_screen(position)
	actor.set_meta("spawn_position",actor.global_position)
	actor.set_meta("safe_zones",[])
	actor.set_meta("zone_generation",1)
	actor.configure_runtime_map_projection(1,Callable(self,"ground_to_screen"),Callable(self,"screen_to_ground"))
	actor.configure_terrain_navigation_context(open_context())
	add_child(actor)
	actor.set_physics_process(false)
	actor.target = player
	actor._retarget_timer = 999.0
	actor._attack_timer = 999.0
	actor.attack_min = 50
	actor.attack_max = 50
	serial += 1
	actor.spatial_actor_runtime_id = serial
	actor.combat_spatial_index = index
	index.register(serial,1,position,actor.combat_radius_gu,serial,actor)
	actor.set_combat_position(ground_to_screen(position),&"hc_epoch_test_setup")
	return actor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	player = PlayerCharacter.new()
	player.name = "CombatEpochPlayer"
	player.global_position = ground_to_screen(Vector2(20.0, 20.0))
	player.set_meta("runtime_map_id", 1)
	player.set_meta("zone_generation", 1)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	player.current_mp = 0
	player.shield_time = 0.0
	await get_tree().physics_frame

	_test_start_gate()
	_test_generic_melee_epoch()
	_test_physical_projectile_epoch()
	_test_target_magic_epoch()
	_test_area_magic_epoch()
	_test_area_attack_epoch()
	finish("combat_epoch_delivery")


func _test_start_gate() -> void:
	var actor := make_enemy(Vector2(21.5, 20.0))
	actor._attack_timer = 0.0
	var starts_before := actor._hc_starts
	check(player.begin_combat_transition("epoch-start-gate"), "E00-begin", "transition fixture begins")
	check(not actor._hc_try_start(player), "E00-hc-start", "HC start rejects an active transition")
	actor.attack_range_gu = 3.0
	actor._attack_hit_delay = 0.1
	actor._physics_process_internal(1.0 / 60.0)
	check(
		actor._hc_starts == starts_before and actor._pending_attack_time < 0.0,
		"E00-generic-start",
		"generic delayed start rejects an active transition",
	)
	check(player.finish_combat_transition("epoch-start-gate"), "E00-ready", "transition fixture returns READY")
	_free_enemy(actor)


func _test_generic_melee_epoch() -> void:
	var actor := make_enemy(Vector2(22.5, 20.0))
	actor.attack_range_gu = 3.0
	actor._attack_hit_delay = 0.05
	actor._attack_timer = 0.0
	actor._physics_process_internal(1.0 / 60.0)
	check(
		str(actor._pending_attack_release_record.get("kind", "")) == "generic_melee",
		"E01-freeze",
		"generic melee freezes a typed release record",
	)
	var hp_before := player.current_hp
	_transition_after_release("epoch-generic")
	actor._update_pending_attack(0.10)
	check(player.current_hp == hp_before, "E01-settle", "old generic melee cannot hit after READY")
	_free_enemy(actor)


func _test_physical_projectile_epoch() -> void:
	var actor := make_enemy(Vector2(23.0, 20.0))
	actor.attack_range_gu = 6.0
	actor.attack_delivery_rule = {
		"kind": "physical_projectile",
		"effectId": "monster.physical_arrow.v1",
		"obstaclePolicy": "environment_can_fly_line",
		"impactDelay": {"baseSeconds": 0.05, "perChebyshevGuSeconds": 0.0},
	}
	check(actor._launch_physical_projectile(player, 50), "E02-freeze", "physical projectile release starts")
	var hp_before := player.current_hp
	_transition_after_release("epoch-projectile")
	actor._update_pending_attack(1.0)
	check(player.current_hp == hp_before, "E02-settle", "old projectile cannot hit after READY")
	_free_enemy(actor)


func _test_target_magic_epoch() -> void:
	var actor := make_enemy(Vector2(23.0, 20.0))
	actor.attack_range_gu = 6.0
	actor.attack_delivery_rule = {
		"kind": "target_magic",
		"effectId": "monster.target_lightning.v1",
		"damageChannel": "magic_defense",
		"rangeShape": "chebyshev_square",
		"range_gu": 6.0,
		"hitDelaySeconds": 0.05,
		"activation": {"hpBelowRatio": 1.1, "orAxisBoundaryTiles": 0.0},
	}
	check(actor._launch_target_magic(player, 50), "E03-freeze", "target magic release starts")
	var hp_before := player.current_hp
	_transition_after_release("epoch-target-magic")
	actor._update_pending_attack(1.0)
	check(player.current_hp == hp_before, "E03-settle", "old target magic cannot hit after READY")
	_free_enemy(actor)


func _test_area_magic_epoch() -> void:
	var actor := make_enemy(Vector2(23.0, 20.0))
	actor.attack_delivery_rule = {
		"kind": "area_magic",
		"effectId": "monster.touch_dragon.area_magic.v1",
		"damageChannel": "magic_defense",
		"bodyOnly": true,
		"range_gu": 6.0,
		"hitDelaySeconds": 0.05,
		"status": {"statusChance": 0.0},
	}
	actor._attack_timer = 0.0
	actor._update_area_magic_delivery(0.0)
	check(not actor._area_magic_release_records.is_empty(), "E04-freeze", "area magic freezes target records")
	var hp_before := player.current_hp
	_transition_after_release("epoch-area-magic")
	actor._update_area_magic_delivery(1.0)
	check(player.current_hp == hp_before, "E04-settle", "old area magic cannot hit after READY")
	_free_enemy(actor)


func _test_area_attack_epoch() -> void:
	var actor := make_enemy(Vector2(23.0, 20.0))
	actor.area_attack_rule = {
		"enabled": true,
		"range_gu": 6.0,
		"targetMode": "current_target",
		"scope": "current_map",
		"hitDelaySeconds": 0.05,
	}
	actor._area_attack_cooldown = 0.0
	actor._update_area_attack(0.0)
	check(not actor._area_attack_release_records.is_empty(), "E05-freeze", "area attack freezes target records")
	var hp_before := player.current_hp
	_transition_after_release("epoch-area-attack")
	actor._update_area_attack(1.0)
	check(player.current_hp == hp_before, "E05-settle", "old area attack cannot hit after READY")
	_free_enemy(actor)


func _transition_after_release(token: String) -> void:
	check(player.begin_combat_transition(token), token + "-begin", "transition increments combat epoch")
	check(player.finish_combat_transition(token), token + "-ready", "transition returns READY before settle")


func _free_enemy(actor: EnemyActor) -> void:
	if actor.spatial_actor_runtime_id > 0:
		index.unregister(actor.spatial_actor_runtime_id)
	actor.queue_free()
