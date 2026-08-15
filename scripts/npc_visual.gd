class_name NPCVisual
extends Node2D

const MANIFEST_PATH := "res://assets/data/classic_npc_art_sources.json"
# Frozen from the primary Npc.wil atlas audit recorded by
# tools/build_classic_npc_assets.py and assets/data/classic_npc_art_sources.json.
# For each appearance, every one of the 32 idle cells was reduced to the
# centre of its non-transparent alpha bbox in cell space, then the horizontal
# centres were medianed. This is source calibration, not a runtime scan.
const SOURCE_VISIBLE_CENTER_X: Dictionary = {
	0: 35.0,
	1: 36.25,
	2: 35.75,
	3: 38.0,
	4: 38.25,
	5: 38.5,
	6: 38.75,
	7: 37.5,
	8: 37.0,
	9: 36.75,
	10: 34.25,
	11: 34.0,
	12: 32.5,
	13: 35.5,
	14: 23.5,
	15: 34.5,
	16: 34.0,
	17: 28.5,
	18: 35.0,
	19: 26.0,
	20: 39.0,
	21: 33.25,
	22: 36.5,
}
var actor: Node2D
var sprite: Sprite2D
var current_direction := 0
var current_frame := 0
var frame_size := Vector2i.ZERO
var foot_anchor := Vector2i.ZERO
var frame_count := 4
var _elapsed := 0.0
var _valid := false
var _stable_frame_center_offset := Vector2.ZERO


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
	_stable_frame_center_offset = Vector2(frame_size) * 0.5 - Vector2(foot_anchor)
	frame_count = int(config.get("framesPerDirection", 4))
	var path := str(config.get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		visible = false
		return
	sprite.texture = load(path) as Texture2D
	sprite.position = -Vector2(foot_anchor)
	_valid = sprite.texture != null
	visible = _valid
	_stable_frame_center_offset = Vector2(
		float(SOURCE_VISIBLE_CENTER_X.get(int(actor.appearance), Vector2(frame_size).x * 0.5 - float(foot_anchor.x))),
		Vector2(frame_size).y * 0.5 - float(foot_anchor.y)
	)
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


func stable_frame_center_offset() -> Vector2:
	# Keep the appearance-level visible centre independent of the animated
	# region/frame. Unknown appearances use the source frame geometry only.
	return _stable_frame_center_offset


func _appearance_config(appearance: int) -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary:
		return {}
	var config: Variant = parsed.get("appearances", {}).get(str(appearance), {})
	return config if config is Dictionary else {}
