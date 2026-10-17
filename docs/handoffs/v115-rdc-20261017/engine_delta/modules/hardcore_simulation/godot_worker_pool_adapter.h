#pragma once

#include "batch_executor.h"

#include "core/object/worker_thread_pool.h"

namespace hardcore::simulation {

// Thin native adapter: no Callable/Node/Resource crosses the batch boundary.
// The build owner supplies the pinned engine include path and pool instance.
class GodotWorkerPoolAdapter final : public BatchExecutor::Pool {
public:
	using GroupID = BatchExecutor::GroupID;
	using GroupCallback = BatchExecutor::GroupCallback;
	explicit GodotWorkerPoolAdapter(WorkerThreadPool &pool) : pool_(pool) {}
	GroupID add_group_task(GroupCallback callback, void *userdata, int elements, int tasks, bool high_priority, const char *description) override {
		return static_cast<GroupID>(pool_.add_native_group_task(callback, userdata, elements, tasks, high_priority, String(description)));
	}
	bool is_group_task_completed(GroupID id) const override { return pool_.is_group_task_completed(static_cast<WorkerThreadPool::GroupID>(id)); }
	void wait_for_group_task_completion(GroupID id) override { pool_.wait_for_group_task_completion(static_cast<WorkerThreadPool::GroupID>(id)); }

private:
	WorkerThreadPool &pool_;
};

} // namespace hardcore::simulation
