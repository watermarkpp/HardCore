extends "res://tests/user_feedback_20260930/natural_crowd_30_actor_test.gd"

## The authorized settled-crowd contract: real attacks enclose all four
## quadrants, legal front actors hold, and rear actors move or encounter a
## fresh body obstruction. The legacy radial/five-slot assertions remain in
## the base fixture and their historical FAIL evidence is retained.
const Step := preload("res://scripts/monster_source176/source_step_plan.gd")
var enclosure_frames := 0
var hold_positions: Dictionary = {}
var maximum_hold_motion := 0.0

func _behavior_complete(target_seen: int, _moved: int, _ready_attackers: int) -> bool:
	var quadrants: Dictionary = {}
	for actor: EnemyActor in actors:
		var point := _ground(actor)
		if actor._hc_access(player) == "CLEAR" and actor._hc_starts > 0:
			var offset := point - _ground(player)
			quadrants[Vector2i(1 if offset.x >= 0.0 else -1, 1 if offset.y >= 0.0 else -1)] = true
			if hold_positions.has(actor.get_instance_id()):
				maximum_hold_motion = maxf(maximum_hold_motion, point.distance_to(hold_positions[actor.get_instance_id()]))
			hold_positions[actor.get_instance_id()] = point
		else:
			hold_positions.erase(actor.get_instance_id())
		if actor._movement_step_active:
			var leg := actor._movement_step_target_ground_gu - actor._movement_step_start_ground_gu
			_check(maxf(absf(leg.x), absf(leg.y)) <= 1.0001, "committed ordinary leg exceeds adjacent component")
	enclosure_frames = enclosure_frames + 1 if quadrants.size() == 4 else 0
	return target_seen == ACTOR_COUNT and enclosure_frames >= 60 and player.current_hp < player.max_hp and _all_served_or_blocked()

func _all_served_or_blocked() -> bool:
	for actor: EnemyActor in actors:
		if float(actual_motion.get(actor.get_instance_id(), 0.0)) > GU.EPSILON_GU or actor._hc_access(player) == "CLEAR":
			continue
		var origin := _ground(actor)
		var next := Step.next_leg(origin, _ground(player), 1.0, GU.EPSILON_GU)
		# A fresh clear ordinary approach cannot remain completely unserved.
		if next.is_finite() and actor._hc_motion_clear(origin, next):
			return false
	return true

func _validate_progress(_moved: int, _clear_attackers: int, sectors: Dictionary) -> void:
	_check(enclosure_frames >= 60, "no sustained four-quadrant real-attack enclosure")
	_check(maximum_hold_motion <= GU.EPSILON_GU, "legal front attacker moved during stationary-player hold")
	_check(_all_served_or_blocked(), "free rear approach received neither motion nor legal attack")
	_check(sectors.size() >= 4, "crowd lacks multiple surrounding directions")

func _evidence_path() -> String:
	return "res://outputs/test_logs/settled_crowd_surround.json"

func _test_marker() -> String:
	return "SETTLED_CROWD_SURROUND_"
