extends Node

const Fixtures := preload(
	"res://tests/helpers/combat_absolute_ground_fixtures.gd"
)
const Mapper := preload("res://scripts/map_coordinate_mapper.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)

const MAP_ID := 9001
const EPSILON := 0.0002

var _index: SpatialIndexScript
var _summon: SummonActor
var _enemy: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_index = SpatialIndexScript.new()
	var spawn_abs := Vector2(130.0, 130.0)
	var target_abs := Vector2(131.2, 130.0)
	_summon = SummonActor.new()
	_summon.setup(null, "神兽", 10, 1, "taoist.summon_divine_beast", 35)
	_summon.global_position = Mapper.ground_position_gu_to_screen_position_px(
		spawn_abs,
		Fixtures.DESIGN_256
	)
	_summon.configure_runtime_map_projection(
		MAP_ID,
		Fixtures.ground_to_screen(Fixtures.DESIGN_256),
		Fixtures.screen_to_ground(Fixtures.DESIGN_256)
	)
	add_child(_summon)
	_summon.set_process(false)
	_summon.set_physics_process(false)
	_summon.configure_spawn_release_footprint("p0:summon:1")
	var spawn_snapshot: Dictionary = _summon.summon_spawn_footprint_snapshot
	assert(
		(spawn_snapshot.get("origin_ground_gu", Vector2.ZERO) as Vector2)
		.distance_to(spawn_abs) <= EPSILON,
		"summon spawn snapshot origin must be absolute map ground"
	)
	assert(
		str(spawn_snapshot.get("coordinate_space", ""))
		== Snapshot.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU,
		"summon spawn snapshot must declare absolute coordinate space"
	)
	_enemy = Fixtures.make_enemy(
		self,
		_index,
		1,
		MAP_ID,
		target_abs,
		Fixtures.DESIGN_256,
		0.3
	)
	var attack_snapshot: Dictionary = (
		_summon.create_attack_release_footprint_snapshot(_enemy)
	)
	assert(
		(attack_snapshot.get("origin_ground_gu", Vector2.ZERO) as Vector2)
		.distance_to(spawn_abs) <= EPSILON,
		"summon attack snapshot origin must be absolute map ground"
	)
	assert(
		bool(_summon.attack_release_snapshot_intersects_target(
			attack_snapshot,
			_enemy
		)),
		"summon attack exact phase must hit the absolute-registered enemy"
	)
	_cleanup()
	await get_tree().process_frame
	print(
		"SUMMON_ABSOLUTE_SNAPSHOT_PASS spawn=%s attack_origin=%s"
		% [
			spawn_snapshot.get("origin_ground_gu", Vector2.ZERO),
			attack_snapshot.get("origin_ground_gu", Vector2.ZERO),
		]
	)
	get_tree().quit(0)


func _cleanup() -> void:
	for node: Node in get_children():
		node.queue_free()
