#pragma once
#include "scene/2d/physics/character_motion_2d.h"
#include "servers/physics_2d/physics_server_2d_wrap_mt.h"

namespace hardcore::simulation {
// The host registry decides CharacterBody capability by the original collider
// ID and RID. Never resolve an active Main Node from the S adapter.
class MotionIdentityRegistry {
public:
	virtual ~MotionIdentityRegistry() = default;
	virtual bool is_character(ObjectID object, RID body) const = 0;
};

class GodotCharacterMotionAdapter;
class MotionTransformQueue {
public:
	virtual ~MotionTransformQueue() = default;
	// The host enqueues only the first notification, in original insertion order.
	// It must flush at the mapped SceneTree/force_update_transform boundaries.
	virtual void enqueue_transform(GodotCharacterMotionAdapter &body) = 0;
};

// This adapter owns no solver or duplicate move kernel. The caller owns the
// logical transform, source CharacterMotion2DState, registry and flush queue.
class GodotCharacterMotionAdapter final : public CharacterMotion2DAdapter {
	PhysicsServer2DWrapMT &server_;
	RID body_;
	Transform2D &logical_transform_;
	const MotionIdentityRegistry &identities_;
	MotionTransformQueue &transforms_;
	bool transform_pending_ = false;
public:
	GodotCharacterMotionAdapter(PhysicsServer2DWrapMT &server, RID body, Transform2D &logical_transform, const MotionIdentityRegistry &identities, MotionTransformQueue &transforms) :
		server_(server), body_(body), logical_transform_(logical_transform), identities_(identities), transforms_(transforms) {}
	Transform2D get_transform() const override { return logical_transform_; }
	void set_transform(const Transform2D &transform) override;
	bool test_motion(const PhysicsServer2D::MotionParameters &parameters, PhysicsServer2D::MotionResult &result) override;
	PhysicsDirectBodyState2D *body_get_direct_state(RID body) override;
	uint32_t get_collision_layer(PhysicsDirectBodyState2D *state, RID body) override;
	bool is_character(ObjectID object, RID body) override;
	void flush_transform();
	bool is_transform_pending() const { return transform_pending_; }
	RID get_body() const { return body_; }
};
} // namespace hardcore::simulation
