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

// This table is deliberately function-local and lazy.  Constructing a
// StringName at namespace scope calls the GDExtension interface during DLL
// load, before Godot has initialized it; the first live query occurs after
// extension initialization and is safe.
struct LiveQueryNames {
    StringName counter = StringName("_record_performance_counter");
    StringName counter_candidates = StringName("enemy_motion_candidate_checks");
    StringName counter_body = StringName("enemy_motion_body_checks");
    StringName surround = StringName("_hc_surround_goal");
    StringName target = StringName("target");
    StringName global_position = StringName("global_position");
    StringName project_ground = StringName("_screen_position_px_to_ground_position_gu");
    StringName target_radius = StringName("_target_combat_radius_gu");
    StringName radius = StringName("combat_radius_gu");
    StringName map = StringName("runtime_map_id");
    StringName spatial = StringName("spatial_index_position");
    StringName can_receive = StringName("can_receive_damage");
    StringName behavior = StringName("behavior_profile");
    StringName world_collision = StringName("worldCollision");
    StringName blocker = StringName("environment_blocker");
    StringName projection = StringName("runtime_screen_to_ground_position_px");
    StringName cache_projection = StringName("_last_spatial_index_projection");
    StringName zone_generation = StringName("zone_generation");
    StringName env_revision = StringName("_environment_collision_revision");
    StringName cache_screen = StringName("_last_spatial_index_screen_position_px");
    StringName cache_ground = StringName("_last_spatial_index_ground_position_gu");
    StringName cache_map = StringName("_last_spatial_index_runtime_map_id");
    StringName cache_generation = StringName("_last_spatial_index_zone_generation");
    StringName cache_revision = StringName("_last_spatial_index_environment_revision");
    StringName rejected = StringName("_body_admission_rejected");
    StringName hp = StringName("current_hp");
    StringName death_pending = StringName("_death_pending");
    StringName dying = StringName("_dying");
    StringName stats_entries = StringName("entries");
    StringName stats_unsupported = StringName("unsupported_owner");
    StringName stats_legacy = StringName("candidate_legacy");
    StringName stats_cache = StringName("cache_hits");
    StringName stats_miss = StringName("miss_callbacks");
    StringName stats_provider = StringName("provider_fallbacks");
    StringName stats_revalidation = StringName("revalidation_failures");
    StringName base_script = StringName("get_base_script");
};

static const LiveQueryNames &live_names() {
    static const LiveQueryNames names;
    return names;
}

#define SN_COUNTER (live_names().counter)
#define SN_COUNTER_CANDIDATES (live_names().counter_candidates)
#define SN_COUNTER_BODY (live_names().counter_body)
#define SN_SURROUND (live_names().surround)
#define SN_TARGET (live_names().target)
#define SN_GLOBAL_POSITION (live_names().global_position)
#define SN_PROJECT_GROUND (live_names().project_ground)
#define SN_TARGET_RADIUS (live_names().target_radius)
#define SN_RADIUS (live_names().radius)
#define SN_MAP (live_names().map)
#define SN_SPATIAL (live_names().spatial)
#define SN_CAN_RECEIVE (live_names().can_receive)
#define SN_BEHAVIOR (live_names().behavior)
#define SN_WORLD_COLLISION (live_names().world_collision)
#define SN_BLOCKER (live_names().blocker)
#define SN_PROJECTION (live_names().projection)
#define SN_CACHE_PROJECTION (live_names().cache_projection)
#define SN_ZONE_GENERATION (live_names().zone_generation)
#define SN_ENV_REVISION (live_names().env_revision)
#define SN_CACHE_SCREEN (live_names().cache_screen)
#define SN_CACHE_GROUND (live_names().cache_ground)
#define SN_CACHE_MAP (live_names().cache_map)
#define SN_CACHE_GENERATION (live_names().cache_generation)
#define SN_CACHE_REVISION (live_names().cache_revision)
#define SN_REJECTED (live_names().rejected)
#define SN_HP (live_names().hp)
#define SN_DEATH_PENDING (live_names().death_pending)
#define SN_DYING (live_names().dying)
#define SN_STATS_ENTRIES (live_names().stats_entries)
#define SN_STATS_UNSUPPORTED (live_names().stats_unsupported)
#define SN_STATS_LEGACY (live_names().stats_legacy)
#define SN_STATS_CACHE (live_names().stats_cache)
#define SN_STATS_MISS (live_names().stats_miss)
#define SN_STATS_PROVIDER (live_names().stats_provider)
#define SN_STATS_REVALIDATION (live_names().stats_revalidation)
#define SN_BASE_SCRIPT (live_names().base_script)

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
    // Godot's is_instance_valid() remains true while a node is queued.  The
    // stock query only rejects that state at its final damage predicate.
    return current == object;
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
    uint64_t previous_id = 0;
    while (script != nullptr) {
        uint64_t current_script_id = script->get_instance_id();
        // A malformed cyclic script chain must terminate without imposing an
        // arbitrary inheritance-depth limit on valid Enemy derivations.
        if (current_script_id == previous_id) {
            return false;
        }
        previous_id = current_script_id;
        if (!script->has_method(SN_BASE_SCRIPT)) {
            return false;
        }
        Variant base_variant = script->call(SN_BASE_SCRIPT);
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
    // This is the engine's public GDScript truth conversion, including all
    // Variant types and their exact error/false behavior.
    out = value.booleanize();
    return true;
}

static bool read_world_collision(Object *object, bool &out) {
    Variant profile_variant = object->get(SN_BEHAVIOR);
    if (profile_variant.get_type() != Variant::DICTIONARY) {
        return false;
    }
    Dictionary profile = profile_variant;
    Variant value = profile.get(SN_WORLD_COLLISION, true);
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
    Object *current_owner = owner;
    if (!live_object(current_owner) || script_id(current_owner) != _exact_enemy_script_id) {
        ++_unsupported_owner;
        return Variant();
    }

    auto fail_after_effect = [this](const char *reason) -> Variant {
        ++_revalidation_failures;
        UtilityFunctions::push_error(String(reason));
        return Variant(false);
    };
    const uint64_t owner_id = current_owner->get_instance_id();
    auto counter = [&current_owner](const StringName &field, int64_t amount = 1) {
        current_owner->call(SN_COUNTER, field, amount);
    };
    counter(SN_COUNTER_CANDIDATES, candidates.size());
    current_owner = ObjectDB::get_instance(owner_id);
    if (current_owner == nullptr) {
        return fail_after_effect("crowd native motion query owner was destroyed after candidate counter");
    }

    Variant surround_variant = current_owner->get(SN_SURROUND);
    Variant target_variant = current_owner->get(SN_TARGET);
    Object *target = object_from_variant(target_variant);
    if (surround_variant.get_type() == Variant::VECTOR2 && finite_vector(static_cast<Vector2>(surround_variant)) && live_object(target)) {
        Vector2 target_position;
        if (!read_vector2(target, SN_GLOBAL_POSITION, target_position)) {
            ++_unsupported_owner;
            return Variant(false);
        }
        Variant ground_variant = current_owner->call(SN_PROJECT_GROUND, target_position);
        current_owner = ObjectDB::get_instance(owner_id);
        if (current_owner == nullptr) {
            return fail_after_effect("crowd native motion query target projection invalidated an object");
        }
        // Projection is allowed to retarget the owner.  Stock code reads the
        // current target only after the projection callback.
        target = object_from_variant(current_owner->get(SN_TARGET));
        if (target != nullptr && !live_object(target)) {
            return fail_after_effect("crowd native target projection produced an invalid current target");
        }
        double target_owner_radius = 0.0;
        if (!read_float(current_owner, SN_RADIUS, target_owner_radius)) {
            return fail_after_effect("crowd native target projection produced an invalid owner radius");
        }
        double target_radius = 0.0;
        Variant radius_variant = current_owner->call(SN_TARGET_RADIUS, target);
        current_owner = ObjectDB::get_instance(owner_id);
        if (current_owner == nullptr) {
            return fail_after_effect("crowd native target radius callback invalidated an object");
        }
        if (radius_variant.get_type() != Variant::INT && radius_variant.get_type() != Variant::FLOAT) {
            ++_unsupported_owner;
            return Variant(false);
        }
        target_radius = static_cast<double>(radius_variant);
        if (ground_variant.get_type() == Variant::VECTOR2) {
            if (core_crossed(a, b, static_cast<Vector2>(ground_variant), target_owner_radius, target_radius)) {
                return false;
            }
        }
    }

    int64_t owner_map = -1;
    double owner_radius = 0.0;
    if (!read_int(current_owner, SN_MAP, owner_map) || !read_float(current_owner, SN_RADIUS, owner_radius)) {
        ++_unsupported_owner;
        return Variant(false);
    }
    Vector2 low(std::min(a.x, b.x), std::min(a.y, b.y));
    Vector2 high(std::max(a.x, b.x), std::max(a.y, b.y));
    for (int i = 0; i < candidates.size(); ++i) {
        current_owner = ObjectDB::get_instance(owner_id);
        if (current_owner == nullptr || !read_int(current_owner, SN_MAP, owner_map) ||
                !read_float(current_owner, SN_RADIUS, owner_radius)) {
            return fail_after_effect("crowd native motion query owner became invalid during candidate iteration");
        }
        target = object_from_variant(current_owner->get(SN_TARGET));
        Object *other = object_from_variant(candidates[i]);
        if (!live_object(other) || !script_is_enemy(other, _exact_enemy_script_id)) {
            continue;
        }
        const uint64_t other_id = other->get_instance_id();
        const uint64_t target_id = target != nullptr ? target->get_instance_id() : 0;
        if (other_id == owner_id || (target_id != 0 && other_id == target_id)) {
            continue;
        }
        int64_t other_map = -1;
        if (!read_int(other, SN_MAP, other_map) || other_map != owner_map) {
            continue;
        }
        counter(SN_COUNTER_BODY);
        current_owner = ObjectDB::get_instance(owner_id);
        other = ObjectDB::get_instance(other_id);
        if (current_owner == nullptr || other == nullptr) {
            return fail_after_effect("crowd native motion query body counter invalidated an object");
        }

        if (script_id(other) != _exact_enemy_script_id) {
            ++_candidate_legacy;
            Variant position_variant = other->call(SN_SPATIAL);
            current_owner = ObjectDB::get_instance(owner_id);
            other = ObjectDB::get_instance(other_id);
            if (current_owner == nullptr || other == nullptr) {
                return fail_after_effect("crowd native legacy position callback invalidated an object");
            }
            if (position_variant.get_type() != Variant::VECTOR2) {
                return fail_after_effect("crowd native legacy spatial position returned a non-Vector2");
            }
            Vector2 legacy_position = position_variant;
            double legacy_radius = 0.0;
            if (!read_float(current_owner, SN_RADIUS, owner_radius) || !read_float(other, SN_RADIUS, legacy_radius)) {
                return fail_after_effect("crowd native legacy radius became invalid after spatial callback");
            }
            double envelope = std::max(0.0, owner_radius + legacy_radius) + 0.0001;
            if (legacy_position.x < low.x - envelope || legacy_position.x > high.x + envelope ||
                    legacy_position.y < low.y - envelope || legacy_position.y > high.y + envelope) {
                continue;
            }
            Variant admissible_variant = other->call(SN_CAN_RECEIVE);
            current_owner = ObjectDB::get_instance(owner_id);
            other = ObjectDB::get_instance(other_id);
            if (current_owner == nullptr || other == nullptr) {
                return fail_after_effect("crowd native legacy eligibility callback invalidated an object");
            }
            bool admissible = false;
            if (!booleanize(admissible_variant, admissible)) {
                return fail_after_effect("crowd native legacy eligibility returned an invalid Variant");
            }
            if (!admissible) {
                continue;
            }
            bool legacy_world_collision = true;
            if (!read_world_collision(other, legacy_world_collision)) {
                return fail_after_effect("crowd native legacy worldCollision became invalid after eligibility callback");
            }
            if (!read_float(current_owner, SN_RADIUS, owner_radius) || !read_float(other, SN_RADIUS, legacy_radius)) {
                return fail_after_effect("crowd native legacy eligibility returned invalid radius");
            }
            if (legacy_world_collision && core_crossed(a, b, legacy_position, owner_radius, legacy_radius)) {
                return false;
            }
            continue;
        }

        Vector2 c;
        bool cache_hit = false;
        Object *blocker = nullptr;
        bool provider_supported = true;
        Variant projection_variant = other->get(SN_PROJECTION);
            Vector2 global_position;
            Vector2 cached_screen;
            Vector2 cached_ground;
            int64_t cached_map = -1;
            int64_t cached_generation = -1;
            int64_t cached_revision = -1;
            // Keep the cache predicate in stock short-circuit order.  In
            // particular, an unknown provider is consulted only after the
            // callable/screen/map/generation predicates have passed.
        if (projection_variant.get_type() != Variant::CALLABLE || !static_cast<Callable>(projection_variant).is_valid()) {
                provider_supported = false;
        } else if (!read_vector2(other, SN_GLOBAL_POSITION, global_position) ||
                    !read_vector2(other, SN_CACHE_SCREEN, cached_screen) ||
                    cached_screen != global_position) {
                provider_supported = false;
        } else if (!read_int(other, SN_CACHE_MAP, cached_map) || cached_map != other_map) {
                provider_supported = false;
        } else {
                int64_t generation = static_cast<int64_t>(other->get_meta(SN_ZONE_GENERATION, -1));
            if (!read_int(other, SN_CACHE_GENERATION, cached_generation) || cached_generation != generation) {
                    provider_supported = false;
            } else {
                    int64_t current_revision = -1;
                    blocker = object_from_variant(other->get(SN_BLOCKER));
                if (blocker != nullptr) {
                        if (_exact_world_background_script_id == 0 ||
                                script_id(blocker) != _exact_world_background_script_id) {
                            provider_supported = false;
                            ++_provider_fallbacks;
                        } else if (!read_int(blocker, SN_ENV_REVISION, current_revision)) {
                            provider_supported = false;
                            ++_provider_fallbacks;
                        }
                }
                if (provider_supported &&
                        (!read_int(other, SN_CACHE_REVISION, cached_revision) || cached_revision != current_revision)) {
                        provider_supported = false;
                    }
                Variant cached_projection_variant = other->get(SN_CACHE_PROJECTION);
                if (provider_supported && cached_projection_variant.get_type() == Variant::CALLABLE &&
                            static_cast<Callable>(projection_variant) == static_cast<Callable>(cached_projection_variant) &&
                            read_vector2(other, SN_CACHE_GROUND, cached_ground)) {
                        c = cached_ground;
                        cache_hit = true;
                        ++_cache_hits;
                }
            }
        }
        if (!cache_hit) {
            ++_miss_callbacks;
            Variant position_variant = other->call(SN_SPATIAL);
            current_owner = ObjectDB::get_instance(owner_id);
            other = ObjectDB::get_instance(other_id);
            if (current_owner == nullptr || other == nullptr) {
                return fail_after_effect("crowd native spatial position callback invalidated an object");
            }
            if (position_variant.get_type() != Variant::VECTOR2) {
                return fail_after_effect("crowd native spatial position returned a non-Vector2");
            }
            c = position_variant;
        }
        if (current_owner == nullptr || !read_float(current_owner, SN_RADIUS, owner_radius)) {
            return fail_after_effect("crowd native motion query owner radius became invalid");
        }
        double other_radius = 0.0;
        if (!read_float(other, SN_RADIUS, other_radius)) {
            return fail_after_effect("crowd native radius became invalid after spatial callback");
        }
        double envelope = std::max(0.0, owner_radius + other_radius) + 0.0001;
        if (c.x < low.x - envelope || c.x > high.x + envelope ||
                c.y < low.y - envelope || c.y > high.y + envelope) {
            continue;
        }
        // A spatial callback may replace the candidate script.  Continue at
        // the current position without restarting the query or incrementing
        // the body counter a second time; the stock legacy suffix is the
        // remaining can_receive/profile/core sequence.
        if (script_id(other) != _exact_enemy_script_id) {
            ++_candidate_legacy;
            Variant admissible_variant = other->call(SN_CAN_RECEIVE);
            current_owner = ObjectDB::get_instance(owner_id);
            other = ObjectDB::get_instance(other_id);
            if (current_owner == nullptr || other == nullptr) {
                return fail_after_effect("crowd native reclassified candidate eligibility invalidated an object");
            }
            bool admissible = false;
            if (!booleanize(admissible_variant, admissible)) {
                return fail_after_effect("crowd native reclassified candidate returned invalid eligibility");
            }
            if (!admissible) {
                continue;
            }
            bool legacy_world_collision = true;
            if (!read_world_collision(other, legacy_world_collision)) {
                return fail_after_effect("crowd native reclassified candidate worldCollision became invalid");
            }
            if (!read_float(current_owner, SN_RADIUS, owner_radius) ||
                    !read_float(other, SN_RADIUS, other_radius)) {
                return fail_after_effect("crowd native reclassified candidate radius became invalid");
            }
            if (legacy_world_collision && core_crossed(a, b, c, owner_radius, other_radius)) {
                return false;
            }
            continue;
        }
        bool rejected = false;
        if (!booleanize(other->get(SN_REJECTED), rejected)) {
            ++_candidate_legacy;
            continue;
        }
        Variant hp_variant;
        if (rejected) {
            continue;
        }
        hp_variant = other->get(SN_HP);
        if ((hp_variant.get_type() != Variant::INT && hp_variant.get_type() != Variant::FLOAT) || static_cast<double>(hp_variant) <= 0.0) {
            continue;
        }
        bool death_pending = false;
        if (!booleanize(other->get(SN_DEATH_PENDING), death_pending) || death_pending) {
            continue;
        }
        bool dying = false;
        if (!booleanize(other->get(SN_DYING), dying) || dying || other->is_queued_for_deletion()) {
            continue;
        }
        bool world_collision = true;
        if (!read_world_collision(other, world_collision)) {
            return fail_after_effect("crowd native worldCollision became invalid in exact predicate");
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
    result[SN_STATS_ENTRIES] = static_cast<int64_t>(_live_entries);
    result[SN_STATS_UNSUPPORTED] = static_cast<int64_t>(_unsupported_owner);
    result[SN_STATS_LEGACY] = static_cast<int64_t>(_candidate_legacy);
    result[SN_STATS_CACHE] = static_cast<int64_t>(_cache_hits);
    result[SN_STATS_MISS] = static_cast<int64_t>(_miss_callbacks);
    result[SN_STATS_PROVIDER] = static_cast<int64_t>(_provider_fallbacks);
    result[SN_STATS_REVALIDATION] = static_cast<int64_t>(_revalidation_failures);
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
