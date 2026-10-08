#ifndef CROWD_MELEE_KERNEL_H
#define CROWD_MELEE_KERNEL_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class CrowdMeleeKernel : public RefCounted {
    GDCLASS(CrowdMeleeKernel, RefCounted)

protected:
    static void _bind_methods();

public:
    int32_t get_abi_version() const;
    bool core_crossed(Vector2 a, Vector2 b, Vector2 c, double ra, double rb) const;
    Array forward_buffers(const PackedFloat64Array &scalars,
            const PackedVector2Array &vectors,
            const PackedInt64Array &identities) const;
    void configure_live_motion_scripts(Object *exact_enemy_script,
            Object *exact_world_background_script);
    Variant motion_candidates_live(Object *owner, Vector2 a, Vector2 b,
            const Array &candidates) const;
    Dictionary get_live_motion_stats() const;
    void reset_live_motion_stats();

private:
    uint64_t _exact_enemy_script_id = 0;
    uint64_t _exact_world_background_script_id = 0;
    mutable uint64_t _live_entries = 0;
    mutable uint64_t _unsupported_owner = 0;
    mutable uint64_t _candidate_legacy = 0;
    mutable uint64_t _cache_hits = 0;
    mutable uint64_t _miss_callbacks = 0;
    mutable uint64_t _provider_fallbacks = 0;
    mutable uint64_t _revalidation_failures = 0;
};

}

#endif
