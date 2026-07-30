extends Node

const OverlayScript := preload(
	"res://scripts/player_ground_runtime_diagnostic_overlay.gd"
)


func _ready() -> void:
	var actor := Node2D.new()
	add_child(actor)
	var overlay := OverlayScript.new()
	overlay.setup(actor)
	actor.add_child(overlay)
	var snapshot := overlay.coordinate_snapshot()
	assert(Vector2(snapshot.actorOrigin).is_zero_approx())
	assert(Vector2(snapshot.physicsFootCenter).is_zero_approx())
	assert(Vector2(snapshot.delta).is_zero_approx())
	print(
		"PLAYER_GROUND_RUNTIME_DIAGNOSTIC_OVERLAY_PASS "
		+ "Android debug player foot stays at the physics actor origin"
	)
	get_tree().quit(0)
