#pragma once
#include "original_primitive_mailbox.h"
#include <optional>
#include <deque>
namespace hardcore::simulation {
// Numeric transport only. It does not load resources, mutate a budget, own a
// world, or interpret texture tokens. Actual Main consumers supply evidence.
class AsyncLiveResourceMailbox {
public:
  using Original=OriginalPrimitiveMailbox;
  using Bytes=Original::Bytes;using Identity=Original::Identity;
  enum class Admission{ACCEPTED,DUPLICATE,BUSY,BACKPRESSURE,INVALID};
  enum class SettlementStatus{SETTLED,PENDING,INVALID};
  enum class After{MAIN_EXECUTED,S_COMMITTED,RETIRED};
  struct Dependency{Identity identity;After after=After::S_COMMITTED;};
  struct Reservation{uint64_t id=0,owner_session=0,ledger_epoch=0;uint8_t lane=0;uint64_t reserved_usec=0,issued_usec=0;Bytes category;};
  struct Request{Original::Request original;Bytes order_key;int priority=0;Reservation reservation;std::vector<Dependency> dependencies;bool cleanup=false;Bytes pre_admission_bytes;Bytes issued_claim_context;};
  struct Reply{Original::Reply original;uint64_t main_cpu_usec=0;Bytes actual_lease_obligations;};
  struct Pending{Request request;bool ready=false;uint64_t acquired_usec=0;};
  struct Completion{Request request;Reply reply;bool ready=false,late=false;uint64_t receipt_received_usec=0,s_poll_epoch=0,queue_wait_usec=0,charged_usec=0,main_cpu_usec=0,acquired_usec=0,queue_residence_usec=0,dispatch_wait_usec=0;};
  struct Settlement{uint64_t reservation_id=0,owner_session_id=0;Identity identity;uint64_t s_commit_epoch=0,started_usec=0,finished_usec=0,charged_usec=0,received_usec=0,queue_wait_usec=0,overrun_usec=0;};
  AsyncLiveResourceMailbox(Original&,uint64_t generation,size_t slots,size_t request_bytes,size_t reply_bytes);
  ~AsyncLiveResourceMailbox(); // Refuse loss of accepted obligations.
  bool bind_owner();
  Admission submit(const Request&); // S nonblocking; ACCEPTED reserves reply storage.
  struct Probe{Admission status=Admission::ACCEPTED;Request request;}; // ACCEPTED here means fresh reservation.
  Probe probe_submission(uint64_t owner_session,uint64_t reservation,const Bytes&); // S exact preimage dedupe.
  Pending acquire(uint64_t actual_acquire_invocation_usec); // Main nonblocking; actual source clock only.
  Pending lookup(const Identity&)const;
  bool acknowledge_prefix(const Identity&,const Original::Prefix&); // Main after actual apply.
  bool claim_execution(const Identity&); // Main unique executor, no second validation call.
  bool submit_result(const Reply&); // Main actual API result, retained even if late.
  Completion poll(const Identity&,uint64_t received_usec,uint64_t s_commit_epoch); // S nonblocking.
  bool settle(const Settlement&); // S verifies sole caller's actual ledger settlement.
  SettlementStatus settle_status(const Settlement&); // One operation; only lock contention is PENDING.
  bool acknowledge_actual_lease_retirement(const Identity&,const Bytes&); // Main vault proof.
  enum class TransferStatus{TRANSFERRED,PENDING,INVALID};
  TransferStatus acknowledge_actual_lease_transfer_status(const Identity&,const Bytes&);
  bool acknowledge_actual_lease_transfer(const Identity&,const Bytes&); // Main verified persistent physical owner, not retirement.
  bool transport_releasable(const Identity&)const; // S nonblocking: transport settled and physically retired or transferred.
  bool retire(const Identity&); // S settled AND real lease obligations gone.
  void request_close();
  bool can_close()const;
  size_t accepted_count()const;
private:
  enum class State{FREE,QUEUED,ACQUIRED,EXECUTING,READY,POLLED,SETTLED};
  struct Slot{State state=State::FREE;Request request;Reply reply;Completion completion;std::shared_ptr<std::vector<uint8_t>> return_slot;bool prefix_applied=false,lease_retired=false,lease_transferred=false;uint64_t acquired_usec=0;Settlement committed_settlement;};
  Original& original_;const uint64_t generation_;const size_t request_bytes_,reply_bytes_;
  const std::thread::id main_;std::thread::id owner_;mutable std::mutex mutex_;std::vector<Slot> slots_;bool closing_=false;
  std::deque<Settlement> recent_settlements_; // At most slot capacity, full numeric receipts; stale replay rejects.
  Slot* find(const Identity&);const Slot* find(const Identity&)const;
  bool eligible(const Slot&)const;
  static bool equal(const Bytes&,const Bytes&);
  static bool equal(const Request&,const Request&);
  static bool equal(const Reply&,const Reply&);
  static bool equal(const Settlement&,const Settlement&);
};
}
