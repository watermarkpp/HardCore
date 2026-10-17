#include "../../native/hardcore_simulation/batch_executor.h"
#include "../../native/hardcore_simulation/presentation_bridge.h"

#include <cassert>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <thread>

using namespace hardcore::simulation;

struct ControlledPool final : BatchExecutor::Pool {
	struct Group { BatchExecutor::GroupCallback callback; void *userdata; int elements; bool done = false; };
	std::vector<Group> groups;
	BatchExecutor::GroupID add_group_task(BatchExecutor::GroupCallback cb, void *ud, int elements, int, bool, const char *) override {
		groups.push_back({cb, ud, elements, false}); return groups.size() - 1;
	}
	bool is_group_task_completed(BatchExecutor::GroupID id) const override { return groups.at(id).done; }
	void wait_for_group_task_completion(BatchExecutor::GroupID id) override { for (int i = 0; i < groups.at(id).elements; ++i) groups.at(id).callback(groups.at(id).userdata, static_cast<uint32_t>(i)); groups.at(id).done = true; }
	void run_one(BatchExecutor::GroupID id, uint32_t index) { groups.at(id).callback(groups.at(id).userdata, index); }
};

static void kernel(const FrozenInput &input, std::vector<uint8_t> &output, void *) { output = input.bytes; }

struct AsyncPool final : BatchExecutor::Pool {
	BatchExecutor::GroupCallback callback = nullptr; void *userdata = nullptr; std::thread worker;
	std::mutex mutex; std::condition_variable cv; std::atomic<bool> done{false};
	BatchExecutor::GroupID add_group_task(BatchExecutor::GroupCallback cb, void *ud, int, int, bool, const char *) override {
		callback = cb; userdata = ud;
		worker = std::thread([this] { callback(userdata, 0); done.store(true, std::memory_order_release); cv.notify_all(); });
		return 0;
	}
	bool is_group_task_completed(BatchExecutor::GroupID) const override { return done.load(std::memory_order_acquire); }
	void wait_for_group_task_completion(BatchExecutor::GroupID) override { if (worker.joinable()) worker.join(); }
};

static std::mutex kernel_mutex;
static std::condition_variable kernel_cv;
static bool kernel_entered = false;
static bool kernel_release = false;
static void blocking_kernel(const FrozenInput &input, std::vector<uint8_t> &output, void *) {
	std::unique_lock<std::mutex> lock(kernel_mutex); output = input.bytes; kernel_entered = true; kernel_cv.notify_all(); kernel_cv.wait(lock, [] { return kernel_release; });
}

static void concurrent_destructor_behavior() {
	AsyncPool pool;
	std::unique_ptr<BatchExecutor> executor = std::make_unique<BatchExecutor>(pool, 1, blocking_kernel);
	BatchTicket ticket{9, 1};
	auto input = std::make_shared<FrozenInput>(); input->bytes = {42};
	assert(executor->dispatch_ready(ticket, {input}, 1, false, BatchExecutor::DispatchWindow{9, false}) == BatchExecutor::DispatchResult::ACCEPTED);
	{ std::unique_lock<std::mutex> lock(kernel_mutex); kernel_cv.wait(lock, [] { return kernel_entered; }); }
	std::atomic<bool> destroyed{false};
	std::thread destroyer([&] { executor.reset(); destroyed.store(true, std::memory_order_release); });
	assert(!destroyed.load(std::memory_order_acquire));
	{ std::lock_guard<std::mutex> lock(kernel_mutex); kernel_release = true; }
	kernel_cv.notify_all(); destroyer.join();
	assert(destroyed.load(std::memory_order_acquire));
}

static void batch_behavior() {
	ControlledPool pool;
	{
		BatchExecutor executor(pool, 1, kernel);
		BatchTicket ticket{7, 1};
		std::vector<std::shared_ptr<const FrozenInput>> inputs;
		for (int i = 0; i < 2; ++i) { auto input = std::make_shared<FrozenInput>(); input->bytes.push_back(static_cast<uint8_t>(i)); inputs.push_back(input); }
		assert(executor.dispatch_ready(ticket, inputs, 1, false, BatchExecutor::DispatchWindow{7, false}) == BatchExecutor::DispatchResult::ACCEPTED);
		pool.run_one(0, 0); // partial READY is visible before the other element completes.
		auto ready = executor.poll_published(ticket);
		assert(ready.block_ids.size() == 1 && ready.block_ids[0] == 0);
		assert(executor.consume_block(ticket, 0, BatchOwner{99})); // consumer owns consumption, producer owner is irrelevant.
		assert(!executor.complete_claimed(ticket, 0, BatchOwner{99})); // cannot complete a consumed block twice.
		assert(executor.claim_block(ticket, 1, BatchOwner{5}) == BatchExecutor::ClaimResult::CLAIMED);
		assert(executor.complete_claimed(ticket, 1, BatchOwner{5}));
		assert(!executor.complete_claimed(ticket, 1, BatchOwner{5})); // completion token is one-shot.
		pool.groups[0].done = true;
		assert(executor.poll_published(ticket).block_ids.size() == 1);
		assert(executor.consume_block(ticket, 1, BatchOwner{77}));
		assert(executor.retire_completed(ticket));
	}
	// Destructor must drain a still-running callback before Task storage dies.
	{
		BatchExecutor executor(pool, 1, kernel);
		BatchTicket ticket{8, 1};
		auto input = std::make_shared<FrozenInput>();
		assert(executor.dispatch_ready(ticket, {input}, 1, false, BatchExecutor::DispatchWindow{8, false}) == BatchExecutor::DispatchResult::ACCEPTED);
	}
}

static void presentation_behavior() {
	PresentationBridge bridge(2);
	for (uint64_t tick = 1; tick <= 3; ++tick) assert(bridge.publish({tick, 0, {}}, {}));
	auto stale = bridge.acquire_frame(1);
	assert(stale.valid() && stale.snapshot->tick == 3);
	assert(bridge.release_frame(stale));
	assert(bridge.publish({4, 0, {}}, {})); // latest snapshot retires stale PUBLISHED slots.
	auto frame = bridge.acquire_frame(1);
	assert(frame.valid() && frame.snapshot->tick == 4);
	assert(bridge.release_frame(frame));
	std::vector<PresentationBridge::Event> events{{1, 4, {1}}, {2, 4, {2}}};
	assert(bridge.publish({5, 2, {}}, events));
	assert(!bridge.ack_events(2)); // not drained and therefore not acknowledged.
	assert(!bridge.drain_events(2, 1).valid()); // insufficient capacity returns whole-bundle NotReady.
	auto lease = bridge.drain_events(2, 2);
	assert(lease.valid() && lease.events.size() == 2);
	assert(bridge.ack_events(2));
}

int main() { batch_behavior(); concurrent_destructor_behavior(); presentation_behavior(); return 0; }
