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

#pragma once

#include "servers/physics_2d/physics_server_2d.h"

// Adapters provide access only; every movement decision is in the shared code.
struct PhysicsMotion2DAdapter {
	virtual ~PhysicsMotion2DAdapter() = default;
	virtual Transform2D get_transform() const = 0;
	virtual void set_transform(const Transform2D &p_transform) = 0;
	virtual bool test_motion(const PhysicsServer2D::MotionParameters &p_parameters, PhysicsServer2D::MotionResult &r_result) = 0;
	virtual bool only_update_transform_changes() const { return false; }
};

struct CharacterMotion2DAdapter : PhysicsMotion2DAdapter {
	virtual PhysicsDirectBodyState2D *body_get_direct_state(RID p_body) = 0;
	virtual uint32_t get_collision_layer(PhysicsDirectBodyState2D *p_state, RID p_body) = 0;
	virtual bool is_character(ObjectID p_object, RID p_body) = 0;
};

bool physics_motion_2d_move_and_collide(PhysicsMotion2DAdapter &p_adapter, const PhysicsServer2D::MotionParameters &p_parameters, PhysicsServer2D::MotionResult &r_result, bool p_test_only = false, bool p_cancel_sliding = true);

// Original CharacterBody2D motion state. Node and S each own one instance.
struct CharacterMotion2DState {
	real_t margin = 0.08;
	int motion_mode = 0;
	int platform_on_leave = 0;

	bool floor_constant_speed = false;
	bool floor_stop_on_slope = true;
	bool floor_block_on_wall = true;
	bool slide_on_ceiling = true;
	int max_slides = 4;
	int platform_layer = 0;
	real_t floor_max_angle = Math::deg_to_rad((real_t)45.0);
	real_t floor_snap_length = 1;
	real_t wall_min_slide_angle = Math::deg_to_rad((real_t)15.0);
	Vector2 up_direction = Vector2(0.0, -1.0);
	uint32_t platform_floor_layers = UINT32_MAX;
	uint32_t platform_wall_layers = 0;
	Vector2 velocity;

	Vector2 floor_normal;
	Vector2 platform_velocity;
	Vector2 wall_normal;
	Vector2 last_motion;
	Vector2 previous_position;
	Vector2 real_velocity;

	RID platform_rid;
	ObjectID platform_object_id;
	bool on_floor = false;
	bool on_ceiling = false;
	bool on_wall = false;

	Vector<PhysicsServer2D::MotionResult> motion_results;

	bool move_and_slide(CharacterMotion2DAdapter &p_adapter, double delta);
	void _move_and_slide_grounded(CharacterMotion2DAdapter &p_adapter, double p_delta, bool p_was_on_floor);
	void _move_and_slide_floating(CharacterMotion2DAdapter &p_adapter, double p_delta);
	void _apply_floor_snap(CharacterMotion2DAdapter &p_adapter, bool p_wall_as_floor = false);
	void _snap_on_floor(CharacterMotion2DAdapter &p_adapter, bool p_was_on_floor, bool p_vel_dir_facing_up, bool p_wall_as_floor = false);
	bool _on_floor_if_snapped(CharacterMotion2DAdapter &p_adapter, bool p_was_on_floor, bool p_vel_dir_facing_up);
	void _set_collision_direction(CharacterMotion2DAdapter &p_adapter, const PhysicsServer2D::MotionResult &p_result);
	void _set_platform_data(CharacterMotion2DAdapter &p_adapter, const PhysicsServer2D::MotionResult &p_result);
};
