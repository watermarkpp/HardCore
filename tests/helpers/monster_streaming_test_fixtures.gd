class_name MonsterStreamingTestFixtures
extends RefCounted

## Q2-D shared fixture rig: creates the single coordinator, installs it as the
## static access path, and spawns real EnemyActor/MonsterVisual instances.

const CoordinatorScript := preload(
	"res://scripts/monster_visual_streaming_coordinator.gd"
)
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

static var _catalog_ids: Array[int] = []


static func catalog_ids() -> Array[int]:
	if not _catalog_ids.is_empty():
		return _catalog_ids
	var catalog_file := FileAccess.open(
		"res://assets/data/runtime/monster_animation_catalog.json",
		FileAccess.READ,
	)
	var catalog: Variant = (
		JSON.parse_string(catalog_file.get_as_text())
		if catalog_file != null
		else null
	)
	assert(catalog is Dictionary)
	for row: Dictionary in (catalog as Dictionary).get("monsters", []):
		_catalog_ids.append(int(row.monster_id))
	assert(_catalog_ids.size() == 214, "catalog must contain 214 monster ids")
	return _catalog_ids


static func make_coordinator():
	var coordinator := CoordinatorScript.new()
	MonsterVisual.set_streaming_coordinator(coordinator)
	return coordinator


static func make_player(host: Node) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	host.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO
	return player


static func make_enemy(
	host: Node,
	player: PlayerCharacter,
	monster_id: int,
	serial: int,
	map_id := 1,
	position_px := Vector2.ZERO
) -> EnemyActor:
	var enemy := EnemyActor.new()
	var data := GameData.get_monster_by_id(monster_id)
	if data.is_empty():
		data = {
			"name": "monster_%d" % monster_id,
			"hp": 100,
			"attackMin": 1,
			"attackMax": 2,
			"level": 1,
			"monsterId": monster_id,
		}
	enemy.setup(data, player, false)
	enemy.configure_runtime_map_projection(
		map_id,
		Callable(host, "_ground_to_screen")
	, GroundUnit.screen_delta_px_to_ground_delta_gu)
	enemy.set_meta("spawn_serial", serial)
	enemy.global_position = position_px
	host.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


static func drive_residency_activation(
	visual: MonsterVisual,
	steps := 40
) -> void:
	## Mirrors the frozen actor residency path: each step forces the 0.12s
	## residency timer and runs one _process frame.
	for _step: int in range(steps):
		if not visual.active_resources.is_empty():
			break
		visual._resource_residency_timer = 0.0
		visual._process(0.13)
