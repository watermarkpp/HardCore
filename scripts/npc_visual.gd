class_name NPCVisual
extends Node2D

const MANIFEST_PATH := "res://assets/data/classic_npc_art_sources.json"
# Frozen from the primary Npc.wil atlas audit recorded by
# tools/build_classic_npc_assets.py and assets/data/classic_npc_art_sources.json.
# For each appearance and logical direction, the four idle cells were reduced
# to the centre of each body-confidence alpha bbox in cell space. A pixel is
# body-confidence when alpha > 0 and Rec.709 luminance > 10/255, excluding the
# source art's dark ground shadow; the four horizontal centres are medianed.
# This is source calibration, not a runtime scan.
const SOURCE_VISIBLE_CENTER_X_BY_DIRECTION: Dictionary = {
	0: [20.75, 25.75, 25.75, 14.75, 19.25, 22.5, 16.25, 16.25],
	1: [23.75, 26.0, 26.0, 19.5, 23.25, 27.75, 20.5, 20.5],
	2: [23.5, 30.5, 30.5, 14.75, 26.0, 32.75, 17.5, 17.5],
	3: [23.0, 21.0, 21.0, 22.0, 23.0, 23.75, 25.0, 25.0],
	4: [22.0, 22.5, 22.5, 21.0, 23.75, 26.0, 23.5, 23.5],
	5: [23.5, 26.0, 26.0, 21.5, 23.75, 26.25, 21.0, 21.0],
	6: [22.5, 22.25, 22.25, 23.25, 22.75, 23.75, 26.0, 26.0],
	7: [23.75, 25.5, 25.5, 17.25, 21.5, 26.5, 22.5, 22.5],
	8: [23.25, 23.0, 23.0, 18.75, 20.75, 22.25, 20.0, 20.0],
	9: [23.0, 26.5, 26.5, 20.25, 22.75, 29.0, 20.0, 20.0],
	10: [23.0, 25.25, 25.25, 21.0, 23.0, 24.75, 21.25, 21.25],
	11: [23.75, 24.5, 24.5, 21.25, 24.5, 24.5, 15.0, 15.0],
	12: [23.0, 25.5, 25.5, 22.25, 20.25, 23.5, 25.5, 25.5],
	13: [23.5, 30.0, 30.0, 17.5, 23.5, 30.25, 22.0, 22.0],
	14: [23.5, 15.5, 15.5, 30.5, 23.5, 15.5, 30.5, 30.5],
	15: [22.5, 30.0, 30.0, 18.25, 12.5, 26.0, 16.5, 16.5],
	16: [23.5, 24.5, 24.5, 17.25, 24.25, 29.5, 21.5, 21.5],
	17: [12.75, 19.25, 19.25, 8.5, 20.5, 30.0, 14.0, 14.0],
	18: [24.0, 23.0, 23.0, 20.0, 24.25, 25.5, 21.0, 21.0],
	19: [24.0, 30.5, 30.5, 15.0, 23.0, 29.5, 16.5, 16.5],
	20: [25.25, 21.75, 21.75, 20.0, 26.0, 25.75, 23.0, 23.0],
	21: [23.5, 33.5, 33.5, 16.25, 19.5, 23.75, 13.5, 13.5],
	22: [17.25, 25.0, 25.0, 12.25, 17.0, 26.5, 10.75, 10.75],
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
