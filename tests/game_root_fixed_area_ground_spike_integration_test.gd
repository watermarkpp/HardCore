extends Node

const GameRootScript := preload("res://scripts/game_root.gd")
const MonsterGroundSpikeEffectScript := preload(
	"res://scripts/monster_ground_spike_effect.gd"
)


func _ready() -> void:
	var root := GameRootScript.new()
	root._zone_generation = 7
	var enemy := EnemyActor.new()
	enemy.monster_id = 180
	enemy.set_meta("zone_generation", 7)
	var descriptor := {
		"effect_id": MonsterGroundSpikeEffectScript.EFFECT_ID,
		"release_id": "area-release-1",
		"source_instance_id": enemy.get_instance_id(),
		"source_monster_id": 180,
		"target_world_px": Vector2(320.0, 240.0),
	}
	descriptor.make_read_only()
	root._on_enemy_fixed_area_ground_spike_requested(descriptor, enemy)
	assert(root.get_child_count() == 1, "valid descriptor must spawn one visual")
	var effect := root.get_child(0) as Node2D
	assert(effect != null)
	assert(effect.global_position == Vector2(320.0, 240.0))
	assert(str(effect.get("release_id")) == "area-release-1")

	var forged := descriptor.duplicate(true)
	forged["source_instance_id"] = enemy.get_instance_id() + 1
	forged.make_read_only()
	root._on_enemy_fixed_area_ground_spike_requested(forged, enemy)
	assert(root.get_child_count() == 1, "forged source must fail closed")

	enemy.set_meta("zone_generation", 6)
	root._on_enemy_fixed_area_ground_spike_requested(descriptor, enemy)
	assert(root.get_child_count() == 1, "stale zone release must fail closed")

	root.free()
	enemy.free()
	print("GAME_ROOT_FIXED_AREA_GROUND_SPIKE_INTEGRATION_PASS")
	get_tree().quit(0)
