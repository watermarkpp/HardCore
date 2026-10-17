#pragma once
#include "core/object/ref_counted.h"
#include "core/object/worker_thread_pool.h"
#include "core/os/thread.h"
#include "pursuit_numeric.h"
#include "close_progress_signal.h"
class HardCoreSimulationHost;
#include <atomic>
#include <mutex>

class HardCorePursuitPlanning final : public RefCounted {
    GDCLASS(HardCorePursuitPlanning, RefCounted);
    struct State;
    struct Wave {
        std::shared_ptr<State> state;
        std::vector<size_t> actors;
        WorkerThreadPool::GroupID group = WorkerThreadPool::INVALID_TASK_ID;
        std::atomic<size_t> callbacks_done{0};
        bool reclaimed = false;
        bool close_debt=false;
    };
    struct State {
        WorkerThreadPool *pool = nullptr;
        std::shared_ptr<hardcore::simulation::CloseProgressSignal> close_progress;
        std::vector<std::unique_ptr<hardcore::simulation::pursuit::Search>> searches;
        std::vector<bool> finished;
        std::vector<std::unique_ptr<Wave>> waves;
        std::mutex mutex;
        std::atomic<bool> ready{false}, dispatch_failed{false};
        std::atomic<bool> stop_requested{false};
        std::atomic<uint64_t> maximum_slice_usec{0}, maximum_active_workers{0}, active_workers{0};
        uint64_t ready_usec = 0, release_usec = 0, deadline_usec = 0;
        uint32_t worker_cap = 0, slice_work = 0, wave_capacity = 0;
        bool dispatch_pending = false;
        size_t cursor = 0;
    };
    Thread::ID owner_ = Thread::get_caller_id();
    bool configured_ = false;
    int max_actors_ = 0, max_peers_ = 0, worker_cap_ = 0, slice_work_ = 0, wave_capacity_ = 0;
    uint64_t next_sequence_ = 0, publication_id_ = 0;
    Dictionary world_identity_, static_descriptor_, active_ticket_;
    std::map<std::string, std::shared_ptr<const hardcore::simulation::pursuit::Navigation>> navigation_;
    std::shared_ptr<const hardcore::simulation::pursuit::FrozenWorld> static_world_;
    std::shared_ptr<State> active_;
    std::shared_ptr<hardcore::simulation::CloseProgressSignal> close_progress_;
    static void worker_slice(void *, uint32_t);
    static void dispatch_wave(const std::shared_ptr<State> &);
    bool owned() const;
    bool reclaim_completed_waves();
protected:
    static void _bind_methods();
public:
    ~HardCorePursuitPlanning();
    int64_t owner_thread_id() const { return int64_t(owner_); }
    bool bind_original_completion_host(const Ref<HardCoreSimulationHost>&host);
    bool configure_owner(int max_actors, int max_peers, int worker_cap, int slice_work, int wave_capacity);
    Dictionary capabilities() const;
    Dictionary publish_static_navigation(const Dictionary &values, const Dictionary &predicates, const Dictionary &world, int64_t revision, const Dictionary &loading_admission);
    Dictionary submit_planning_batch(const Dictionary &snapshot, int64_t deadline_usec);
    Dictionary poll_planning_batch(const Dictionary &ticket);
    bool retire_planning_batch(const Dictionary &ticket);
    bool cancel_planning_batch(const Dictionary &ticket);
    bool has_pending_planning_batches() const;
    bool close_owner();
};
