#pragma once
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <map>
#include <mutex>
#include <thread>
#include <vector>

namespace hardcore::simulation {
class OriginalPrimitiveMailbox {
public:
    using Bytes=std::shared_ptr<const std::vector<uint8_t>>;
    enum class Channel:uint8_t{RESOURCE,WORLD};
    struct Identity{uint64_t generation=0,sequence=0;bool operator==(const Identity&o)const{return generation==o.generation&&sequence==o.sequence;}};
    struct Event{uint64_t ordinal=0;Bytes bytes;};
    struct Prefix{uint64_t generation=0,journal_generation=0,through=0;Bytes bytes;std::vector<Event> events;};
    struct PrefixReceipt{uint64_t generation=0,journal_generation=0,through=0;bool applied=false;};
    struct Request{Identity identity;uint64_t predecessor=0,submitted_usec=0,deadline_usec=0,call_ordinal=0;Channel channel=Channel::RESOURCE;Prefix prefix;Bytes bytes,source_site_bytes;};
    struct Ack{Identity identity;uint64_t journal_generation=0,through=0;Bytes prefix_bytes;bool applied=false;};
    struct Reply{Identity identity;Bytes request_bytes,bytes;uint64_t started_usec=0,finished_usec=0;};
    struct Pending{Request request;bool ready=false;bool valid()const{return ready;}};
    struct ExchangeResult{bool accepted=false,late=false;Bytes bytes;Ack prefix_ack;};
    OriginalPrimitiveMailbox(uint64_t generation,size_t request_capacity,size_t result_capacity,size_t prefix_capacity);
    struct MainPrefixClaim{bool ready=false;uint64_t after=0,through=0;std::vector<Event> events;};
    enum class MainEventStatus{READY,PENDING,INVALID};
    enum class PublishedReadStatus { READY, PENDING, BUSY, INVALID };
    struct PublishedRead { PublishedReadStatus status=PublishedReadStatus::INVALID; Prefix prefix; };
    PublishedRead inspect_next_published_prefix()const; // Main peek of existing FIFO; no new admission or ACK.
    MainEventStatus actual_published_prefix_status(const Prefix&)const; // Main factual ACK observation only.
    MainEventStatus claimed_main_event_status(uint64_t journal,uint64_t ordinal,const Bytes&)const;
    MainEventStatus try_register_original_presentation_prefix(const Prefix&);
    MainPrefixClaim claim_main_prefix(const Prefix&); // Main unique delta across normal/cold/live consumers.
    enum class AsyncAdmission{ACCEPTED,BUSY,INVALID,BACKPRESSURE};
    struct AsyncPreview{uint64_t sequence=0,call_ordinal=0;};
    AsyncPreview preview_async(const Bytes&)const; // S try-lock, no resource wait.
    AsyncAdmission admit_async(const Request&); // S try-lock, shared admission sequence/site allocator.
    bool ack_async_prefix(const Request&); // Main factual receipt, never S applied-ledger writes.
    bool commit_async(const Identity&); // S budget settled.
    enum class AsyncCommit{COMMITTED,BUSY,INVALID};
    AsyncCommit commit_async_status(const Identity&);
    struct OperationState{bool available=false,completed=false,retired=false;};
    OperationState read_operation_state_try(const Identity&)const;
    bool retire_async(const Identity&); // S after actual Main lease retirement.
    bool operation_completed(const Identity&)const;
    bool operation_retired(const Identity&)const;
    bool bind_owner();
    bool stage_prefix(const Prefix&);
    bool register_published_prefix(const Prefix&); // S exact producer; repeats dedupe.
    bool ack_published_prefix(const Prefix&); // Main actual consumer receipt, ledger unchanged.
    PrefixReceipt consume_published_receipts(); // S advances its sole applied ledger.
    size_t unsettled_published_count()const;
    ExchangeResult exchange(const Request&); // S-only CV park, no deadline cancellation.
    Pending acquire_pending(); // Main-only, nonblocking unique acquisition.
    bool ack_prefix(const Ack&);
    bool claim_execution(const Identity&); // Main-only, unique original API execution.
    bool submit(const Reply&);
    Pending lookup(const Identity&)const;
    uint64_t next_sequence()const;
    uint64_t completed_sequence()const;
    uint64_t late_count()const;
    uint64_t applied_prefix()const;
    uint64_t next_call_ordinal(const Bytes&)const; // S-only, exact complete source site wire.
    bool finish_call_site(const Bytes&); // End the original scope, no accepted packet.
    bool reset_call_sites(); // Actual source Clock epoch transition only.
    void request_close();
    bool close_requested()const;
    bool mark_quiescent();
    bool quiescent()const;
    bool can_join()const;
    bool in_flight()const;
    bool prefix_applied(const Identity&)const;
private:
    const uint64_t generation_;
    const size_t request_capacity_,result_capacity_,prefix_capacity_;
    const std::thread::id main_;
    std::thread::id owner_;
    mutable std::mutex mutex_;
    std::condition_variable returned_;
    Prefix staged_;
    Request active_,last_request_;
    Reply reply_,last_reply_;
    Ack ack_,last_ack_;
    std::shared_ptr<std::vector<uint8_t>> reserved_return_slot_;
    bool active_valid_=false,acquired_=false,prefix_applied_=false,execution_claimed_=false,reply_ready_=false;
    bool close_requested_=false,quiescent_=false;
    uint64_t admitted_=0,retired_=0,main_applied_prefix_=0;
    Prefix main_claimed_prefix_;bool main_claimed_=false;
    bool acknowledge_main_prefix_locked(const Prefix&);
    struct AdmissionRecord{Request request;bool committed=false,retired=false;};
    std::map<uint64_t,AdmissionRecord> admissions_;
    bool admit_locked(const Request&);
    void advance_frontiers();
    uint64_t completed_=0,late_count_=0,applied_prefix_=0,journal_generation_=0;
    std::map<std::vector<uint8_t>,uint64_t> completed_calls_; // Admission call ordinal, full bytes, not hash-only identity.
    struct Published{Prefix prefix;bool acknowledged=false;};
    std::vector<Published> published_;
    Prefix last_published_ack_;
    std::map<uint64_t,Bytes> known_events_;
    size_t known_event_bytes_=0; // The journal wire budget is independent of FIFO/ticket slots.
    bool register_events(const Prefix&);
    void prune_events();
    static bool equal(const Bytes&,const Bytes&);
    static bool equal(const Prefix&,const Prefix&);
    static bool equal(const Reply&,const Reply&);
};
} // namespace hardcore::simulation
