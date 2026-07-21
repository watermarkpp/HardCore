extends Node

const OFFICIAL_VERSION_ID := "bich_orc_tomb_official_v1"
const MAP_IDS := [
	"bich_province",
	"orc_tomb_1",
	"orc_tomb_2",
	"orc_tomb_3",
]
const RUNTIME_IDS := [4, 217, 218, 221]


func _ready() -> void:
	var documents: Array[Dictionary] = []
	var runtimes: Array[Dictionary] = []
	for index in MAP_IDS.size():
		var map_id: String = MAP_IDS[index]
		var source := MapEditorLoadService.load_document(
			MapEditorSaveService.default_path(map_id)
		)
		assert(source.ok, "%s:%s" % [map_id, source.get("errors", [])])
		var document: Dictionary = source.document
		assert(int(document.runtime_map_id) == RUNTIME_IDS[index])
		assert(
			str(document.editor_meta.official_version_id)
			== OFFICIAL_VERSION_ID
		)
		assert(
			str(document.editor_meta.official_source_authority)
			== "user_saved_editor_document"
		)
		assert(bool(document.editor_meta.runtime_approved))
		var runtime_result := MapEditorRuntimeMapService.load_runtime(
			MapEditorBuildRuntimeService.default_runtime_path(map_id)
		)
		assert(
			runtime_result.ok,
			"%s_runtime:%s" % [map_id, runtime_result.get("errors", [])]
		)
		var runtime: Dictionary = runtime_result.runtime
		assert(str(runtime.source.map_id) == map_id)
		assert(
			int(runtime.source.revision)
			== int(document.editor_meta.revision)
		)
		assert(not str(runtime.build_sha256).is_empty())
		documents.append(document)
		runtimes.append(runtime)

	var bich_east: Dictionary = documents[0].layers.map_exit_points.filter(
		func(entry: Dictionary) -> bool:
			return str(entry.semantic_id) == "map_exit_000002"
	)[0]
	assert(bich_east.tile == [72.0, 5.0])
	assert(str(bich_east.target_map_key) == "orc_tomb_1")
	assert(int(bich_east.target_map_id) == 217)

	_assert_runtime_link(runtimes[1], runtimes[2])
	_assert_runtime_link(runtimes[2], runtimes[3])
	assert(runtimes[3].semantics.map_exit_points.is_empty())

	var floor_two_npcs: Array = runtimes[2].semantics.npc_points
	assert(floor_two_npcs.size() == 2)
	var npc_tiles := {}
	for npc: Dictionary in floor_two_npcs:
		npc_tiles[str(npc.npc_id)] = Vector2i(
			int(npc.tile[0]),
			int(npc.tile[1])
		)
		assert(not npc.has("editor_visual_asset_id"))
		assert(not npc.has("placeholder_instance_id"))
	assert(
		npc_tiles["npc.expansion.bich_pharmacist"]
		== Vector2i(2, 5)
	)
	assert(npc_tiles["npc.4.001"] == Vector2i(6, 3))
	assert(runtimes[3].semantics.npc_points.is_empty())

	var floor_three_spawns := {}
	for entry: Dictionary in (
		runtimes[3].semantics.monster_spawn
		+ runtimes[3].semantics.boss_spawn
	):
		floor_three_spawns[str(entry.semantic_id)] = Vector2i(
			int(entry.tile[0]),
			int(entry.tile[1])
		)
	assert(floor_three_spawns["boss_spawn_000003"] == Vector2i(32, 3))
	assert(floor_three_spawns["monster_spawn_000007"] == Vector2i(5, 6))
	assert(floor_three_spawns["monster_spawn_000024"] == Vector2i(11, 29))
	assert(floor_three_spawns["monster_spawn_000028"] == Vector2i(27, 10))
	assert(floor_three_spawns["monster_spawn_000030"] == Vector2i(32, 16))
	print(
		(
			"BICH_ORC_TOMB_OFFICIAL_MAPS_PASS maps=4 "
			+ "bich_exit=72,5 floor2_npcs=2 floor3_npcs=0"
		)
	)
	get_tree().quit(0)


func _assert_runtime_link(source: Dictionary, target: Dictionary) -> void:
	assert(source.semantics.map_exit_points.size() == 1)
	assert(target.semantics.map_entrance_points.size() == 1)
	var map_exit: Dictionary = source.semantics.map_exit_points[0]
	var entrance: Dictionary = target.semantics.map_entrance_points[0]
	assert(str(map_exit.target_map_id) == str(target.source.map_id))
	assert(str(map_exit.target_entrance_id) == str(entrance.entrance_id))
