extends RefCounted

## Shared fixture for the Q3 formal skill-entry tests.  It deliberately uses
## the authored mapped world and GameRoot's spawn/position transactions so a
## test cannot accidentally pass or fail on a raw screen-space offset.

const FIXTURE_GROUND_POSITION := Vector2(40.5, 13.5)
const CASTER_GROUND_OFFSET := Vector2(-2.0, 0.0)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")


static func target_screen_position(game: Node) -> Vector2:
	return game._canonical_ground_gu_to_screen_px(FIXTURE_GROUND_POSITION)


static func prepare_target(
	owner: Node,
	game: Node,
	caster: PlayerCharacter,
	monster_id: int,
	label: String,
) -> EnemyActor:
	await wait_for_formal_world(owner, game, label)
	var caster_ground: Vector2 = FIXTURE_GROUND_POSITION + CASTER_GROUND_OFFSET
	var caster_position: Vector2 = game._canonical_ground_gu_to_screen_px(caster_ground)
	assert(caster_position.is_finite(), "%s caster needs a finite map projection" % label)
	game._set_player_world_position(caster_position)
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			caster_ground,
			game._active_safe_zones,
		),
		"%s caster must be outside the authored safe area" % label,
	)
	for value: Variant in owner.get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).set_combat_position(
				caster.global_position + Vector2(3000.0, 3000.0),
				&"test_fixture_clear",
			)

	var target_ground := FIXTURE_GROUND_POSITION
	var target_position: Vector2 = game._canonical_ground_gu_to_screen_px(target_ground)
	assert(target_position.is_finite(), "%s target needs a finite map projection" % label)
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			target_ground,
			game._active_safe_zones,
		),
		"%s target must be outside the authored safe area" % label,
	)
	var canonical_data: Dictionary = GameData.get_monster_by_id(monster_id)
	assert(
		not canonical_data.is_empty(),
		"%s monster_id=%d must exist" % [label, monster_id],
	)
	var target: EnemyActor = game._spawn_enemy(
		canonical_data,
		target_position,
		false,
		-1.0,
		{
			"respawn_enabled": false,
			"spawn_slot_id": "test:formal_skill:%s:%d" % [label, monster_id],
		},
	)
	assert(
		target != null
			and target.monster_id == monster_id
			and not target.is_boss
			and target.runtime_map_id == int(game.get("current_map_id"))
			and target.projection_ready()
			and target.spatial_actor_runtime_id > 0,
		"%s target must use the formal exact-ID mapped spawn" % label,
	)
	if target == null:
		return null
	target.max_hp = 9999
	target.current_hp = target.max_hp
	target.control_time = 60.0
	target.set_physics_process(false)
	await owner.get_tree().process_frame
	assert(
		game._combat_target_world_clear(target, caster.global_position, true),
		"%s target must have a clear WORLD path" % label,
	)
	return target


static func wait_for_formal_world(owner: Node, game: Node, label: String) -> void:
	var deadline_ms: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline_ms:
		var current_map_id: int = int(game.get("current_map_id"))
		var input_enabled: bool = bool(game.call("gameplay_input_is_enabled"))
		if current_map_id >= 0 and input_enabled:
			break
		await owner.get_tree().process_frame
	assert(
		int(game.get("current_map_id")) == GameData.service_runtime_map_id(0),
		"%s must wait for the formal mapped world" % label,
	)
	assert(game.gameplay_input_is_enabled(), "%s must wait for READY input" % label)
	assert(not game._active_safe_zones.is_empty(), "%s needs the formal safe-zone context" % label)
