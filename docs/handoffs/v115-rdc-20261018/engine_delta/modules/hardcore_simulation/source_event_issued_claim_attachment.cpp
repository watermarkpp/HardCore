#include "source_event_reply_mailbox.h"
#include <algorithm>
namespace hardcore::simulation {
SourceEventReplyMailbox::Transfer*SourceEventReplyMailbox::find_transfer(const TransferIdentity&id){for(auto&r:transfers_)if(r.used&&r.id==id)return &r;return nullptr;}
const SourceEventReplyMailbox::Transfer*SourceEventReplyMailbox::find_transfer(const TransferIdentity&id)const{for(const auto&r:transfers_)if(r.used&&r.id==id)return &r;return nullptr;}
SourceEventReplyMailbox::TransferRead SourceEventReplyMailbox::transfer_read(const Transfer&r,Status status)const{
 TransferRead out;out.status=status;out.identity=r.id;out.state=r.state;out.evidence=r.evidence;out.acceptance=r.acceptance;out.observation=r.observation;out.facts=r.facts;out.count=r.count;out.terminal_count=r.terminal_count;out.entry=r.entry;out.session=r.session;out.source_owner=r.source_owner;out.observation_operation=r.observation_operation;out.observation_first=r.observation_first;out.in_flight=r.in_flight;out.queue_removed=r.queue_removed;out.fault=r.fault;return out;
}
std::vector<SourceEventReplyMailbox::Bytes> SourceEventReplyMailbox::transfer_evidence(const Identity&id)const{std::vector<Bytes>out;for(const auto&r:transfers_)if(r.used&&r.id.parent==id)out.push_back(r.evidence);return out;}
void SourceEventReplyMailbox::maybe_retire(Transfer&r){if(r.state==TransferState::ORIGIN_RELEASED&&r.terminal_count==r.count&&r.queue_removed&&!r.in_flight&&!r.fault)r.state=TransferState::TERMINAL;}
void SourceEventReplyMailbox::collect_delivered(){for(auto&r:transfers_)if(r.used&&r.delivered&&!find(r.id.parent)&&!find_lifetime(r.id.parent)){transfer_claims_reserved_-=r.count;r={};}}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::offer_transfer(const TransferIdentity&id,const Bytes&e,uint64_t count){
 if(std::this_thread::get_id()!=main_||id.parent.generation!=generation_||!id.parent.journal||!id.parent.ordinal||!id.transfer||!count||!e||e->empty()||e->size()>reply_capacity_)return Status::INVALID;
 std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;
 if(auto*r=find_transfer(id))return r->count==count&&same(r->evidence,e)?Status::READY:Status::INVALID;
 auto*parent=find(id.parent);if(!parent||!parent->accepted||!parent->claimed||parent->submitted)return Status::INVALID;
 collect_delivered();if(count>transfers_.size()-transfer_claims_reserved_)return Status::BACKPRESSURE;
 for(auto&r:transfers_)if(!r.used){
  // Reserve complete association and ACK capacity before exposing OFFERED.
  // A bad_alloc occurs before any state/counter mutation and cannot adopt work.
  auto buffer=std::make_shared<std::vector<uint8_t>>();buffer->reserve(reply_capacity_);std::vector<Bytes>facts;facts.reserve(static_cast<size_t>(count));
  r={};r.id=id;r.evidence=e;r.count=count;r.ack_buffer=std::move(buffer);r.facts=std::move(facts);r.used=true;transfer_claims_reserved_+=count;return Status::READY;
 }return Status::BACKPRESSURE;
}
SourceEventReplyMailbox::TransferRead SourceEventReplyMailbox::inspect_transfer(const TransferIdentity&id)const{
 if(std::this_thread::get_id()!=main_&&std::this_thread::get_id()!=owner_)return {Status::INVALID};
 std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {};auto*r=find_transfer(id);return r?transfer_read(*r):TransferRead{Status::INVALID};
}
SourceEventReplyMailbox::TransferRead SourceEventReplyMailbox::begin_transfer_accept(const TransferIdentity&id){
 if(std::this_thread::get_id()!=owner_)return {Status::INVALID};std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {};
 auto*r=find_transfer(id);if(!r)return {Status::INVALID};if(r->state!=TransferState::OFFERED)return transfer_read(*r);if(r->accepting)return transfer_read(*r,Status::PENDING);
 r->accepting=true;auto out=transfer_read(*r);out.admit=!r->attempted;r->attempted=true;return out;
}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::finish_transfer_accept(const TransferIdentity&id,const ClaimQueue&q,const Bytes&ack){
 if(std::this_thread::get_id()!=owner_)return Status::INVALID;std::lock_guard<std::mutex>lock(mutex_);auto*r=find_transfer(id);if(!r||!r->accepting||r->state!=TransferState::OFFERED)return Status::INVALID;
 r->accepting=false;
 if(q.insertion==Insertion::NONE){r->attempted=false;r->fault=false;return Status::PENDING;}
 if(q.insertion!=Insertion::EXACT||q.count!=r->count||q.remaining!=r->count||q.location<0||!q.session||!q.owner||!ack||ack->empty()||ack->size()>reply_capacity_){r->fault=true;return Status::INVALID;}
 // Recovering insertion-before-ACK never repeats the original admission.
 r->ack_buffer->assign(ack->begin(),ack->end());r->acceptance=r->ack_buffer;r->entry=q.entry;r->session=q.session;r->source_owner=q.owner;r->state=TransferState::ACCEPTED;r->fault=false;return Status::READY;
}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::observe_transfer_queue(const TransferIdentity&id,const ClaimQueue&q){
 if(std::this_thread::get_id()!=owner_)return Status::INVALID;std::lock_guard<std::mutex>lock(mutex_);auto*r=find_transfer(id);if(!r||r->state==TransferState::OFFERED||q.entry!=r->entry||q.count!=r->count||q.session!=r->session||q.owner!=r->source_owner||q.remaining!=r->count-r->terminal_count)return Status::INVALID;
 if(q.insertion==Insertion::REMOVED){if(q.location!=-1||q.remaining)return Status::INVALID;r->queue_removed=true;}else if(q.insertion==Insertion::EXACT){if(q.location<0||!q.remaining||r->queue_removed)return Status::INVALID;}else return Status::INVALID;
 maybe_retire(*r);return Status::READY;
}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::release_transfer_origin(const TransferIdentity&id){
 if(std::this_thread::get_id()!=main_)return Status::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;auto*r=find_transfer(id);if(!r||r->state==TransferState::OFFERED)return Status::INVALID;
 if(r->state==TransferState::ACCEPTED)r->state=TransferState::ORIGIN_RELEASED;maybe_retire(*r);return Status::READY;
}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::begin_transfer_leaf(const TransferIdentity&id,uint64_t entry,uint64_t first,uint64_t remaining,uint64_t operation,uint64_t session,uint64_t owner){
 if(std::this_thread::get_id()!=owner_||!operation)return Status::INVALID;std::lock_guard<std::mutex>lock(mutex_);auto*r=find_transfer(id);
 if(!r||r->state==TransferState::OFFERED||r->state==TransferState::TERMINAL||r->entry!=entry||r->terminal_count!=first||!remaining||remaining!=r->count-first||session!=r->session||owner!=r->source_owner||r->in_flight||r->queue_removed||r->fault||operation<=r->operation)return Status::INVALID;
 r->operation=operation;r->in_flight=true;return Status::READY;
}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::begin_live_transfer_leaf(const TransferIdentity&id,uint64_t entry,uint64_t first,uint64_t remaining,uint64_t operation,uint64_t session,uint64_t owner){
 if(std::this_thread::get_id()!=main_||!operation)return Status::INVALID;
 std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;
 auto*r=find_transfer(id);
 if(!r||r->state==TransferState::OFFERED||r->state==TransferState::TERMINAL||r->entry!=entry||r->terminal_count!=first||!remaining||remaining!=r->count-first||session!=r->session||owner!=r->source_owner||r->in_flight||r->queue_removed||r->fault||operation<=r->operation)return Status::INVALID;
 r->operation=operation;r->in_flight=true;return Status::READY;
}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::finish_transfer_leaf(const TransferIdentity&id,uint64_t operation,uint64_t first,uint64_t count,const Bytes&fact){
 if(std::this_thread::get_id()!=main_)return Status::INVALID;std::lock_guard<std::mutex>lock(mutex_);auto*r=find_transfer(id);
 if(!r||!r->in_flight||r->operation!=operation||r->terminal_count!=first||count>r->count-first||(count&&(!fact||fact->empty()||fact->size()>reply_capacity_))||(!count&&fact))return Status::INVALID;
 if(count){r->facts.push_back(fact);r->terminal_count+=count;}r->in_flight=false;maybe_retire(*r);return Status::READY;
}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::ack_transfer_delivery(const TransferIdentity&id){
 if(std::this_thread::get_id()!=main_)return Status::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;auto*r=find_transfer(id);if(!r||r->state!=TransferState::TERMINAL)return Status::INVALID;r->delivered=true;collect_delivered();return Status::READY;
}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::remember_transfer_observation(const TransferIdentity&id,uint64_t operation,const Bytes&actual){
 if(std::this_thread::get_id()!=main_||!actual||actual->empty()||actual->size()>reply_capacity_)return Status::INVALID;std::lock_guard<std::mutex>lock(mutex_);auto*r=find_transfer(id);if(!r||!r->in_flight||r->operation!=operation)return Status::INVALID;r->observation=actual;r->observation_operation=operation;r->observation_first=r->terminal_count;return Status::READY;
}
std::vector<SourceEventReplyMailbox::TransferRead> SourceEventReplyMailbox::inspect_main_transfers()const{
 if(std::this_thread::get_id()!=main_)return {};std::lock_guard<std::mutex>lock(mutex_);std::vector<TransferRead>out;for(const auto&r:transfers_)if(r.used)out.push_back(transfer_read(r));return out;
}
}
