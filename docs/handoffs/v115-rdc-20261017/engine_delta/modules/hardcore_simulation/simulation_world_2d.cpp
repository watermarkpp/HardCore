#include "simulation_world_2d.h"
#include "numeric_point_query_scope.h"

#include "core/object/class_db.h"
#include <algorithm>
#include <cmath>

namespace {
bool number(const Variant &p_value) {
	return (p_value.get_type() == Variant::INT || p_value.get_type() == Variant::FLOAT) && std::isfinite(static_cast<double>(p_value));
}
bool mask_valid(int64_t p_value) { return p_value >= 0 && uint64_t(p_value) <= UINT32_MAX; }
bool transform_valid(const Transform2D &p_transform) {
	return p_transform[0].is_finite() && p_transform[1].is_finite() && p_transform[2].is_finite() && !Math::is_zero_approx(p_transform.determinant());
}
Dictionary failure(const String &p_reason) {
	Dictionary result;
	result["ok"] = false;
	result["error"] = p_reason;
	// No collided=false on failure: consumers cannot interpret an access error
	// as a successful unobstructed movement or an unobstructed LOS.
	return result;
}
Dictionary motion_result(const PhysicsServer2D::MotionResult &p_result, bool p_collided) {
	Dictionary result;
	result["ok"] = true;
	result["collided"] = p_collided;
	result["travel"] = p_result.travel;
	result["remainder"] = p_result.remainder;
	result["collision_point"] = p_result.collision_point;
	result["collision_normal"] = p_result.collision_normal;
	result["collider_velocity"] = p_result.collider_velocity;
	result["collision_depth"] = p_result.collision_depth;
	result["collision_safe_fraction"] = p_result.collision_safe_fraction;
	result["collision_unsafe_fraction"] = p_result.collision_unsafe_fraction;
	result["collision_local_shape"] = p_result.collision_local_shape;
	result["collider_id"] = static_cast<int64_t>(uint64_t(p_result.collider_id));
	result["collider_rid"] = p_result.collider;
	result["collider_shape"] = p_result.collider_shape;
	return result;
}
bool convex_points_valid(const PackedVector2Array &p_points) {
	if (p_points.size() < 3) return false;
	real_t orientation = 0;
	for (int i = 0; i < p_points.size(); ++i) {
		if (!p_points[i].is_finite()) return false;
		real_t cross = (p_points[(i + 1) % p_points.size()] - p_points[i]).cross(p_points[(i + 2) % p_points.size()] - p_points[(i + 1) % p_points.size()]);
		if (Math::is_zero_approx(cross)) return false;
		if (i == 0) orientation = cross;
		else if ((cross > 0) != (orientation > 0)) return false;
	}
	return true;
}
} // namespace

bool HardCoreSimulationActorMotion2D::require_access(bool p_query) const {
	ERR_FAIL_COND_V_MSG(world == nullptr || adapter == nullptr, false, "Simulation actor motion is retired or was not created by its S world.");
	return world->require_access(p_query);
}
void HardCoreSimulationActorMotion2D::detach() {
	adapter.reset();
	world = nullptr;
	body = RID();
}
Vector2 HardCoreSimulationActorMotion2D::position_screen_px() const {
	ERR_FAIL_COND_V(!require_access(false), Vector2());
	return logical_transform.get_origin();
}
Vector2 HardCoreSimulationActorMotion2D::velocity_screen_px_per_sec() const {
	ERR_FAIL_COND_V(!require_access(false), Vector2());
	return motion.velocity;
}
bool HardCoreSimulationActorMotion2D::set_position_screen_px(const Vector2 &p_position) {
	ERR_FAIL_COND_V(!require_access(false) || !p_position.is_finite(), false);
	Transform2D updated = logical_transform;
	updated.set_origin(p_position);
	adapter->set_transform(updated);
	return true;
}
bool HardCoreSimulationActorMotion2D::set_velocity_screen_px_per_sec(const Vector2 &p_velocity) {
	ERR_FAIL_COND_V(!require_access(false) || !p_velocity.is_finite(), false);
	motion.velocity = p_velocity;
	return true;
}
bool HardCoreSimulationActorMotion2D::stop_velocity() { return set_velocity_screen_px_per_sec(Vector2()); }
double HardCoreSimulationActorMotion2D::safe_margin() const {
	// Default-property discovery may inspect an uncreated prototype. A retired
	// real actor keeps its canonical ID, so it cannot enter this constructor-only
	// branch or bypass the original world/owner access contract below.
	if (canonical_id == 0 && world == nullptr && adapter == nullptr && !body.is_valid()) return motion.margin;
	ERR_FAIL_COND_V(!require_access(false), -1.0);
	return motion.margin;
}
void HardCoreSimulationActorMotion2D::set_safe_margin(double p_margin) {
	ERR_FAIL_COND(!require_access(false) || !std::isfinite(p_margin) || p_margin < 0);
	motion.margin = p_margin;
}
Dictionary HardCoreSimulationActorMotion2D::collide_motion(const Vector2 &p_motion, bool p_test_only, double p_safe_margin, bool p_recovery_as_collision) {
	if (!require_access(true)) return failure("motion_owner_or_phase_violation");
	ERR_FAIL_COND_V(!p_motion.is_finite() || !std::isfinite(p_safe_margin) || p_safe_margin < 0, failure("invalid_motion_parameters"));
	PhysicsServer2D::MotionParameters parameters(logical_transform, p_motion, p_safe_margin);
	parameters.recovery_as_collision = p_recovery_as_collision;
	PhysicsServer2D::MotionResult result;
	const bool collided = physics_motion_2d_move_and_collide(*adapter, parameters, result, p_test_only);
	return motion_result(result, collided);
}
Dictionary HardCoreSimulationActorMotion2D::slide(double p_delta) {
	if (!require_access(true)) return failure("slide_owner_or_phase_violation");
	ERR_FAIL_COND_V(!std::isfinite(p_delta) || p_delta < 0, failure("invalid_slide_delta"));
	const bool collided = motion.move_and_slide(*adapter, p_delta);
	Dictionary result = state();
	result["collided"] = collided;
	return result;
}
Dictionary HardCoreSimulationActorMotion2D::state() const {
	if (!require_access(false)) return failure("actor_owner_or_lifetime_violation");
	Dictionary result;
	result["ok"] = true;
	result["canonical_id"] = canonical_id;
	result["body_rid"] = body;
	result["position_screen_px"] = logical_transform.get_origin();
	result["velocity_screen_px_per_sec"] = motion.velocity;
	result["safe_margin"] = motion.margin;
	result["motion_mode"] = motion.motion_mode;
	result["max_slides"] = motion.max_slides;
	result["previous_position"] = motion.previous_position;
	result["real_velocity"] = motion.real_velocity;
	result["last_motion"] = motion.last_motion;
	result["floor_normal"] = motion.floor_normal;
	result["wall_normal"] = motion.wall_normal;
	result["platform_velocity"] = motion.platform_velocity;
	result["platform_rid"] = motion.platform_rid;
	result["platform_object_id"] = static_cast<int64_t>(uint64_t(motion.platform_object_id));
	result["on_floor"] = motion.on_floor;
	result["on_ceiling"] = motion.on_ceiling;
	result["on_wall"] = motion.on_wall;
	result["transform_pending"] = adapter->is_transform_pending();
	Array collisions;
	for (const PhysicsServer2D::MotionResult &collision : motion.motion_results) collisions.push_back(motion_result(collision, true));
	result["slide_collisions"] = collisions;
	return result;
}
RID HardCoreSimulationActorMotion2D::get_body_rid() const {
	ERR_FAIL_COND_V(!require_access(false), RID());
	return body;
}
int64_t HardCoreSimulationActorMotion2D::get_canonical_id() const {
	ERR_FAIL_COND_V(!require_access(false), 0);
	return canonical_id;
}

HardCoreSimulationWorld2D::HardCoreSimulationWorld2D() {
	PhysicsServer2DWrapMT *candidate = Object::cast_to<PhysicsServer2DWrapMT>(PhysicsServer2D::get_singleton());
	ERR_FAIL_COND_MSG(candidate == nullptr || !candidate->is_external_owner_thread(), "Construct simulation world only on the claimed S physics owner; default-mode fallback is forbidden.");
	server = candidate;
	owner = Thread::get_caller_id();
}
HardCoreSimulationWorld2D::~HardCoreSimulationWorld2D() {
	if (initialized && !closed) {
		CRASH_COND_MSG(!require_access(false), "Live simulation world must be retired on S before host finish/join.");
		close();
	}
}
bool HardCoreSimulationWorld2D::require_access(bool p_query, bool p_require_initialized) const {
	ERR_FAIL_COND_V_MSG(owner != Thread::get_caller_id() || server == nullptr || server != PhysicsServer2D::get_singleton(), false, "Simulation world access requires its original S owner and singleton.");
	ERR_FAIL_COND_V_MSG(!server->is_external_owner_thread() || server->is_external_finished(), false, "Simulation world access after physics owner release is forbidden.");
	ERR_FAIL_COND_V_MSG(closed || (p_require_initialized && !initialized), false, "Simulation world is uninitialized or retired.");
	ERR_FAIL_COND_V_MSG(p_query && !server->is_external_query_phase(), false, "Simulation motion and LOS require the original H/P query phase.");
	return true;
}
bool HardCoreSimulationWorld2D::initialize(const Dictionary &p_default_area) {
	ERR_FAIL_COND_V(!require_access(false, false) || initialized, false);
	// These are Main-published exact numeric ProjectSettings values from the
	// same keys used by World2D::get_space. S never reads ProjectSettings.
	ERR_FAIL_COND_V(!number(p_default_area.get("gravity", Variant())) || !number(p_default_area.get("linear_damp", Variant())) || !number(p_default_area.get("angular_damp", Variant())), false);
	ERR_FAIL_COND_V(p_default_area.get("gravity_vector", Variant()).get_type() != Variant::VECTOR2, false);
	Vector2 gravity_vector = p_default_area["gravity_vector"];
	ERR_FAIL_COND_V(!gravity_vector.is_finite(), false);
	space = server->space_create();
	ERR_FAIL_COND_V(space.is_null(), false);
	server->space_set_active(space, true);
	server->area_set_param(space, PhysicsServer2D::AREA_PARAM_GRAVITY, p_default_area["gravity"]);
	server->area_set_param(space, PhysicsServer2D::AREA_PARAM_GRAVITY_VECTOR, gravity_vector);
	server->area_set_param(space, PhysicsServer2D::AREA_PARAM_LINEAR_DAMP, p_default_area["linear_damp"]);
	server->area_set_param(space, PhysicsServer2D::AREA_PARAM_ANGULAR_DAMP, p_default_area["angular_damp"]);
	initialized = true;
	return true;
}

bool HardCoreSimulationWorld2D::validate_shape(const Dictionary &p_shape) const {
	if (p_shape.get("type", Variant()).get_type() != Variant::INT || !p_shape.has("data")) return false;
	Variant data = p_shape["data"];
	int type = p_shape["type"];
	switch (type) {
		case PhysicsServer2D::SHAPE_RECTANGLE:
		case PhysicsServer2D::SHAPE_CAPSULE: {
			if (data.get_type() != Variant::VECTOR2) return false;
			Vector2 dimensions = data;
			if (!dimensions.is_finite() || dimensions.x <= 0 || dimensions.y <= 0) return false;
			break;
		}
		case PhysicsServer2D::SHAPE_CIRCLE:
			if (!number(data) || double(data) <= 0) return false;
			break;
		case PhysicsServer2D::SHAPE_CONVEX_POLYGON:
			if (data.get_type() != Variant::PACKED_VECTOR2_ARRAY || !convex_points_valid(data)) return false;
			break;
		case PhysicsServer2D::SHAPE_CONCAVE_POLYGON: {
			if (data.get_type() != Variant::PACKED_VECTOR2_ARRAY) return false;
			PackedVector2Array points = data;
			if (points.is_empty() || points.size() % 2 != 0) return false;
			for (const Vector2 &point : points) if (!point.is_finite()) return false;
			break;
		}
		case PhysicsServer2D::SHAPE_SEGMENT: {
			if (data.get_type() != Variant::RECT2) return false;
			Rect2 segment = data;
			if (!segment.position.is_finite() || !segment.size.is_finite() || segment.position == segment.size) return false;
			break;
		}
		default: return false; // Unsupported source descriptors fail explicitly.
	}
	if (p_shape.has("transform") && (p_shape["transform"].get_type() != Variant::TRANSFORM2D || !transform_valid(p_shape["transform"]))) return false;
	if (p_shape.has("disabled") && p_shape["disabled"].get_type() != Variant::BOOL) return false;
	if (p_shape.has("one_way") && p_shape["one_way"].get_type() != Variant::BOOL) return false;
	if (p_shape.has("one_way_margin") && (!number(p_shape["one_way_margin"]) || double(p_shape["one_way_margin"]) < 0)) return false;
	if (p_shape.has("one_way_direction") && (p_shape["one_way_direction"].get_type() != Variant::VECTOR2 || !Vector2(p_shape["one_way_direction"]).is_finite())) return false;
	if (p_shape.has("solver_bias") && !number(p_shape["solver_bias"])) return false;
	return true;
}
RID HardCoreSimulationWorld2D::create_shape(const Dictionary &p_shape) {
	RID shape;
	switch (int(p_shape["type"])) {
		case PhysicsServer2D::SHAPE_RECTANGLE: shape = server->rectangle_shape_create(); break;
		case PhysicsServer2D::SHAPE_CAPSULE: shape = server->capsule_shape_create(); break;
		case PhysicsServer2D::SHAPE_CIRCLE: shape = server->circle_shape_create(); break;
		case PhysicsServer2D::SHAPE_CONVEX_POLYGON: shape = server->convex_polygon_shape_create(); break;
		case PhysicsServer2D::SHAPE_CONCAVE_POLYGON: shape = server->concave_polygon_shape_create(); break;
		case PhysicsServer2D::SHAPE_SEGMENT: shape = server->segment_shape_create(); break;
	}
	ERR_FAIL_COND_V(shape.is_null(), RID());
	server->shape_set_data(shape, p_shape["data"]);
	if (p_shape.has("solver_bias")) server->shape_set_custom_solver_bias(shape, p_shape["solver_bias"]);
	return shape;
}

Ref<HardCoreSimulationActorMotion2D> HardCoreSimulationWorld2D::create_actor(int64_t p_canonical_id, const Dictionary &p_configuration) {
	ERR_FAIL_COND_V(!require_access(false), Ref<HardCoreSimulationActorMotion2D>());
	ERR_FAIL_COND_V(p_canonical_id <= 0 || bodies.count(p_canonical_id) != 0, Ref<HardCoreSimulationActorMotion2D>());
	ERR_FAIL_COND_V(p_configuration.get("footprint_points", Variant()).get_type() != Variant::PACKED_VECTOR2_ARRAY || p_configuration.get("position_screen_px", Variant()).get_type() != Variant::VECTOR2, Ref<HardCoreSimulationActorMotion2D>());
	PackedVector2Array points = p_configuration["footprint_points"];
	Vector2 position = p_configuration["position_screen_px"];
	// Main obtains these 16 numeric vertices from WorldSpatialRules. Do not
	// construct a Shape2D resource or regenerate trigonometry on S.
	ERR_FAIL_COND_V(points.size() != 16 || !convex_points_valid(points) || !position.is_finite(), Ref<HardCoreSimulationActorMotion2D>());
	ERR_FAIL_COND_V(p_configuration.get("collision_layer", Variant()).get_type() != Variant::INT || p_configuration.get("collision_mask", Variant()).get_type() != Variant::INT, Ref<HardCoreSimulationActorMotion2D>());
	int64_t layer = p_configuration["collision_layer"], mask = p_configuration["collision_mask"];
	ERR_FAIL_COND_V(!mask_valid(layer) || !mask_valid(mask), Ref<HardCoreSimulationActorMotion2D>());
	// Floating is the actual project contract. Reject an unported mode rather
	// than silently interpreting grounded settings as floating.
	ERR_FAIL_COND_V(int(p_configuration.get("motion_mode", 1)) != 1, Ref<HardCoreSimulationActorMotion2D>());
	Variant margin_value = p_configuration.get("safe_margin", 0.35);
	Variant slides_value = p_configuration.get("max_slides", 6);
	ERR_FAIL_COND_V(!number(margin_value) || double(margin_value) < 0 || slides_value.get_type() != Variant::INT || int64_t(slides_value) < 1 || int64_t(slides_value) > INT32_MAX, Ref<HardCoreSimulationActorMotion2D>());
	Variant wall_angle = p_configuration.get("wall_min_slide_angle", Math::deg_to_rad(15.0));
	Variant priority = p_configuration.get("collision_priority", 1.0);
	ERR_FAIL_COND_V(!number(wall_angle) || double(wall_angle) < 0 || !number(priority) || double(priority) <= 0, Ref<HardCoreSimulationActorMotion2D>());
	Dictionary shape_config;
	shape_config["type"] = PhysicsServer2D::SHAPE_CONVEX_POLYGON;
	shape_config["data"] = points;
	RID shape = create_shape(shape_config);
	ERR_FAIL_COND_V(shape.is_null(), Ref<HardCoreSimulationActorMotion2D>());
	RID body = server->body_create();
	if (body.is_null()) { server->free_rid(shape); return Ref<HardCoreSimulationActorMotion2D>(); }
	Ref<HardCoreSimulationActorMotion2D> actor;
	actor.instantiate();
	actor->world = this;
	actor->canonical_id = p_canonical_id;
	actor->body = body;
	actor->logical_transform.set_origin(position);
	actor->motion.motion_mode = 1;
	actor->motion.margin = margin_value;
	actor->motion.max_slides = slides_value;
	actor->motion.wall_min_slide_angle = wall_angle;
	actor->adapter = std::make_unique<hardcore::simulation::GodotCharacterMotionAdapter>(*server, body, actor->logical_transform,
			static_cast<const hardcore::simulation::MotionIdentityRegistry &>(*this), static_cast<hardcore::simulation::MotionTransformQueue &>(*this));
	server->body_set_mode(body, PhysicsServer2D::BODY_MODE_KINEMATIC);
	server->body_attach_object_instance_id(body, ObjectID(uint64_t(p_canonical_id)));
	server->body_set_collision_layer(body, uint32_t(layer));
	server->body_set_collision_mask(body, uint32_t(mask));
	server->body_set_collision_priority(body, priority);
	server->body_set_pickable(body, false);
	server->body_add_shape(body, shape, Transform2D(), false);
	server->body_set_state(body, PhysicsServer2D::BODY_STATE_TRANSFORM, actor->logical_transform);
	server->body_set_space(body, space);
	BodyEntry entry;
	entry.identity = p_canonical_id; entry.body = body; entry.shapes.push_back(shape); entry.actor = actor;
	bodies.emplace(p_canonical_id, std::move(entry));
	body_identities.emplace(body.get_id(), p_canonical_id);
	return actor;
}

RID HardCoreSimulationWorld2D::create_static_body(int64_t p_canonical_id, const Transform2D &p_transform, const Array &p_shapes, int64_t p_collision_layer, int64_t p_collision_mask) {
	ERR_FAIL_COND_V(!require_access(false) || p_canonical_id <= 0 || bodies.count(p_canonical_id) || !transform_valid(p_transform) || !mask_valid(p_collision_layer) || !mask_valid(p_collision_mask) || p_shapes.is_empty(), RID());
	for (int i = 0; i < p_shapes.size(); ++i) ERR_FAIL_COND_V(p_shapes[i].get_type() != Variant::DICTIONARY || !validate_shape(p_shapes[i]), RID());
	BodyEntry entry;
	entry.identity = p_canonical_id;
	entry.body = server->body_create();
	ERR_FAIL_COND_V(entry.body.is_null(), RID());
	server->body_set_mode(entry.body, PhysicsServer2D::BODY_MODE_STATIC);
	server->body_attach_object_instance_id(entry.body, ObjectID(uint64_t(p_canonical_id)));
	server->body_set_collision_layer(entry.body, uint32_t(p_collision_layer));
	server->body_set_collision_mask(entry.body, uint32_t(p_collision_mask));
	server->body_set_pickable(entry.body, false);
	server->body_set_state(entry.body, PhysicsServer2D::BODY_STATE_TRANSFORM, p_transform);
	for (int i = 0; i < p_shapes.size(); ++i) {
		Dictionary descriptor = p_shapes[i];
		RID shape = create_shape(descriptor);
		if (shape.is_null()) { release_body(entry); return RID(); }
		entry.shapes.push_back(shape);
		server->body_add_shape(entry.body, shape, descriptor.get("transform", Transform2D()), descriptor.get("disabled", false));
		server->body_set_shape_as_one_way_collision(entry.body, i, descriptor.get("one_way", false), descriptor.get("one_way_margin", 0.0), descriptor.get("one_way_direction", Vector2(0, 1)));
	}
	server->body_set_space(entry.body, space);
	RID result = entry.body;
	bodies.emplace(p_canonical_id, std::move(entry));
	body_identities.emplace(result.get_id(), p_canonical_id);
	return result;
}
HardCoreSimulationWorld2D::BodyEntry *HardCoreSimulationWorld2D::find_body(RID p_body) {
	auto found = body_identities.find(p_body.get_id());
	return found == body_identities.end() ? nullptr : &bodies.at(found->second);
}
const HardCoreSimulationWorld2D::BodyEntry *HardCoreSimulationWorld2D::find_body(RID p_body) const {
	auto found = body_identities.find(p_body.get_id());
	return found == body_identities.end() ? nullptr : &bodies.at(found->second);
}
bool HardCoreSimulationWorld2D::is_character(ObjectID p_object, RID p_body) const {
	CRASH_COND_MSG(!require_access(true), "Character capability access outside S query phase.");
	auto found = bodies.find(static_cast<int64_t>(uint64_t(p_object)));
	return found != bodies.end() && found->second.body == p_body && found->second.actor.is_valid();
}
void HardCoreSimulationWorld2D::enqueue_transform(hardcore::simulation::GodotCharacterMotionAdapter &p_body) {
	CRASH_COND_MSG(!require_access(false), "Transform enqueue outside S world lifetime.");
	// Adapter calls us only on the first pending notification. Retain original
	// insertion order, including repeated writes to the same logical position.
	transform_queue.push_back(&p_body);
}
bool HardCoreSimulationWorld2D::flush_transforms(const String &p_mapped_boundary) {
	ERR_FAIL_COND_V(!require_access(false) || p_mapped_boundary.is_empty(), false);
	last_flush_identities.clear();
	for (auto *adapter : transform_queue) {
		const BodyEntry *entry = find_body(adapter->get_body());
		CRASH_COND_MSG(entry == nullptr, "Queued transform references a retired body.");
		last_flush_identities.push_back(entry->identity);
		adapter->flush_transform();
	}
	transform_queue.clear();
	last_flush_boundary = p_mapped_boundary;
	++flush_serial;
	return true;
}
void HardCoreSimulationWorld2D::release_body(BodyEntry &p_entry) {
	if (p_entry.actor.is_valid()) {
		auto *adapter = p_entry.actor->adapter.get();
		transform_queue.erase(std::remove(transform_queue.begin(), transform_queue.end(), adapter), transform_queue.end());
		p_entry.actor->detach();
		p_entry.actor.unref();
	}
	server->body_set_space(p_entry.body, RID());
	server->free_rid(p_entry.body);
	body_identities.erase(p_entry.body.get_id());
	for (RID shape : p_entry.shapes) server->free_rid(shape);
	p_entry.shapes.clear();
}
bool HardCoreSimulationWorld2D::retire_body(RID p_body) {
	ERR_FAIL_COND_V(!require_access(false), false);
	BodyEntry *entry = find_body(p_body);
	ERR_FAIL_NULL_V(entry, false);
	int64_t identity = entry->identity;
	release_body(*entry);
	bodies.erase(identity);
	return true;
}
bool HardCoreSimulationWorld2D::retire_actor(int64_t p_canonical_id) {
	ERR_FAIL_COND_V(!require_access(false), false);
	auto found = bodies.find(p_canonical_id);
	ERR_FAIL_COND_V(found == bodies.end() || found->second.actor.is_null(), false);
	return retire_body(found->second.body);
}
bool HardCoreSimulationWorld2D::set_body_collision_filters(RID p_body, int64_t p_layer, int64_t p_mask) {
	ERR_FAIL_COND_V(!require_access(false) || find_body(p_body) == nullptr || !mask_valid(p_layer) || !mask_valid(p_mask), false);
	server->body_set_collision_layer(p_body, uint32_t(p_layer));
	server->body_set_collision_mask(p_body, uint32_t(p_mask));
	return true;
}
bool HardCoreSimulationWorld2D::set_body_collision_priority(RID p_body, double p_priority) {
	ERR_FAIL_COND_V(!require_access(false) || find_body(p_body) == nullptr || !std::isfinite(p_priority) || p_priority <= 0, false);
	server->body_set_collision_priority(p_body, p_priority);
	return true;
}
bool HardCoreSimulationWorld2D::set_body_pickable(RID p_body, bool p_pickable) {
    ERR_FAIL_COND_V(!require_access(false) || find_body(p_body) == nullptr, false);
    server->body_set_pickable(p_body, p_pickable);
    return true;
}
bool HardCoreSimulationWorld2D::set_body_shape_disabled(RID p_body, int p_shape, bool p_disabled) {
	ERR_FAIL_COND_V(!require_access(false), false);
	BodyEntry *entry = find_body(p_body);
	ERR_FAIL_COND_V(entry == nullptr || p_shape < 0 || size_t(p_shape) >= entry->shapes.size(), false);
	server->body_set_shape_disabled(p_body, p_shape, p_disabled);
	return true;
}
bool HardCoreSimulationWorld2D::set_body_shape_transform(RID p_body, int p_shape, const Transform2D &p_transform) {
	ERR_FAIL_COND_V(!require_access(false) || !transform_valid(p_transform), false);
	BodyEntry *entry = find_body(p_body);
	ERR_FAIL_COND_V(entry == nullptr || p_shape < 0 || size_t(p_shape) >= entry->shapes.size(), false);
	server->body_set_shape_transform(p_body, p_shape, p_transform);
	return true;
}
bool HardCoreSimulationWorld2D::set_body_one_way_collision(RID p_body, int p_shape, bool p_enabled, double p_margin, const Vector2 &p_direction) {
	ERR_FAIL_COND_V(!require_access(false) || !std::isfinite(p_margin) || p_margin < 0 || !p_direction.is_finite(), false);
	BodyEntry *entry = find_body(p_body);
	ERR_FAIL_COND_V(entry == nullptr || p_shape < 0 || size_t(p_shape) >= entry->shapes.size(), false);
	server->body_set_shape_as_one_way_collision(p_body, p_shape, p_enabled, p_margin, p_direction);
	return true;
}
bool HardCoreSimulationWorld2D::set_static_body_transform(RID p_body, const Transform2D &p_transform) {
	ERR_FAIL_COND_V(!require_access(false) || !transform_valid(p_transform), false);
	BodyEntry *entry = find_body(p_body);
	ERR_FAIL_COND_V(entry == nullptr || entry->actor.is_valid(), false);
	server->body_set_state(p_body, PhysicsServer2D::BODY_STATE_TRANSFORM, p_transform);
	return true;
}
bool HardCoreSimulationWorld2D::set_collision_exception(RID p_body, RID p_other, bool p_enabled) {
	ERR_FAIL_COND_V(!require_access(false) || p_body == p_other || find_body(p_body) == nullptr || find_body(p_other) == nullptr, false);
	if (p_enabled) server->body_add_collision_exception(p_body, p_other);
	else server->body_remove_collision_exception(p_body, p_other);
	return true;
}
Dictionary HardCoreSimulationWorld2D::intersect_ray(const Vector2 &p_from, const Vector2 &p_to, int64_t p_mask, const Array &p_exclude, bool p_collide_with_bodies, bool p_collide_with_areas, bool p_hit_from_inside) {
	if (!require_access(true)) return failure("ray_owner_or_phase_violation");
	ERR_FAIL_COND_V(!p_from.is_finite() || !p_to.is_finite() || !mask_valid(p_mask), failure("invalid_ray_parameters"));
	PhysicsDirectSpaceState2D::RayParameters parameters;
	parameters.from = p_from;
	parameters.to = p_to;
	parameters.collision_mask = uint32_t(p_mask);
	parameters.collide_with_bodies = p_collide_with_bodies;
	parameters.collide_with_areas = p_collide_with_areas;
	parameters.hit_from_inside = p_hit_from_inside;
	parameters.resolve_collider_object = false;
	for (int i = 0; i < p_exclude.size(); ++i) {
		ERR_FAIL_COND_V(p_exclude[i].get_type() != Variant::RID || find_body(p_exclude[i]) == nullptr, failure("ray_exclude_is_not_owned_body"));
		parameters.exclude.insert(p_exclude[i]);
	}
	PhysicsDirectSpaceState2D *direct = server->space_get_direct_state(space);
	ERR_FAIL_NULL_V(direct, failure("ray_direct_state_unavailable"));
	PhysicsDirectSpaceState2D::RayResult hit;
	bool collided = direct->intersect_ray(parameters, hit);
	CRASH_COND_MSG(hit.collider != nullptr, "S numeric ray unexpectedly resolved a live ObjectDB pointer.");
	Dictionary result;
	result["ok"] = true;
	result["collided"] = collided;
	if (collided) {
		result["position"] = hit.position;
		result["normal"] = hit.normal;
		result["rid"] = hit.rid;
		result["collider_id"] = static_cast<int64_t>(uint64_t(hit.collider_id));
		result["shape"] = hit.shape;
	}
	return result;
}
Dictionary HardCoreSimulationWorld2D::intersect_original_pick_point(const Vector2 &p_position, int64_t p_canvas_instance_id) {
    if (!require_access(true)) return failure("point_owner_or_phase_violation");
    ERR_FAIL_COND_V(!p_position.is_finite() || p_canvas_instance_id < 0, failure("invalid_point_parameters"));
    PhysicsDirectSpaceState2D::PointParameters parameters;
    parameters.position = p_position;
    parameters.canvas_instance_id = ObjectID(uint64_t(p_canvas_instance_id));
    parameters.collide_with_areas = true;
    parameters.pick_point = true;
    PhysicsDirectSpaceState2D *direct = server->space_get_direct_state(space);
    ERR_FAIL_NULL_V(direct, failure("point_direct_state_unavailable"));
    // Match original Viewport picking's 64 shape results and backend order.
    // The scoped backend switch changes only ObjectDB pointer resolution.
    PhysicsDirectSpaceState2D::ShapeResult hits[64];
    hardcore::simulation::ScopedNumericPointQuery numeric;
    const int count = direct->intersect_point(parameters, hits, 64);
    Array results;
    for (int n = 0; n < count; ++n) {
        CRASH_COND_MSG(hits[n].collider != nullptr, "S numeric point query resolved a live ObjectDB pointer.");
        const BodyEntry *entry = find_body(hits[n].rid);
        ERR_FAIL_COND_V(entry == nullptr || uint64_t(entry->identity) != uint64_t(hits[n].collider_id), failure("point_hit_identity_not_owned"));
        Dictionary hit; hit["collider_id"] = entry->identity; hit["rid"] = hits[n].rid; hit["shape"] = hits[n].shape;
        results.push_back(hit);
    }
    Dictionary result; result["ok"] = true; result["hits"] = results; result["limit"] = 64;
    return result;
}
Dictionary HardCoreSimulationWorld2D::intersect_shape_empty(const Ref<PhysicsShapeQueryParameters2D> &p_query) {
	if (!require_access(true)) return failure("shape_owner_or_phase_violation");
	ERR_FAIL_COND_V(p_query.is_null(), failure("shape_query_missing"));
	PhysicsDirectSpaceState2D::ShapeParameters parameters = p_query->get_parameters();
	ERR_FAIL_COND_V(!parameters.shape_rid.is_valid() || !transform_valid(parameters.transform) || !parameters.motion.is_finite() || !std::isfinite(parameters.margin) || parameters.margin < 0, failure("invalid_shape_parameters"));
	parameters.resolve_collider_object = false;
	for (const RID &excluded : parameters.exclude) {
		ERR_FAIL_COND_V(find_body(excluded) == nullptr, failure("shape_exclude_is_not_owned_body"));
	}
	PhysicsDirectSpaceState2D *direct = server->space_get_direct_state(space);
	ERR_FAIL_NULL_V(direct, failure("shape_direct_state_unavailable"));
	PhysicsDirectSpaceState2D::ShapeResult hit;
	const int count = direct->intersect_shape(parameters, &hit, 1);
	CRASH_COND_MSG(hit.collider != nullptr, "S numeric shape query unexpectedly resolved a live ObjectDB pointer.");
	Dictionary result;
	result["ok"] = true;
	result["empty"] = count == 0;
	return result;
}
Dictionary HardCoreSimulationWorld2D::state() const {
	if (!require_access(false)) return failure("world_owner_or_lifetime_violation");
	Dictionary result;
	result["ok"] = true;
	result["space_rid"] = space;
	result["body_count"] = int64_t(bodies.size());
	result["pending_transforms"] = int64_t(transform_queue.size());
	result["flush_serial"] = flush_serial;
	result["last_flush_boundary"] = last_flush_boundary;
	result["last_flush_identities"] = last_flush_identities;
	result["owner_thread"] = int64_t(owner);
	return result;
}
bool HardCoreSimulationWorld2D::close() {
	ERR_FAIL_COND_V(!require_access(false), false);
	for (auto &entry : bodies) release_body(entry.second);
	bodies.clear();
	transform_queue.clear();
	server->space_set_active(space, false);
	server->free_rid(space);
	space = RID();
	closed = true;
	// Host releases external owner once after model destruction. No sync,
	// step, finish, extra query flush, or singleton replacement belongs here.
	return true;
}

void HardCoreSimulationActorMotion2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("position_screen_px"), &HardCoreSimulationActorMotion2D::position_screen_px);
	ClassDB::bind_method(D_METHOD("velocity_screen_px_per_sec"), &HardCoreSimulationActorMotion2D::velocity_screen_px_per_sec);
	ClassDB::bind_method(D_METHOD("set_position_screen_px", "position"), &HardCoreSimulationActorMotion2D::set_position_screen_px);
	ClassDB::bind_method(D_METHOD("set_velocity_screen_px_per_sec", "velocity"), &HardCoreSimulationActorMotion2D::set_velocity_screen_px_per_sec);
	ClassDB::bind_method(D_METHOD("stop_velocity"), &HardCoreSimulationActorMotion2D::stop_velocity);
	ClassDB::bind_method(D_METHOD("safe_margin"), &HardCoreSimulationActorMotion2D::safe_margin);
	ClassDB::bind_method(D_METHOD("set_safe_margin", "margin"), &HardCoreSimulationActorMotion2D::set_safe_margin);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "collision_safe_margin"), "set_safe_margin", "safe_margin");
	ClassDB::bind_method(D_METHOD("collide_motion", "motion", "test_only", "safe_margin", "recovery_as_collision"), &HardCoreSimulationActorMotion2D::collide_motion, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("slide", "delta"), &HardCoreSimulationActorMotion2D::slide);
	ClassDB::bind_method(D_METHOD("state"), &HardCoreSimulationActorMotion2D::state);
	ClassDB::bind_method(D_METHOD("get_body_rid"), &HardCoreSimulationActorMotion2D::get_body_rid);
	ClassDB::bind_method(D_METHOD("get_canonical_id"), &HardCoreSimulationActorMotion2D::get_canonical_id);
}
void HardCoreSimulationWorld2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize", "default_area"), &HardCoreSimulationWorld2D::initialize);
	ClassDB::bind_method(D_METHOD("create_actor", "canonical_id", "configuration"), &HardCoreSimulationWorld2D::create_actor);
	ClassDB::bind_method(D_METHOD("create_static_body", "canonical_id", "transform", "shapes", "collision_layer", "collision_mask"), &HardCoreSimulationWorld2D::create_static_body, DEFVAL(1), DEFVAL(1));
	ClassDB::bind_method(D_METHOD("retire_body", "body"), &HardCoreSimulationWorld2D::retire_body);
	ClassDB::bind_method(D_METHOD("retire_actor", "canonical_id"), &HardCoreSimulationWorld2D::retire_actor);
	ClassDB::bind_method(D_METHOD("set_body_collision_filters", "body", "layer", "mask"), &HardCoreSimulationWorld2D::set_body_collision_filters);
	ClassDB::bind_method(D_METHOD("set_body_collision_priority", "body", "priority"), &HardCoreSimulationWorld2D::set_body_collision_priority);
	ClassDB::bind_method(D_METHOD("set_body_pickable", "body", "pickable"), &HardCoreSimulationWorld2D::set_body_pickable);
	ClassDB::bind_method(D_METHOD("intersect_original_pick_point", "position", "canvas_instance_id"), &HardCoreSimulationWorld2D::intersect_original_pick_point, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("set_body_shape_disabled", "body", "shape", "disabled"), &HardCoreSimulationWorld2D::set_body_shape_disabled);
	ClassDB::bind_method(D_METHOD("set_body_shape_transform", "body", "shape", "transform"), &HardCoreSimulationWorld2D::set_body_shape_transform);
	ClassDB::bind_method(D_METHOD("set_body_one_way_collision", "body", "shape", "enabled", "margin", "direction"), &HardCoreSimulationWorld2D::set_body_one_way_collision);
	ClassDB::bind_method(D_METHOD("set_static_body_transform", "body", "transform"), &HardCoreSimulationWorld2D::set_static_body_transform);
	ClassDB::bind_method(D_METHOD("set_collision_exception", "body", "other", "enabled"), &HardCoreSimulationWorld2D::set_collision_exception);
	ClassDB::bind_method(D_METHOD("flush_transforms", "mapped_boundary"), &HardCoreSimulationWorld2D::flush_transforms);
	ClassDB::bind_method(D_METHOD("intersect_ray", "from", "to", "mask", "exclude", "collide_with_bodies", "collide_with_areas", "hit_from_inside"), &HardCoreSimulationWorld2D::intersect_ray, DEFVAL(Array()), DEFVAL(true), DEFVAL(false), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("intersect_shape_empty", "query"), &HardCoreSimulationWorld2D::intersect_shape_empty);
	ClassDB::bind_method(D_METHOD("state"), &HardCoreSimulationWorld2D::state);
	ClassDB::bind_method(D_METHOD("close"), &HardCoreSimulationWorld2D::close);
}
