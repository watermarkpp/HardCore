class_name CombatAbsoluteGroundFixtures
extends RefCounted

## FREEZE-P0 shared fixture rig: every fixture uses a REAL non-zero map center
## (design_size -> center) and the formal map-aware absolute Ground GU
## conversions. Identity fixtures are never used as primary evidence here.

const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const FireWallControllerScript := preload(
	"res://scripts/fire_wall_field_controller.gd"
)

const DESIGN_256 := Vector2i(256, 256)
const DESIGN_300x200 := Vector2i(300, 200)


static func map_center(design_size: Vector2i) -> Vector2:
	return (Vector2(design_size) - Vector2.ONE) * 0.5


static func screen_to_ground(design_size: Vector2i) -> Callable:
	return func(screen_position_px: Vector2) -> Vector2:
		return Mapper.screen_position_px_to_ground_position_gu(
			screen_position_px,
			design_size
		)


static func ground_to_screen(design_size: Vector2i) -> Callable:
	return func(ground_position_gu: Vector2) -> Vector2:
		return Mapper.ground_position_gu_to_screen_position_px(
			ground_position_gu,
			design_size
		)


static func absolute_context(
	map_id: int,
	origin_ground_gu: Vector2,
	design_size: Vector2i
) -> Dictionary:
	var context := Snapshot.make_absolute_runtime_context(
		map_id,
		origin_ground_gu,
		origin_ground_gu,
		ground_to_screen(design_size)
	)
	context["expected_runtime_map_id"] = map_id
	return context


static func make_enemy(
	host: Node,
	index: SpatialIndexScript,
	serial: int,
	map_id: int,
	absolute_center_ground_gu: Vector2,
	design_size: Vector2i,
	combat_radius_gu := 0.3
) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup(
		{
			"name": "p0_abs_%d" % serial,
			"hp": 99999,
			"attackMin": 1,
			"attackMax": 1,
			"level": 1,
		},
		null,
		false
	)
	enemy.configure_runtime_map_projection(
		map_id,
		ground_to_screen(design_size),
		screen_to_ground(design_size)
	)
	enemy.configure_spatial_index(index, serial)
	enemy.global_position = Mapper.ground_position_gu_to_screen_position_px(
		absolute_center_ground_gu,
		design_size
	)
	enemy.combat_radius_gu = combat_radius_gu
	enemy.set_meta("spawn_position", enemy.global_position)
	host.add_child(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	index.register(
		serial,
		map_id,
		absolute_center_ground_gu,
		combat_radius_gu,
		serial,
		enemy,
		Callable(enemy, "spatial_index_position")
	)
	return enemy


static func move_enemy_absolute(
	enemy: EnemyActor,
	new_absolute_ground_gu: Vector2,
	design_size: Vector2i,
	reason := &"p0_forced"
) -> void:
	enemy.set_combat_position(
		Mapper.ground_position_gu_to_screen_position_px(
			new_absolute_ground_gu,
			design_size
		),
		reason
	)


static func make_projectile(
	host: Node,
	index: SpatialIndexScript,
	map_id: int,
	origin_absolute_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	design_size: Vector2i,
	maximum_distance_gu := 12.0,
	projectile_radius_gu := 0.2
) -> SkillProjectile:
	var projectile := SkillProjectile.new()
	projectile.setup_ground_unit_projectile(
		Mapper.ground_position_gu_to_screen_position_px(
			origin_absolute_ground_gu,
			design_size
		),
		direction_ground_gu.normalized(),
		maximum_distance_gu,
		7,
		4.0,
		projectile_radius_gu
	)
	projectile.configure_runtime_map_projection(
		map_id,
		ground_to_screen(design_size),
		screen_to_ground(design_size)
	)
	projectile.configure_spatial_index(index)
	host.add_child(projectile)
	return projectile


static func make_fire_wall_controller(
	host: Node,
	index: SpatialIndexScript,
	map_id: int,
	origin_absolute_ground_gu: Vector2,
	design_size: Vector2i,
	damage_applier: Callable,
	caster: Node2D,
	release_id := "p0:fw:1",
	radius_gu := 0.5
) -> FireWallControllerScript:
	var context := absolute_context(map_id, origin_absolute_ground_gu, design_size)
	var cells: Array[Vector2i] = [
		Vector2i(roundi(origin_absolute_ground_gu.x), roundi(origin_absolute_ground_gu.y)),
		Vector2i(roundi(origin_absolute_ground_gu.x) + 1, roundi(origin_absolute_ground_gu.y)),
		Vector2i(roundi(origin_absolute_ground_gu.x), roundi(origin_absolute_ground_gu.y) + 1),
		Vector2i(roundi(origin_absolute_ground_gu.x) + 1, roundi(origin_absolute_ground_gu.y) + 1),
	]
	var snapshot := SpellGeometry.create_exact_cell_union_release_snapshot(
		"wizard.fire_wall",
		release_id,
		origin_absolute_ground_gu,
		cells,
		context
	)
	var positions: Array[Vector2] = []
	for cell: Vector2i in cells:
		positions.append(
			Mapper.ground_position_gu_to_screen_position_px(
				Vector2(cell) + Vector2(0.5, 0.5),
				design_size
			)
		)
	var empty_filters: Array[Callable] = []
	var controller := FireWallControllerScript.new()
	controller.setup_fire_wall_field(
		caster,
		"wizard.fire_wall",
		{
			"raw_power": 11,
			"radius_gu": radius_gu,
			"duration_seconds": 2.0,
			"tick_interval_ms": 1000,
		},
		positions,
		cells,
		empty_filters,
		damage_applier,
		screen_to_ground(design_size),
		release_id,
		snapshot,
		context,
		index,
		map_id
	)
	host.add_child(controller)
	controller.set_physics_process(false)
	return controller
