extends Node2D

const F := preload("res://tests/source176_r3/helpers/runtime_fixture.gd")
const Neighbor := preload("res://scripts/monster_neighbor_step_policy.gd")
var failures: Array = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	for residual: float in [-0.00009, -0.00002, 0.00002, 0.00009]:
		for axis: int in 2:
			var victim := F.player(self, Vector2(16.5, 16.5))
			var origin := Vector2(20.5 + residual, 20.85403) if axis == 0 else Vector2(20.85403, 20.5 + residual)
			var actor := F.enemy(self, 24, origin, victim)
			actor._leave_background_deep_sleep()
			actor.set_physics_process(false)
			actor._hc_sync_navigation()
			actor._hc_known_target_id = victim.get_instance_id()
			actor._hc_known_ground = F.to_ground(victim.global_position)
			actor._hc_observed = true
			actor._hc_flank_anchor = actor._hc_known_ground
			actor._hc_flank_waypoint = Vector2(20.5, 20.5)
			actor._hc_owned_movement_call = true
			var current := actor.spatial_index_position()
			var neighbor := actor._hc_neighbor(current, victim, Vector2i(-1, -1))
			if neighbor == Vector2i.ZERO:
				failures.append("projection residual suppressed remaining flank axis: " + str([residual, axis]))
			var displacement: Vector2 = actor._hc_step_override - current
			if displacement.length() <= 0.3 or not Neighbor.motion_follows_direction(displacement, Vector2.UP if axis == 0 else Vector2.LEFT):
				failures.append("flank endpoint did not preserve the remaining axis: " + str(displacement))
			F.dispose(actor, victim)
	print("FLANK_PROJECTION_RESIDUAL_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
