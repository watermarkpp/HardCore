extends Node

const LOGICAL_VIEWPORT := Vector2i(1280, 720)
const CAMERA_ZOOM := 1.06
const TILE_SIZE := 32
const CHARACTER_FRAME := Vector2i(64, 96)
const CHARACTER_FOOT_ANCHOR := Vector2i(32, 80)
const WARRIOR_FRAME := Vector2i(192, 160)
const WARRIOR_SOURCE_FOOT_ANCHOR := Vector2i(64, 80)
const WARRIOR_FOOT_ANCHOR := Vector2i(96, 108)
const PLAYER_VISUAL_ALIGNMENT_CONTRACT_ID := (
	"player.visual_ground_alignment.manual.v1"
)
# User-approved local acceptance-lab result saved on 2026-07-30.  The visual
# layers move as one unit; the CharacterBody2D origin and collision shape stay
# at (0, 0).
const PLAYER_VISUAL_RUNTIME_POSITION := Vector2(7.5, 12.5)
const PLAYER_VISUAL_FOOT_ANCHOR_ADJUSTMENT := Vector2(-7.5, -12.5)
const WARRIOR_ATTACK_FRAME := WARRIOR_FRAME
const WARRIOR_ATTACK_FOOT_ANCHOR := WARRIOR_FOOT_ANCHOR
const MONSTER_FRAME := Vector2i(64, 64)
const MONSTER_FOOT_ANCHOR := Vector2i(32, 52)
const BOSS_FRAME := Vector2i(128, 128)
const BOSS_FOOT_ANCHOR := Vector2i(64, 108)
const PLAYER_COLLISION_RADIUS := 18.0
# The classic warrior's visible body/head centre is eight pixels left of the
# CharacterBody2D origin because of the source WIL draw offset.  Anchor the bar
# to that visible centre; keeping x=0 made it appear consistently to the right.
const PLAYER_HEALTH_BAR_OFFSET := Vector2(-8.0, -95.0)
const MONSTER_COLLISION_RADIUS := 16.0
const BOSS_COLLISION_RADIUS := 28.0
const MAX_ATLAS_SIZE := 2048

const DIRECTIONS := [&"s", &"sw", &"w", &"nw", &"n", &"ne", &"e", &"se"]
const ANIMATION_FRAMES := {
	&"idle": 4,
	&"walk": 8,
	&"attack": 6,
	&"cast": 6,
	&"hit": 3,
	&"death": 6,
}

const WARRIOR_ANIMATION_FRAMES := {
	&"idle": 4,
	&"walk": 6,
	&"attack": 6,
	&"cast": 6,
	&"hit": 3,
	&"death": 4,
}


static func direction_index(direction: Vector2) -> int:
	if direction.length_squared() < 0.0001:
		return 0
	return wrapi(int(round((direction.angle() - PI / 2.0) / (TAU / 8.0))), 0, 8)


static func mir2_client_direction_row(direction: Vector2) -> int:
	# Android presentation keeps vertical rows but mirrors horizontal rows.
	return [4, 5, 6, 7, 0, 1, 2, 3][direction_index(direction)]
