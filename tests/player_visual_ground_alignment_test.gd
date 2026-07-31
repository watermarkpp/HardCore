extends Node

const CONTRACT_PATH := "res://assets/data/player_visual_alignment.json"
const SOURCE_DRAFT_SHA256 := (
	"5D01E19C509E9C970B928475263E233552EE50A00BE7C04FD3BF6BD1CFD088A4"
)


func _ready() -> void:
	var original_test_mode := PlayerState.test_mode
	PlayerState.test_mode = true
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	player.visual._process(0.0)

	assert(
		ArtSpec.PLAYER_VISUAL_ALIGNMENT_CONTRACT_ID
			== "player.visual_ground_alignment.manual.v1"
	)
	assert(
		player.visual.position == ArtSpec.PLAYER_VISUAL_RUNTIME_POSITION
	)
	var visual_foot_point: Vector2 = (
		player.visual.position
		+ player.visual.sprite.position
		+ Vector2(ArtSpec.WARRIOR_FOOT_ANCHOR)
		+ ArtSpec.PLAYER_VISUAL_FOOT_ANCHOR_ADJUSTMENT
	)
	assert(
		visual_foot_point.is_zero_approx(),
		"formal visual foot point must coincide with actor origin: %s"
			% visual_foot_point
	)
	var collision: CollisionShape2D = player.get_node("CollisionShape2D")
	assert(collision.position.is_zero_approx())
	assert(
		(collision.shape as ConvexPolygonShape2D).points
			== WorldSpatialRules.actor_footprint_polygon(
				ArtSpec.PLAYER_COLLISION_RADIUS
			)
	)

	var file := FileAccess.open(CONTRACT_PATH, FileAccess.READ)
	var contract: Variant = (
		JSON.parse_string(file.get_as_text()) if file != null else null
	)
	assert(contract is Dictionary)
	assert(
		str(contract.get("contractId", ""))
			== ArtSpec.PLAYER_VISUAL_ALIGNMENT_CONTRACT_ID
	)
	assert(
		str(contract.get("sourceDraft", {}).get("sha256", ""))
			== SOURCE_DRAFT_SHA256
	)
	assert(
		contract.get("runtimeVisualPosition", [])
			== [
				ArtSpec.PLAYER_VISUAL_RUNTIME_POSITION.x,
				ArtSpec.PLAYER_VISUAL_RUNTIME_POSITION.y,
			]
	)
	assert(
		contract.get("visualFootAnchorAdjustment", [])
			== [
				ArtSpec.PLAYER_VISUAL_FOOT_ANCHOR_ADJUSTMENT.x,
				ArtSpec.PLAYER_VISUAL_FOOT_ANCHOR_ADJUSTMENT.y,
			]
	)

	player.queue_free()
	await get_tree().process_frame
	PlayerState.test_mode = original_test_mode
	print(
		"PLAYER_VISUAL_GROUND_ALIGNMENT_PASS visual_foot=(0,0) "
		+ "physics_origin=(0,0) source_draft_sha256=%s"
		% SOURCE_DRAFT_SHA256
	)
	get_tree().quit(0)
