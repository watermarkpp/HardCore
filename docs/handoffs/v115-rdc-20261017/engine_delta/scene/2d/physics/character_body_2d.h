/**************************************************************************/
/*  character_body_2d.h                                                   */
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

#pragma once

#include "scene/2d/physics/character_motion_2d.h"
#include "scene/2d/physics/kinematic_collision_2d.h"
#include "scene/2d/physics/physics_body_2d.h"

class CharacterBody2D : public PhysicsBody2D, protected CharacterMotion2DState {
	GDCLASS(CharacterBody2D, PhysicsBody2D);

public:
	enum MotionMode {
		MOTION_MODE_GROUNDED,
		MOTION_MODE_FLOATING,
	};
	enum PlatformOnLeave {
		PLATFORM_ON_LEAVE_ADD_VELOCITY,
		PLATFORM_ON_LEAVE_ADD_UPWARD_VELOCITY,
		PLATFORM_ON_LEAVE_DO_NOTHING,
	};
	bool move_and_slide();
	// Internal deterministic adapter entry; script API retains its original delta source.
	bool move_and_slide_with_delta(double p_delta);
	void apply_floor_snap();

	const Vector2 &get_velocity() const;
	void set_velocity(const Vector2 &p_velocity);

	bool is_on_floor() const;
	bool is_on_floor_only() const;
	bool is_on_wall() const;
	bool is_on_wall_only() const;
	bool is_on_ceiling() const;
	bool is_on_ceiling_only() const;
	const Vector2 &get_last_motion() const;
	Vector2 get_position_delta() const;
	const Vector2 &get_floor_normal() const;
	const Vector2 &get_wall_normal() const;
	const Vector2 &get_real_velocity() const;

	real_t get_floor_angle(const Vector2 &p_up_direction = Vector2(0.0, -1.0)) const;
	const Vector2 &get_platform_velocity() const;

	int get_slide_collision_count() const;
	PhysicsServer2D::MotionResult get_slide_collision(int p_bounce) const;

	void set_safe_margin(real_t p_margin);
	real_t get_safe_margin() const;

	bool is_floor_stop_on_slope_enabled() const;
	void set_floor_stop_on_slope_enabled(bool p_enabled);

	bool is_floor_constant_speed_enabled() const;
	void set_floor_constant_speed_enabled(bool p_enabled);

	bool is_floor_block_on_wall_enabled() const;
	void set_floor_block_on_wall_enabled(bool p_enabled);

	bool is_slide_on_ceiling_enabled() const;
	void set_slide_on_ceiling_enabled(bool p_enabled);

	int get_max_slides() const;
	void set_max_slides(int p_max_slides);

	real_t get_floor_max_angle() const;
	void set_floor_max_angle(real_t p_radians);

	real_t get_floor_snap_length();
	void set_floor_snap_length(real_t p_floor_snap_length);

	real_t get_wall_min_slide_angle() const;
	void set_wall_min_slide_angle(real_t p_radians);

	uint32_t get_platform_floor_layers() const;
	void set_platform_floor_layers(const uint32_t p_exclude_layer);

	uint32_t get_platform_wall_layers() const;
	void set_platform_wall_layers(const uint32_t p_exclude_layer);

	void set_motion_mode(MotionMode p_mode);
	MotionMode get_motion_mode() const;

	void set_platform_on_leave(PlatformOnLeave p_on_leave_velocity);
	PlatformOnLeave get_platform_on_leave() const;

	CharacterBody2D();

private:
	Vector<Ref<KinematicCollision2D>> slide_colliders;

	Ref<KinematicCollision2D> _get_slide_collision(int p_bounce);
	Ref<KinematicCollision2D> _get_last_slide_collision();
	const Vector2 &get_up_direction() const;
	void set_up_direction(const Vector2 &p_up_direction);

protected:
	void _notification(int p_what);
	static void _bind_methods();
	void _validate_property(PropertyInfo &p_property) const;
};

VARIANT_ENUM_CAST(CharacterBody2D::MotionMode);
VARIANT_ENUM_CAST(CharacterBody2D::PlatformOnLeave);
