#ifndef CROWD_MELEE_KERNEL_H
#define CROWD_MELEE_KERNEL_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class CrowdMeleeKernel : public RefCounted {
    GDCLASS(CrowdMeleeKernel, RefCounted)

protected:
    static void _bind_methods();

public:
    int32_t get_abi_version() const;
    bool core_crossed(Vector2 a, Vector2 b, Vector2 c, double ra, double rb) const;
};

}

#endif
