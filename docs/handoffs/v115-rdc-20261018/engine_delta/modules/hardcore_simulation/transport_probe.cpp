#include "transport_probe.h"

#ifdef DEBUG_ENABLED
#include "batch_executor.h"
#include "godot_worker_pool_adapter.h"
#include "physics_motion_parity_tests.h"
#include "presentation_bridge.h"

#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/os/thread.h"

#include <cstring>
#include <mutex>
#include <set>

using namespace hardcore::simulation;

namespace {
struct ProbeContext {
    std::mutex mutex;
    std::set<Thread::ID> callers;
};

uint64_t checksum(const FrozenInput &input) {
    uint64_t result = input.input_version;
    for (uint8_t value : input.bytes) {
        result = (result * 33u) ^ value;
    }
    return result;
}

void transport_kernel(const FrozenInput &input, std::vector<uint8_t> &output, void *userdata) {
    auto *context = static_cast<ProbeContext *>(userdata);
    {
        std::lock_guard<std::mutex> lock(context->mutex);
        context->callers.insert(Thread::get_caller_id());
    }
    const uint64_t result = checksum(input);
    output.resize(sizeof(result));
    std::memcpy(output.data(), &result, sizeof(result));
}
}

void HardCoreMulticoreProbe::_bind_methods() {
    ClassDB::bind_method(D_METHOD("run_worker_transport"), &HardCoreMulticoreProbe::run_worker_transport);
    ClassDB::bind_method(D_METHOD("run_motion_parity"), &HardCoreMulticoreProbe::run_motion_parity);
}

Dictionary HardCoreMulticoreProbe::run_worker_transport() {
    Dictionary result;
    result["scope"] = "real_godot_pool_transport_not_gameplay_or_performance";
    result["success"] = false;
    WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
    if (pool == nullptr) {
        result["reason"] = "missing_worker_pool";
        return result;
    }
    GodotWorkerPoolAdapter adapter(*pool);
    ProbeContext context;
    // The probe context outlives executor shutdown, including failure exits.
    BatchExecutor executor(adapter, 1, transport_kernel, &context);
    std::vector<std::shared_ptr<const FrozenInput>> inputs;
    for (uint32_t index = 0; index < 8; ++index) {
        auto input = std::make_shared<FrozenInput>();
        input->input_version = index + 1;
        input->bytes.resize(16384);
        for (uint32_t offset = 0; offset < input->bytes.size(); ++offset) {
            input->bytes[offset] = static_cast<uint8_t>((index * 17 + offset) & 255);
        }
        inputs.push_back(input);
    }
    BatchTicket ticket{1, 1};
    if (executor.dispatch_ready(ticket, inputs, 2, false, {1, false}) != BatchExecutor::DispatchResult::ACCEPTED) {
        result["reason"] = "dispatch_rejected";
        return result;
    }
    std::vector<bool> consumed(inputs.size(), false);
    size_t count = 0;
    const uint64_t deadline = OS::get_singleton()->get_ticks_usec() + 10000000;
    while (count < inputs.size() && OS::get_singleton()->get_ticks_usec() < deadline) {
        for (uint32_t id : executor.poll_published(ticket).block_ids) {
            if (id >= inputs.size() || consumed[id]) {
                result["reason"] = "invalid_or_repeated_ready";
                return result;
            }
            auto output = executor.acquire_output(ticket, id);
            if (!output.valid() || output.bytes->size() != sizeof(uint64_t)) {
                result["reason"] = "invalid_output";
                return result;
            }
            uint64_t actual = 0;
            std::memcpy(&actual, output.bytes->data(), sizeof(actual));
            if (actual != checksum(*inputs[id]) || !executor.consume_block(ticket, id, {1})) {
                result["reason"] = "output_mismatch_or_double_consume";
                return result;
            }
            consumed[id] = true;
            ++count;
        }
        if (count < inputs.size()) {
            // Diagnostic fixture only. The production presentation path never
            // invokes this method or waits for a worker group on Main.
            OS::get_singleton()->delay_usec(1000);
        }
    }
    if (count != inputs.size()) {
        result["reason"] = "transport_timeout";
        return result;
    }
    // Group completion and block publication are separate observations.
    bool retired = false;
    while (!(retired = executor.retire_completed(ticket)) && OS::get_singleton()->get_ticks_usec() < deadline) {
        executor.poll_published(ticket);
        OS::get_singleton()->delay_usec(1000);
    }
    if (!retired || executor.in_flight() != 0) {
        result["reason"] = "group_retirement_timeout";
        return result;
    }
    PresentationBridge presentation(8);
    if (!presentation.publish({1, 1, {42}}, {{1, 1, {7}}})) {
        result["reason"] = "presentation_publish_failed";
        return result;
    }
    auto frame = presentation.acquire_frame(1);
    auto events = presentation.drain_events(1, 8);
    if (!frame.valid() || !events.valid() || events.events.size() != 1 || frame.snapshot->last_effect_ordinal != events.last_ordinal || presentation.ack_events(2)) {
        result["reason"] = "presentation_watermark_failed";
        return result;
    }
    if (!presentation.ack_events(1) || !presentation.release_frame(frame)) {
        result["reason"] = "presentation_retirement_failed";
        return result;
    }
    {
        std::lock_guard<std::mutex> lock(context.mutex);
        result["worker_thread_count"] = static_cast<int64_t>(context.callers.size());
        result["kernel_ran_on_caller"] = context.callers.count(Thread::get_caller_id()) != 0;
        if (context.callers.empty() || context.callers.count(Thread::get_caller_id()) != 0) {
            result["reason"] = "kernel_not_executed_by_worker";
            return result;
        }
    }
    result["completed_blocks"] = static_cast<int64_t>(count);
    result["success"] = true;
    return result;
}

Dictionary HardCoreMulticoreProbe::run_motion_parity() {
    return hardcore::simulation::run_physics_motion_parity_tests();
}
#endif
