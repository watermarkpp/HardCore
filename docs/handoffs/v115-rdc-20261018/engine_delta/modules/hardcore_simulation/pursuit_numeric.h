#pragma once
#include "core/math/vector2.h"
#include "core/math/vector2i.h"
#include "core/math/rect2.h"
#include <vector>
#include <map>
#include <set>
#include <queue>
#include <memory>
#include <string>
#include <cstdint>
#include <limits>

namespace hardcore::simulation::pursuit {
// Godot Vector2 expressions retain real_t; GDScript scalar floats stay double.
constexpr double GEO_EPS = 0.000001;
constexpr double GU_EPS = 0.0001;
using Polygon = std::vector<Vector2>;
struct CellLess { bool operator()(Vector2i a, Vector2i b) const { return a.y != b.y ? a.y < b.y : a.x < b.x; } };
struct Link { int to = -1; Vector2 portal; double cost = 0; };
struct Attachment { int face = -1; Vector2 point; bool valid() const { return face >= 0; } };
struct Navigation {
    bool polygon = false;
    Vector2i design_size;
    std::vector<Polygon> parts, faces;
    std::vector<Vector2> centers;
    std::vector<std::vector<Link>> links;
    std::map<Vector2i, std::vector<int>, CellLess> part_buckets, face_buckets;
    std::vector<Vector2i> first_buckets;
    std::vector<Rect2> padded_bounds;
    std::set<Vector2i, CellLess> blocked_cells;
    double radius = 0;
    std::string radius_key, build_sha256;
    bool inside(Vector2, double) const;
    bool capsule_blocked(Vector2, Vector2, double) const;
    bool cell_walkable(Vector2i, double) const;
    bool neighbor_clear(Vector2i, Vector2i, double) const;
    Attachment attach(Vector2, double) const;
};
struct Peer {
    uint64_t id = 0, life = 0, shape_revision = 0;
    int64_t stable_order = 0;
    Vector2 position;
    double radius = 0, margin = 0;
    bool enemy = false, damage_eligible = false, world_collision = false;
};
struct Actor {
    uint64_t id = 0, life = 0, target_id = 0, target_life = 0, shape_revision = 0;
    Vector2 position, target;
    double radius = 0, target_radius = 0, margin = 0, target_margin = 0;
    int64_t stable_order = 0;
    bool surround_present = false, flank_present = false;
    Vector2 surround, flank;
    int surround_slot = -1;
    bool side_retry_due = false;
    std::vector<Vector2> retained_route;
    size_t route_index = 0;
    std::set<std::pair<Vector2i, Vector2i>, bool(*)(const std::pair<Vector2i, Vector2i>&, const std::pair<Vector2i, Vector2i>&)> failed_edges;
    Actor();
};
// Static predicates are preparation hints. The exact original S predicates
// repair/admit each selected leg. WORLD/native rays never run on W.
struct FrozenWorld {
    std::vector<Polygon> world_parts, safe_zone_polygons;
    std::vector<std::pair<Vector2, double>> safe_zone_circles;
    bool point_allowed(Vector2, double) const;
    bool segment_clear(Vector2, Vector2) const;
};
struct Output {
    uint64_t id = 0, life = 0;
    std::string status;
    std::vector<Vector2> route;
    bool surround_present = false, flank_present = false;
    Vector2 surround, flank;
    int surround_slot = -1;
    uint64_t expansions = 0, slices = 0, work_units = 0, numeric_checks = 0;
};
Vector2 next_source_leg(Vector2 origin, Vector2 waypoint, double component_budget = 1.0);
bool capsule_hits_polygon(Vector2 a, Vector2 b, double radius, const Polygon &);
bool point_in_polygon(Vector2, const Polygon &);

// The original resumable polygon phases and original legacy A* tie order.
// Each advance performs at most limit original work units and returns to W.
// No Object, Variant, Callable, RNG, HP, PhysicsServer or gameplay mutation.
class Search {
public:
    Search(std::shared_ptr<const Navigation>, std::shared_ptr<const FrozenWorld>, Actor, std::shared_ptr<const std::vector<Peer>>);
    bool advance(uint32_t limit);
    const Output &output() const { return output_; }
private:
    std::shared_ptr<const Navigation> nav_;
    std::shared_ptr<const FrozenWorld> world_;
    std::shared_ptr<const std::vector<Peer>> peers_;
    Actor actor_;
    Output output_;
    enum class Phase { STATION, FLANK, CONTACT, GOALS, ATTACH_START, ATTACH_GOALS, SEARCH, RECONSTRUCT, ASSEMBLE, SMOOTH, DONE } phase_ = Phase::STATION;
    struct Goal { Vector2i cell; Vector2 goal; Attachment attachment; };
    struct Item { double f = 0, g = 0; int face = -1; Vector2i cell; };
    struct Less { bool operator()(const Item &a, const Item &b) const; };
    std::priority_queue<Item, std::vector<Item>, Less> heap_;
    std::vector<Goal> goals_;
    Attachment start_;
    std::map<int, double> scores_;
    std::map<int, std::pair<int, Vector2>> parents_;
    std::set<int> closed_;
    std::map<Vector2i, double, CellLess> grid_scores_;
    std::map<Vector2i, Vector2i, CellLess> grid_parents_;
    std::set<Vector2i, CellLess> grid_closed_;
    std::vector<int> reverse_faces_, face_chain_;
    std::vector<Vector2> raw_path_;
    double best_cost_ = std::numeric_limits<double>::infinity();
    int best_goal_ = -1, cursor_ = -1, assemble_index_ = 1, smooth_index_ = 0, smooth_probe_ = -1;
    size_t goal_index_ = 0, sample_index_ = 0, station_index_ = 0;
    double station_cost_ = std::numeric_limits<double>::infinity();
    Vector2 victim_anchor_;
    bool far_approach_ = false;
    double best_extent_ = -1;
    Vector2 smooth_anchor_;
    Vector2i grid_cursor_;
    bool grid_reconstructing_ = false;
    bool point_allowed(Vector2);
    bool destination_clear(Vector2);
    bool motion_clear(Vector2, Vector2);
    bool edge_clear(Vector2i, Vector2i) const;
    double heuristic(int) const;
    double grid_heuristic(Vector2i) const;
    void finish(const char *);
    void station_one();
    void flank_one();
    void contact_one();
    bool frontline(Vector2) const;
    void goal_one();
    void attach_goal_one();
    void search_one();
    void reconstruct_one();
    void assemble_one();
    void smooth_one();
};
} // namespace hardcore::simulation::pursuit
