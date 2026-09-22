extends Node

const Migrator := preload(
	"res://tools/map_editor/formal_runtime_collision_contract_migrator.gd"
)
const JsonCodec := preload(
	"res://scripts/map_editor/map_editor_json_codec.gd"
)
const RuntimeCollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

const FIXTURE_ROOT := "user://formal_runtime_collision_contract_migrator/"
const REGISTRY_PATH := FIXTURE_ROOT + "map_runtime_release_registry.json"
const BICH_KEY := "world_bich_province"
const MENGZHONG_KEY := "world_mengzhong_province"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var cli_scene: Variant = load(
		"res://tools/map_editor/migrate_formal_runtime_collision_contract.tscn"
	)
	assert(cli_scene is PackedScene, "formal migration scene entry failed to load")
	_assert_cli_selection_contract()
	_assert_exact_selection_preflights_every_formal_map()
	_reset_fixture()
	var original := _write_fixture()
	var migrator := Migrator.new()
	var exact := migrator.migrate(
		{"map_key": MENGZHONG_KEY},
		{
			"registry_path": REGISTRY_PATH,
			"runtime_root": FIXTURE_ROOT,
			"expected_formal_count": 2,
		}
	)
	assert(bool(exact.get("ok", false)), str(exact))
	assert(int(exact.get("changed_count", 0)) == 1, str(exact))
	_assert_exact_migration(original)

	_reset_fixture()
	original = _write_fixture()
	migrator = Migrator.new()
	migrator.test_fail_after_promotions = 1
	var forced_failure := migrator.migrate(
		{"all_formal": true},
		{
			"registry_path": REGISTRY_PATH,
			"runtime_root": FIXTURE_ROOT,
			"expected_formal_count": 2,
		}
	)
	assert(not bool(forced_failure.get("ok", true)), str(forced_failure))
	assert(
		str(forced_failure.get("error", "")).begins_with(
			"forced_commit_failure:rollback=true"
		),
		str(forced_failure)
	)
	_assert_fixture_bytes(original)

	migrator = Migrator.new()
	var all_formal := migrator.migrate(
		{"all_formal": true},
		{
			"registry_path": REGISTRY_PATH,
			"runtime_root": FIXTURE_ROOT,
			"expected_formal_count": 2,
		}
	)
	assert(bool(all_formal.get("ok", false)), str(all_formal))
	assert(int(all_formal.get("changed_count", 0)) == 2, str(all_formal))
	var final_registry := _read_json(REGISTRY_PATH)
	for entry: Dictionary in final_registry.maps:
		var runtime := _read_json(str(entry.runtime_path))
		assert(
			str(runtime.collision.coordinate_contract_id)
			== RuntimeCollisionGeometry.CONTRACT_ID
		)
		assert(str(entry.approved_build_sha256) == str(runtime.build_sha256))
	_reset_fixture()
	print(
		"FORMAL_RUNTIME_COLLISION_CONTRACT_MIGRATOR_PASS exact=1 all=2 rollback=1"
	)
	get_tree().quit(0)


func _assert_exact_selection_preflights_every_formal_map() -> void:
	_reset_fixture()
	var original := _write_fixture()
	var registry := _read_json(REGISTRY_PATH)
	registry.maps[0]["approved_build_sha256"] = "0".repeat(64)
	_write_json(REGISTRY_PATH, registry)
	original.texts["registry"] = _read_text(REGISTRY_PATH)
	var result := Migrator.new().migrate(
		{"map_key": MENGZHONG_KEY},
		{
			"registry_path": REGISTRY_PATH,
			"runtime_root": FIXTURE_ROOT,
			"expected_formal_count": 2,
		}
	)
	assert(not bool(result.get("ok", true)), str(result))
	assert(
		str(result.get("error", ""))
		== "registry_runtime_hash_mismatch:%s" % BICH_KEY,
		str(result)
	)
	_assert_fixture_bytes(original)
	_reset_fixture()


func _assert_cli_selection_contract() -> void:
	assert(not bool(Migrator.parse_cli_args(PackedStringArray()).get("ok", true)))
	assert(not bool(Migrator.parse_cli_args(PackedStringArray([
		"--all-formal", "--map=world_bich_province",
	])).get("ok", true)))
	assert(not bool(Migrator.parse_cli_args(PackedStringArray([
		"--map=../unsafe",
	])).get("ok", true)))
	assert(bool(Migrator.parse_cli_args(PackedStringArray([
		"--all-formal",
	])).get("ok", false)))
	assert(bool(Migrator.parse_cli_args(PackedStringArray([
		"--map=world_mengzhong_province",
	])).get("ok", false)))


func _write_fixture() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(FIXTURE_ROOT)
	)
	var bich := _runtime(BICH_KEY, 990101, false)
	var mengzhong := _runtime(MENGZHONG_KEY, 990102, true)
	_write_json(_runtime_path(BICH_KEY), bich)
	_write_json(_runtime_path(MENGZHONG_KEY), mengzhong)
	_rewrite_as_crlf(_runtime_path(BICH_KEY))
	_rewrite_as_crlf(_runtime_path(MENGZHONG_KEY))
	var registry := {
		"schema_version": 1,
		"registry_contract_id": "mse.map.runtime.release.v1",
		"maps": [
			_entry(BICH_KEY, 990101, str(bich.build_sha256), 4),
			_entry(MENGZHONG_KEY, 990102, str(mengzhong.build_sha256), 7),
		],
	}
	_write_json(REGISTRY_PATH, registry)
	registry = _read_json(REGISTRY_PATH)
	return {
		"bich": bich,
		"mengzhong": mengzhong,
		"registry": registry,
		"texts": {
			BICH_KEY: _read_text(_runtime_path(BICH_KEY)),
			MENGZHONG_KEY: _read_text(_runtime_path(MENGZHONG_KEY)),
			"registry": _read_text(REGISTRY_PATH),
		},
	}


func _runtime(map_key: String, runtime_map_id: int, mengzhong: bool) -> Dictionary:
	var monster_spawn := {
		"kind": "monster_spawn",
		"semantic_id": "spawn.%s" % map_key,
		"spawn_group_id": "group.%s" % map_key,
		"monster_id": 137 if mengzhong else 1,
		"radius_gu": 8.0,
		"respawn_policy_id": "special_normal_900s" if mengzhong else "normal_300s",
		"respawn_seconds": 900 if mengzhong else 300,
		"tile": [67.0, 42.0] if mengzhong else [12.0, 14.0],
	}
	var runtime := {
		"build_sha256": "",
		"runtime_schema_version": 2,
		"unit_contract_id": "ground_unit.v1",
		"projection_contract_id": "ground_absolute_projection.v1",
		"source": {
			"map_id": map_key,
			"runtime_map_id": runtime_map_id,
			"display_name": "盟重省" if mengzhong else "比奇省",
			"candidate_binding": {
				"document_sha256": "fixture_document",
				"authoring_sha256": "fixture_authoring",
			},
		},
		"design": {"design_size": [128.0, 128.0]},
		"ground": {
			"ground_mode": "authored",
			"default_fill_asset_id": "ground.fixture",
			"tile_overrides": {},
		},
		"instances": [{
			"instance_id": "inst_000026" if mengzhong else "inst_000001",
			"asset_id": "fixture.asset",
			"tile": [67.0, 42.0] if mengzhong else [12.0, 14.0],
			"runtime_export": true,
		}],
		"collision": {
			"coordinate_contract_id": Migrator.LEGACY_COLLISION_CONTRACT_ID,
			"physics_source_id": "published_blocked_cells_after_erasure_v1",
			"blocked_tiles": ["1,1"],
			"blocked_count": 1,
			"manual_shapes": [],
			"erased_cells": [],
		},
		"semantics": {
			"monster_spawn": [monster_spawn],
			"boss_spawn": [],
			"npc_points": [],
			"door_points": [],
			"map_entrance_points": [],
			"map_exit_points": [],
			"respawn_points": [{
				"semantic_id": "respawn.%s" % map_key,
				"kind": "respawn_point",
				"tile": [64.0, 64.0],
			}],
			"safe_area": [],
			"light": [],
			"region_trigger": [],
		},
	}
	# Match MapEditorBuildRuntimeService._compile_runtime_with_hash: normalize
	# JSON number representations before the canonical build hash is frozen.
	var normalized: Variant = JSON.parse_string(JsonCodec.encode(runtime))
	assert(normalized is Dictionary)
	runtime = normalized
	runtime["build_sha256"] = Migrator.runtime_build_sha256(runtime)
	return runtime


func _entry(
	map_key: String,
	runtime_map_id: int,
	approved_hash: String,
	revision: int
) -> Dictionary:
	return {
		"approval_revision": revision,
		"approval_source": "test_fixture",
		"approved_build_sha256": approved_hash,
		"display_name": map_key,
		"map_key": map_key,
		"release_state": "implemented_playable",
		"runtime_map_id": runtime_map_id,
		"runtime_path": _runtime_path(map_key),
	}


func _assert_exact_migration(original: Dictionary) -> void:
	assert(
		_read_text(_runtime_path(BICH_KEY)) == str(original.texts[BICH_KEY]),
		"unselected formal runtime changed"
	)
	var after := _read_json(_runtime_path(MENGZHONG_KEY))
	assert(
		not _read_text(_runtime_path(MENGZHONG_KEY)).contains("\r\n"),
		"migrated runtime was not normalized to canonical LF",
	)
	var before: Dictionary = original.mengzhong
	assert(
		str(after.collision.coordinate_contract_id)
		== RuntimeCollisionGeometry.CONTRACT_ID
	)
	assert(str(after.build_sha256) != str(before.build_sha256))
	assert(
		str(after.build_sha256) == Migrator.runtime_build_sha256(after),
		"runtime hash did not use canonical build algorithm"
	)
	var restored := after.duplicate(true)
	restored["build_sha256"] = before.build_sha256
	restored.collision["coordinate_contract_id"] = (
		before.collision.coordinate_contract_id
	)
	assert(restored == before, "runtime payload changed outside allowed fields")
	assert(
		after.semantics == before.semantics,
		"Mengzhong respawn/semantic fields changed"
	)
	assert(
		after.semantics.monster_spawn
		== before.semantics.monster_spawn,
		"Mengzhong monster respawn policy changed"
	)
	assert(
		after.semantics.respawn_points
		== before.semantics.respawn_points,
		"Mengzhong respawn points changed"
	)
	var registry := _read_json(REGISTRY_PATH)
	assert(registry.maps[0] == original.registry.maps[0])
	var target_entry: Dictionary = registry.maps[1]
	var old_target_entry: Dictionary = original.registry.maps[1]
	assert(int(target_entry.runtime_map_id) == int(old_target_entry.runtime_map_id))
	assert(int(target_entry.approval_revision) == 8)
	assert(str(target_entry.approved_build_sha256) == str(after.build_sha256))
	target_entry["approval_revision"] = old_target_entry.approval_revision
	target_entry["approved_build_sha256"] = old_target_entry.approved_build_sha256
	assert(target_entry == old_target_entry, "registry changed outside allowlist")


func _assert_fixture_bytes(original: Dictionary) -> void:
	assert(_read_text(_runtime_path(BICH_KEY)) == str(original.texts[BICH_KEY]))
	assert(
		_read_text(_runtime_path(MENGZHONG_KEY))
		== str(original.texts[MENGZHONG_KEY])
	)
	assert(_read_text(REGISTRY_PATH) == str(original.texts.registry))


func _runtime_path(map_key: String) -> String:
	return FIXTURE_ROOT + map_key + ".runtime.json"


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot write fixture %s" % path)
	file.store_string(JsonCodec.encode(value))
	file.close()


func _rewrite_as_crlf(path: String) -> void:
	var text := _read_text(path)
	assert(not text.contains("\r"), "fixture unexpectedly contains CR")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot rewrite CRLF fixture %s" % path)
	file.store_string(text.replace("\n", "\r\n"))
	file.close()


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_text(path))
	return parsed if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "cannot read fixture %s" % path)
	var text := file.get_as_text()
	file.close()
	return text


func _reset_fixture() -> void:
	var absolute := ProjectSettings.globalize_path(FIXTURE_ROOT)
	if DirAccess.dir_exists_absolute(absolute):
		_remove_tree(absolute)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name in [".", ".."]:
			continue
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
