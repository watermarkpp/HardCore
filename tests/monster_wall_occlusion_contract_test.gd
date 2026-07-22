extends Node2D


const CASES := [
	{"monster_id": 31, "boss": false, "sort_y": 168.0},
	{"monster_id": 76, "boss": true, "sort_y": 232.0},
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	y_sort_enabled = true
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	player.global_position = Vector2(1200, 200)
	add_child(player)
	player.set_physics_process(false)

	var occluder := Node2D.new()
	occluder.position = Vector2(320, 200)
	occluder.z_index = 0
	occluder.set_meta("editor_runtime_actor_occluder", true)
	add_child(occluder)
	var wall_front := Sprite2D.new()
	wall_front.set_meta("editor_runtime_render_domain", MonsterVisual.ACTOR_Y_SORT_RENDER_DOMAIN)
	occluder.add_child(wall_front)

	var enemies: Array[EnemyActor] = []
	for sample: Dictionary in CASES:
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(int(sample.monster_id)), player, bool(sample.boss))
		enemy.global_position = Vector2(320, float(sample.sort_y))
		add_child(enemy)
		enemy.set_physics_process(false)
		enemies.append(enemy)
	await get_tree().process_frame

	assert(enemies[0].global_position.y < occluder.global_position.y)
	assert(enemies[1].global_position.y > occluder.global_position.y)
	assert(occluder.get_parent() == self)
	for enemy: EnemyActor in enemies:
		assert(enemy.get_parent() == self, "monster and actor occluder must be direct Y-sort siblings")
		_assert_item(enemy, "actor_root")
		_assert_item(enemy.name_label, "name_label")
		_assert_item(enemy.visual, "visual_root")
		_assert_item(enemy.visual.get_node("BodySprite"), "body_sprite")
		_assert_no_detached_canvas(enemy)
		assert(enemy.visual.uses_final_art(), "normal/Boss final frame Sprite2D was not exercised")
	assert(enemies[0].z_index == occluder.z_index and enemies[1].z_index == occluder.z_index)
	print("MONSTER_WALL_OCCLUSION_CONTRACT_PASS")
	get_tree().quit(0)


func _assert_item(item: CanvasItem, role: String) -> void:
	assert(item.z_index == 0 and item.z_as_relative)
	assert(not item.y_sort_enabled and not item.is_set_as_top_level())
	assert(not item.show_behind_parent)
	assert(str(item.get_meta("monster_render_domain", "")) == MonsterVisual.ACTOR_Y_SORT_RENDER_DOMAIN)
	assert(str(item.get_meta("monster_render_contract", "")) == MonsterVisual.ACTOR_Y_SORT_RENDER_CONTRACT)
	assert(str(item.get_meta("monster_render_role", "")) == role)


func _assert_no_detached_canvas(root: Node) -> void:
	for child: Node in root.get_children():
		assert(not child is CanvasLayer, "monster composite contains a detached CanvasLayer")
		if child is CanvasItem:
			var item := child as CanvasItem
			assert(item.z_index == 0 and item.z_as_relative, "monster child bypasses its actor Z plane")
			assert(not item.y_sort_enabled and not item.is_set_as_top_level(), "monster child starts a detached sort domain")
			assert(not item.show_behind_parent, "monster child changes the composite draw order")
		_assert_no_detached_canvas(child)
