#include "physics_motion_parity_tests.h"
#ifdef DEBUG_ENABLED
#include "motion_adapter.h"
#include "core/variant/array.h"
#include "scene/2d/physics/character_body_2d.h"

namespace hardcore::simulation {
namespace {
// No test replacement solver: both adapters query the live singleton backend.
class ParityCharacter final : public CharacterBody2D {
public:
	CharacterMotion2DState &state() { return *this; }
};
struct Identities final : MotionIdentityRegistry {
	RID character_platform;
	bool is_character(ObjectID, RID body) const override { return body == character_platform; }
};
struct TransformQueue final : MotionTransformQueue {
	Vector<GodotCharacterMotionAdapter *> pending;
	void enqueue_transform(GodotCharacterMotionAdapter &body) override { pending.push_back(&body); }
	void flush() {
		for (GodotCharacterMotionAdapter *body : pending) body->flush_transform();
		pending.clear();
	}
};
struct Fixture {
	PhysicsServer2DWrapMT &server;
	RID space;
	RID actor_shape;
	RID raw_actor;
	ParityCharacter *node = nullptr;
	Vector<RID> obstacles;
	Vector<RID> shapes;
	Fixture(PhysicsServer2DWrapMT &p_server) : server(p_server) {
		space = server.space_create();
		server.space_set_active(space, true);
		actor_shape = server.circle_shape_create();
		server.shape_set_data(actor_shape, 1.0);
		node = memnew(ParityCharacter);
		server.body_add_shape(node->get_rid(), actor_shape, Transform2D(), false);
		server.body_set_space(node->get_rid(), space);
		raw_actor = server.body_create();
		server.body_set_mode(raw_actor, PhysicsServer2D::BODY_MODE_KINEMATIC);
		server.body_add_shape(raw_actor, actor_shape, Transform2D(), false);
		server.body_set_space(raw_actor, space);
		server.body_add_collision_exception(node->get_rid(), raw_actor);
		server.body_add_collision_exception(raw_actor, node->get_rid());
	}
	RID rectangle(Vector2 position, Vector2 half_extents, real_t angle = 0.0, Vector2 linear_velocity = Vector2()) {
		RID shape = server.rectangle_shape_create();
		server.shape_set_data(shape, half_extents);
		shapes.push_back(shape);
		RID body = server.body_create();
		server.body_set_mode(body, PhysicsServer2D::BODY_MODE_STATIC);
		server.body_add_shape(body, shape, Transform2D(), false);
		server.body_set_state(body, PhysicsServer2D::BODY_STATE_TRANSFORM, Transform2D(angle, position));
		server.body_set_state(body, PhysicsServer2D::BODY_STATE_LINEAR_VELOCITY, linear_velocity);
		server.body_set_space(body, space);
		obstacles.push_back(body);
		return body;
	}
	void flush_both(TransformQueue &queue) {
		// Rootless Node fixture has no SceneTree notification list. Explicitly
		// submit both requests at the same boundary; full SceneTree parity is separate.
		server.body_set_state(node->get_rid(), PhysicsServer2D::BODY_STATE_TRANSFORM, node->get_global_transform());
		queue.flush();
	}
	~Fixture() {
		memdelete(node);
		server.free_rid(raw_actor);
		for (RID body : obstacles) server.free_rid(body);
		server.free_rid(actor_shape);
		for (RID shape : shapes) server.free_rid(shape);
		server.free_rid(space);
	}
};
bool same_result(const PhysicsServer2D::MotionResult &a, const PhysicsServer2D::MotionResult &b) {
	return a.travel == b.travel && a.remainder == b.remainder && a.collision_point == b.collision_point &&
		a.collision_normal == b.collision_normal && a.collider_velocity == b.collider_velocity &&
		a.collision_depth == b.collision_depth && a.collision_safe_fraction == b.collision_safe_fraction &&
		a.collision_unsafe_fraction == b.collision_unsafe_fraction && a.collision_local_shape == b.collision_local_shape &&
		a.collider == b.collider && a.collider_id == b.collider_id && a.collider_shape == b.collider_shape;
}
bool same_state(const CharacterMotion2DState &a, const CharacterMotion2DState &b) {
	if (a.velocity != b.velocity || a.floor_normal != b.floor_normal || a.wall_normal != b.wall_normal ||
		a.platform_velocity != b.platform_velocity || a.last_motion != b.last_motion || a.previous_position != b.previous_position ||
		a.real_velocity != b.real_velocity || a.platform_rid != b.platform_rid || a.platform_object_id != b.platform_object_id ||
		a.platform_layer != b.platform_layer || a.on_floor != b.on_floor || a.on_ceiling != b.on_ceiling || a.on_wall != b.on_wall ||
		a.motion_results.size() != b.motion_results.size()) return false;
	for (int i = 0; i < a.motion_results.size(); ++i) {
		if (!same_result(a.motion_results[i], b.motion_results[i])) return false;
	}
	return true;
}
} // namespace

Dictionary run_physics_motion_parity_tests() {
	Dictionary report;
	Array cases;
	PhysicsServer2DWrapMT *server = Object::cast_to<PhysicsServer2DWrapMT>(PhysicsServer2D::get_singleton());
	if (!server || server->is_external_owner_mode() || !Thread::is_main_thread()) {
		report["status"] = "BLOCKED";
		report["reason"] = "Node parity requires ordinary mode on Main with the real GodotPhysics2D backend.";
		return report;
	}
	const char *names[] = { "free_grounded", "free_floating", "zero_overlap_recovery", "slanted_wall", "wall_corner", "floor_snap", "moving_platform", "ceiling", "zero_no_collision", "test_only", "cancel_sliding_false", "one_way" };
	bool all_ok = true;
	for (int scenario = 0; scenario < 12; ++scenario) {
		Fixture fixture(*server);
		Transform2D logical;
		CharacterMotion2DState state;
		state.velocity = Vector2(60, 0);
		Identities identities;
		TransformQueue queue;
		GodotCharacterMotionAdapter adapter(*server, fixture.raw_actor, logical, identities, queue);
		if (scenario == 1 || scenario == 3 || scenario == 4) state.motion_mode = 1;
		if (scenario == 2) { fixture.rectangle(Vector2(0, 1.5), Vector2(10, 1)); state.velocity = Vector2(); }
		if (scenario == 3) fixture.rectangle(Vector2(2.5, 0), Vector2(0.5, 10), 0.3);
		if (scenario == 4) { fixture.rectangle(Vector2(2.5, 0), Vector2(0.5, 10)); fixture.rectangle(Vector2(0, 2.5), Vector2(10, 0.5)); state.velocity = Vector2(120, 120); }
		// A prior on-floor frame always carries its normalized contact normal.
		// Seeding only the flag creates an impossible controller state and the
		// original constant-speed snap branch correctly rejects slide(Vector2()).
		if (scenario == 5) { fixture.rectangle(Vector2(0, 2.5), Vector2(20, 1)); state.on_floor = true; state.floor_normal = state.up_direction; state.velocity = Vector2(30, 0); state.floor_constant_speed = true; }
		if (scenario == 6) {
			state.platform_rid = fixture.rectangle(Vector2(0, 2.08), Vector2(20, 1), 0, Vector2(30, 0));
			state.on_floor = true; state.floor_normal = state.up_direction; state.platform_layer = 1; state.platform_velocity = Vector2(30, 0); state.velocity = Vector2(0, 60);
		}
		if (scenario == 7) { fixture.rectangle(Vector2(0, -2.5), Vector2(20, 1)); state.velocity = Vector2(30, -120); state.slide_on_ceiling = false; }
		if (scenario == 8) state.velocity = Vector2();
		if (scenario == 11) {
			RID platform = fixture.rectangle(Vector2(0, 2.5), Vector2(20, 1));
			server->body_set_shape_as_one_way_collision(platform, 0, true, 1.0, Vector2(0, 1));
			state.velocity = Vector2(0, 120);
		}
		fixture.node->state() = state;
		bool passed = true;
		int iterations = (scenario == 9 || scenario == 10) ? 1 : 4;
		for (int tick = 0; tick < iterations; ++tick) {
			bool node_hit;
			bool raw_hit;
			if (scenario == 9 || scenario == 10) {
				PhysicsServer2D::MotionParameters parameters(logical, Vector2(2, 0), state.margin);
				PhysicsServer2D::MotionResult node_result, raw_result;
				node_hit = fixture.node->move_and_collide(parameters, node_result, scenario == 9, scenario != 10);
				raw_hit = physics_motion_2d_move_and_collide(adapter, parameters, raw_result, scenario == 9, scenario != 10);
				passed = passed && same_result(node_result, raw_result);
			} else {
				node_hit = fixture.node->move_and_slide_with_delta(1.0 / 60.0);
				raw_hit = state.move_and_slide(adapter, 1.0 / 60.0);
				passed = passed && same_state(fixture.node->state(), state);
			}
			passed = passed && node_hit == raw_hit && fixture.node->get_global_transform() == logical;
			if ((scenario == 0 || scenario == 1) && tick == 0) passed = passed && logical.columns[2] == Vector2(1, 0);
			if (scenario == 8 || scenario == 9) passed = passed && logical.columns[2] == Vector2();
			fixture.flush_both(queue);
		}
		Dictionary item;
		item["case"] = names[scenario]; item["status"] = passed ? "PASS" : "FAIL";
		item["position"] = logical.columns[2]; item["node_position"] = fixture.node->get_global_position();
		item["collision_count"] = state.motion_results.size(); item["floor"] = state.on_floor; item["wall"] = state.on_wall;
		cases.push_back(item);
		all_ok = all_ok && passed;
	}
	report["status"] = all_ok ? "PASS" : "FAIL";
	report["cases"] = cases;
	report["scope"] = "Real backend, Node/nonNode shared controller equality; rootless explicit transform flush. Full gameplay phase/trace/owner/device acceptance is separate.";
	return report;
}
} // namespace hardcore::simulation

#endif // DEBUG_ENABLED
