extends Node

const OverlayScript := preload(
	"res://scripts/player_ground_runtime_diagnostic_overlay.gd"
)


func _ready() -> void:
	assert(
		not OverlayScript.enabled_for_runtime(),
		"player ground diagnostic visuals must stay disabled in gameplay",
	)
	var actor := Node2D.new()
	add_child(actor)
	var overlay := OverlayScript.new()
	overlay.setup(actor)
	actor.add_child(overlay)
	assert(not overlay.visible, "retired player ground overlay must remain invisible")
	var snapshot := overlay.coordinate_snapshot()
	assert(Vector2(snapshot.actorOrigin).is_zero_approx())
	assert(Vector2(snapshot.physicsFootCenter).is_zero_approx())
	assert(Vector2(snapshot.delta).is_zero_approx())
	print(
		"PLAYER_GROUND_RUNTIME_DIAGNOSTIC_OVERLAY_PASS "
		+ "runtime lines and text disabled; coordinate snapshot remains test-only"
	)
	get_tree().quit(0)
