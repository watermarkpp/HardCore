#include "source_event_reply_mailbox.h"
#include <algorithm>
namespace hardcore::simulation {
SourceEventReplyMailbox::SourceEventReplyMailbox(uint64_t g,size_t n,size_t e,size_t r):generation_(g),normal_slots_(n),event_capacity_(e),reply_capacity_(r),main_(std::this_thread::get_id()),slots_(n*3),lifetimes_(n),transfers_(n*3){}
bool SourceEventReplyMailbox::same(const Bytes&a,const Bytes&b){return a&&b&&*a==*b;}
SourceEventReplyMailbox::Slot*SourceEventReplyMailbox::find(const Identity&id){for(auto&s:slots_)if(s.used&&s.id==id)return &s;return nullptr;}
const SourceEventReplyMailbox::Slot*SourceEventReplyMailbox::find(const Identity&id)const{for(const auto&s:slots_)if(s.used&&s.id==id)return &s;return nullptr;}
SourceEventReplyMailbox::Lifetime*SourceEventReplyMailbox::find_lifetime(const Identity&id){for(auto&s:lifetimes_)if(s.used&&s.id==id)return &s;return nullptr;}
const SourceEventReplyMailbox::Lifetime*SourceEventReplyMailbox::find_lifetime(const Identity&id)const{for(const auto&s:lifetimes_)if(s.used&&s.id==id)return &s;return nullptr;}
bool SourceEventReplyMailbox::bind_owner(){std::lock_guard<std::mutex>lock(mutex_);if(std::this_thread::get_id()==main_||owner_!=std::thread::id{})return false;owner_=std::this_thread::get_id();return true;}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::reserve(const Identity&id,const Bytes&e,bool cleanup){
 if(std::this_thread::get_id()!=owner_||id.generation!=generation_||!id.journal||!id.ordinal||!e||e->empty()||e->size()>event_capacity_)return Status::INVALID;
 std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;
 if(auto*s=find(id))return same(s->event,e)?Status::READY:Status::INVALID;
 if((closing_.load(std::memory_order_acquire)&&!cleanup)||(journal_&&journal_!=id.journal)||id.ordinal<=accepted_high_water_)return Status::INVALID;
 const size_t first=cleanup?normal_slots_:0,last=cleanup?slots_.size():normal_slots_;for(size_t i=first;i<last;++i){auto&s=slots_[i];if(!s.used){auto buffer=std::make_shared<std::vector<uint8_t>>();buffer->reserve(reply_capacity_);s={};s.buffer=std::move(buffer);s.event=e;s.id=id;s.used=true;return Status::READY;}}
 return Status::BACKPRESSURE;
}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::accept(const Identity&id,const Bytes&e,const Bytes&p){if(std::this_thread::get_id()!=owner_||!p)return Status::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;auto*s=find(id);if(!s||!same(s->event,e)||(journal_&&journal_!=id.journal))return Status::INVALID;if(s->accepted)return same(s->prefix,p)?Status::READY:Status::INVALID;s->prefix=p;s->accepted=true;journal_=id.journal;accepted_high_water_=std::max(accepted_high_water_,id.ordinal);return Status::READY;}
bool SourceEventReplyMailbox::cancel_unaccepted(const Identity&id){if(std::this_thread::get_id()!=owner_)return false;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return false;auto*s=find(id);if(!s||s->accepted||s->claimed)return false;*s={};return true;}
SourceEventReplyMailbox::Read SourceEventReplyMailbox::acquire_prefix()const{if(std::this_thread::get_id()!=main_)return {Status::INVALID,{},{},{},{},0,false,false};std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {};const Slot*next=nullptr;for(const auto&s:slots_)if(s.used&&s.accepted&&!s.claimed&&(!next||s.id.ordinal<next->id.ordinal))next=&s;return next?Read{Status::READY,next->id,next->event,next->prefix,{},0,false,false}:Read{};}
SourceEventReplyMailbox::Read SourceEventReplyMailbox::inspect_main(const Identity&id)const{if(std::this_thread::get_id()!=main_)return {Status::INVALID,{},{},{},{},0,false,false};std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {};auto*s=find(id);if(!s){auto*l=find_lifetime(id);return l?Read{Status::READY,l->id,l->event,l->prefix,l->reply,l->node,true,l->retired}:Read{Status::INVALID,{},{},{},{},0,false,false};}if(!s->accepted)return {};return {Status::READY,s->id,s->event,s->prefix,s->submitted?Bytes(s->buffer):Bytes{},s->node,s->consumed,s->retired};}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::claim(const Identity&id,const Bytes&e){if(std::this_thread::get_id()!=main_)return Status::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;auto*s=find(id);if(!s)return Status::INVALID;if(!s->accepted)return Status::PENDING;if(s->claimed||!same(s->event,e))return Status::INVALID;s->claimed=true;return Status::READY;}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::submit(const Identity&id,const Bytes&r,uint64_t node){if(std::this_thread::get_id()!=main_||!r||r->empty()||r->size()>reply_capacity_)return Status::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;auto*s=find(id);if(!s||!s->claimed)return Status::INVALID;if(s->submitted)return s->node==node&&*s->buffer==*r?Status::READY:Status::INVALID;s->buffer->assign(r->begin(),r->end());s->reply_size=r->size();s->node=node;s->submitted=true;s->retired=node==0;return Status::READY;}
SourceEventReplyMailbox::Read SourceEventReplyMailbox::poll(const Identity&id)const{
 if(std::this_thread::get_id()!=owner_)return {Status::INVALID};
 std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {};
 Read out;out.identity=id;out.claim_transfers=transfer_evidence(id);auto*s=find(id);
 if(s){out.event=s->event;out.prefix=s->prefix;if(!s->submitted)return out;out.status=Status::READY;out.reply=s->buffer;out.node=s->node;out.consumed=s->consumed;out.retired=s->retired;out.received_usec=s->received_usec;out.s_poll_epoch=s->s_poll_epoch;return out;}
 auto*l=find_lifetime(id);if(!l){out.status=Status::INVALID;return out;}out.status=Status::READY;out.event=l->event;out.prefix=l->prefix;out.reply=l->reply;out.node=l->node;out.consumed=true;out.retired=l->retired;out.received_usec=l->received_usec;out.s_poll_epoch=l->s_poll_epoch;return out;
}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::consume(const Identity&id){if(std::this_thread::get_id()!=owner_)return Status::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;auto*s=find(id);if(!s)return find_lifetime(id)?Status::READY:Status::INVALID;if(!s->submitted)return Status::INVALID;s->consumed=true;return Status::READY;}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::acknowledge_retired(const Identity&id,uint64_t node){if(std::this_thread::get_id()!=main_)return Status::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;auto*s=find(id);if(!s){auto*l=find_lifetime(id);if(!l||l->node!=node)return Status::INVALID;l->retired=true;return Status::READY;}if(!s->submitted||s->node!=node)return Status::INVALID;s->retired=true;return Status::READY;}
SourceEventReplyMailbox::Status SourceEventReplyMailbox::retire(const Identity&id){if(std::this_thread::get_id()!=owner_)return Status::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;auto*s=find(id);if(!s){auto*l=find_lifetime(id);if(!l)return Status::INVALID;if(!l->retired)return Status::PENDING;*l={};collect_delivered();return Status::READY;}if(!s->consumed)return Status::PENDING;if(!s->retired){for(auto&l:lifetimes_)if(!l.used){l={true,false,s->id,s->event,s->prefix,s->buffer,s->node,s->observed,s->received_usec,s->s_poll_epoch};*s={};collect_delivered();return Status::READY;}return Status::PENDING;}*s={};collect_delivered();return Status::READY;}
void SourceEventReplyMailbox::request_close(){closing_.store(true,std::memory_order_release);}
bool SourceEventReplyMailbox::can_close()const{std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return false;for(const auto&s:slots_)if(s.used)return false;for(const auto&l:lifetimes_)if(l.used)return false;for(const auto&r:transfers_)if(r.used)return false;return true;}
}

namespace hardcore::simulation {
SourceEventReplyMailbox::Read SourceEventReplyMailbox::poll_with_observation(const Identity&id,uint64_t now,uint64_t epoch){
 if(std::this_thread::get_id()!=owner_||!now)return {Status::INVALID};
 std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {};
 Read out;out.identity=id;out.claim_transfers=transfer_evidence(id);auto*s=find(id);
 if(s){out.event=s->event;out.prefix=s->prefix;if(!s->submitted)return out;if(!s->observed){s->observed=true;s->received_usec=now;s->s_poll_epoch=epoch;}
  out.status=Status::READY;out.reply=s->buffer;out.node=s->node;out.consumed=s->consumed;out.retired=s->retired;out.received_usec=s->received_usec;out.s_poll_epoch=s->s_poll_epoch;return out;}
 auto*l=find_lifetime(id);if(!l){out.status=Status::INVALID;return out;}if(!l->observed){l->observed=true;l->received_usec=now;l->s_poll_epoch=epoch;}
 out.status=Status::READY;out.event=l->event;out.prefix=l->prefix;out.reply=l->reply;out.node=l->node;out.consumed=true;out.retired=l->retired;out.received_usec=l->received_usec;out.s_poll_epoch=l->s_poll_epoch;return out;
}
}
