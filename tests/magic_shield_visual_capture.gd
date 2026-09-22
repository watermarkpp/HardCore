extends Node

const OUTPUT_PATH := (
	"res://outputs/visual_acceptance/magic_shield/"
	+ "wizard_magic_shield_primary_footpoint_centered_behind_body.png"
)
const CANVAS_SIZE := Vector2i(320, 280)
const ACTOR_FOOTPOINT := Vector2(160.0, 205.0)


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession(ProfessionRules.profession_display_name("wizard"))
	PlayerState.level = 40
	PlayerState.recalculate_stats()

	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = ACTOR_FOOTPOINT
	player.visual.set_process(false)
	player.visual._process(0.0)

	var shield := CasterSkillAnimationPlayer.new()
	add_child(shield)
	assert(shield.configure("wizard.magic_shield"))
	shield._process(shield.animation_duration() + 0.01)
	assert(shield.current_frame_index == shield.frame_count() - 1)

	var canvas := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("151b21"))
	_blend_sprite_at_actor_footpoint(canvas, shield, ACTOR_FOOTPOINT)
	# Draw the actual runtime body after the shield. This is the formal y-sort
	# contract: same footpoint, shield behind, body unobstructed.
	_blend_sprite_at_actor_footpoint(
		canvas,
		player.visual.sprite,
		ACTOR_FOOTPOINT + player.visual.position
	)
	var output_absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(output_absolute.get_base_dir())
	assert(canvas.save_png(output_absolute) == OK)
	print("MAGIC_SHIELD_VISUAL_CAPTURE_PASS: %s" % output_absolute)
	get_tree().quit(0)


func _blend_sprite_at_actor_footpoint(
	canvas: Image,
	sprite: Sprite2D,
	actor_footpoint: Vector2
) -> void:
	assert(sprite.texture != null)
	var image := sprite.texture.get_image()
	if sprite.region_enabled:
		image = image.get_region(Rect2i(sprite.region_rect))
	if sprite.flip_h:
		image.flip_x()
	if sprite.flip_v:
		image.flip_y()
	var top_left := actor_footpoint + sprite.position + sprite.offset
	if sprite.centered:
		top_left -= Vector2(image.get_size()) * 0.5
	canvas.blend_rect(
		image,
		Rect2i(Vector2i.ZERO, image.get_size()),
		Vector2i(roundi(top_left.x), roundi(top_left.y))
	)
