#pragma once
#include "batch_types.h"
#include "core/math/vector2.h"
#include <vector>
#include <memory>
#include <cstdint>

namespace hardcore::simulation::crowd {
// Vector expressions stay pinned Godot real_t. GDScript scalar float expressions
// are double. In particular radii are NOT packed in Vector4/PackedFloat32Array.
enum class Kind : uint8_t { MOTION = 0, DESTINATION = 1, CONTACT = 2 };
struct Query {
    Kind kind = Kind::MOTION;
    Vector2 a, b; // CONTACT: a=origin, b=unnormalized original direction.
    double own_radius = 0.0, own_margin = 0.0, epsilon = 0.0001;
};
struct Peer {
    uint64_t runtime_id = 0, life = 0, pose_revision = 0, radius_revision = 0;
    int64_t map = -1;
    Vector2 center;
    double radius = 0.0, margin = 0.0;
};
struct Row { bool envelope = false, crossed = false; double limit = 1.0; };
struct Input { Query query; std::vector<Peer> peers; };
struct Output { std::vector<Row> rows; };
bool core_crossed(Vector2 a, Vector2 b, Vector2 c, double ra, double rb, double epsilon);
double free_ray_extent(Vector2 origin, Vector2 direction, Vector2 center, double radius, double extent, double epsilon);
Row evaluate(const Query &, const Peer &);
bool same_query(const Query &, const Query &);
bool same_peer(const Peer &, const Peer &);
std::shared_ptr<const FrozenInput> freeze_input(const Input &, uint64_t version);
bool thaw_input(const FrozenInput &, Input &);
bool decode_output(const std::vector<uint8_t> &, Output &);
void batch_kernel(const FrozenInput &, std::vector<uint8_t> &, void *);
} // namespace hardcore::simulation::crowd
