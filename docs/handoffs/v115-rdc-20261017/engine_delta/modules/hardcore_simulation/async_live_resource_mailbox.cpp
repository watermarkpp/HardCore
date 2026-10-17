#include "async_live_resource_mailbox.h"
#include <algorithm>
#include <tuple>
#include <cstdlib>
namespace hardcore::simulation {
AsyncLiveResourceMailbox::AsyncLiveResourceMailbox(Original&o,uint64_t g,size_t n,size_t req,size_t res):original_(o),generation_(g),request_bytes_(req),reply_bytes_(res),main_(std::this_thread::get_id()),slots_(n){for(auto&s:slots_)s.return_slot=std::make_shared<std::vector<uint8_t>>(reply_bytes_);}
AsyncLiveResourceMailbox::~AsyncLiveResourceMailbox(){for(const auto&s:slots_)if(s.state!=State::FREE)std::abort();}
bool AsyncLiveResourceMailbox::equal(const Bytes&a,const Bytes&b){return a&&b&&*a==*b;}
bool AsyncLiveResourceMailbox::equal(const Request&a,const Request&b){
  if(!(a.original.identity==b.original.identity)||!equal(a.original.bytes,b.original.bytes)||!equal(a.original.source_site_bytes,b.original.source_site_bytes)||!equal(a.original.prefix.bytes,b.original.prefix.bytes)||!equal(a.order_key,b.order_key)||a.priority!=b.priority||a.cleanup!=b.cleanup||a.original.predecessor!=b.original.predecessor||a.original.call_ordinal!=b.original.call_ordinal||a.original.deadline_usec!=b.original.deadline_usec||a.original.submitted_usec!=b.original.submitted_usec||a.reservation.id!=b.reservation.id||a.reservation.owner_session!=b.reservation.owner_session||a.reservation.ledger_epoch!=b.reservation.ledger_epoch||a.reservation.lane!=b.reservation.lane||a.reservation.reserved_usec!=b.reservation.reserved_usec||a.reservation.issued_usec!=b.reservation.issued_usec||!equal(a.reservation.category,b.reservation.category)||a.dependencies.size()!=b.dependencies.size())return false;
  const auto&x=a.original.prefix;const auto&y=b.original.prefix;if(x.generation!=y.generation||x.journal_generation!=y.journal_generation||x.through!=y.through||x.events.size()!=y.events.size())return false;for(size_t n=0;n<x.events.size();++n)if(x.events[n].ordinal!=y.events[n].ordinal||!equal(x.events[n].bytes,y.events[n].bytes))return false;
  if((a.pre_admission_bytes||b.pre_admission_bytes)&&!equal(a.pre_admission_bytes,b.pre_admission_bytes))return false;
  if((a.issued_claim_context||b.issued_claim_context)&&!equal(a.issued_claim_context,b.issued_claim_context))return false;
  for(size_t n=0;n<a.dependencies.size();++n)if(!(a.dependencies[n].identity==b.dependencies[n].identity)||a.dependencies[n].after!=b.dependencies[n].after)return false;return true;
}
bool AsyncLiveResourceMailbox::equal(const Reply&a,const Reply&b){return a.original.identity==b.original.identity&&a.original.started_usec==b.original.started_usec&&a.original.finished_usec==b.original.finished_usec&&a.main_cpu_usec==b.main_cpu_usec&&equal(a.original.request_bytes,b.original.request_bytes)&&equal(a.original.bytes,b.original.bytes)&&equal(a.actual_lease_obligations,b.actual_lease_obligations);}
bool AsyncLiveResourceMailbox::equal(const Settlement&a,const Settlement&b){return a.reservation_id==b.reservation_id&&a.owner_session_id==b.owner_session_id&&a.identity==b.identity&&a.s_commit_epoch==b.s_commit_epoch&&a.started_usec==b.started_usec&&a.finished_usec==b.finished_usec&&a.charged_usec==b.charged_usec&&a.received_usec==b.received_usec&&a.queue_wait_usec==b.queue_wait_usec&&a.overrun_usec==b.overrun_usec;}
AsyncLiveResourceMailbox::Slot* AsyncLiveResourceMailbox::find(const Identity&id){for(auto&s:slots_)if(s.state!=State::FREE&&s.request.original.identity==id)return &s;return nullptr;}
const AsyncLiveResourceMailbox::Slot* AsyncLiveResourceMailbox::find(const Identity&id)const{for(const auto&s:slots_)if(s.state!=State::FREE&&s.request.original.identity==id)return &s;return nullptr;}
bool AsyncLiveResourceMailbox::bind_owner(){std::lock_guard<std::mutex>lock(mutex_);if(std::this_thread::get_id()==main_||owner_!=std::thread::id{})return false;owner_=std::this_thread::get_id();return true;}
AsyncLiveResourceMailbox::Probe AsyncLiveResourceMailbox::probe_submission(uint64_t session,uint64_t reservation,const Bytes&wire){if(std::this_thread::get_id()!=owner_)return {Admission::INVALID,{}};std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {Admission::BUSY,{}};for(const auto&s:slots_)if(s.state!=State::FREE&&s.request.reservation.owner_session==session&&s.request.reservation.id==reservation)return {equal(wire,s.request.pre_admission_bytes)?Admission::DUPLICATE:Admission::INVALID,s.request};return {};}
AsyncLiveResourceMailbox::Admission AsyncLiveResourceMailbox::submit(const Request&r){
  if(std::this_thread::get_id()!=owner_)return Admission::INVALID;
  std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Admission::BUSY;
  if(auto*prior=find(r.original.identity))return equal(prior->request,r)?Admission::DUPLICATE:Admission::INVALID;
  if(r.original.identity.generation!=generation_||!r.original.identity.sequence||!r.original.bytes||r.original.bytes->size()>request_bytes_||!r.order_key||r.order_key->empty()||r.order_key->size()>request_bytes_||r.priority<0||r.priority>2||r.reservation.id==0||r.reservation.owner_session==0||r.reservation.lane>2||!r.reservation.category||r.reservation.category->empty()||r.reservation.category->size()>request_bytes_||(r.pre_admission_bytes&&r.pre_admission_bytes->size()>request_bytes_)||(r.issued_claim_context&&r.issued_claim_context->size()>request_bytes_)||r.dependencies.size()>slots_.size()+1||r.reservation.issued_usec>r.original.submitted_usec||(closing_&&!r.cleanup))return Admission::INVALID;
  for(const auto&s:slots_)if(s.state!=State::FREE&&s.request.reservation.id==r.reservation.id&&s.request.reservation.owner_session==r.reservation.owner_session)return Admission::INVALID;
  if(r.original.channel!=Original::Channel::RESOURCE)return Admission::INVALID;
  for(const auto&d:r.dependencies)if(d.identity.generation!=generation_||!d.identity.sequence||d.identity.sequence>=r.original.identity.sequence||static_cast<unsigned>(d.after)>static_cast<unsigned>(After::RETIRED))return Admission::INVALID;
  Slot*free=nullptr;for(auto&s:slots_)if(s.state==State::FREE){free=&s;break;}if(!free)return Admission::BACKPRESSURE;
  auto result=original_.admit_async(r.original);if(result==Original::AsyncAdmission::BUSY)return Admission::BUSY;if(result==Original::AsyncAdmission::BACKPRESSURE)return Admission::BACKPRESSURE;if(result!=Original::AsyncAdmission::ACCEPTED)return Admission::INVALID;
  free->request=r;free->state=State::QUEUED;free->prefix_applied=false;free->lease_retired=false;return Admission::ACCEPTED;
}
bool AsyncLiveResourceMailbox::eligible(const Slot&s)const{
  for(const auto&other:slots_)if(other.state!=State::FREE&&other.request.original.identity.sequence<s.request.original.identity.sequence&&equal(other.request.order_key,s.request.order_key)&&other.state!=State::SETTLED)return false;
  for(const auto&d:s.request.dependencies){const auto*prior=find(d.identity);auto state=original_.read_operation_state_try(d.identity);if(!state.available)return false;switch(d.after){case After::MAIN_EXECUTED:if(prior&&(prior->state<State::READY))return false;if(!prior&&!state.completed)return false;break;case After::S_COMMITTED:if(!state.completed)return false;break;case After::RETIRED:if(!state.retired)return false;break;}}
  return true;
}
AsyncLiveResourceMailbox::Pending AsyncLiveResourceMailbox::acquire(uint64_t acquired){
  if(std::this_thread::get_id()!=main_)return {};std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {};
  Slot*best=nullptr;for(auto&s:slots_)if(s.state==State::QUEUED&&eligible(s)){if(!best||s.request.priority>best->request.priority||(s.request.priority==best->request.priority&&std::tie(s.request.original.deadline_usec,s.request.original.identity.sequence)<std::tie(best->request.original.deadline_usec,best->request.original.identity.sequence)))best=&s;}
  if(!best||acquired<best->request.original.submitted_usec)return {};best->state=State::ACQUIRED;best->acquired_usec=acquired;return {best->request,true,acquired};
}
AsyncLiveResourceMailbox::Pending AsyncLiveResourceMailbox::lookup(const Identity&id)const{std::lock_guard<std::mutex>lock(mutex_);const auto*s=find(id);return s?Pending{s->request,true,s->acquired_usec}:Pending{};}
bool AsyncLiveResourceMailbox::acknowledge_prefix(const Identity&id,const Original::Prefix&p){
  if(std::this_thread::get_id()!=main_)return false;std::lock_guard<std::mutex>lock(mutex_);auto*s=find(id);if(!s||s->state<State::ACQUIRED||p.generation!=s->request.original.prefix.generation||p.journal_generation!=s->request.original.prefix.journal_generation||p.through!=s->request.original.prefix.through||!equal(p.bytes,s->request.original.prefix.bytes))return false;
  if(!original_.ack_async_prefix(s->request.original))return false;s->prefix_applied=true;return true;
}
bool AsyncLiveResourceMailbox::claim_execution(const Identity&id){if(std::this_thread::get_id()!=main_)return false;std::lock_guard<std::mutex>lock(mutex_);auto*s=find(id);if(!s||s->state!=State::ACQUIRED||!s->prefix_applied)return false;s->state=State::EXECUTING;return true;}
bool AsyncLiveResourceMailbox::submit_result(const Reply&r){
  if(std::this_thread::get_id()!=main_)return false;std::lock_guard<std::mutex>lock(mutex_);auto*s=find(r.original.identity);if(!s||!r.original.bytes||r.original.bytes->size()>reply_bytes_||!r.actual_lease_obligations||r.actual_lease_obligations->size()>reply_bytes_)return false;
  if(s->state>=State::READY)return equal(s->reply,r);
  if(s->state!=State::EXECUTING||!equal(r.original.request_bytes,s->request.original.bytes)||r.original.started_usec<s->acquired_usec||r.original.finished_usec<r.original.started_usec)return false;
  s->return_slot->resize(r.original.bytes->size());std::copy(r.original.bytes->begin(),r.original.bytes->end(),s->return_slot->begin());s->reply=r;s->reply.original.bytes=s->return_slot;s->lease_retired=r.actual_lease_obligations->empty();s->state=State::READY;return true;
}
AsyncLiveResourceMailbox::Completion AsyncLiveResourceMailbox::poll(const Identity&id,uint64_t received,uint64_t epoch){
  if(std::this_thread::get_id()!=owner_)return {};std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {};auto*s=find(id);if(!s||s->state<State::READY)return {};if(s->state>=State::POLLED)return s->completion;
  if(received<s->reply.original.finished_usec)return {};s->completion={s->request,s->reply,true,s->reply.original.finished_usec>s->request.original.deadline_usec||received>s->request.original.deadline_usec,received,epoch,s->reply.original.started_usec-s->request.original.submitted_usec,s->reply.original.finished_usec-s->reply.original.started_usec,s->reply.main_cpu_usec,s->acquired_usec,s->acquired_usec-s->request.original.submitted_usec,s->reply.original.started_usec-s->acquired_usec};s->state=State::POLLED;return s->completion;
}
bool AsyncLiveResourceMailbox::settle(const Settlement&v){return settle_status(v)==SettlementStatus::SETTLED;}
AsyncLiveResourceMailbox::SettlementStatus AsyncLiveResourceMailbox::settle_status(const Settlement&v){
  if(std::this_thread::get_id()!=owner_)return SettlementStatus::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return SettlementStatus::PENDING;auto*s=find(v.identity);if(!s){for(const auto&old:recent_settlements_)if(old.identity==v.identity)return equal(old,v)?SettlementStatus::SETTLED:SettlementStatus::INVALID;return SettlementStatus::INVALID;}if(s->state==State::SETTLED)return equal(s->committed_settlement,v)?SettlementStatus::SETTLED:SettlementStatus::INVALID;if(s->state!=State::POLLED)return SettlementStatus::INVALID;
  const auto&c=s->completion;const auto&r=s->request.reservation;
  if(v.reservation_id!=r.id||v.owner_session_id!=r.owner_session||v.s_commit_epoch<c.s_poll_epoch||v.started_usec!=c.reply.original.started_usec||v.finished_usec!=c.reply.original.finished_usec||v.charged_usec!=c.charged_usec||v.received_usec!=c.receipt_received_usec||v.queue_wait_usec!=c.queue_wait_usec||v.overrun_usec!=(c.charged_usec>r.reserved_usec?c.charged_usec-r.reserved_usec:0))return SettlementStatus::INVALID;
  auto committed=original_.commit_async_status(v.identity);if(committed==Original::AsyncCommit::BUSY)return SettlementStatus::PENDING;if(committed!=Original::AsyncCommit::COMMITTED)return SettlementStatus::INVALID;s->committed_settlement=v;s->state=State::SETTLED;return SettlementStatus::SETTLED;
}
bool AsyncLiveResourceMailbox::acknowledge_actual_lease_retirement(const Identity&id,const Bytes&witness){if(std::this_thread::get_id()!=main_)return false;std::lock_guard<std::mutex>lock(mutex_);auto*s=find(id);if(!s||s->state<State::READY||!equal(s->reply.actual_lease_obligations,witness))return false;s->lease_retired=true;return true;}
AsyncLiveResourceMailbox::TransferStatus AsyncLiveResourceMailbox::acknowledge_actual_lease_transfer_status(const Identity&id,const Bytes&witness){if(std::this_thread::get_id()!=main_)return TransferStatus::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return TransferStatus::PENDING;auto*s=find(id);if(!s||s->state<State::READY||!witness||witness->empty()||!equal(s->reply.actual_lease_obligations,witness))return TransferStatus::INVALID;s->lease_transferred=true;return TransferStatus::TRANSFERRED;}
bool AsyncLiveResourceMailbox::acknowledge_actual_lease_transfer(const Identity&id,const Bytes&witness){return acknowledge_actual_lease_transfer_status(id,witness)==TransferStatus::TRANSFERRED;}
bool AsyncLiveResourceMailbox::transport_releasable(const Identity&id)const{if(std::this_thread::get_id()!=owner_)return false;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return false;auto*s=find(id);return s&&s->state==State::SETTLED&&(s->lease_retired||s->lease_transferred);}
bool AsyncLiveResourceMailbox::retire(const Identity&id){if(std::this_thread::get_id()!=owner_)return false;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return false;auto*s=find(id);if(!s||s->state!=State::SETTLED||(!s->lease_retired&&!s->lease_transferred)||!original_.retire_async(id))return false;recent_settlements_.push_back(s->committed_settlement);if(recent_settlements_.size()>slots_.size())recent_settlements_.pop_front();auto buffer=s->return_slot;*s=Slot{};if(buffer.use_count()!=1)buffer=std::make_shared<std::vector<uint8_t>>(reply_bytes_);s->return_slot=std::move(buffer);return true;}
void AsyncLiveResourceMailbox::request_close(){std::lock_guard<std::mutex>lock(mutex_);closing_=true;}
bool AsyncLiveResourceMailbox::can_close()const{std::lock_guard<std::mutex>lock(mutex_);if(!closing_)return false;for(const auto&s:slots_)if(s.state!=State::FREE)return false;return true;}
size_t AsyncLiveResourceMailbox::accepted_count()const{std::lock_guard<std::mutex>lock(mutex_);size_t n=0;for(const auto&s:slots_)if(s.state!=State::FREE)++n;return n;}
}
