extends Node


const REQUIRED_ACTIONS := ["idle", "walk", "attack", "hit", "death"]
const ZUMA_SOURCE_STARTS := {
	"idle": 1340,
	"walk": 1420,
	"attack": 1500,
	"hit": 1580,
	"death": 1600,
}
const ZUMA_SOURCE_STRIDES := {
	"idle": 10,
	"walk": 10,
	"attack": 10,
	"hit": 2,
	"death": 10,
}
const COW_MONSTER_IDS := [
	212, 213, 214, 215, 216, 217, 218,
	219, 220, 221, 222, 223, 224, 225,
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var boss_manifest := _load_json(
		"res://assets/data/classic_boss_client_art_sources.json"
	)
	var boss_entries: Dictionary = boss_manifest.get(
		"runtimeMappingsByMonsterId", {}
	)
	var zuma: Dictionary = boss_entries.get("160", {})
	assert(Vector2(zuma.get("frameSize", [0, 0])[0], zuma.get("frameSize", [0, 0])[1]) == Vector2(384, 336))
	assert(Vector2(zuma.get("footAnchor", [0, 0])[0], zuma.get("footAnchor", [0, 0])[1]) == Vector2(114, 237))
	assert(
		zuma.get("clientRuleDistribution", "")
		== "source.original_gameofmir.mirclient"
	)
	for action_name: String in REQUIRED_ACTIONS:
		var action: Dictionary = zuma.get("actions", {}).get(action_name, {})
		assert(
			int(action.get("sourceStart", -1))
			== int(ZUMA_SOURCE_STARTS[action_name]),
			"祖玛教主 %s 读到了错误的物化/特效帧" % action_name,
		)
		assert(
			int(action.get("sourceDirectionStride", -1))
			== int(ZUMA_SOURCE_STRIDES[action_name])
		)

	var dragon: Dictionary = boss_entries.get("124", {})
	assert(not dragon.is_empty())
	for action_name: String in ["idle", "attack", "death"]:
		var action: Dictionary = dragon.get("actions", {}).get(action_name, {})
		assert(
			_unique_frame_hashes(
				str(action.get("path", "")),
				Vector2i(
					int(dragon.frameSize[0]),
					int(dragon.frameSize[1]),
				),
				int(action.get("framesPerDirection", 0)),
			) > 1,
			"触龙神 %s 没有可播放的不同动画帧" % action_name,
		)

	var complete_manifest := _load_json(
		"res://assets/data/complete_monster_client_art_sources.json"
	)
	var cow_general: Dictionary = complete_manifest.get(
		"runtimeMappingsByMonsterId", {}
	).get("218", {})
	assert(cow_general.get("frameSize", []) == [272.0, 272.0])
	assert(cow_general.get("footAnchor", []) == [84.0, 143.0])
	assert(
		int(cow_general.get("alphaIslandCleanup", {}).get(
			"maxPixels", 0
		)) == 48
	)
	for action_name: String in REQUIRED_ACTIONS:
		var cleanup: Dictionary = cow_general.get(
			"actions", {}
		).get(action_name, {}).get("alphaIslandCleanup", {})
		assert(int(cleanup.get("removedComponents", 0)) > 0)
		assert(int(cleanup.get("removedPixels", 0)) > 0)
	var cow_attack := Image.load_from_file(
		ProjectSettings.globalize_path(
			str(cow_general.actions.attack.path)
		)
	)
	assert(not cow_attack.is_empty())
	# attack S frame 0 previously showed a detached dark vertical bar and a
	# red/green control-color dash at these exact local coordinates.
	assert(cow_attack.get_pixel(63, 4 * 272 + 140).a == 0.0)
	assert(cow_attack.get_pixel(63, 4 * 272 + 180).a == 0.0)

	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	for monster_id: int in COW_MONSTER_IDS:
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(monster_id), player, false)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		assert(enemy.visual.uses_final_art())
		assert(
			enemy.visual.sprite.region_filter_clip_enabled,
			"monsterId=%d atlas region can bleed neighboring frame fragments"
			% monster_id,
		)
		enemy.queue_free()
		await get_tree().process_frame

	print(
		"MONSTER_REPORTED_ANIMATION_REGRESSION_PASS "
		+ "zuma_sources=correct touch_dragon_frames=present "
		+ "cow_region_isolation=14 cow_general_fragments=removed"
	)
	get_tree().quit(0)


func _unique_frame_hashes(
	path: String,
	frame_size: Vector2i,
	frame_count: int,
) -> int:
	assert(path.begins_with("res://"))
	assert(frame_count > 1)
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert(not image.is_empty())
	var hashes := {}
	for frame in range(frame_count):
		var region := image.get_region(
			Rect2i(
				frame * frame_size.x,
				0,
				frame_size.x,
				frame_size.y,
			)
		)
		hashes[_sha256(region.get_data())] = true
	return hashes.size()


func _sha256(payload: PackedByteArray) -> String:
	var context := HashingContext.new()
	assert(context.start(HashingContext.HASH_SHA256) == OK)
	assert(context.update(payload) == OK)
	return context.finish().hex_encode()


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = (
		JSON.parse_string(file.get_as_text()) if file != null else null
	)
	return parsed if parsed is Dictionary else {}
