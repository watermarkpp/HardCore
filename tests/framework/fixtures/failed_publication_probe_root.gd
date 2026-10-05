extends "res://tests/framework/fixtures/published_birth_probe_root.gd"

# Author a malformed extra descriptor through the real cold collection. The
# original publication, failure owner and recovery transition all still run.
var reject_home_publication := false
var home_operations := 0

func _complete_service_home_travel(red_name: bool, initial: bool, fallback_zone: String, after_arrival: Callable) -> void:
	home_operations += 1
	super._complete_service_home_travel(red_name, initial, fallback_zone, after_arrival)
	if reject_home_publication:
		_spawn_enemy({"monster_id": 19.5}, _canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5)), false, -1.0,
			{"respawn_enabled": false, "spawn_slot_id": "test:failed-publication:home"})
