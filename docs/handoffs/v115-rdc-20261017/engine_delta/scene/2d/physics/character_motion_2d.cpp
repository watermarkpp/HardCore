/**************************************************************************/
/*  character_body_2d.cpp                                                 */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "character_motion_2d.h"

// Mechanically extracted from pinned Godot 4.7; see extraction manifest.
#define FLOOR_ANGLE_THRESHOLD 0.01

bool physics_motion_2d_move_and_collide(PhysicsMotion2DAdapter &p_adapter, const PhysicsServer2D::MotionParameters &p_parameters, PhysicsServer2D::MotionResult &r_result, bool p_test_only, bool p_cancel_sliding) {
	if (p_adapter.only_update_transform_changes()) {
		ERR_PRINT("Move functions do not work together with 'sync to physics' option. See the documentation for details.");
	}

	bool colliding = p_adapter.test_motion(p_parameters, r_result);

	// Restore direction of motion to be along original motion,
	// in order to avoid sliding due to recovery,
	// but only if collision depth is low enough to avoid tunneling.
	if (p_cancel_sliding) {
		real_t motion_length = p_parameters.motion.length();
		real_t precision = 0.001;

		if (colliding) {
			// Can't just use margin as a threshold because collision depth is calculated on unsafe motion,
			// so even in normal resting cases the depth can be a bit more than the margin.
			precision += motion_length * (r_result.collision_unsafe_fraction - r_result.collision_safe_fraction);

			if (r_result.collision_depth > p_parameters.margin + precision) {
				p_cancel_sliding = false;
			}
		}

		if (p_cancel_sliding) {
			// When motion is null, recovery is the resulting motion.
			Vector2 motion_normal;
			if (motion_length > CMP_EPSILON) {
				motion_normal = p_parameters.motion / motion_length;
			}

			// Check depth of recovery.
			real_t projected_length = r_result.travel.dot(motion_normal);
			Vector2 recovery = r_result.travel - motion_normal * projected_length;
			real_t recovery_length = recovery.length();
			// Fixes cases where canceling slide causes the motion to go too deep into the ground,
			// because we're only taking rest information into account and not general recovery.
			if (recovery_length < p_parameters.margin + precision) {
				// Apply adjustment to motion.
				r_result.travel = motion_normal * projected_length;
				r_result.remainder = p_parameters.motion - r_result.travel;
			}
		}
	}

	if (!p_test_only) {
		Transform2D gt = p_parameters.from;
		gt.columns[2] += r_result.travel;
		p_adapter.set_transform(gt);
	}

	return colliding;
}

bool CharacterMotion2DState::move_and_slide(CharacterMotion2DAdapter &p_adapter, double delta) {
	Vector2 current_platform_velocity = platform_velocity;
	Transform2D gt = p_adapter.get_transform();
	previous_position = gt.columns[2];

	if ((on_floor || on_wall) && platform_rid.is_valid()) {
		bool excluded = false;
		if (on_floor) {
			excluded = (platform_floor_layers & platform_layer) == 0;
		} else if (on_wall) {
			excluded = (platform_wall_layers & platform_layer) == 0;
		}
		if (!excluded) {
			//this approach makes sure there is less delay between the actual body velocity and the one we saved
			PhysicsDirectBodyState2D *bs = p_adapter.body_get_direct_state(platform_rid);
			if (bs) {
				Vector2 local_position = gt.columns[2] - bs->get_transform().columns[2];
				current_platform_velocity = bs->get_velocity_at_local_position(local_position);
			} else {
				// Body is removed or destroyed, invalidate floor.
				current_platform_velocity = Vector2();
				platform_rid = RID();
			}
		} else {
			current_platform_velocity = Vector2();
		}
	}

	motion_results.clear();
	last_motion = Vector2();

	bool was_on_floor = on_floor;
	on_floor = false;
	on_ceiling = false;
	on_wall = false;

	if (!current_platform_velocity.is_zero_approx()) {
		PhysicsServer2D::MotionParameters parameters(p_adapter.get_transform(), current_platform_velocity * delta, margin);
		parameters.recovery_as_collision = true; // Also report collisions generated only from recovery.
		parameters.exclude_bodies.insert(platform_rid);
		if (platform_object_id.is_valid()) {
			parameters.exclude_objects.insert(platform_object_id);
		}

		PhysicsServer2D::MotionResult floor_result;
		if (physics_motion_2d_move_and_collide(p_adapter, parameters, floor_result, false, false)) {
			motion_results.push_back(floor_result);
			_set_collision_direction(p_adapter, floor_result);
		}
	}

	if (motion_mode == 0) {
		_move_and_slide_grounded(p_adapter, delta, was_on_floor);
	} else {
		_move_and_slide_floating(p_adapter, delta);
	}

	// Compute real velocity.
	real_velocity = (p_adapter.get_transform().columns[2] - previous_position) / delta;

	if (platform_on_leave != 2) {
		// Add last platform velocity when just left a moving platform.
		if (!on_floor && !on_wall) {
			if (platform_on_leave == 1 && current_platform_velocity.dot(up_direction) < 0) {
				current_platform_velocity = current_platform_velocity.slide(up_direction);
			}
			velocity += current_platform_velocity;
		}
	}

	return motion_results.size() > 0;
}

void CharacterMotion2DState::_move_and_slide_grounded(CharacterMotion2DAdapter &p_adapter, double p_delta, bool p_was_on_floor) {
	Vector2 motion = velocity * p_delta;
	Vector2 motion_slide_up = motion.slide(up_direction);

	Vector2 prev_floor_normal = floor_normal;

	platform_rid = RID();
	platform_object_id = ObjectID();
	floor_normal = Vector2();
	platform_velocity = Vector2();

	// No sliding on first attempt to keep floor motion stable when possible,
	// When stop on slope is enabled or when there is no up direction.
	bool sliding_enabled = !floor_stop_on_slope;
	// Constant speed can be applied only the first time sliding is enabled.
	bool can_apply_constant_speed = sliding_enabled;
	// If the platform's ceiling push down the body.
	bool apply_ceiling_velocity = false;
	bool first_slide = true;
	bool vel_dir_facing_up = velocity.dot(up_direction) > 0;
	Vector2 last_travel;

	for (int iteration = 0; iteration < max_slides; ++iteration) {
		PhysicsServer2D::MotionParameters parameters(p_adapter.get_transform(), motion, margin);
		parameters.recovery_as_collision = true; // Also report collisions generated only from recovery.

		Vector2 prev_position = parameters.from.columns[2];

		PhysicsServer2D::MotionResult result;
		bool collided = physics_motion_2d_move_and_collide(p_adapter, parameters, result, false, !sliding_enabled);

		last_motion = result.travel;

		if (collided) {
			motion_results.push_back(result);
			_set_collision_direction(p_adapter, result);

			// If we hit a ceiling platform, we set the vertical velocity to at least the platform one.
			if (on_ceiling && result.collider_velocity != Vector2() && result.collider_velocity.dot(up_direction) < 0) {
				// If ceiling sliding is on, only apply when the ceiling is flat or when the motion is upward.
				if (!slide_on_ceiling || motion.dot(up_direction) < 0 || (result.collision_normal + up_direction).length() < 0.01) {
					apply_ceiling_velocity = true;
					Vector2 ceiling_vertical_velocity = up_direction * up_direction.dot(result.collider_velocity);
					Vector2 motion_vertical_velocity = up_direction * up_direction.dot(velocity);
					if (motion_vertical_velocity.dot(up_direction) > 0 || ceiling_vertical_velocity.length_squared() > motion_vertical_velocity.length_squared()) {
						velocity = ceiling_vertical_velocity + velocity.slide(up_direction);
					}
				}
			}

			if (on_floor && floor_stop_on_slope && (velocity.normalized() + up_direction).length() < 0.01) {
				Transform2D gt = p_adapter.get_transform();
				if (result.travel.length() <= margin + CMP_EPSILON) {
					gt.columns[2] -= result.travel;
				}
				p_adapter.set_transform(gt);
				velocity = Vector2();
				last_motion = Vector2();
				motion = Vector2();
				break;
			}

			if (result.remainder.is_zero_approx()) {
				motion = Vector2();
				break;
			}

			// Move on floor only checks.
			if (floor_block_on_wall && on_wall && motion_slide_up.dot(result.collision_normal) <= 0) {
				// Avoid to move forward on a wall if floor_block_on_wall is true.
				if (p_was_on_floor && !on_floor && !vel_dir_facing_up) {
					// If the movement is large the body can be prevented from reaching the walls.
					if (result.travel.length() <= margin + CMP_EPSILON) {
						// Cancels the motion.
						Transform2D gt = p_adapter.get_transform();
						gt.columns[2] -= result.travel;
						p_adapter.set_transform(gt);
					}
					// Determines if you are on the ground.
					_snap_on_floor(p_adapter, true, false, true);
					velocity = Vector2();
					last_motion = Vector2();
					motion = Vector2();
					break;
				}
				// Prevents the body from being able to climb a slope when it moves forward against the wall.
				else if (!on_floor) {
					motion = up_direction * up_direction.dot(result.remainder);
					motion = motion.slide(result.collision_normal);
				} else {
					motion = result.remainder;
				}
			}
			// Constant Speed when the slope is upward.
			else if (floor_constant_speed && (on_floor && !on_wall && !on_ceiling) && can_apply_constant_speed && p_was_on_floor && motion.dot(result.collision_normal) < 0) {
				can_apply_constant_speed = false;
				Vector2 motion_slide_norm = result.remainder.slide(result.collision_normal).normalized();
				motion = motion_slide_norm * (motion_slide_up.length() - result.travel.slide(up_direction).length() - last_travel.slide(up_direction).length());
			}
			// Regular sliding, the last part of the test handle the case when you don't want to slide on the ceiling.
			else if ((sliding_enabled || !on_floor) && (!on_ceiling || slide_on_ceiling || !vel_dir_facing_up) && !apply_ceiling_velocity) {
				Vector2 slide_motion = result.remainder.slide(result.collision_normal);
				if (slide_motion.dot(velocity) > 0.0) {
					motion = slide_motion;
				} else {
					motion = Vector2();
				}
				if (slide_on_ceiling && on_ceiling) {
					// Apply slide only in the direction of the input motion, otherwise just stop to avoid jittering when moving against a wall.
					if (vel_dir_facing_up) {
						velocity = velocity.slide(result.collision_normal);
					} else {
						// Avoid acceleration in slope when falling.
						velocity = up_direction * up_direction.dot(velocity);
					}
				}
			}
			// No sliding on first attempt to keep floor motion stable when possible.
			else {
				motion = result.remainder;
				if (on_ceiling && !slide_on_ceiling && vel_dir_facing_up) {
					velocity = velocity.slide(up_direction);
					motion = motion.slide(up_direction);
				}
			}

			last_travel = result.travel;
		}
		// When you move forward in a downward slope you don’t collide because you will be in the air.
		// This test ensures that constant speed is applied, only if the player is still on the ground after the snap is applied.
		else if (floor_constant_speed && first_slide && _on_floor_if_snapped(p_adapter, p_was_on_floor, vel_dir_facing_up)) {
			can_apply_constant_speed = false;
			sliding_enabled = true;
			Transform2D gt = p_adapter.get_transform();
			gt.columns[2] = prev_position;
			p_adapter.set_transform(gt);

			Vector2 motion_slide_norm = motion.slide(prev_floor_normal).normalized();
			motion = motion_slide_norm * (motion_slide_up.length());
			collided = true;
		}

		can_apply_constant_speed = !can_apply_constant_speed && !sliding_enabled;
		sliding_enabled = true;
		first_slide = false;

		if (!collided || motion.is_zero_approx()) {
			break;
		}
	}

	_snap_on_floor(p_adapter, p_was_on_floor, vel_dir_facing_up);

	// Scales the horizontal velocity according to the wall slope.
	if ((on_wall && !on_floor && !on_ceiling) && motion_slide_up.dot(motion_results.get(0).collision_normal) < 0) {
		Vector2 slide_motion = velocity.slide(motion_results.get(0).collision_normal);
		if (motion_slide_up.dot(slide_motion) < 0) {
			velocity = up_direction * up_direction.dot(velocity);
		} else {
			// Keeps the vertical motion from velocity and add the horizontal motion of the projection.
			velocity = up_direction * up_direction.dot(velocity) + slide_motion.slide(up_direction);
		}
	}

	// Reset the gravity accumulation when touching the ground.
	if (on_floor && !vel_dir_facing_up) {
		velocity = velocity.slide(up_direction);
	}
}

void CharacterMotion2DState::_move_and_slide_floating(CharacterMotion2DAdapter &p_adapter, double p_delta) {
	Vector2 motion = velocity * p_delta;

	platform_rid = RID();
	platform_object_id = ObjectID();
	floor_normal = Vector2();
	platform_velocity = Vector2();

	bool first_slide = true;
	for (int iteration = 0; iteration < max_slides; ++iteration) {
		PhysicsServer2D::MotionParameters parameters(p_adapter.get_transform(), motion, margin);
		parameters.recovery_as_collision = true; // Also report collisions generated only from recovery.

		PhysicsServer2D::MotionResult result;
		bool collided = physics_motion_2d_move_and_collide(p_adapter, parameters, result, false, false);

		last_motion = result.travel;

		if (collided) {
			motion_results.push_back(result);
			_set_collision_direction(p_adapter, result);

			if (result.remainder.is_zero_approx()) {
				motion = Vector2();
				break;
			}

			if (wall_min_slide_angle != 0 && result.get_angle(-velocity.normalized()) < wall_min_slide_angle + FLOOR_ANGLE_THRESHOLD) {
				motion = Vector2();
			} else if (first_slide) {
				Vector2 motion_slide_norm = result.remainder.slide(result.collision_normal).normalized();
				motion = motion_slide_norm * (motion.length() - result.travel.length());
			} else {
				motion = result.remainder.slide(result.collision_normal);
			}

			if (motion.dot(velocity) <= 0.0) {
				motion = Vector2();
			}
		}

		if (!collided || motion.is_zero_approx()) {
			break;
		}

		first_slide = false;
	}
}

void CharacterMotion2DState::_apply_floor_snap(CharacterMotion2DAdapter &p_adapter, bool p_wall_as_floor) {
	if (on_floor) {
		return;
	}

	// Snap by at least collision margin to keep floor state consistent.
	real_t length = MAX(floor_snap_length, margin);

	PhysicsServer2D::MotionParameters parameters(p_adapter.get_transform(), -up_direction * length, margin);
	parameters.recovery_as_collision = true; // Also report collisions generated only from recovery.
	parameters.collide_separation_ray = true;

	PhysicsServer2D::MotionResult result;
	if (physics_motion_2d_move_and_collide(p_adapter, parameters, result, true, false)) {
		if ((result.get_angle(up_direction) <= floor_max_angle + FLOOR_ANGLE_THRESHOLD) ||
				(p_wall_as_floor && result.get_angle(-up_direction) > floor_max_angle + FLOOR_ANGLE_THRESHOLD)) {
			on_floor = true;
			floor_normal = result.collision_normal;
			_set_platform_data(p_adapter, result);

			// Ensure that we only move the body along the up axis, because
			// move_and_collide may stray the object a bit when getting it unstuck.
			// Canceling this motion should not affect move_and_slide, as previous
			// calls to move_and_collide already took care of freeing the body.
			if (result.travel.length() > margin) {
				result.travel = up_direction * up_direction.dot(result.travel);
			} else {
				result.travel = Vector2();
			}

			parameters.from.columns[2] += result.travel;
			p_adapter.set_transform(parameters.from);
		}
	}
}

void CharacterMotion2DState::_snap_on_floor(CharacterMotion2DAdapter &p_adapter, bool p_was_on_floor, bool p_vel_dir_facing_up, bool p_wall_as_floor) {
	if (on_floor || !p_was_on_floor || p_vel_dir_facing_up) {
		return;
	}

	_apply_floor_snap(p_adapter, p_wall_as_floor);
}

bool CharacterMotion2DState::_on_floor_if_snapped(CharacterMotion2DAdapter &p_adapter, bool p_was_on_floor, bool p_vel_dir_facing_up) {
	if (up_direction == Vector2() || on_floor || !p_was_on_floor || p_vel_dir_facing_up) {
		return false;
	}

	// Snap by at least collision margin to keep floor state consistent.
	real_t length = MAX(floor_snap_length, margin);

	PhysicsServer2D::MotionParameters parameters(p_adapter.get_transform(), -up_direction * length, margin);
	parameters.recovery_as_collision = true; // Also report collisions generated only from recovery.
	parameters.collide_separation_ray = true;

	PhysicsServer2D::MotionResult result;
	if (physics_motion_2d_move_and_collide(p_adapter, parameters, result, true, false)) {
		if (result.get_angle(up_direction) <= floor_max_angle + FLOOR_ANGLE_THRESHOLD) {
			return true;
		}
	}

	return false;
}

void CharacterMotion2DState::_set_collision_direction(CharacterMotion2DAdapter &p_adapter, const PhysicsServer2D::MotionResult &p_result) {
	if (motion_mode == 0 && p_result.get_angle(up_direction) <= floor_max_angle + FLOOR_ANGLE_THRESHOLD) { //floor
		on_floor = true;
		floor_normal = p_result.collision_normal;
		_set_platform_data(p_adapter, p_result);
	} else if (motion_mode == 0 && p_result.get_angle(-up_direction) <= floor_max_angle + FLOOR_ANGLE_THRESHOLD) { //ceiling
		on_ceiling = true;
	} else {
		on_wall = true;
		wall_normal = p_result.collision_normal;
		// Don't apply wall velocity when the collider is a CharacterBody2D.
		if (!p_adapter.is_character(p_result.collider_id, p_result.collider)) {
			_set_platform_data(p_adapter, p_result);
		}
	}
}

void CharacterMotion2DState::_set_platform_data(CharacterMotion2DAdapter &p_adapter, const PhysicsServer2D::MotionResult &p_result) {
	PhysicsDirectBodyState2D *bs = p_adapter.body_get_direct_state(p_result.collider);
	if (bs == nullptr) {
		return;
	}

	platform_rid = p_result.collider;
	platform_object_id = p_result.collider_id;
	platform_velocity = p_result.collider_velocity;

	platform_layer = p_adapter.get_collision_layer(bs, p_result.collider);

}
