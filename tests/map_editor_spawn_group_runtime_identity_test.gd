extends Node

const GameRootScript := preload("res://scripts/game_root.gd")


func _ready() -> void:
	var bridged_ordinary := {
		"spawn_group": {
			"spawn_group_id": "map:world_bich_province:ordinary:forest_01",
			"semantic_id": "monster_spawn_000001",
		}
	}
	assert(
		GameRootScript._editor_spawn_group_id(
			bridged_ordinary, 910001, 0, false
		) == "map:world_bich_province:ordinary:forest_01"
	)

	var direct_ordinary := {
		"spawn_group_id": "map:world_bich_province:ordinary:forest_02",
		"spawnGroupId": "retired-camel-id",
	}
	assert(
		GameRootScript._editor_spawn_group_id(
			direct_ordinary, 910001, 1, false
		) == "map:world_bich_province:ordinary:forest_02"
	)

	var legacy_group := {"spawn_group": {"id": "legacy:stable-group"}}
	assert(
		GameRootScript._editor_spawn_group_id(
			legacy_group, 910001, 2, false
		) == "legacy:stable-group"
	)
	assert(
		GameRootScript._editor_spawn_group_id(
			{}, 910001, 3, false
		) == "editor:910001:3"
	)
	assert(
		GameRootScript._editor_spawn_group_id(
			{}, 915003, 0, true
		) == "editor:915003:boss:0"
	)

	print("MAP_EDITOR_SPAWN_GROUP_RUNTIME_IDENTITY_PASS")
	get_tree().quit(0)
