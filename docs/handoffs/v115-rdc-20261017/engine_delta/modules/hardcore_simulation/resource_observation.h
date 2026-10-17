#pragma once

#include "core/object/ref_counted.h"
#include "core/templates/hash_set.h"
#include "core/variant/dictionary.h"

// Main's actual ResourceLoader primitive. It owns neither loader admission,
// coordinator policy, resources, budgets, nor gameplay-ready state.
class HardCoreResourceObservation : public RefCounted {
	GDCLASS(HardCoreResourceObservation, RefCounted);
	HashSet<uint64_t> generations;
protected:
	static void _bind_methods();
public:
	Dictionary threaded_status(const String &p_path, int64_t p_process_epoch, int64_t p_bridge_generation);
	Dictionary retire_generation(int64_t p_bridge_generation);
	~HardCoreResourceObservation();
};
