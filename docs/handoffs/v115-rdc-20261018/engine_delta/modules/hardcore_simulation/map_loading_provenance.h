#pragma once
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
namespace hardcore::simulation {
// Immutable provenance register, not a request/result queue or a resource owner.
class MapLoadingProvenance {
public:
 using Bytes=std::shared_ptr<const std::vector<uint8_t>>;
 enum class State { LOADING, RETAINED, CLOSED };
 struct Snapshot {uint64_t generation=0,scope=0,producer=0,coordinator=0;int64_t map=-1;std::string transition;State state=State::LOADING;Bytes scope_wire,descriptor,world;};
 MapLoadingProvenance(uint64_t generation,size_t capacity):generation_(generation),capacity_(capacity),main_(std::this_thread::get_id()){}
 bool bind_owner();
 bool bind_main_owner(uint64_t actual_producer); // Binding itself retains real owner debt.
 bool publish(const Snapshot&); // Main after actual producer verification outside this class.
 std::shared_ptr<const Snapshot> read_owner() const;
 bool permits(const Snapshot&,bool cleanup=false) const;
 bool commit_arrival(const Snapshot&); // S-only CAS of the exact LOADING scope.
 bool certify_owner_closed(const Bytes& actual_terminal_receipt); // Main only; byte fact, no guessed IO.
 bool can_close() const;
private:
 const uint64_t generation_;const size_t capacity_;const std::thread::id main_;std::thread::id owner_;
 uint64_t producer_=0;std::atomic<bool> owner_open_{false};
 std::atomic<uint64_t> arrived_scope_{0};
 std::mutex mutation_mutex_; // Never waits on Main or S; failed try-lock retains debt.
 std::shared_ptr<const Snapshot> current_;Bytes terminal_;
 static bool same(const Bytes&,const Bytes&);
};
}
