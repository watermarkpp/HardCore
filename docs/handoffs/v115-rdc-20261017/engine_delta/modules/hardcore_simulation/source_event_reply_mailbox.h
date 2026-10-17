#pragma once
#include <cstdint>
#include <atomic>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>
namespace hardcore::simulation {
class SourceEventReplyMailbox {
public:
 using Bytes=std::shared_ptr<const std::vector<uint8_t>>;
 struct Identity{uint64_t generation=0,journal=0,ordinal=0;bool operator==(const Identity&b)const{return generation==b.generation&&journal==b.journal&&ordinal==b.ordinal;}};
 enum class Status{READY,PENDING,BACKPRESSURE,INVALID};
 struct Read{Status status=Status::PENDING;Identity identity;Bytes event,prefix,reply;uint64_t node=0;bool consumed=false,retired=false;uint64_t received_usec=0,s_poll_epoch=0;std::vector<Bytes> claim_transfers;};
 struct TransferIdentity{Identity parent;uint64_t transfer=0;bool operator==(const TransferIdentity&b)const{return parent==b.parent&&transfer==b.transfer;}};
 enum class TransferState{OFFERED,ACCEPTED,ORIGIN_RELEASED,TERMINAL};
 enum class Insertion{NONE,EXACT,REMOVED,UNKNOWN};
 struct ClaimQueue{Insertion insertion=Insertion::UNKNOWN;uint64_t entry=0;int64_t location=-1;uint64_t count=0,remaining=0,session=0,owner=0;};
 struct TransferRead{Status status=Status::PENDING;TransferIdentity identity;TransferState state=TransferState::OFFERED;Bytes evidence,acceptance,observation;std::vector<Bytes> facts;uint64_t count=0,terminal_count=0,entry=0,session=0,source_owner=0,observation_operation=0,observation_first=0;bool admit=false,in_flight=false,queue_removed=false,fault=false;};
 // Attached evidence on the existing accepted/claimed caster record. These
 // records never schedule work and never retain a parent execution slot.
 Status offer_transfer(const TransferIdentity&,const Bytes&evidence,uint64_t count);
 TransferRead inspect_transfer(const TransferIdentity&)const;
 TransferRead begin_transfer_accept(const TransferIdentity&); // S; reserves ACK storage before callback, prevents reentry.
 Status finish_transfer_accept(const TransferIdentity&,const ClaimQueue&,const Bytes&actual_ack);
 Status observe_transfer_queue(const TransferIdentity&,const ClaimQueue&);
 Status release_transfer_origin(const TransferIdentity&); // Main after actual origin verifier.
 Status begin_transfer_leaf(const TransferIdentity&,uint64_t entry,uint64_t first,uint64_t remaining,uint64_t operation,uint64_t session,uint64_t owner);
 // Native Main executor only; parameters come from the admitted LIVE slot.
 Status begin_live_transfer_leaf(const TransferIdentity&,uint64_t entry,uint64_t first,uint64_t remaining,uint64_t operation,uint64_t session,uint64_t owner);
 Status finish_transfer_leaf(const TransferIdentity&,uint64_t operation,uint64_t first,uint64_t count,const Bytes&actual_fact); // Main original reply only; count zero is nonterminal.
 Status remember_transfer_observation(const TransferIdentity&,uint64_t operation,const Bytes&actual_observation);
 Status ack_transfer_delivery(const TransferIdentity&); // Internal original IO observation/ACK boundary only.
 std::vector<TransferRead> inspect_main_transfers()const;
 size_t attached_record_capacity()const{return transfers_.size();}
 SourceEventReplyMailbox(uint64_t generation,size_t slots,size_t event_bytes,size_t reply_bytes);
 bool bind_owner();
 Status reserve(const Identity&,const Bytes&event,bool cleanup); // S before sole journal append.
 Status accept(const Identity&,const Bytes&event,const Bytes&actual_prefix); // S after real registered append.
 bool cancel_unaccepted(const Identity&); // S only append failed, no accepted event.
 Read acquire_prefix()const; // Main closing driver; original shared prefix consumer still applies it.
 Read inspect_main(const Identity&)const;
 Status claim(const Identity&,const Bytes&actual_claimed_event); // Main once, prefix proof checked by Host.
 Status submit(const Identity&,const Bytes&reply,uint64_t actual_node); // Main actual Node lifetime or zero.
 Read poll_with_observation(const Identity&,uint64_t now_usec,uint64_t s_clock_epoch);
 Read poll(const Identity&)const; // S LIVE/close, no normal input.
 Status consume(const Identity&); // S applies actual reply once.
 Status acknowledge_retired(const Identity&,uint64_t actual_node); // Main only after real ObjectDB absence.
 Status retire(const Identity&); // S only consumed and Main real lifetime gone.
 void request_close();
 bool can_close()const;
private:
 struct Slot{bool used=false,accepted=false,claimed=false,submitted=false,consumed=false,retired=false;Identity id;Bytes event,prefix;std::shared_ptr<std::vector<uint8_t>>buffer;size_t reply_size=0;uint64_t node=0;bool observed=false;uint64_t received_usec=0,s_poll_epoch=0;};
 struct Lifetime{bool used=false,retired=false;Identity id;Bytes event,prefix,reply;uint64_t node=0;bool observed=false;uint64_t received_usec=0,s_poll_epoch=0;};
 const uint64_t generation_;const size_t normal_slots_,event_capacity_,reply_capacity_;const std::thread::id main_;std::thread::id owner_;
 mutable std::mutex mutex_;std::vector<Slot>slots_;std::vector<Lifetime>lifetimes_;std::atomic<bool>closing_{false};uint64_t accepted_high_water_=0,journal_=0;
 struct Transfer{bool used=false,accepting=false,attempted=false,fault=false,queue_removed=false,in_flight=false,delivered=false;TransferIdentity id;TransferState state=TransferState::OFFERED;Bytes evidence,acceptance,observation;std::shared_ptr<std::vector<uint8_t>>ack_buffer;std::vector<Bytes>facts;uint64_t count=0,terminal_count=0,entry=0,session=0,source_owner=0,operation=0,observation_operation=0,observation_first=0;};
 std::vector<Transfer>transfers_;uint64_t transfer_claims_reserved_=0;
 Transfer*find_transfer(const TransferIdentity&);const Transfer*find_transfer(const TransferIdentity&)const;
 TransferRead transfer_read(const Transfer&,Status=Status::READY)const;
 void maybe_retire(Transfer&);void collect_delivered();
 std::vector<Bytes> transfer_evidence(const Identity&)const;
 Slot*find(const Identity&);const Slot*find(const Identity&)const;
 Lifetime*find_lifetime(const Identity&);const Lifetime*find_lifetime(const Identity&)const;
 static bool same(const Bytes&,const Bytes&);
};
}
