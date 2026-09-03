class_name FireWallControllerTestFixtures
extends RefCounted

## Q2-C: shared fixture rig for the formal FireWall controller tests. FireWalls
## are created through the production setup entry (setup_fire_wall_field) with
## one canonical 2x2 union snapshot and the shared RuntimeCombatSpatialIndex.
## The identity projection (ground_delta <-> screen_delta) makes canonical
## absolute ground GU equal the index's coordinate space, keeping fixtures
## deterministic.

const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const FireWallFieldControllerScript := preload(
	"res://scripts/fire_wall_field_controller.gd"
)

const SKILL_ID := "wizard.fire_wall"


static func make_controller(
	host: Node,
	index: SpatialIndexScript,
	map_id: int,
	anchor_ground_gu: Vector2,
	effect: Dictionary,
	release_id: String,
	caster: Node2D,
	damage_applier: Callable,
	origin_cell := Vector2i.ZERO
) -> FireWallFieldControllerScript:
	var context := Snapshot.make_absolute_runtime_context(
		map_id,
		anchor_ground_gu,
		anchor_ground_gu,
		Callable(host, "_ground_to_screen")
	)
	context["expected_runtime_map_id"] = map_id
	var cells: Array[Vector2i] = [
		origin_cell,
		origin_cell + Vector2i.RIGHT,
		origin_cell + Vector2i.DOWN,
		origin_cell + Vector2i.ONE,
	]
	var snapshot := SpellGeometry.create_exact_cell_union_release_snapshot(
		SKILL_ID,
		release_id,
		anchor_ground_gu,
		cells,
		context
	)
	var positions: Array[Vector2] = []
	for cell: Vector2i in cells:
		positions.append(
			GroundUnit.ground_delta_gu_to_screen_delta_px(
				anchor_ground_gu + Vector2(cell)
			)
		)
	var coverage_cells: Array[Vector2i] = cells
	var empty_filters: Array[Callable] = []
	var controller := FireWallFieldControllerScript.new()
	controller.setup_fire_wall_field(
		caster,
		SKILL_ID,
		effect,
		positions,
		coverage_cells,
		empty_filters,
		damage_applier,
		Callable(host, "_screen_to_ground"),
		release_id,
		snapshot,
		context,
		index,
		map_id
	)
	host.add_child(controller)
	controller.set_physics_process(false)
	return controller


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
	enemy.setup(GameData.get_monster_by_id(19), null, false)
	enemy.max_hp = hp
	enemy.current_hp = hp
	enemy.configure_runtime_map_projection(
		map_id,
		Callable(host, "_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)
	enemy.configure_spatial_index(index, serial)
	enemy.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		center_ground_gu
	)
	enemy.combat_radius_gu = combat_radius_gu
	host.add_child(enemy)
	enemy.set_physics_process(false)
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
