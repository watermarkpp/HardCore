extends Node

const RUNTIME_PATH := (
	"res://assets/data/runtime/map_editor/"
	+ "fengmo_purgatory_corridor.runtime.json"
)
const REGISTRY_PATH := (
	"res://assets/data/runtime/map_editor/map_runtime_release_registry.json"
)
const EXPECTED_ORDINARY_IDS := [112, 126, 128, 129, 132, 138, 148, 150, 153, 156]
const EXPECTED_BOSS_IDS := [135, 141, 152, 155, 158]
const EXPECTED_BUILD_SHA256 := (
	"e6085fa11ccbcd3a09872b6a83a9292257a658d32d46a3d6e1fb53997c683ec5"
)


func _ready() -> void:
	var runtime := _read_json(RUNTIME_PATH)
	var registry := _read_json(REGISTRY_PATH)
	assert(not runtime.is_empty(), "formal purgatory runtime must load")
	assert(not registry.is_empty(), "formal release registry must load")
	assert(str(runtime.get("build_sha256", "")) == EXPECTED_BUILD_SHA256)
	var ordinary: Array = runtime.get("semantics", {}).get(
		"monster_spawn", []
	)
	var bosses: Array = runtime.get("semantics", {}).get("boss_spawn", [])
	assert(ordinary.size() == 10)
	assert(bosses.size() == 5)
	assert(_sorted_monster_ids(ordinary) == EXPECTED_ORDINARY_IDS)
	assert(_sorted_monster_ids(bosses) == EXPECTED_BOSS_IDS)
	assert(not _contains_monster_id(ordinary, 157))
	assert(not _contains_monster_id(bosses, 157))
	assert(not _contains_monster_id(ordinary, 159))
	assert(not _contains_monster_id(bosses, 159))
	_assert_horn_fly_contract(ordinary)
	_assert_best_guard_variant_contract(bosses)

	var matches: Array = registry.get("maps", []).filter(
		func(entry: Dictionary) -> bool:
			return (
				str(entry.get("map_key", ""))
					== "fengmo_purgatory_corridor"
				or int(entry.get("runtime_map_id", -1)) == 914007
			)
	)
	assert(matches.size() == 1)
	var release: Dictionary = matches[0]
	assert(str(release.get("release_state", "")) == "implemented_playable")
	assert(int(release.get("approval_revision", -1)) == 2)
	assert(
		str(release.get("approved_build_sha256", ""))
		== str(runtime.get("build_sha256", ""))
	)
	print(
		"MAP_MONSTER_PLACEMENT_RUNTIME_SPAWN_CLOSURE_PASS "
		+ "ordinary=10 boss=5 revision=2 hash=%s"
		% str(runtime.get("build_sha256", ""))
	)
	get_tree().quit(0)


func _assert_horn_fly_contract(entries: Array) -> void:
	for entry: Dictionary in entries:
		if int(entry.get("monster_id", -1)) != 126:
			continue
		assert(str(entry.get("kind", "")) == "monster_spawn")
		assert(str(entry.get("classification", "")) == "special")
		return
	assert(false, "monster_id=126 must remain in monster_spawn")


func _assert_best_guard_variant_contract(entries: Array) -> void:
	for entry: Dictionary in entries:
		if int(entry.get("monster_id", -1)) != 158:
			continue
		assert(
			_normalized_ids(entry.get("placement_evidence", {}).get(
				"selected_from_variant_group", []
			)) == [158, 159]
		)
		return
	assert(false, "monster_id=158 must be the sole selected guard variant")


func _normalized_ids(values: Array) -> Array:
	var ids: Array = []
	for value: Variant in values:
		ids.append(int(value))
	return ids


func _contains_monster_id(entries: Array, monster_id: int) -> bool:
	for entry: Dictionary in entries:
		if int(entry.get("monster_id", -1)) == monster_id:
			return true
	return false


func _sorted_monster_ids(entries: Array) -> Array:
	var ids: Array = []
	for entry: Dictionary in entries:
		ids.append(int(entry.get("monster_id", -1)))
	ids.sort()
	return ids


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
