extends "res://scripts/npc_actor.gd"
const PinnedVisual := preload("res://scripts/gameplay/world/world_npc_pinned_visual.gd")
var _original_pin_configured := false
var _original_texture: Texture2D
var _original_configuration: Dictionary
func configure_original_loading_texture(texture: Texture2D,configuration: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or is_inside_tree() or _original_pin_configured: return false
	_original_pin_configured=true; _original_texture=texture; _original_configuration=configuration.duplicate(true); return true
func interact(_game: Node) -> void: push_error("Source-only NPC interaction invoked on Main shell")
func face_toward(_target_position: Vector2,_as_default := false) -> void: push_error("Source-only NPC facing invoked on Main shell")
func reset_to_default_facing() -> void: push_error("Source-only NPC reset invoked on Main shell")
func _ready() -> void:
	visual = PinnedVisual.new()
	visual.name = "NPCVisual"
	if _original_pin_configured:
		visual.configure_original_loading_texture(_original_texture,_original_configuration)
	visual.setup(self)
	add_child(visual)
	name_label = Label.new()
	name_label.text = npc_name
	name_label.position = Vector2(-75.0, -76.0)
	name_label.size = Vector2(150, 25)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.98, 0.78, 0.42))
	add_child(name_label)
	_refresh_name_label_anchor()
	queue_redraw()
