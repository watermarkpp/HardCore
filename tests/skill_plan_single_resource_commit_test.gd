extends Node

## Q3-A: one successful release spends the resource exactly once (MP drop ==
## one cost) and the canonical plan quotes the identical cost.

const Fixtures := preload(
	"res://tests/helpers/skill_execution_plan_test_fixtures.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Plan := preload("res://scripts/skills/skill_execution_plan.gd")
const DataLoader := preload("res://scripts/skills/skill_data_loader.gd")
const FIXTURE_MONSTER_ID := 19
## The central outdoor authored spawn avoids the Home polygon and map edge.
const FIXTURE_GROUND_POSITION := Vector2(40.5, 13.5)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 35
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {"火墙": 1}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	for _i: int in range(5):
		await get_tree().process_frame
	await _wait_for_formal_world(game)
	var caster: PlayerCharacter = game.player
	caster.current_mp = 500
	var caster_ground: Vector2 = FIXTURE_GROUND_POSITION - Vector2(2.0, 0.0)
	var caster_position: Vector2 = game._canonical_ground_gu_to_screen_px(caster_ground)
	assert(caster_position.is_finite(), "resource commit fixture needs a finite map projection")
	game._set_player_world_position(caster_position)
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			caster_ground,
			game._active_safe_zones,
		),
		"resource commit caster fixture must be outside the authored safe area",
	)
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).set_combat_position(
				caster.global_position + Vector2(3000.0, 3000.0),
				&"test_fixture_clear",
			)
	var target_position: Vector2 = game._canonical_ground_gu_to_screen_px(FIXTURE_GROUND_POSITION)
	assert(target_position.is_finite(), "resource commit fixture needs a finite target projection")
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			FIXTURE_GROUND_POSITION,
			game._active_safe_zones,
		),
		"resource commit target fixture must be outside the authored safe area",
	)
	var canonical_data := GameData.get_monster_by_id(FIXTURE_MONSTER_ID)
	assert(
		not canonical_data.is_empty(),
		"resource commit fixture monster_id=%d must exist" % FIXTURE_MONSTER_ID
	)
	var target: EnemyActor = game._spawn_enemy(
		canonical_data,
		target_position,
		false,
		-1.0,
		{
			"respawn_enabled": false,
			"spawn_slot_id": "test:skill_plan_resource_commit:%d" % FIXTURE_MONSTER_ID,
		},
	)
	assert(
		target != null
			and target.monster_id == FIXTURE_MONSTER_ID
			and not target.is_boss
			and target.runtime_map_id == int(game.get("current_map_id"))
			and target.projection_ready()
			and target.spatial_actor_runtime_id > 0,
		"resource commit fixture must use the formal exact-ID mapped spawn",
	)
	target.max_hp = 9999
	target.current_hp = target.max_hp
	assert(
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.can_receive_damage(),
		"resource commit fixture target must survive exact-ID admission"
	)
	target.set_physics_process(false)
	target.apply_control(10.0)
	await get_tree().process_frame
	assert(
		game._combat_target_world_clear(target, caster.global_position, true),
		"resource commit target must have a clear WORLD path",
	)
	game._set_magic_locked_target(target, true)
	assert(game.magic_locked_target == target, "resource commit target was rejected by the formal WORLD gate")
	game._skill_cast_target = target
	await get_tree().process_frame

	var definition := DataLoader.skill("wizard.fire_wall")
	var mp_cost := int((definition.get("mp_cost_by_rank", [0, 0, 0, 0]) as Array)[1])
	var mp_before: int = game.player.current_mp
	var result: Dictionary = game._execute_canonical_skill(
		"火墙",
		game.player.global_position,
		Vector2.RIGHT,
		12
	)
	assert(
		bool(result.get("accepted", false)),
		"fire wall must be accepted: %s" % str(result)
	)
	var mp_after: int = game.player.current_mp
	assert(
		mp_before - mp_after == mp_cost,
		"resource must be committed exactly once (%d spent, expected %d)"
		% [mp_before - mp_after, mp_cost]
	)
	# Canonical plan quotes the identical cost.
	var request := Fixtures.make_request(
		"wizard.fire_wall",
		1,
		35,
		Vector2i.ZERO,
		Vector2i.DOWN,
		Fixtures.default_target_context(true),
		Fixtures.default_resource_context(500)
	)
	var snapshot := Fixtures.circle_snapshot(
		self,
		"wizard.fire_wall",
		"q3a:mp:1",
		1,
		Vector2(0, 0),
		2.0
	)
	var plan: Dictionary = Router.build_canonical_plan(
		request,
		Fixtures.canonical_context(1, "q3a:mp:1", 0, 0, snapshot)
	)
	assert(
		int(plan.get("resource_cost", {}).get("mp_cost", 0)) == mp_cost,
		"canonical plan must quote the same mp cost"
	)
	_cleanup(game, target)
	await get_tree().process_frame
	print("SKILL_PLAN_SINGLE_RESOURCE_COMMIT_PASS mp=%d" % mp_cost)
	get_tree().quit(0)


func _cleanup(game: Node, target: EnemyActor) -> void:
	if is_instance_valid(target):
		target.queue_free()
	if is_instance_valid(game):
		game.queue_free()


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnit.ground_delta_gu_to_screen_delta_px(value)


func _wait_for_formal_world(game: Node) -> void:
	var deadline_ms: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline_ms:
		var current_map_id: int = int(game.get("current_map_id"))
		var input_enabled: bool = bool(game.call("gameplay_input_is_enabled"))
		if current_map_id >= 0 and input_enabled:
			break
		await get_tree().process_frame
	assert(
		int(game.get("current_map_id")) == GameData.service_runtime_map_id(0),
		"resource commit fixture must wait for the formal mapped world",
	)
	assert(game.gameplay_input_is_enabled(), "resource commit fixture must wait for READY input")
	assert(not game._active_safe_zones.is_empty(), "resource commit fixture needs the formal safe-zone context")

const Router := preload("res://scripts/skills/skill_runtime_router.gd")
