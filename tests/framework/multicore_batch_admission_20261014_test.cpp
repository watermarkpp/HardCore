#include "../../native/hardcore_simulation/batch_executor.h"
#include "../../native/hardcore_simulation/presentation_bridge.h"
#include <iostream>
#include <stdexcept>

using namespace hardcore::simulation;
#define CHECK(v) do { if (!(v)) throw std::runtime_error(#v); } while (false)

struct RejectingPool final : BatchExecutor::Pool {
    int submitted = 0;
    mutable int polled = 0;
    int waited = 0;
    BatchExecutor::GroupID add_group_task(BatchExecutor::GroupCallback, void *, int, int, bool, const char *) override {
        ++submitted;
        return UINT64_MAX; // Godot's signed INVALID_GROUP_ID through the adapter.
    }
    bool is_group_task_completed(BatchExecutor::GroupID) const override { ++polled; return false; }
    void wait_for_group_task_completion(BatchExecutor::GroupID) override { ++waited; }
};
static void copy_kernel(const FrozenInput &in, std::vector<uint8_t> &out, void *) { out = in.bytes; }

int main() {
    RejectingPool pool;
    try {
        auto input = std::make_shared<FrozenInput>();
        input->bytes = {1, 2, 3};
        {
            BatchExecutor executor(pool, 2, copy_kernel);
            CHECK(executor.dispatch_ready({11, 1}, {input}, 1, false, {10, true}) == BatchExecutor::DispatchResult::INVALID_TICKET);
            CHECK(pool.submitted == 0); // Same-tick lookahead never admits future ticks.
            CHECK(executor.dispatch_ready({10, 1}, {input}, 0, false, {10, false}) == BatchExecutor::DispatchResult::INVALID_INPUT);
            CHECK(pool.submitted == 0); // Zero workers cannot create stranded accepted work.
            CHECK(executor.dispatch_ready({10, 1}, {input}, 1, false, {10, false}) != BatchExecutor::DispatchResult::ACCEPTED);
            CHECK(executor.in_flight() == 0);
        }
        CHECK(pool.waited == 0 && pool.polled == 0);
        PresentationBridge bridge(8);
        for (uint64_t tick = 1; tick <= 100; ++tick) CHECK(bridge.publish({tick, 0, {static_cast<uint8_t>(tick)}}, {}));
        auto leased = bridge.acquire_frame(1);
        CHECK(leased.valid() && leased.snapshot->tick == 100);
        // A reader's held slot cannot be reused, but publication can continue
        // in the other slots without waiting for display Main.
        for (uint64_t tick = 101; tick <= 200; ++tick) CHECK(bridge.publish({tick, 0, {}}, {}));
        CHECK(leased.snapshot->tick == 100 && leased.snapshot->bytes[0] == 100);
        CHECK(bridge.release_frame(leased));
        auto latest = bridge.acquire_frame(101);
        CHECK(latest.valid() && latest.snapshot->tick == 200);
        CHECK(bridge.release_frame(latest));
        std::cout << "PASS multicore_batch_admission three rejection boundaries and no invalid-group waits\n";
        return 0;
    } catch (const std::exception &e) {
        std::cout << "FAIL multicore_batch_admission " << e.what() << '\n';
        return 1;
    }
}
