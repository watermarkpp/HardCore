class_name NPCVisual
extends Node2D

const MANIFEST_PATH := "res://assets/data/classic_npc_art_sources.json"
# Frozen from the primary Npc.wil atlas audit recorded by
# tools/build_classic_npc_assets.py and assets/data/classic_npc_art_sources.json.
# For each appearance and logical direction, the four idle cells were reduced
# to the centre of each non-transparent alpha bbox in cell space, then the
# four horizontal centres were medianed. This is source calibration, not a
# runtime scan.
const SOURCE_VISIBLE_CENTER_X_BY_DIRECTION: Dictionary = {
	0: [36.25, 40.25, 40.25, 28.0, 33.0, 36.25, 32.25, 32.25],
	1: [36.0, 37.0, 37.0, 32.5, 37.75, 42.75, 33.5, 33.5],
	2: [35.25, 44.0, 44.0, 25.5, 36.25, 44.5, 28.75, 28.75],
	3: [38.0, 34.25, 34.25, 37.5, 39.0, 40.5, 39.5, 39.5],
	4: [35.5, 34.75, 34.75, 35.75, 39.75, 43.0, 38.75, 38.75],
	5: [38.5, 40.0, 40.0, 37.5, 41.0, 41.5, 36.75, 36.75],
	6: [38.0, 35.5, 35.5, 38.75, 40.75, 41.5, 40.5, 40.5],
	7: [38.75, 38.5, 38.5, 30.5, 34.5, 38.75, 37.0, 37.0],
	8: [37.25, 37.0, 37.0, 33.25, 34.75, 36.5, 34.5, 34.5],
	9: [36.25, 41.5, 41.5, 31.5, 37.0, 45.75, 34.75, 34.75],
	10: [32.75, 35.75, 35.75, 33.75, 35.25, 38.5, 33.5, 33.5],
	11: [34.5, 34.25, 34.25, 35.25, 35.0, 34.25, 29.25, 29.25],
	12: [31.5, 32.5, 32.5, 34.0, 30.5, 34.75, 36.0, 36.0],
	13: [35.0, 38.0, 38.0, 28.25, 34.25, 42.75, 35.5, 35.5],
	14: [23.5, 17.5, 17.5, 30.5, 23.5, 17.5, 30.5, 30.5],
	15: [45.0, 45.5, 45.5, 29.5, 27.0, 35.25, 33.75, 33.75],
	16: [36.0, 34.0, 34.0, 31.0, 39.5, 45.0, 33.75, 33.75],
	17: [23.25, 31.0, 31.0, 18.25, 30.75, 44.0, 25.25, 25.25],
	18: [35.0, 38.5, 38.5, 33.0, 35.25, 38.0, 34.5, 34.5],
	19: [26.0, 32.5, 32.5, 18.0, 25.0, 31.5, 22.5, 22.5],
	20: [41.0, 35.5, 35.5, 38.5, 45.5, 42.75, 39.0, 39.0],
	21: [36.0, 47.5, 47.5, 29.5, 31.0, 35.0, 25.0, 25.0],
	22: [36.75, 45.0, 45.0, 26.75, 36.5, 47.25, 21.5, 21.5],
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
	_stable_frame_center_offset = _frame_center_offset_for_direction(ArtSpec.direction_index(actor.facing))
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
	# region/frame. The direction row changes only when the actor turns; unknown
	# appearances use the source frame geometry only.
	if is_instance_valid(actor):
		_stable_frame_center_offset = _frame_center_offset_for_direction(ArtSpec.direction_index(actor.facing))
	return _stable_frame_center_offset


func _frame_center_offset_for_direction(direction_index: int) -> Vector2:
	var geometric := Vector2(frame_size).x * 0.5 - float(foot_anchor.x)
	var appearance_values: Variant = SOURCE_VISIBLE_CENTER_X_BY_DIRECTION.get(int(actor.appearance), null) if is_instance_valid(actor) else null
	var center_x := geometric
	if appearance_values is Array and direction_index >= 0 and direction_index < appearance_values.size():
		center_x = float(appearance_values[direction_index])
	return Vector2(center_x, Vector2(frame_size).y * 0.5 - float(foot_anchor.y))


func _appearance_config(appearance: int) -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary:
		return {}
	var config: Variant = parsed.get("appearances", {}).get(str(appearance), {})
	return config if config is Dictionary else {}
