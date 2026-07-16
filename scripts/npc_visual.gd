class_name NPCVisual
extends Node2D

const MANIFEST_PATH := "res://assets/data/classic_npc_art_sources.json"

var actor: Node2D
var sprite: Sprite2D
var current_direction := 0
var current_frame := 0
var frame_size := Vector2i.ZERO
var foot_anchor := Vector2i.ZERO
var frame_count := 4
var _elapsed := 0.0
var _valid := false


func setup(owner_actor: Node2D) -> void:
	actor = owner_actor


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.name = "ClassicNpcSprite"
	sprite.region_enabled = true
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	var config := _appearance_config(int(actor.appearance))
	if config.is_empty():
		visible = false
		return
	frame_size = Vector2i(int(config.frameSize[0]), int(config.frameSize[1]))
	foot_anchor = Vector2i(int(config.footAnchor[0]), int(config.footAnchor[1]))
	frame_count = int(config.get("framesPerDirection", 4))
	var path := str(config.get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		visible = false
		return
	sprite.texture = load(path) as Texture2D
	sprite.position = -Vector2(foot_anchor)
	_valid = sprite.texture != null
	visible = _valid
	_update_region()


func _process(delta: float) -> void:
	if not _valid or not is_instance_valid(actor):
		return
	_elapsed += delta
	current_frame = int(floor(_elapsed * 5.0)) % maxi(1, frame_count)
	current_direction = ArtSpec.direction_index(actor.facing)
	_update_region()


func _update_region() -> void:
	if sprite != null:
		sprite.region_rect = Rect2(current_frame * frame_size.x, current_direction * frame_size.y, frame_size.x, frame_size.y)


func uses_final_art() -> bool:
	return _valid and sprite != null and sprite.texture != null


func _appearance_config(appearance: int) -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary:
		return {}
	var config: Variant = parsed.get("appearances", {}).get(str(appearance), {})
	return config if config is Dictionary else {}
