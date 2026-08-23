class_name MonsterGroundSpikeEffect
extends Node2D

## Presentation-only fixed-area ground spike. Gameplay owns the descriptor and
## damage transaction; this node only renders the supplied eight-frame atlas
## once at the target's captured world-pixel footpoint.

const EFFECT_ID := "monster.fixed_area_ground_spike.v1"
const SOURCE_TEXTURE_PATH := (
	"res://assets/art/monsters/effects/fixed_area_ground_spike_rgba_v1.png"
)
const FRAME_COLUMNS := 4
const FRAME_ROWS := 2
const FRAME_COUNT := FRAME_COLUMNS * FRAME_ROWS
const FRAME_SIZE := Vector2i(384, 512)
const FRAME_FPS := 12.0
const FRAME_ANIMATION := &"fixed_area_ground_spike"
const ACTOR_VISIBILITY_Z_INDEX := -1

## The source atlas has a deliberately moving silhouette. These per-frame
## offsets keep the visible root/crack contact on the captured target footpoint
## while allowing the authored frame to retain its full height.
const FRAME_ANCHOR_Y_PX: Array[float] = [
	-182.0, -204.0, -248.0, -249.0,
	-214.0, -214.0, -234.0, -194.0,
]

signal playback_finished(effect: Node2D)

var release_descriptor: Dictionary = {}
var target_world_px := Vector2.ZERO
var release_id := ""
var _sprite: AnimatedSprite2D
var _source_texture: Texture2D
var _elapsed_seconds := 0.0
var _current_frame := 0
var _finished := false


static func create_visual(descriptor: Dictionary) -> Node2D:
	var effect := new()
	effect.setup(descriptor)
	return effect


func setup(descriptor: Dictionary) -> void:
	# Preserve the producer's read-only descriptor and never derive gameplay
	# state from the effect. Mutable caller dictionaries are frozen on a private
	# shallow copy so this node cannot mutate caller-owned fields.
	if descriptor.is_read_only():
		release_descriptor = descriptor
	else:
		release_descriptor = descriptor.duplicate(true)
		release_descriptor.make_read_only()
	var effect_id := str(release_descriptor.get("effect_id", ""))
	if not effect_id.is_empty() and effect_id != EFFECT_ID:
		visible = false
		return
	target_world_px = release_descriptor.get("target_world_px", Vector2.ZERO)
	if not target_world_px is Vector2:
		target_world_px = Vector2.ZERO
	global_position = target_world_px
	release_id = str(release_descriptor.get("release_id", ""))
	if is_inside_tree():
		_install_animation()


func play_once(descriptor: Dictionary = {}) -> void:
	if not descriptor.is_empty():
		setup(descriptor)
	_elapsed_seconds = 0.0
	_current_frame = 0
	_finished = false
	if _sprite == null and is_inside_tree():
		_install_animation()
	_set_frame(0)
	set_process(true)


func _ready() -> void:
	# Effects are world content and sit behind the actor composite while still
	# remaining visible around the target's feet.
	z_as_relative = true
	z_index = ACTOR_VISIBILITY_Z_INDEX
	add_to_group("zone_content")
	_install_animation()
	_set_frame(0)
	set_process(true)


func _install_animation() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	_source_texture = _load_source_texture()
	var frames := SpriteFrames.new()
	frames.add_animation(FRAME_ANIMATION)
	frames.set_animation_speed(FRAME_ANIMATION, FRAME_FPS)
	frames.set_animation_loop(FRAME_ANIMATION, false)
	for frame_index: int in range(FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas = _source_texture
		atlas.region = Rect2(
			Vector2(
				float(frame_index % FRAME_COLUMNS) * FRAME_SIZE.x,
				float(frame_index / FRAME_COLUMNS) * FRAME_SIZE.y,
			),
			Vector2(FRAME_SIZE),
		)
		frames.add_frame(FRAME_ANIMATION, atlas)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "FixedAreaGroundSpikeFrames"
	_sprite.sprite_frames = frames
	_sprite.animation = FRAME_ANIMATION
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.z_as_relative = true
	_sprite.z_index = 0
	add_child(_sprite)


func _load_source_texture() -> Texture2D:
	# The effect asset may be newly staged before Godot's editor importer has
	# generated a .import sidecar. Image.load keeps the runtime/headless path
	# deterministic while still consuming the exact authored PNG bytes.
	var image := Image.new()
	if image.load(SOURCE_TEXTURE_PATH) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed_seconds += maxf(0.0, delta)
	var frame_index := mini(
		FRAME_COUNT - 1,
		int(floor(_elapsed_seconds * FRAME_FPS)),
	)
	_set_frame(frame_index)
	if _elapsed_seconds >= float(FRAME_COUNT) / FRAME_FPS:
		_finished = true
		set_process(false)
		playback_finished.emit(self)
		queue_free()


func _set_frame(frame_index: int) -> void:
	_current_frame = clampi(frame_index, 0, FRAME_COUNT - 1)
	if _sprite == null or not is_instance_valid(_sprite):
		return
	_sprite.frame = _current_frame
	_sprite.position = Vector2(
		0.0,
		FRAME_ANCHOR_Y_PX[_current_frame],
	)


func frame_count() -> int:
	return FRAME_COUNT


func current_frame() -> int:
	return _current_frame


func is_finished() -> bool:
	return _finished


func source_texture_path() -> String:
	return SOURCE_TEXTURE_PATH


func visual_descriptor() -> Dictionary:
	var descriptor := {
		"effect_id": EFFECT_ID,
		"release_id": release_id,
		"source_texture_path": SOURCE_TEXTURE_PATH,
		"frame_count": FRAME_COUNT,
		"frame_columns": FRAME_COLUMNS,
		"frame_rows": FRAME_ROWS,
		"frame_size": FRAME_SIZE,
		"frame_fps": FRAME_FPS,
		"anchor_policy": "per_frame_ground_contact_y",
		"damage_owner": "enemy.fixed_area_ground_spike_release",
		"release_policy": "once_then_queue_free",
	}
	descriptor.make_read_only()
	return descriptor
