extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(ArtSpec.LOGICAL_VIEWPORT == Vector2i(1280, 720), "逻辑分辨率规范错误")
	assert(ArtSpec.TILE_SIZE == 32 and ArtSpec.MAX_ATLAS_SIZE == 2048, "瓦片或图集规范错误")
	assert(ArtSpec.DIRECTIONS.size() == 8 and ArtSpec.ANIMATION_FRAMES.size() == 6, "方向或动画状态规范不完整")
	assert(ArtSpec.direction_index(Vector2.DOWN) == 0, "南方向索引错误")
	assert(ArtSpec.direction_index(Vector2.LEFT) == 2, "西方向索引错误")
	assert(ArtSpec.direction_index(Vector2.UP) == 4, "北方向索引错误")
	assert(ArtSpec.direction_index(Vector2.RIGHT) == 6, "东方向索引错误")
	assert(ArtSpec.mir2_client_direction_row(Vector2.UP) == 0, "Hum图集北方向行错误")
	assert(ArtSpec.mir2_client_direction_row(Vector2.DOWN) == 4, "Hum图集南方向行错误")
	assert(ArtSpec.mir2_client_direction_row(Vector2.LEFT) == 6, "Hum图集西方向行错误")
	assert(ArtSpec.mir2_client_direction_row(Vector2.RIGHT) == 2, "Hum图集东方向行错误")
	var character_texture: Texture2D = load("res://assets/art/samples/technical_character.svg")
	var monster_texture: Texture2D = load("res://assets/art/samples/technical_monster.svg")
	var tile_texture: Texture2D = load("res://assets/art/samples/technical_tileset.svg")
	assert(character_texture.get_size() == Vector2(256, 768), "人物技术图集尺寸错误")
	assert(monster_texture.get_size() == Vector2(256, 512), "怪物技术图集尺寸错误")
	assert(tile_texture.get_size() == Vector2(256, 128), "地图技术图集尺寸错误")
	var sample: Node = load("res://scenes/technical_art_sample.tscn").instantiate()
	add_child(sample)
	await get_tree().process_frame
	var actor: CharacterBody2D = sample.get_node("TechnicalCharacter")
	var monster: CharacterBody2D = sample.get_node("TechnicalMonster")
	var wall: StaticBody2D = sample.get_node("TechnicalWorldCollision")
	assert(actor.collision_layer == 2 and monster.collision_layer == 3 and wall.collision_layer == 1, "技术样例碰撞层错误")
	assert((actor.get_node("CollisionShape2D").shape as CircleShape2D).radius == ArtSpec.PLAYER_COLLISION_RADIUS, "人物碰撞半径错误")
	assert((monster.get_node("CollisionShape2D").shape as CircleShape2D).radius == ArtSpec.MONSTER_COLLISION_RADIUS, "怪物碰撞半径错误")
	assert(get_tree().get_nodes_in_group("art_sample_tiles").size() == 1, "地图技术样例未生成")
	print("ART_SPEC_PASS：1280×720、32px瓦片、八方向、图集、锚点与碰撞层技术标准正常")
	get_tree().quit(0)
