#include "crowd_melee_kernel.h"

#include <godot_cpp/classes/geometry2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

void CrowdMeleeKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_abi_version"), &CrowdMeleeKernel::get_abi_version);
    ClassDB::bind_method(D_METHOD("core_crossed", "a", "b", "c", "ra", "rb"), &CrowdMeleeKernel::core_crossed);
}

int32_t CrowdMeleeKernel::get_abi_version() const {
    return 1;
}

bool CrowdMeleeKernel::core_crossed(Vector2 a, Vector2 b, Vector2 c, double ra, double rb) const {
    // This is intentionally the exact numeric policy in
    // scripts/monster_ai_package/policy.gd::core_crossed.
    double radius_sum = ra + rb;
    double r = radius_sum < 0.0 ? 0.0 : radius_sum;
    double before = static_cast<double>(a.distance_squared_to(c));
    double after = static_cast<double>(b.distance_squared_to(c));
    double rr = r * r;
    if (before < rr) {
        return (b - a).dot(a - c) < -0.0001 || after < before - 0.0001;
    }

    Geometry2D *geometry = Geometry2D::get_singleton();
    if (geometry == nullptr) return false;
    Vector2 q = geometry->get_closest_point_to_segment(c, a, b);
    double closest = static_cast<double>(q.distance_squared_to(c));
    return closest < rr - 0.0001;
}

}
