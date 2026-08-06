class_name PersistentGroundEffectTestFixtures
extends RefCounted

## Q2-B: shared fixture rig for the persistent ground effect tests. Effects are
## created through the formal production entry (CasterSkillRuntime.create_ground_effects)
## and registered into a PersistentGroundEffectManager backed by one shared
## RuntimeCombatSpatialIndex instance. Enemies are registered exactly once.

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const CasterRuntime := preload("res://scripts/caster_skill_runtime.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const ManagerScript := preload(
	"res://scripts/persistent_ground_effect_manager.gd"
)

const SNAPSHOT_CONTEXT_META := &"q2b_snapshot_expected_context"


static func new_manager(
	index: SpatialIndexScript
) -> ManagerScript:
	return ManagerScript.new(index)


static func make_enemy(
	host: Node,
	index: SpatialIndexScript,
	serial: int,
	map_id: int,
	center_ground_gu: Vector2,
	combat_radius_gu := 0.25,
	hp := 10000
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{
			"name": "q2b_enemy_%d" % serial,
			"hp": hp,
			"attackMin": 1,
			"attackMax": 1,
			"level": 1,
		},
		null,
		false
	)
	enemy.configure_runtime_map_projection(
		map_id,
		Callable(host, "_ground_to_screen")
	)
	enemy.configure_spatial_index(index, serial)
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	enemy.combat_radius_gu = combat_radius_gu
	host.add_child(enemy)
	index.register(
		serial,
		map_id,
		center_ground_gu,
		combat_radius_gu,
		serial,
		enemy,
		Callable(enemy, "spatial_index_position")
	)
	return enemy


static func absolute_context(
	host: Node,
	map_id: int
) -> Dictionary:
	return Snapshot.make_absolute_runtime_context(
		map_id,
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(host, "_ground_to_screen")
	)


static func create_effect(
	host: Node,
	skill_id: String,
	release_id: String,
	map_id: int,
	center_ground_gu: Vector2,
	radius_gu: float,
	tick_interval_s: float,
	duration_s: float,
	damage: int,
	caster: Node2D,
	damage_applier: Callable
) -> GroundSkillEffect:
	var context := absolute_context(host, map_id)
	var snapshot := Snapshot.create_circle(
		skill_id,
		release_id,
		center_ground_gu,
		radius_gu,
		16,
		context
	)
	var plan := {
		"skill_id": skill_id,
		"operation": "ground_dot",
		"visual": {"role": "ground_effect"},
		"success": true,
		"release_id": release_id,
		"damage": damage,
		"duration_seconds": duration_s,
		"tick_interval_seconds": tick_interval_s,
		"visual_radius_px": 22.08,
		"snapshot_coordinate_context": context,
		"skill_footprint_snapshot": snapshot,
	}
	var effects: Array[GroundSkillEffect] = CasterRuntime.create_ground_effects(
		plan,
		Vector2.ZERO,
		Color.WHITE,
		caster
	)
	assert(
		not effects.is_empty(),
		"formal ground effect production entry must create at least one effect"
	)
	var effect := effects[0] as GroundSkillEffect
	effect.configure_runtime_resolution(
		caster,
		damage_applier,
		true,
		Callable(host, "_snapshot_contains_enemy").bind(snapshot),
		Callable(host, "_screen_to_ground")
	)
	effect.set_meta(SNAPSHOT_CONTEXT_META, context)
	return effect


static func register_effect(
	manager: ManagerScript,
	effect: GroundSkillEffect,
	effect_runtime_id: int,
	map_id: int,
	damage_applier: Callable,
	lifecycle_applier := Callable()
) -> bool:
	effect.manager_owned_damage_ticks = true
	var snapshot: Dictionary = effect.skill_footprint_snapshot
	return manager.register({
		"effect_runtime_id": effect_runtime_id,
		"skill_id": effect.skill_id,
		"release_id": effect.release_id,
		"snapshot_id": str(snapshot.get("snapshot_id", effect.release_id)),
		"runtime_map_id": map_id,
		"caster_reference": effect.source_actor,
		"canonical_snapshot": snapshot,
		"expected_context": effect.get_meta(SNAPSHOT_CONTEXT_META, {}),
		"tick_interval_s": effect.tick_interval,
		"expiration_s": effect.duration,
		"stacking_policy": "per_effect_independent",
		"claim_policy": "effect_claim_only",
		"damage_callback": damage_applier,
		"lifecycle_callback": lifecycle_applier,
		"manager_owned_damage_ticks": true,
		"effect": effect,
	})
