extends "res://scripts/npc_visual.gd"
var _original_pin_configured := false
var _original_texture: Texture2D
var _original_configuration: Dictionary
func configure_original_loading_texture(texture: Texture2D,configuration: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or is_inside_tree() or _original_pin_configured: return false
	_original_pin_configured=true; _original_texture=texture; _original_configuration=configuration.duplicate(true); return true
func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.name = "ClassicNpcSprite"
	sprite.region_enabled = true
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	var config := _original_configuration if _original_pin_configured else _appearance_config(int(actor.appearance))
	if config.is_empty():
		visible = false
		return
	frame_size = Vector2i(int(config.frameSize[0]), int(config.frameSize[1]))
	foot_anchor = Vector2i(int(config.footAnchor[0]), int(config.footAnchor[1]))
	_stable_frame_center_offset = Vector2(frame_size) * 0.5 - Vector2(foot_anchor)
	frame_count = int(config.get("framesPerDirection", 4))
	var path := str(config.get("path", ""))
	if path.is_empty() or (not _original_pin_configured and not ResourceLoader.exists(path)):
		visible = false
		return
	sprite.texture = _original_texture if _original_pin_configured else load(path) as Texture2D
	sprite.position = -Vector2(foot_anchor)
	_valid = sprite.texture != null
	visible = _valid
	_stable_frame_center_offset = _frame_center_offset_for_direction(ArtSpec.direction_index(actor.facing))
	_update_region()
