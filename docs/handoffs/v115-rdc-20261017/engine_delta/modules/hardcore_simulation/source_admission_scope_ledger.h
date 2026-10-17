#pragma once
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
namespace hardcore::simulation {
class SourceAdmissionScopeLedger {
public:
 using Bytes=std::shared_ptr<const std::vector<uint8_t>>;
 enum class State{PREPARED,COMMITTED,ABORTED};
 enum class Status{READY,PENDING,INVALID};
 struct Snapshot{uint64_t generation=0,scope_id=0,producer=0;std::string profile;State state=State::PREPARED;Bytes world,receipt,publication;};
 struct Read{Status status=Status::PENDING;Snapshot snapshot;};
 explicit SourceAdmissionScopeLedger(uint64_t generation,std::size_t bytes):generation_(generation),capacity_(bytes),main_(std::this_thread::get_id()){}
 bool bind_owner();
 Status publish(const Snapshot&); // Main actual producer, no queue or gameplay state writes.
 Read claim(uint64_t scope); // S nonblocking adoption admission, no stack park.
 Read poll(uint64_t scope)const; // Actual Main committed/aborted status only.
 Status permission(uint64_t scope,const std::string&opcode)const;
 bool allows(uint64_t scope,const std::string&opcode)const;
 bool finish(uint64_t scope); // S only after actual Main terminal scope receipt.
 bool quiescent()const;
 bool retire_unclaimed_aborted_main(); // Main only, no Source owner has ever claimed this scope.
private:
 const uint64_t generation_;const std::size_t capacity_;const std::thread::id main_;std::thread::id owner_;
 mutable std::mutex mutex_;Snapshot active_;bool claimed_=false,finished_=true;uint64_t retired_scope_=0;
 static bool same(const Snapshot&,const Snapshot&);
};
}
