extends Node

const OverlayScript := preload(
	"res://scripts/monster_ground_runtime_diagnostic_overlay.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(24), player, false)
	add_child(enemy)
	enemy.set_physics_process(false)
	await get_tree().process_frame

	enemy.facing = Vector2.DOWN
	enemy.movement_facing = Vector2.DOWN
	enemy.visual._process(0.0)
	var overlay := OverlayScript.new()
	overlay.setup(enemy)
	add_child(overlay)
	var snapshot := overlay.coordinate_snapshot()
	assert(int(snapshot.monsterId) == 24)
	assert(snapshot.action == "idle")
	assert(snapshot.directionLabel == "S")
	assert(int(snapshot.sourceDirectionRow) == 4)
	assert(Vector2(snapshot.actorOrigin).is_zero_approx())
	assert(Vector2(snapshot.manualVisualFoot).is_zero_approx())
	assert(Vector2(snapshot.runtimeTargetRing).is_zero_approx())
	assert(Vector2(snapshot.manualMinusActor).is_zero_approx())
	assert(Vector2(snapshot.ringMinusActor).is_zero_approx())
	assert(Vector2(snapshot.ringMinusManual).is_zero_approx())
	assert(Vector2(snapshot.visualPosition).is_equal_approx(Vector2(8.5, -8.0)))
	assert(Vector2(snapshot.visualFootOffset).is_equal_approx(Vector2(-8.5, 8.0)))

	enemy.visual.position += Vector2(2.5, 6.0)
	var separated := overlay.coordinate_snapshot()
	assert(Vector2(separated.manualVisualFoot).is_equal_approx(Vector2(2.5, 6.0)))
	assert(Vector2(separated.runtimeTargetRing).is_zero_approx())
	assert(Vector2(separated.ringMinusManual).is_equal_approx(Vector2(-2.5, -6.0)))
	print(
		"MONSTER_GROUND_RUNTIME_DIAGNOSTIC_OVERLAY_PASS "
		+ "production actor/manual-foot/ring coordinates remain independently observable"
	)
	get_tree().quit(0)
