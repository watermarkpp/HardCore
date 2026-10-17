#include "resource_observation.h"

#include "core/io/resource_loader.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/os/thread.h"

namespace {
Dictionary rejected(const char *p_reason) {
	Dictionary result;
	result["ok"] = false;
	result["error"] = p_reason;
	return result;
}
}

void HardCoreResourceObservation::_bind_methods() {
	ClassDB::bind_method(D_METHOD("threaded_status", "path", "observation_process_epoch", "bridge_generation"), &HardCoreResourceObservation::threaded_status);
	ClassDB::bind_method(D_METHOD("retire_generation", "bridge_generation"), &HardCoreResourceObservation::retire_generation);
}

Dictionary HardCoreResourceObservation::threaded_status(const String &p_path, int64_t p_process_epoch, int64_t p_bridge_generation) {
	if (!Thread::is_main_thread()) {
		return rejected("resource_observation_requires_main");
	}
	if (p_process_epoch < 0 || p_bridge_generation <= 0) {
		return rejected("resource_observation_identity_invalid");
	}
	generations.insert(static_cast<uint64_t>(p_bridge_generation));
	float progress = 0.0f;
	bool ensured = false;
	const uint64_t started = OS::get_singleton()->get_ticks_usec();
	const ResourceLoader::ThreadLoadStatus status = ResourceLoader::load_threaded_get_status_at_process_epoch(
			p_path, static_cast<uint64_t>(p_process_epoch), static_cast<uint64_t>(p_bridge_generation), &progress, &ensured);
	const uint64_t finished = OS::get_singleton()->get_ticks_usec();
	Dictionary result;
	result["ok"] = true;
	result["status"] = static_cast<int>(status);
	result["progress"] = progress;
	result["observation_process_epoch"] = p_process_epoch;
	result["bridge_generation"] = p_bridge_generation;
	result["actual_start_usec"] = static_cast<int64_t>(started);
	result["actual_end_usec"] = static_cast<int64_t>(finished);
	// This denotes the original ensure-load-progress call, not a promise that
	// a background loader or driver made progress. Return the sampled status.
	result["progress_ensured"] = ensured;
	return result;
}

Dictionary HardCoreResourceObservation::retire_generation(int64_t p_bridge_generation) {
	if (!Thread::is_main_thread()) {
		return rejected("resource_observation_requires_main");
	}
	if (p_bridge_generation <= 0) {
		return rejected("resource_observation_identity_invalid");
	}
	if (generations.erase(static_cast<uint64_t>(p_bridge_generation))) {
		ResourceLoader::retire_hardcore_observation_generation(static_cast<uint64_t>(p_bridge_generation));
	}
	Dictionary result;
	result["ok"] = true;
	return result;
}

HardCoreResourceObservation::~HardCoreResourceObservation() {
	// This removes only observation bookkeeping. It does not consume, cancel,
	// or forget any ResourceLoader request or accepted resource obligation.
	for (uint64_t generation : generations) {
		ResourceLoader::retire_hardcore_observation_generation(generation);
	}
}
