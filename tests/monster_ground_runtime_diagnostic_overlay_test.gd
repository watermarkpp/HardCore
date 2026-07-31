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
	overlay._process(0.0)
	assert(overlay.visible, "all living monsters must expose the Android debug probe")
	var snapshot := overlay.coordinate_snapshot()
	assert(snapshot.contract == OverlayScript.COORDINATE_FINGERPRINT_CONTRACT)
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
	assert(Vector2(snapshot.footAnchor) == Vector2(enemy.visual.foot_anchor))
	assert(Vector2(snapshot.actorGroundOffset) == Vector2(32.0, 28.0))
	assert(
		Vector2(snapshot.sourceActorOrigin).is_equal_approx(
			Vector2(snapshot.visualPosition) - Vector2(snapshot.actorGroundOffset)
		)
	)
	assert(
		Vector2(snapshot.migratedActorFoot).is_equal_approx(
			Vector2(snapshot.visualPosition)
		),
		"the monster client-origin migration must be algebraically identical to the accurate player path",
	)
	assert(
		Vector2(snapshot.visualCanvasDelta).is_equal_approx(
			Vector2(snapshot.visualPosition)
		)
	)
	assert(
		Vector2(snapshot.spriteCanvasDelta).is_equal_approx(
			Vector2(snapshot.visualPosition) + Vector2(snapshot.spritePosition)
		)
	)
	assert(Vector2(snapshot.visualGlobalScale).is_equal_approx(Vector2.ONE))
	assert(Vector2(snapshot.spriteGlobalScale).is_equal_approx(Vector2.ONE))
	assert(Vector2(snapshot.frameSize) == Vector2(enemy.visual.frame_size))
	assert(Vector2(snapshot.regionSize) == Vector2(enemy.visual.frame_size))
	assert(Vector2(snapshot.textureSize).x > 0.0)
	assert(not str(snapshot.texturePath).is_empty())

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
