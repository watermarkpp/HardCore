extends Node

const GroundUnit := preload("res://scripts/ground_unit_space.gd")

const MAP_ID := 9001


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var summon := SummonActor.new()
	summon.setup(null, "骷髅", 10, 1, "taoist.summon_skeleton", 35)
	summon.global_position = Vector2(0.0, 80.0)
	# Mapped world with screen_to_ground MISSING.
	summon.configure_runtime_map_projection(
		MAP_ID,
		GroundUnit.ground_delta_gu_to_screen_delta_px
	)
	add_child(summon)
	summon.set_process(false)
	summon.set_physics_process(false)
	assert(
		not summon.projection_ready(),
		"mapped summon without screen_to_ground must not be projection-ready"
	)
	summon.configure_spawn_release_footprint("p01:summon:1")
	assert(
		summon.summon_spawn_footprint_snapshot.is_empty(),
		"mapped summon must not create a spawn snapshot without projection"
	)
	var target := EnemyActor.new()
	target.setup(
		{"name": "p01_target", "hp": 9999, "attackMin": 1, "attackMax": 1, "level": 1},
		null,
		false
	)
	target.global_position = GroundUnit.ground_delta_gu_to_screen_delta_px(
		Vector2(131.0, 130.0)
	)
	add_child(target)
	target.set_process(false)
	target.set_physics_process(false)
	var attack: Dictionary = summon.create_attack_release_footprint_snapshot(
		target
	)
	assert(
		attack.is_empty(),
		"mapped summon must not create an attack snapshot without projection"
	)
	assert(
		not summon.attack_release_snapshot_intersects_target(attack, target),
		"mapped summon must never enter the spatial hit flow without projection"
	)
	assert(
		summon.missing_projection_rejection_count >= 2,
		"mapped summon must record spawn + attack rejections"
	)
	assert(
		str(summon.projection_rejection_reason)
		== str(GroundUnit.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION),
		"summon rejection must use the unified reason"
	)
	var rejection_count := summon.missing_projection_rejection_count
	summon.queue_free()
	target.queue_free()
	await get_tree().process_frame
	print(
		"MAPPED_SUMMON_MISSING_PROJECTION_REJECTED_PASS rejections=%d"
		% rejection_count
	)
	get_tree().quit(0)
