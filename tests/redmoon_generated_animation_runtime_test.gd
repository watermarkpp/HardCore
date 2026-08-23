extends Node


const EXPECTED_FRAMES := {
	"idle": 4,
	"walk": 4,
	"attack": 6,
	"hit": 2,
	"death": 20,
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var monster_data := GameData.get_monster_by_id(180)
	assert(not monster_data.is_empty(), "redmoon gameplay data missing")
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var enemy := EnemyActor.new()
	enemy.setup(monster_data, player, true)
	add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().process_frame
	var visual: MonsterVisual = enemy.visual
	assert(visual.uses_final_art(), "redmoon final art did not load")
	assert(visual.frame_size == Vector2i(288, 208))
	var fixed_contact := enemy.ground_indicator_center()
	var fixed_radii := enemy.ground_indicator_radii()
	for action_name: String in EXPECTED_FRAMES:
		var frame_count := MonsterAnimationPolicy.frame_count(
			visual.active_resources,
			StringName(action_name),
		)
		assert(frame_count == EXPECTED_FRAMES[action_name])
		var texture: Texture2D = visual.active_resources[action_name]
		assert(texture != null)
		assert(texture.get_width() == 288 * frame_count)
		assert(texture.get_height() == 208 * 8)
		for direction in range(8):
			for frame in range(frame_count):
				visual.current_state = action_name
				visual.current_direction = direction
				visual.current_frame = frame
				visual.sprite.texture = texture
				visual.sprite.region_rect = Rect2(
					frame * 288,
					direction * 208,
					288,
					208,
				)
				assert(enemy.ground_indicator_center().is_equal_approx(fixed_contact))
				assert(enemy.ground_indicator_radii().is_equal_approx(fixed_radii))
	print("REDMOON_GENERATED_ANIMATION_RUNTIME_PASS native-alpha five-action atlas loaded for all frames and directions")
	get_tree().quit(0)
