#include "motion_adapter.h"
namespace hardcore::simulation {
void GodotCharacterMotionAdapter::set_transform(const Transform2D &transform) {
	logical_transform_ = transform;
	if (!transform_pending_) {
		transform_pending_ = true;
		transforms_.enqueue_transform(*this);
	}
}
void GodotCharacterMotionAdapter::flush_transform() {
	if (!transform_pending_) return;
	transform_pending_ = false;
	server_.body_set_state(body_, PhysicsServer2D::BODY_STATE_TRANSFORM, logical_transform_);
}
bool GodotCharacterMotionAdapter::test_motion(const PhysicsServer2D::MotionParameters &parameters, PhysicsServer2D::MotionResult &result) {
	return server_.body_test_motion(body_, parameters, &result);
}
PhysicsDirectBodyState2D *GodotCharacterMotionAdapter::body_get_direct_state(RID body) {
	return server_.body_get_direct_state(body);
}
uint32_t GodotCharacterMotionAdapter::get_collision_layer(PhysicsDirectBodyState2D *state, RID) {
	return state->get_collision_layer();
}
bool GodotCharacterMotionAdapter::is_character(ObjectID object, RID body) {
	return identities_.is_character(object, body);
}
} // namespace hardcore::simulation
