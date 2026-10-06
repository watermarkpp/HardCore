extends RefCounted

## Shared fixture for the Q3 formal skill-entry tests.  It deliberately uses
## the authored mapped world and GameRoot's spawn/position transactions so a
## test cannot accidentally pass or fail on a raw screen-space offset.

const FIXTURE_GROUND_POSITION := Vector2(40.5, 13.5)
const CASTER_GROUND_OFFSET := Vector2(-2.0, 0.0)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const FormalInitialReady := preload("res://tests/helpers/formal_initial_ready.gd")


static func target_screen_position(game: Node) -> Vector2:
	return game._canonical_ground_gu_to_screen_px(FIXTURE_GROUND_POSITION)


## Publish the complete test target set once, before accepting any work.
## Descriptors: id, ground OR position, respawn (default -1), and context
## containing the stable spawn_slot_id (or authored spawn_group_id fallback).
static func publish_targets(
	owner: Node,
	game: Node,
	descriptors: Array[Dictionary],
	label: String,
) -> Array[EnemyActor]:
	await wait_for_formal_world(owner, game, label)
	var plan: Array[Dictionary] = descriptors.duplicate(true)
	var slots: Array[String] = []
	for descriptor: Dictionary in plan:
		var context: Dictionary = descriptor.get("context", {})
		var slot := str(context.get("spawn_slot_id", context.get("spawn_group_id", "")))
		assert(not slot.is_empty() and slot not in slots, "%s requires unique stable target slots" % label)
		assert(not GameData.get_monster_by_id(int(descriptor.get("id", -1))).is_empty(),
			"%s target needs an exact canonical monster ID" % label)
		assert(descriptor.has("ground") or descriptor.has("position"), "%s target needs authored geometry" % label)
		slots.append(slot)
	var map_id: int = game.current_map_id
	var zone: String = game.current_zone
	var map_data: Dictionary = game.current_map_data.duplicate(true)
	var operation := func():
		# This is the real map retirement/republication path. Keep every
		# authored normal descriptor, then collect all fixture targets together.
		game._load_zone(zone, true, map_data)
		for descriptor: Dictionary in plan:
			var position: Vector2 = descriptor.get("position", Vector2.INF)
			if descriptor.has("ground"):
				position = game._canonical_ground_gu_to_screen_px(descriptor.ground)
			assert(position.is_finite(), "%s target needs a finite map projection" % label)
			game._spawn_enemy(GameData.get_monster_by_id(int(descriptor.id)), position, false,
				float(descriptor.get("respawn", -1.0)), descriptor.get("context", {}))
	var deadline_ms: int = Time.get_ticks_msec() + 5000
	var started: bool = game._begin_map_transition(operation, map_id)
	assert(started, "%s must publish through the real map transition owner" % label)
	while game._map_transition_in_progress and Time.get_ticks_msec() < deadline_ms:
		await owner.get_tree().process_frame
	assert(not game._map_transition_in_progress and game.gameplay_input_is_enabled()
		and Time.get_ticks_msec() <= deadline_ms,
		"%s republication must complete READY within the original fixture deadline" % label)
	assert(game.current_map_id == map_id and bool(game.feature_world_capacity_bound().sealed),
		"%s must preserve the formal map and publish a sealed complete plan" % label)
	var targets: Array[EnemyActor] = []
	for index in range(plan.size()):
		var target: EnemyActor
		for value: Variant in game._active_enemy_cache.values():
			if not is_instance_valid(value) or not value is EnemyActor: continue
			var candidate := value as EnemyActor
			if candidate.is_queued_for_deletion(): continue
			if str(candidate.get_meta("spawn_slot_id", "")) != slots[index]: continue
			if candidate.monster_id != int(plan[index].id) or candidate.runtime_map_id != map_id: continue
			if int(candidate.get_meta("zone_generation", -1)) != game._zone_generation: continue
			target = candidate
			break
		assert(target != null, "%s published target slot must materialize: %s" % [label, slots[index]])
		targets.append(target)
	return targets


static func prepare_target(
	owner: Node,
	game: Node,
	caster: PlayerCharacter,
	monster_id: int,
	label: String,
) -> EnemyActor:
	var descriptors: Array[Dictionary] = [{"id": monster_id, "ground": FIXTURE_GROUND_POSITION,
		"respawn": -1.0, "context": {"respawn_enabled": false,
			"spawn_slot_id": "test:formal_skill:%s:%d" % [label, monster_id]}}]
	var targets := await prepare_published_target_set(owner, game, caster, descriptors, label)
	return targets[0] if not targets.is_empty() else null


## Prepare the first receiver as before, retaining every published fixture
## receiver in place while relocating only the authored ambient population.
static func prepare_published_target_set(
	owner: Node,
	game: Node,
	caster: PlayerCharacter,
	descriptors: Array[Dictionary],
	label: String,
) -> Array[EnemyActor]:
	var targets := await publish_targets(owner, game, descriptors, label)
	var monster_id: int = int(descriptors[0].id) if not descriptors.is_empty() else -1
	var target: EnemyActor = targets[0] if not targets.is_empty() else null
	# Later receivers used to be born after this preparation frame. Temporarily
	# stop their physics here; restore the original flags before caller setup.
	var later_physics_flags: Array[bool] = []
	for index in range(1, targets.size()):
		later_physics_flags.append(targets[index].is_physics_processing())
		targets[index].set_physics_process(false)
	var caster_ground: Vector2 = FIXTURE_GROUND_POSITION + CASTER_GROUND_OFFSET
	var caster_position: Vector2 = game._canonical_ground_gu_to_screen_px(caster_ground)
	assert(caster_position.is_finite(), "%s caster needs a finite map projection" % label)
	game._set_player_world_position(caster_position)
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			caster_ground, game._active_safe_zones),
		"%s caster must be outside the authored safe area" % label,
	)
	for value: Variant in game._active_enemy_cache.values():
		if value is EnemyActor and value not in targets:
			(value as EnemyActor).set_combat_position(
				caster.global_position + Vector2(3000.0, 3000.0), &"test_fixture_clear")
	assert(
		not WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			FIXTURE_GROUND_POSITION, game._active_safe_zones),
		"%s target must be outside the authored safe area" % label,
	)
	assert(
		target != null and target.monster_id == monster_id and not target.is_boss
			and target.runtime_map_id == int(game.get("current_map_id"))
			and target.projection_ready() and target.spatial_actor_runtime_id > 0,
		"%s target must use the formal exact-ID mapped spawn" % label,
	)
	if target == null: return targets
	target.max_hp = 9999
	target.current_hp = target.max_hp
	target.control_time = 60.0
	target.set_physics_process(false)
	await owner.get_tree().process_frame
	for index in range(1, targets.size()):
		targets[index].set_physics_process(later_physics_flags[index - 1])
	assert(game._combat_target_world_clear(target, caster.global_position, true),
		"%s target must have a clear WORLD path" % label)
	return targets


static func wait_for_formal_world(owner: Node, game: Node, label: String) -> void:
	# 2026-10-06 fixture migration: the original five-second poll predated the
	# staged asynchronous bootstrap and failed before any publication logic.
	# The shared helper now waits for the full formal initial-READY contract;
	# its 60s ceiling is the production fail-safe window, not a startup
	# performance PASS threshold (startup stays OPEN / PRODUCT SLA MISSING).
	# The original assertion set below is kept unchanged. The separate
	# republication deadline inside publish_targets() is a different contract
	# and is intentionally untouched.
	await FormalInitialReady.wait_for_initial_ready(owner, game, label)
	assert(
		int(game.get("current_map_id")) == GameData.service_runtime_map_id(0),
		"%s must wait for the formal mapped world" % label,
	)
	assert(game.gameplay_input_is_enabled(), "%s must wait for READY input" % label)
	assert(not game._active_safe_zones.is_empty(), "%s needs the formal safe-zone context" % label)
