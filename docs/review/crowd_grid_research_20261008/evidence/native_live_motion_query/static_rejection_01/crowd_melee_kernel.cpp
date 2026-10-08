#include "crowd_melee_kernel.h"

#include <algorithm>

#include <godot_cpp/classes/geometry2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

namespace {

static Object *object_from_variant(const Variant &value) {
    if (value.get_type() != Variant::OBJECT) {
        return nullptr;
    }
    return value;
}

static bool live_object(Object *object) {
    if (object == nullptr) {
        return false;
    }
    Object *current = ObjectDB::get_instance(object->get_instance_id());
    return current == object && !object->is_queued_for_deletion();
}

static uint64_t script_id(Object *object) {
    if (!live_object(object)) {
        return 0;
    }
    Object *script = object_from_variant(object->get_script());
    return script == nullptr ? 0 : script->get_instance_id();
}

static bool script_is_enemy(Object *object, uint64_t exact_script_id) {
    uint64_t current_id = script_id(object);
    if (current_id == 0 || exact_script_id == 0) {
        return false;
    }
    if (current_id == exact_script_id) {
        return true;
    }
    Object *script = object_from_variant(object->get_script());
    for (int depth = 0; script != nullptr && depth < 32; ++depth) {
        if (!script->has_method(StringName("get_base_script"))) {
            return false;
        }
        Variant base_variant = script->call(StringName("get_base_script"));
        script = object_from_variant(base_variant);
        if (script != nullptr && script->get_instance_id() == exact_script_id) {
            return true;
        }
    }
    return false;
}

static bool read_vector2(Object *object, const StringName &name, Vector2 &out) {
    Variant value = object->get(name);
    if (value.get_type() != Variant::VECTOR2) {
        return false;
    }
    out = value;
    return true;
}

static bool read_int(Object *object, const StringName &name, int64_t &out) {
    Variant value = object->get(name);
    if (value.get_type() == Variant::INT) {
        out = static_cast<int64_t>(value);
        return true;
    }
    if (value.get_type() == Variant::FLOAT) {
        out = static_cast<int64_t>(static_cast<double>(value));
        return true;
    }
    return false;
}

static bool read_float(Object *object, const StringName &name, double &out) {
    Variant value = object->get(name);
    if (value.get_type() != Variant::INT && value.get_type() != Variant::FLOAT) {
        return false;
    }
    out = static_cast<double>(value);
    return true;
}

static bool booleanize(const Variant &value, bool &out) {
    switch (value.get_type()) {
        case Variant::BOOL:
            out = static_cast<bool>(value);
            return true;
        case Variant::INT:
            out = static_cast<int64_t>(value) != 0;
            return true;
        case Variant::FLOAT:
            out = static_cast<double>(value) != 0.0;
            return true;
        case Variant::STRING:
            out = !String(value).is_empty();
            return true;
        case Variant::NIL:
            out = false;
            return true;
        default:
            return false;
    }
}

static bool read_world_collision(Object *object, bool &out) {
    Variant profile_variant = object->get(StringName("behavior_profile"));
    if (profile_variant.get_type() != Variant::DICTIONARY) {
        return false;
    }
    Dictionary profile = profile_variant;
    Variant value = profile.get(StringName("worldCollision"), true);
    return booleanize(value, out);
}

static bool finite_vector(const Vector2 &value) {
    return value.is_finite();
}

} // namespace

void CrowdMeleeKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_abi_version"), &CrowdMeleeKernel::get_abi_version);
    ClassDB::bind_method(D_METHOD("core_crossed", "a", "b", "c", "ra", "rb"), &CrowdMeleeKernel::core_crossed);
    ClassDB::bind_method(D_METHOD("forward_buffers", "scalars", "vectors", "identities"), &CrowdMeleeKernel::forward_buffers);
    ClassDB::bind_method(D_METHOD("configure_live_motion_scripts", "exact_enemy_script", "exact_world_background_script"), &CrowdMeleeKernel::configure_live_motion_scripts);
    ClassDB::bind_method(D_METHOD("motion_candidates_live", "owner", "a", "b", "candidates"), &CrowdMeleeKernel::motion_candidates_live);
    ClassDB::bind_method(D_METHOD("get_live_motion_stats"), &CrowdMeleeKernel::get_live_motion_stats);
    ClassDB::bind_method(D_METHOD("reset_live_motion_stats"), &CrowdMeleeKernel::reset_live_motion_stats);
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

Array CrowdMeleeKernel::forward_buffers(const PackedFloat64Array &scalars,
        const PackedVector2Array &vectors,
        const PackedInt64Array &identities) const {
    // This is a deliberately state-free ABI probe. Packed arrays use Godot's
    // copy-on-write storage, so placing each input in a new Array preserves a
    // value snapshot while allowing later caller mutation to detach safely.
    Array channels;
    channels.push_back(scalars);
    channels.push_back(vectors);
    channels.push_back(identities);
    return channels;
}

void CrowdMeleeKernel::configure_live_motion_scripts(Object *exact_enemy_script,
        Object *exact_world_background_script) {
    _exact_enemy_script_id = live_object(exact_enemy_script) ? exact_enemy_script->get_instance_id() : 0;
    _exact_world_background_script_id = live_object(exact_world_background_script) ? exact_world_background_script->get_instance_id() : 0;
}

Variant CrowdMeleeKernel::motion_candidates_live(Object *owner, Vector2 a, Vector2 b,
        const Array &candidates) const {
    ++_live_entries;
    if (!live_object(owner) || script_id(owner) != _exact_enemy_script_id) {
        ++_unsupported_owner;
        return Variant();
    }

    auto counter = [owner](const StringName &field, int64_t amount = 1) {
        owner->call(StringName("_record_performance_counter"), field, amount);
    };
    counter(StringName("enemy_motion_candidate_checks"), candidates.size());
    if (!live_object(owner)) {
        ++_revalidation_failures;
        return Variant();
    }

    Variant surround_variant = owner->get(StringName("_hc_surround_goal"));
    Variant target_variant = owner->get(StringName("target"));
    Object *target = object_from_variant(target_variant);
    if (surround_variant.get_type() == Variant::VECTOR2 && finite_vector(static_cast<Vector2>(surround_variant)) && live_object(target)) {
        Vector2 target_position;
        if (!read_vector2(target, StringName("global_position"), target_position)) {
            ++_unsupported_owner;
            return Variant();
        }
        Variant ground_variant = owner->call(StringName("_screen_position_px_to_ground_position_gu"), target_position);
        if (!live_object(owner) || !live_object(target)) {
            ++_revalidation_failures;
            return Variant();
        }
        double target_radius = 0.0;
        Variant radius_variant = owner->call(StringName("_target_combat_radius_gu"), target);
        if (radius_variant.get_type() != Variant::INT && radius_variant.get_type() != Variant::FLOAT) {
            ++_unsupported_owner;
            return Variant();
        }
        target_radius = static_cast<double>(radius_variant);
        if (ground_variant.get_type() == Variant::VECTOR2) {
            double owner_radius = 0.0;
            if (!read_float(owner, StringName("combat_radius_gu"), owner_radius)) {
                ++_unsupported_owner;
                return Variant();
            }
            if (core_crossed(a, b, static_cast<Vector2>(ground_variant), owner_radius, target_radius)) {
                return false;
            }
        }
    }

    int64_t owner_map = -1;
    double owner_radius = 0.0;
    if (!read_int(owner, StringName("runtime_map_id"), owner_map) || !read_float(owner, StringName("combat_radius_gu"), owner_radius)) {
        ++_unsupported_owner;
        return Variant();
    }
    Vector2 low(std::min(a.x, b.x), std::min(a.y, b.y));
    Vector2 high(std::max(a.x, b.x), std::max(a.y, b.y));
    const uint64_t owner_id = owner->get_instance_id();

    for (int i = 0; i < candidates.size(); ++i) {
        if (!live_object(owner) || !read_int(owner, StringName("runtime_map_id"), owner_map) ||
                !read_float(owner, StringName("combat_radius_gu"), owner_radius)) {
            ++_revalidation_failures;
            return Variant();
        }
        target = object_from_variant(owner->get(StringName("target")));
        Object *other = object_from_variant(candidates[i]);
        if (!live_object(other) || !script_is_enemy(other, _exact_enemy_script_id)) {
            continue;
        }
        if (other->get_instance_id() == owner_id || (live_object(target) && other->get_instance_id() == target->get_instance_id())) {
            continue;
        }
        int64_t other_map = -1;
        if (!read_int(other, StringName("runtime_map_id"), other_map) || other_map != owner_map) {
            continue;
        }
        counter(StringName("enemy_motion_body_checks"));
        if (!live_object(owner) || !live_object(other)) {
            ++_revalidation_failures;
            return Variant();
        }

        if (script_id(other) != _exact_enemy_script_id) {
            ++_candidate_legacy;
            Variant position_variant = other->call(StringName("spatial_index_position"));
            if (!live_object(owner) || !live_object(other)) {
                ++_revalidation_failures;
                return Variant();
            }
            if (position_variant.get_type() != Variant::VECTOR2) {
                continue;
            }
            Vector2 legacy_position = position_variant;
            double legacy_radius = 0.0;
            if (!read_float(other, StringName("combat_radius_gu"), legacy_radius)) {
                continue;
            }
            double envelope = std::max(0.0, owner_radius + legacy_radius) + 0.0001;
            if (legacy_position.x < low.x - envelope || legacy_position.x > high.x + envelope ||
                    legacy_position.y < low.y - envelope || legacy_position.y > high.y + envelope) {
                continue;
            }
            Variant admissible_variant = other->call(StringName("can_receive_damage"));
            if (!live_object(owner) || !live_object(other)) {
                ++_revalidation_failures;
                return Variant();
            }
            bool admissible = false;
            if (!booleanize(admissible_variant, admissible)) {
                continue;
            }
            if (!read_float(owner, StringName("combat_radius_gu"), owner_radius)) {
                ++_revalidation_failures;
                return Variant();
            }
            bool legacy_world_collision = true;
            if (!read_world_collision(other, legacy_world_collision)) {
                continue;
            }
            if (admissible && legacy_world_collision && core_crossed(a, b, legacy_position, owner_radius, legacy_radius)) {
                return false;
            }
            continue;
        }

        Vector2 c;
        bool cache_hit = false;
        Variant blocker_variant = other->get(StringName("environment_blocker"));
        Object *blocker = object_from_variant(blocker_variant);
        bool provider_supported = true;
        if (blocker != nullptr && (_exact_world_background_script_id == 0 || script_id(blocker) != _exact_world_background_script_id)) {
            provider_supported = false;
            ++_provider_fallbacks;
        } else {
            Variant projection_variant = other->get(StringName("runtime_screen_to_ground_position_px"));
            Variant cached_projection_variant = other->get(StringName("_last_spatial_index_projection"));
            Vector2 global_position;
            Vector2 cached_screen;
            Vector2 cached_ground;
            int64_t cached_map = -1;
            int64_t cached_generation = -1;
            int64_t cached_revision = -1;
            int64_t generation = static_cast<int64_t>(other->get_meta(StringName("zone_generation"), -1));
            int64_t current_revision = -1;
            if (blocker != nullptr) {
                if (!read_int(blocker, StringName("_environment_collision_revision"), current_revision)) {
                    provider_supported = false;
                    ++_provider_fallbacks;
                }
            }
            if (provider_supported && projection_variant.get_type() == Variant::CALLABLE && cached_projection_variant.get_type() == Variant::CALLABLE &&
                    static_cast<Callable>(projection_variant).is_valid() && static_cast<Callable>(cached_projection_variant).is_valid() &&
                    static_cast<Callable>(projection_variant) == static_cast<Callable>(cached_projection_variant) &&
                    read_vector2(other, StringName("global_position"), global_position) &&
                    read_vector2(other, StringName("_last_spatial_index_screen_position_px"), cached_screen) &&
                    read_vector2(other, StringName("_last_spatial_index_ground_position_gu"), cached_ground) &&
                    read_int(other, StringName("_last_spatial_index_runtime_map_id"), cached_map) &&
                    read_int(other, StringName("_last_spatial_index_zone_generation"), cached_generation) &&
                    read_int(other, StringName("_last_spatial_index_environment_revision"), cached_revision) &&
                    cached_screen == global_position && cached_map == other_map && cached_generation == generation && cached_revision == current_revision) {
                c = cached_ground;
                cache_hit = true;
                ++_cache_hits;
            }
        }

        if (!cache_hit) {
            ++_miss_callbacks;
            Variant position_variant = other->call(StringName("spatial_index_position"));
            if (!live_object(owner) || !live_object(other)) {
                ++_revalidation_failures;
                return Variant();
            }
            if (position_variant.get_type() != Variant::VECTOR2) {
                ++_candidate_legacy;
                continue;
            }
            c = position_variant;
        }
        if (!live_object(owner) || !read_float(owner, StringName("combat_radius_gu"), owner_radius)) {
            ++_revalidation_failures;
            return Variant();
        }
        double other_radius = 0.0;
        if (!read_float(other, StringName("combat_radius_gu"), other_radius)) {
            ++_candidate_legacy;
            continue;
        }
        if (c.x < low.x - std::max(0.0, owner_radius + other_radius) - 0.0001 || c.x > high.x + std::max(0.0, owner_radius + other_radius) + 0.0001 ||
                c.y < low.y - std::max(0.0, owner_radius + other_radius) - 0.0001 || c.y > high.y + std::max(0.0, owner_radius + other_radius) + 0.0001) {
            continue;
        }
        Variant rejected_variant = other->get(StringName("_body_admission_rejected"));
        Variant hp_variant = other->get(StringName("current_hp"));
        Variant death_pending_variant = other->get(StringName("_death_pending"));
        Variant dying_variant = other->get(StringName("_dying"));
        bool rejected = false;
        bool death_pending = false;
        bool dying = false;
        if (!booleanize(rejected_variant, rejected) || !booleanize(death_pending_variant, death_pending) || !booleanize(dying_variant, dying) ||
                (hp_variant.get_type() != Variant::INT && hp_variant.get_type() != Variant::FLOAT)) {
            ++_candidate_legacy;
            continue;
        }
        bool can_damage = !rejected && static_cast<double>(hp_variant) > 0.0 && !death_pending && !dying && !other->is_queued_for_deletion();
        if (!can_damage) {
            continue;
        }
        bool world_collision = true;
        if (!read_world_collision(other, world_collision)) {
            ++_candidate_legacy;
            continue;
        }
        if (!world_collision || !core_crossed(a, b, c, owner_radius, other_radius)) {
            continue;
        }
        return false;
    }
    return true;
}

Dictionary CrowdMeleeKernel::get_live_motion_stats() const {
    Dictionary result;
    result[StringName("entries")] = static_cast<int64_t>(_live_entries);
    result[StringName("unsupported_owner")] = static_cast<int64_t>(_unsupported_owner);
    result[StringName("candidate_legacy")] = static_cast<int64_t>(_candidate_legacy);
    result[StringName("cache_hits")] = static_cast<int64_t>(_cache_hits);
    result[StringName("miss_callbacks")] = static_cast<int64_t>(_miss_callbacks);
    result[StringName("provider_fallbacks")] = static_cast<int64_t>(_provider_fallbacks);
    result[StringName("revalidation_failures")] = static_cast<int64_t>(_revalidation_failures);
    return result;
}

void CrowdMeleeKernel::reset_live_motion_stats() {
    _live_entries = 0;
    _unsupported_owner = 0;
    _candidate_legacy = 0;
    _cache_hits = 0;
    _miss_callbacks = 0;
    _provider_fallbacks = 0;
    _revalidation_failures = 0;
}

}
