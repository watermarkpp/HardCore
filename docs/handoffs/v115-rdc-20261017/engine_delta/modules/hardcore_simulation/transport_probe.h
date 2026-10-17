#pragma once

#ifdef DEBUG_ENABLED
#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"

// Integration diagnostics only. This does not run game AI or commit gameplay.
class HardCoreMulticoreProbe : public RefCounted {
    GDCLASS(HardCoreMulticoreProbe, RefCounted);

protected:
    static void _bind_methods();

public:
    Dictionary run_worker_transport();
    Dictionary run_motion_parity();
};
#endif
