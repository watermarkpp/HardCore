class_name TechnicalArtSample
extends Node2D

const CHARACTER_TEXTURE := preload("res://assets/art/samples/technical_character.svg")
const MONSTER_TEXTURE := preload("res://assets/art/samples/technical_monster.svg")
const TILE_TEXTURE := preload("res://assets/art/samples/technical_tileset.svg")


func _ready() -> void:
	_build_floor()
	_build_actor_sample()
	_build_monster_sample()
	_build_world_collision()
	_build_labels()


func _build_floor() -> void:
	var floor_root := Node2D.new()
	floor_root.name = "TechnicalTileGrid"
	floor_root.add_to_group("art_sample_tiles")
	add_child(floor_root)
	for y in range(6):
		for x in range(10):
			var tile := Sprite2D.new()
			tile.texture = TILE_TEXTURE
			tile.region_enabled = true
			tile.region_rect = Rect2((x % 8) * ArtSpec.TILE_SIZE, (y % 4) * ArtSpec.TILE_SIZE, ArtSpec.TILE_SIZE, ArtSpec.TILE_SIZE)
			tile.position = Vector2(496 + x * ArtSpec.TILE_SIZE, 272 + y * ArtSpec.TILE_SIZE)
			floor_root.add_child(tile)


func _build_actor_sample() -> void:
	var actor := CharacterBody2D.new()
	actor.name = "TechnicalCharacter"
	actor.position = Vector2(600, 426)
	actor.collision_layer = 2
	actor.add_to_group("art_sample_character")
	add_child(actor)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = CHARACTER_TEXTURE
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, ArtSpec.CHARACTER_FRAME)
	sprite.centered = false
	sprite.position = -Vector2(ArtSpec.CHARACTER_FOOT_ANCHOR)
	actor.add_child(sprite)
	actor.add_child(_circle_collision(ArtSpec.PLAYER_COLLISION_RADIUS_PX))


func _build_monster_sample() -> void:
	var monster := CharacterBody2D.new()
	monster.name = "TechnicalMonster"
	monster.position = Vector2(744, 426)
	monster.collision_layer = 3
	monster.add_to_group("art_sample_monster")
	add_child(monster)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = MONSTER_TEXTURE
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, ArtSpec.MONSTER_FRAME)
	sprite.centered = false
	sprite.position = -Vector2(ArtSpec.MONSTER_FOOT_ANCHOR)
	monster.add_child(sprite)
	monster.add_child(_circle_collision(ArtSpec.MONSTER_COLLISION_RADIUS_PX))


func _build_world_collision() -> void:
	var wall := StaticBody2D.new()
	wall.name = "TechnicalWorldCollision"
	wall.collision_layer = 1
	wall.position = Vector2(640, 480)
	wall.add_to_group("art_sample_collision")
	add_child(wall)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(320, 16)
	collision.shape = shape
	wall.add_child(collision)


func _build_labels() -> void:
	var title := Label.new()
	title.name = "SampleTitle"
	title.text = "M1 技术样例｜32px瓦片｜64×96人物｜64×64怪物"
	title.position = Vector2(430, 205)
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)


func _circle_collision(radius: float) -> CollisionShape2D:
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision.shape = shape
	return collision
