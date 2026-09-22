extends Node

## MAP-SAFETY-R1: the formal identity contract for the former clone-workspace
## passages is now the snake_mine series:
##   connection_passage_1 -> snake_mine_passage_1 (runtime 912001)
##   connection_passage_2 -> snake_mine_passage_2 (runtime 912002)
## The formal documents carry two real portals each. Historical clone
## provenance in editor_meta (full_workspace_clone_without_exit_links_v1)
## describes where the workspaces came from; it is no longer interpreted as
## "the map must have no exits".

const SPECS := [
	{
		"map_id": "snake_mine_passage_1",
		"runtime_map_id": 912001,
		"legacy_map_id": "connection_passage_1",
		"expected_exit_keys": ["world_snake_valley", "snake_mine_passage_2"],
	},
	{
		"map_id": "snake_mine_passage_2",
		"runtime_map_id": 912002,
		"legacy_map_id": "connection_passage_2",
		"expected_exit_keys": ["snake_unknown_dark_palace", "snake_mine_passage_1"],
	},
]


func _ready() -> void:
	for spec: Dictionary in SPECS:
		var map_id := str(spec.map_id)
		var path := "res://map_editor_workspace/%s/%s.editor.json" % [map_id, map_id]
		var loaded := MapEditorLoadService.load_document(path, false)
		assert(loaded.ok, str(loaded.get("errors", [])))
		var document: Dictionary = loaded.document
		assert(str(document.map_id) == map_id)
		assert(int(document.runtime_map_id) == int(spec.runtime_map_id))
		assert(document.design.design_size == [50.0, 50.0])
		var exits: Array = document.layers.map_exit_points
		assert(exits.size() == 2, "%s exit count %d" % [map_id, exits.size()])
		var target_keys := {}
		for exit_point: Dictionary in exits:
			assert(bool(exit_point.get("runtime_export", false)), str(exit_point))
			assert(bool(exit_point.get("target_configured", false)), str(exit_point))
			target_keys[str(exit_point.get("target_map_key", ""))] = true
		var expected: Array = spec.expected_exit_keys
		assert(target_keys.size() == expected.size(), "%s exit keys %s" % [map_id, str(target_keys)])
		for key: String in expected:
			assert(target_keys.has(key), "%s missing exit %s" % [map_id, key])
		assert(str(document.ground.workspace_manifest).contains(map_id))
		assert(str(document.ground.workspace_state).contains(map_id))
		assert(FileAccess.file_exists("res://map_editor_workspace/%s/ground/ground_manifest.json" % map_id))
		assert(FileAccess.file_exists("res://map_editor_workspace/%s/ground/baked_preview/bake_manifest.json" % map_id))
		# Identity migration: the legacy connection_passage keys must resolve
		# to the formal snake_mine_passage workspaces.
		assert(
			MapEditorSaveService.canonical_workspace_path(
				MapEditorSaveService.default_path(str(spec.legacy_map_id))
			)
			== MapEditorSaveService.default_path(map_id),
			"legacy %s did not canonicalize to %s" % [str(spec.legacy_map_id), map_id]
		)

	print("MAP_WORKSPACE_CLONE_CATALOG_PASS")
	get_tree().quit(0)
