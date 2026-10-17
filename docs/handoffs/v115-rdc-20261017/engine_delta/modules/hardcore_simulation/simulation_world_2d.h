#pragma once

#include "motion_adapter.h"
#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include <memory>
#include <unordered_map>
#include <vector>

class HardCoreSimulationWorld2D;

// One S-owned controller per original positive canonical actor handle. No Node,
// ObjectDB lookup, RNG or gameplay state is owned by this object.
class HardCoreSimulationActorMotion2D : public RefCounted {
	GDCLASS(HardCoreSimulationActorMotion2D, RefCounted);
	friend class HardCoreSimulationWorld2D;
	HardCoreSimulationWorld2D *world = nullptr;
	int64_t canonical_id = 0;
	RID body;
	Transform2D logical_transform;
	CharacterMotion2DState motion;
	std::unique_ptr<hardcore::simulation::GodotCharacterMotionAdapter> adapter;
	bool require_access(bool p_query) const;
	void detach();
protected:
	static void _bind_methods();
public:
	Vector2 position_screen_px() const;
	Vector2 velocity_screen_px_per_sec() const;
	bool set_position_screen_px(const Vector2 &p_position);
	bool set_velocity_screen_px_per_sec(const Vector2 &p_velocity);
	bool stop_velocity();
	double safe_margin() const;
	void set_safe_margin(double p_margin);
	Dictionary collide_motion(const Vector2 &p_motion, bool p_test_only, double p_safe_margin, bool p_recovery_as_collision = false);
	Dictionary slide(double p_delta);
	Dictionary state() const;
	RID get_body_rid() const;
	int64_t get_canonical_id() const;
};

// This world uses the already-claimed process-wide PhysicsServer2D singleton.
// Host alone drives sync/step/process/finish. All instance methods are S-only.
class HardCoreSimulationWorld2D : public RefCounted,
		private hardcore::simulation::MotionIdentityRegistry,
		private hardcore::simulation::MotionTransformQueue {
	GDCLASS(HardCoreSimulationWorld2D, RefCounted);
	friend class HardCoreSimulationActorMotion2D;
	struct BodyEntry {
		int64_t identity = 0;
		RID body;
		std::vector<RID> shapes;
		Ref<HardCoreSimulationActorMotion2D> actor;
	};
	PhysicsServer2DWrapMT *server = nullptr;
	Thread::ID owner = Thread::UNASSIGNED_ID;
	RID space;
	bool initialized = false;
	bool closed = false;
	std::unordered_map<int64_t, BodyEntry> bodies;
	std::unordered_map<uint64_t, int64_t> body_identities;
	std::vector<hardcore::simulation::GodotCharacterMotionAdapter *> transform_queue;
	int64_t flush_serial = 0;
	String last_flush_boundary;
	PackedInt64Array last_flush_identities;
	bool require_access(bool p_query, bool p_require_initialized = true) const;
	BodyEntry *find_body(RID p_body);
	const BodyEntry *find_body(RID p_body) const;
	bool is_character(ObjectID p_object, RID p_body) const override;
	void enqueue_transform(hardcore::simulation::GodotCharacterMotionAdapter &p_body) override;
	void release_body(BodyEntry &p_entry);
	bool validate_shape(const Dictionary &p_shape) const;
	RID create_shape(const Dictionary &p_shape);
protected:
	static void _bind_methods();
public:
	HardCoreSimulationWorld2D();
	~HardCoreSimulationWorld2D();
	bool initialize(const Dictionary &p_default_area);
	Ref<HardCoreSimulationActorMotion2D> create_actor(int64_t p_canonical_id, const Dictionary &p_configuration);
	RID create_static_body(int64_t p_canonical_id, const Transform2D &p_transform, const Array &p_shapes, int64_t p_collision_layer = 1, int64_t p_collision_mask = 1);
	bool retire_body(RID p_body);
	bool retire_actor(int64_t p_canonical_id);
	bool set_body_collision_filters(RID p_body, int64_t p_layer, int64_t p_mask);
	bool set_body_collision_priority(RID p_body, double p_priority);
	bool set_body_pickable(RID p_body, bool p_pickable);
	bool set_body_shape_disabled(RID p_body, int p_shape, bool p_disabled);
	bool set_body_shape_transform(RID p_body, int p_shape, const Transform2D &p_transform);
	bool set_body_one_way_collision(RID p_body, int p_shape, bool p_enabled, double p_margin, const Vector2 &p_direction);
	bool set_static_body_transform(RID p_body, const Transform2D &p_transform);
	bool set_collision_exception(RID p_body, RID p_other, bool p_enabled);
	bool flush_transforms(const String &p_mapped_boundary);
	Dictionary intersect_ray(const Vector2 &p_from, const Vector2 &p_to, int64_t p_mask, const Array &p_exclude = Array(), bool p_collide_with_bodies = true, bool p_collide_with_areas = false, bool p_hit_from_inside = false);
	Dictionary intersect_original_pick_point(const Vector2 &p_position, int64_t p_canvas_instance_id = 0);
	Dictionary intersect_shape_empty(const Ref<PhysicsShapeQueryParameters2D> &p_query);
	Dictionary state() const;
	bool close();
};
