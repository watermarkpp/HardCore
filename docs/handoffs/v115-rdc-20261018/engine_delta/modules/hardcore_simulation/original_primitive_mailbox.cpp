#include "original_primitive_mailbox.h"
#include <algorithm>

namespace hardcore::simulation {
OriginalPrimitiveMailbox::OriginalPrimitiveMailbox(uint64_t generation,size_t request_capacity,size_t result_capacity,size_t prefix_capacity):generation_(generation),request_capacity_(request_capacity),result_capacity_(result_capacity),prefix_capacity_(prefix_capacity),main_(std::this_thread::get_id()){
    reserved_return_slot_=std::make_shared<std::vector<uint8_t>>(result_capacity_);
}
bool OriginalPrimitiveMailbox::equal(const Bytes&a,const Bytes&b){return a&&b&&*a==*b;}
bool OriginalPrimitiveMailbox::equal(const Prefix&a,const Prefix&b){if(a.generation!=b.generation||a.journal_generation!=b.journal_generation||a.through!=b.through||!equal(a.bytes,b.bytes)||a.events.size()!=b.events.size())return false;for(size_t n=0;n<a.events.size();++n)if(a.events[n].ordinal!=b.events[n].ordinal||!equal(a.events[n].bytes,b.events[n].bytes))return false;return true;}
bool OriginalPrimitiveMailbox::equal(const Reply&a,const Reply&b){return a.identity==b.identity&&a.started_usec==b.started_usec&&a.finished_usec==b.finished_usec&&equal(a.request_bytes,b.request_bytes)&&equal(a.bytes,b.bytes);}
bool OriginalPrimitiveMailbox::register_events(const Prefix&p,bool commit){
    // prefix_capacity_ bounds outstanding packets/tickets, not the number of
    // original display events inside one valid packet. A single real P batch
    // already contains 35 events (37440 bytes) with a 32-packet production FIFO.
    if(p.generation!=generation_||p.journal_generation==0||(journal_generation_&&p.journal_generation!=journal_generation_)||!p.bytes||p.bytes->size()>request_capacity_)return false;
    uint64_t prior=applied_prefix_;size_t added_bytes=0;
    for(const auto&e:p.events){
        if(!e.bytes||e.bytes->empty()||e.bytes->size()>request_capacity_||e.ordinal!=prior+1)return false;
        auto old=known_events_.find(e.ordinal);
        if(old!=known_events_.end()){if(!equal(old->second,e.bytes))return false;}
        else{
            if(known_event_bytes_>request_capacity_||added_bytes>request_capacity_-known_event_bytes_||e.bytes->size()>request_capacity_-known_event_bytes_-added_bytes)return false;
            added_bytes+=e.bytes->size();
        }
        prior=e.ordinal;
    }
    if(prior!=p.through)return false;
    if(!commit)return true;
    // Admission is atomic: invalid ordinals/bytes never partially consume the
    // journal budget. Only the original S ACK/continuation path releases it.
    for(const auto&e:p.events)known_events_[e.ordinal]=e.bytes;
    known_event_bytes_+=added_bytes;
    journal_generation_=p.journal_generation;return true;
}
void OriginalPrimitiveMailbox::prune_events(){for(auto i=known_events_.begin();i!=known_events_.end()&&i->first<=applied_prefix_;){known_event_bytes_-=i->second->size();i=known_events_.erase(i);}}
bool OriginalPrimitiveMailbox::bind_owner(){std::lock_guard<std::mutex> lock(mutex_);if(std::this_thread::get_id()==main_||owner_!=std::thread::id{})return false;owner_=std::this_thread::get_id();return true;}
bool OriginalPrimitiveMailbox::stage_prefix(const Prefix&p){
    std::lock_guard<std::mutex> lock(mutex_);
    if(std::this_thread::get_id()!=owner_||active_valid_||quiescent_||p.generation!=generation_||p.journal_generation==0||p.through<applied_prefix_||!p.bytes||p.bytes->size()>request_capacity_)return false;
    if(!register_events(p))return false;
    // Allocate only while no accepted continuation exists. The last result may
    // still be retained by its S consumer or duplicate-reply cache.
    if(!reserved_return_slot_)reserved_return_slot_=std::make_shared<std::vector<uint8_t>>(result_capacity_);
    journal_generation_=p.journal_generation;staged_=p;return true;
}
bool OriginalPrimitiveMailbox::register_published_prefix(const Prefix&p){
    std::lock_guard<std::mutex> lock(mutex_);if(std::this_thread::get_id()!=owner_||active_valid_||quiescent_)return false;
    for(const auto&entry:published_)if(equal(entry.prefix,p))return true;
    if(equal(last_published_ack_,p))return true;
    if(published_.size()>=prefix_capacity_||!register_events(p))return false;
    published_.push_back({p,false});return true;
}
bool OriginalPrimitiveMailbox::ack_published_prefix(const Prefix&p){
    std::lock_guard<std::mutex> lock(mutex_);if(std::this_thread::get_id()!=main_)return false;
    for(auto&entry:published_)if(equal(entry.prefix,p)){if(entry.acknowledged)return main_claimed_?acknowledge_main_prefix_locked(p):true;if(!acknowledge_main_prefix_locked(p))return false;entry.acknowledged=true;return true;}
    return equal(last_published_ack_,p)&&(!main_claimed_||acknowledge_main_prefix_locked(p));
}
OriginalPrimitiveMailbox::PrefixReceipt OriginalPrimitiveMailbox::consume_published_receipts(){
    std::lock_guard<std::mutex> lock(mutex_);if(std::this_thread::get_id()!=owner_||active_valid_)return {};
    // Main only records factual receipts. This method, and the original S
    // continuation return, are the sole writes of the source applied ledger.
    for(const auto&entry:published_)if(entry.acknowledged)applied_prefix_=std::max(applied_prefix_,entry.prefix.through);
    // A later LIVE ACK proves event application, not receipt of an earlier
    // separately held packet. Retain that exact obligation until its own Main
    // ACK, including the race between Main claim and this Source consume.
    for(auto i=published_.begin();i!=published_.end();)if(i->acknowledged){last_published_ack_=i->prefix;i=published_.erase(i);}else ++i;
    prune_events();return {generation_,journal_generation_,applied_prefix_,journal_generation_!=0};
}
size_t OriginalPrimitiveMailbox::unsettled_published_count()const{std::lock_guard<std::mutex> lock(mutex_);size_t count=0;for(const auto&entry:published_)if(!entry.acknowledged||entry.prefix.through>applied_prefix_)++count;return count;}
OriginalPrimitiveMailbox::ExchangeResult OriginalPrimitiveMailbox::exchange(const Request&r){
    std::unique_lock<std::mutex> lock(mutex_);
    if(std::this_thread::get_id()!=owner_||std::this_thread::get_id()==main_||active_valid_||quiescent_||!equal(r.prefix,staged_)||!admit_locked(r))return {};
    active_=r;active_valid_=true;acquired_=false;prefix_applied_=false;execution_claimed_=false;reply_ready_=false;
    // close_requested and elapsed deadlines are deliberately absent from this
    // predicate. Neither may unwind an accepted original GDScript stack.
    returned_.wait(lock,[this]{return reply_ready_;});
    ExchangeResult result;result.accepted=true;result.late=reply_.finished_usec>active_.deadline_usec;result.bytes=reply_.bytes;result.prefix_ack=ack_;
    if(result.late)++late_count_;
    auto &record=admissions_.at(active_.identity.sequence);record.committed=true;record.retired=true;advance_frontiers();
    applied_prefix_=std::max(applied_prefix_,ack_.through);
    last_request_=active_;last_reply_=reply_;last_ack_=ack_;
    prune_events();
    active_={};reply_={};ack_={};staged_={};reserved_return_slot_.reset();active_valid_=false;acquired_=false;prefix_applied_=false;execution_claimed_=false;reply_ready_=false;
    return result;
}
OriginalPrimitiveMailbox::Pending OriginalPrimitiveMailbox::acquire_pending(){if(std::this_thread::get_id()!=main_)return {};std::unique_lock<std::mutex> lock(mutex_,std::try_to_lock);if(!lock.owns_lock()||!active_valid_||acquired_)return {};acquired_=true;return {active_,true};}
bool OriginalPrimitiveMailbox::ack_prefix(const Ack&a){
    std::lock_guard<std::mutex> lock(mutex_);if(std::this_thread::get_id()!=main_||!a.applied)return false;
    if(active_valid_&&acquired_&&a.identity==active_.identity&&a.journal_generation==active_.prefix.journal_generation&&a.through==active_.prefix.through&&equal(a.prefix_bytes,active_.prefix.bytes)){
        if(prefix_applied_)return a.identity==ack_.identity&&a.through==ack_.through&&a.journal_generation==ack_.journal_generation&&equal(a.prefix_bytes,ack_.prefix_bytes);
        if(!acknowledge_main_prefix_locked(active_.prefix))return false;ack_=a;prefix_applied_=true;return true;
    }
    return a.identity==last_ack_.identity&&a.through==last_ack_.through&&a.journal_generation==last_ack_.journal_generation&&equal(a.prefix_bytes,last_ack_.prefix_bytes);
}
bool OriginalPrimitiveMailbox::submit(const Reply&r){
    std::lock_guard<std::mutex> lock(mutex_);
    if(std::this_thread::get_id()!=main_||!r.bytes||r.bytes->size()>result_capacity_)return false;
    if(active_valid_&&r.identity==active_.identity){
        if(!acquired_||!prefix_applied_||!execution_claimed_||!equal(r.request_bytes,active_.bytes)||r.started_usec<active_.submitted_usec||r.finished_usec<r.started_usec)return false;
        if(reply_ready_)return equal(r,reply_);
        // One result slot was physically reserved before admission. No queue,
        // future operation or destructive close can overwrite this result.
        reserved_return_slot_->resize(r.bytes->size());
        std::copy(r.bytes->begin(),r.bytes->end(),reserved_return_slot_->begin());
        reply_=r;reply_.bytes=reserved_return_slot_;reply_ready_=true;returned_.notify_one();return true;
    }
    return r.identity==last_reply_.identity&&equal(r,last_reply_);
}
bool OriginalPrimitiveMailbox::claim_execution(const Identity&i){std::lock_guard<std::mutex> lock(mutex_);if(std::this_thread::get_id()!=main_||!active_valid_||!acquired_||!prefix_applied_||execution_claimed_||!(active_.identity==i))return false;execution_claimed_=true;return true;}
OriginalPrimitiveMailbox::Pending OriginalPrimitiveMailbox::lookup(const Identity&i)const{std::lock_guard<std::mutex> lock(mutex_);if(active_valid_&&i==active_.identity)return {active_,true};if(last_request_.identity==i&&i.sequence>0)return {last_request_,true};return {};}
uint64_t OriginalPrimitiveMailbox::next_sequence()const{std::lock_guard<std::mutex> lock(mutex_);return admitted_+1;}
uint64_t OriginalPrimitiveMailbox::completed_sequence()const{std::lock_guard<std::mutex> lock(mutex_);return completed_;}
uint64_t OriginalPrimitiveMailbox::late_count()const{std::lock_guard<std::mutex> lock(mutex_);return late_count_;}
uint64_t OriginalPrimitiveMailbox::applied_prefix()const{std::lock_guard<std::mutex> lock(mutex_);return applied_prefix_;}
uint64_t OriginalPrimitiveMailbox::next_call_ordinal(const Bytes&s)const{std::lock_guard<std::mutex> lock(mutex_);if(std::this_thread::get_id()!=owner_||quiescent_||!s||s->empty()||s->size()>request_capacity_)return 0;auto found=completed_calls_.find(*s);return found==completed_calls_.end()?1:found->second+1;}
bool OriginalPrimitiveMailbox::finish_call_site(const Bytes&s){std::lock_guard<std::mutex> lock(mutex_);if(std::this_thread::get_id()!=owner_||active_valid_||!s||s->empty())return false;completed_calls_.erase(*s);return true;}
bool OriginalPrimitiveMailbox::reset_call_sites(){std::lock_guard<std::mutex> lock(mutex_);if(std::this_thread::get_id()!=owner_||active_valid_)return false;completed_calls_.clear();return true;}
void OriginalPrimitiveMailbox::request_close(){std::lock_guard<std::mutex> lock(mutex_);close_requested_=true;}
bool OriginalPrimitiveMailbox::close_requested()const{std::lock_guard<std::mutex> lock(mutex_);return close_requested_;}
bool OriginalPrimitiveMailbox::mark_quiescent(){std::lock_guard<std::mutex> lock(mutex_);if(std::this_thread::get_id()!=owner_||!close_requested_||active_valid_||!admissions_.empty())return false;for(const auto&entry:published_)if(!entry.acknowledged||entry.prefix.through>applied_prefix_)return false;quiescent_=true;return true;}
bool OriginalPrimitiveMailbox::quiescent()const{std::lock_guard<std::mutex> lock(mutex_);return quiescent_;}
bool OriginalPrimitiveMailbox::can_join()const{std::lock_guard<std::mutex> lock(mutex_);return close_requested_&&quiescent_&&!active_valid_&&admissions_.empty();}
bool OriginalPrimitiveMailbox::in_flight()const{std::lock_guard<std::mutex> lock(mutex_);return active_valid_;}
bool OriginalPrimitiveMailbox::prefix_applied(const Identity&i)const{std::lock_guard<std::mutex> lock(mutex_);return (active_valid_&&active_.identity==i&&prefix_applied_)||(last_ack_.identity==i&&i.sequence>0&&last_ack_.applied);}
bool OriginalPrimitiveMailbox::admit_locked(const Request&r){
    if(quiescent_||r.identity.generation!=generation_||r.identity.sequence!=admitted_+1||r.predecessor!=admitted_||r.submitted_usec==0||r.deadline_usec==0||!r.bytes||r.bytes->size()>request_capacity_||!r.source_site_bytes||r.source_site_bytes->empty()||r.source_site_bytes->size()>request_capacity_)return false;
    auto prior=completed_calls_.find(*r.source_site_bytes);if(r.call_ordinal!=(prior==completed_calls_.end()?1:prior->second+1))return false;
    admissions_.emplace(r.identity.sequence,AdmissionRecord{r,false,false});admitted_=r.identity.sequence;completed_calls_[*r.source_site_bytes]=r.call_ordinal;return true;
}
void OriginalPrimitiveMailbox::advance_frontiers(){
    while(true){auto i=admissions_.find(completed_+1);if(i==admissions_.end()||!i->second.committed)break;++completed_;}
    while(true){auto i=admissions_.find(retired_+1);if(i==admissions_.end()||!i->second.retired)break;++retired_;admissions_.erase(i);}
}
OriginalPrimitiveMailbox::AsyncAdmission OriginalPrimitiveMailbox::admit_async(const Request&r,bool reject_closing){
    if(std::this_thread::get_id()!=owner_)return AsyncAdmission::INVALID;
    std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return AsyncAdmission::BUSY;
    if(reject_closing&&(active_valid_||quiescent_))return AsyncAdmission::INVALID;
    if(!reject_closing&&(active_valid_||quiescent_||admissions_.size()>=prefix_capacity_))return AsyncAdmission::BACKPRESSURE;
    if(r.identity.generation!=generation_||r.identity.sequence!=admitted_+1||r.predecessor!=admitted_||!r.source_site_bytes||r.call_ordinal!=((completed_calls_.find(*r.source_site_bytes)==completed_calls_.end())?1:completed_calls_.at(*r.source_site_bytes)+1))return AsyncAdmission::INVALID;
    if(r.submitted_usec==0||r.deadline_usec==0||!r.bytes||r.bytes->size()>request_capacity_||r.source_site_bytes->empty()||r.source_site_bytes->size()>request_capacity_)return AsyncAdmission::INVALID;
    bool known=false;for(const auto&e:published_)if(equal(e.prefix,r.prefix)){known=true;break;}
    // Close may decline only a fully validated fresh intent. This path must
    // not register events, reserve a slot or advance the Original allocator.
    if(reject_closing){
        if(!known&&!register_events(r.prefix,false))return AsyncAdmission::INVALID;
        return AsyncAdmission::NOT_ADMITTED_CLOSING;
    }
    if(!known){if(published_.size()>=prefix_capacity_)return AsyncAdmission::BACKPRESSURE;if(!register_events(r.prefix))return AsyncAdmission::INVALID;published_.push_back({r.prefix,false});}
    return admit_locked(r)?AsyncAdmission::ACCEPTED:AsyncAdmission::INVALID;
}
bool OriginalPrimitiveMailbox::ack_async_prefix(const Request&r){
    std::lock_guard<std::mutex>lock(mutex_);if(std::this_thread::get_id()!=main_)return false;
    auto i=admissions_.find(r.identity.sequence);if(r.identity.generation!=generation_||i==admissions_.end()||!equal(i->second.request.bytes,r.bytes)||!equal(i->second.request.prefix,r.prefix))return false;
    for(auto&e:published_)if(equal(e.prefix,r.prefix)){if(e.acknowledged)return main_claimed_?acknowledge_main_prefix_locked(r.prefix):true;if(!acknowledge_main_prefix_locked(r.prefix))return false;e.acknowledged=true;return true;}
    return r.prefix.through<=main_applied_prefix_&&(!main_claimed_||acknowledge_main_prefix_locked(r.prefix)); // Exact accepted prefix already actually acknowledged.
}
OriginalPrimitiveMailbox::AsyncCommit OriginalPrimitiveMailbox::commit_async_status(const Identity&id){if(std::this_thread::get_id()!=owner_||id.generation!=generation_)return AsyncCommit::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return AsyncCommit::BUSY;auto i=admissions_.find(id.sequence);if(i==admissions_.end()||i->second.committed)return AsyncCommit::INVALID;i->second.committed=true;advance_frontiers();return AsyncCommit::COMMITTED;}
bool OriginalPrimitiveMailbox::commit_async(const Identity&id){return commit_async_status(id)==AsyncCommit::COMMITTED;}
bool OriginalPrimitiveMailbox::retire_async(const Identity&id){std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock()||std::this_thread::get_id()!=owner_||id.generation!=generation_)return false;auto i=admissions_.find(id.sequence);if(i==admissions_.end()||!i->second.committed||i->second.retired)return false;i->second.retired=true;advance_frontiers();return true;}
bool OriginalPrimitiveMailbox::operation_completed(const Identity&id)const{std::lock_guard<std::mutex>lock(mutex_);if(id.generation!=generation_||!id.sequence||id.sequence>admitted_)return false;if(id.sequence<=completed_)return true;auto i=admissions_.find(id.sequence);return i!=admissions_.end()&&i->second.committed;}
bool OriginalPrimitiveMailbox::operation_retired(const Identity&id)const{std::lock_guard<std::mutex>lock(mutex_);if(id.generation!=generation_||!id.sequence||id.sequence>admitted_)return false;if(id.sequence<=retired_)return true;auto i=admissions_.find(id.sequence);return i!=admissions_.end()&&i->second.retired;}
OriginalPrimitiveMailbox::MainPrefixClaim OriginalPrimitiveMailbox::claim_main_prefix(const Prefix&p){
    if(std::this_thread::get_id()!=main_)return {};std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock()||main_claimed_)return {};
    bool known=(active_valid_&&equal(active_.prefix,p))||equal(last_published_ack_,p);for(const auto&e:published_)if(equal(e.prefix,p)){known=true;break;}for(const auto&e:admissions_)if(equal(e.second.request.prefix,p)){known=true;break;}if(!known||p.generation!=generation_||p.journal_generation!=journal_generation_)return {};
    MainPrefixClaim claim;claim.ready=true;claim.after=main_applied_prefix_;claim.through=p.through;
    uint64_t prior=main_applied_prefix_;for(const auto&e:p.events)if(e.ordinal>main_applied_prefix_){if(e.ordinal!=prior+1)return {};claim.events.push_back(e);prior=e.ordinal;}
    if(p.through>main_applied_prefix_&&prior!=p.through)return {};main_claimed_prefix_=p;main_claimed_=true;return claim;
}
bool OriginalPrimitiveMailbox::acknowledge_main_prefix_locked(const Prefix&p){
    if(!main_claimed_||!equal(main_claimed_prefix_,p))return false;
    main_applied_prefix_=std::max(main_applied_prefix_,p.through);main_claimed_prefix_={};main_claimed_=false;return true;
}
OriginalPrimitiveMailbox::AsyncPreview OriginalPrimitiveMailbox::preview_async(const Bytes&s)const{if(std::this_thread::get_id()!=owner_)return {};std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock()||!s||s->empty()||quiescent_)return {};auto i=completed_calls_.find(*s);return {admitted_+1,i==completed_calls_.end()?1:i->second+1};}
OriginalPrimitiveMailbox::OperationState OriginalPrimitiveMailbox::read_operation_state_try(const Identity&id)const{std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {};OperationState state;state.available=true;if(id.generation!=generation_||!id.sequence||id.sequence>admitted_)return state;auto i=admissions_.find(id.sequence);state.completed=id.sequence<=completed_||(i!=admissions_.end()&&i->second.committed);state.retired=id.sequence<=retired_||(i!=admissions_.end()&&i->second.retired);return state;}
} // namespace hardcore::simulation

namespace hardcore::simulation {
OriginalPrimitiveMailbox::MainEventStatus OriginalPrimitiveMailbox::claimed_main_event_status(uint64_t journal,uint64_t ordinal,const Bytes&wire)const{
 if(std::this_thread::get_id()!=main_||!wire)return MainEventStatus::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return MainEventStatus::PENDING;
 if(!main_claimed_||main_claimed_prefix_.journal_generation!=journal)return MainEventStatus::INVALID;for(const auto&e:main_claimed_prefix_.events)if(e.ordinal==ordinal)return e.bytes&&*e.bytes==*wire?MainEventStatus::READY:MainEventStatus::INVALID;return MainEventStatus::INVALID;
}
OriginalPrimitiveMailbox::MainEventStatus OriginalPrimitiveMailbox::try_register_original_presentation_prefix(const Prefix&p){
 if(std::this_thread::get_id()!=owner_)return MainEventStatus::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return MainEventStatus::PENDING;
 if(active_valid_||quiescent_)return MainEventStatus::INVALID;for(const auto&entry:published_)if(equal(entry.prefix,p))return MainEventStatus::READY;
 if(equal(last_published_ack_,p))return MainEventStatus::READY;if(published_.size()>=prefix_capacity_)return MainEventStatus::PENDING;if(!register_events(p))return MainEventStatus::INVALID;
 published_.push_back({p,false});return MainEventStatus::READY;
}
}

namespace hardcore::simulation {
OriginalPrimitiveMailbox::MainEventStatus OriginalPrimitiveMailbox::actual_published_prefix_status(const Prefix&p)const{
 if(std::this_thread::get_id()!=main_||p.generation!=generation_||!p.bytes)return MainEventStatus::INVALID;
 std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return MainEventStatus::PENDING;
 if(p.journal_generation!=journal_generation_)return MainEventStatus::INVALID;
 // Caller uses the immutable prefix originally validated at accepted-event
 // registration. Later S pruning cannot turn an actual Main ACK into a miss.
 return p.through<=main_applied_prefix_?MainEventStatus::READY:MainEventStatus::PENDING;
}
}

namespace hardcore::simulation {
OriginalPrimitiveMailbox::PublishedRead OriginalPrimitiveMailbox::inspect_next_published_prefix()const {
    if(std::this_thread::get_id()!=main_)return {};
    std::unique_lock<std::mutex> lock(mutex_,std::try_to_lock);
    if(!lock.owns_lock()||main_claimed_)return {PublishedReadStatus::BUSY,{}};
    // Returning a prefix is not claiming it. All consumers still use the same
    // existing claim_main_prefix / physical apply / ACK boundary.
    // Empty bootstrap prefixes also establish journal ownership. Preserve
    // FIFO even when a later non-empty prefix is already registered.
    for(const auto &entry:published_)
        if(!entry.acknowledged)return {PublishedReadStatus::READY,entry.prefix};
    return {PublishedReadStatus::PENDING,{}};
}
}
