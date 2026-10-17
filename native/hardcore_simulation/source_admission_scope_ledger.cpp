#include "source_admission_scope_ledger.h"
namespace hardcore::simulation {
bool SourceAdmissionScopeLedger::same(const Snapshot&a,const Snapshot&b){return a.generation==b.generation&&a.scope_id==b.scope_id&&a.producer==b.producer&&a.profile==b.profile&&a.world&&b.world&&*a.world==*b.world&&a.receipt&&b.receipt&&*a.receipt==*b.receipt&&a.publication&&b.publication&&*a.publication==*b.publication;}
bool SourceAdmissionScopeLedger::bind_owner(){std::lock_guard<std::mutex>lock(mutex_);if(std::this_thread::get_id()==main_||owner_!=std::thread::id{})return false;owner_=std::this_thread::get_id();return true;}
SourceAdmissionScopeLedger::Status SourceAdmissionScopeLedger::publish(const Snapshot&s){
 if(std::this_thread::get_id()!=main_||s.generation!=generation_||!s.scope_id||!s.producer||s.profile.empty()||!s.world||!s.receipt||!s.publication||s.receipt->empty()||s.publication->empty()||s.world->size()>capacity_||s.receipt->size()>capacity_-s.world->size()||s.publication->size()>capacity_-s.world->size()-s.receipt->size())return Status::INVALID;
 std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;
 if(finished_){if(s.scope_id<=retired_scope_||s.state!=State::PREPARED)return Status::INVALID;active_=s;claimed_=false;finished_=false;return Status::READY;}
 if(!same(active_,s))return Status::INVALID;
 if(active_.state==s.state)return Status::READY;
 if(active_.state!=State::PREPARED||s.state==State::PREPARED||(!claimed_&&s.state!=State::ABORTED))return Status::INVALID;
 active_.state=s.state;return Status::READY;
}
SourceAdmissionScopeLedger::Read SourceAdmissionScopeLedger::claim(uint64_t scope){if(std::this_thread::get_id()!=owner_)return {Status::INVALID,{}};std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {};if(finished_||active_.scope_id!=scope||active_.state!=State::PREPARED)return {Status::INVALID,{}};claimed_=true;return {Status::READY,active_};}
SourceAdmissionScopeLedger::Read SourceAdmissionScopeLedger::poll(uint64_t scope)const{if(std::this_thread::get_id()!=owner_)return {Status::INVALID,{}};std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {};if(finished_||active_.scope_id!=scope)return {Status::INVALID,{}};return {Status::READY,active_};}
SourceAdmissionScopeLedger::Status SourceAdmissionScopeLedger::permission(uint64_t scope,const std::string&op)const{if(std::this_thread::get_id()!=owner_)return Status::INVALID;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::PENDING;if(finished_||!claimed_||active_.scope_id!=scope||active_.state==State::ABORTED)return Status::INVALID;if(op=="feature.source_admission_prepare"||op=="feature.source_admission_commit"||op=="feature.source_admission_abort")return active_.state==State::PREPARED?Status::READY:Status::INVALID;return op=="feature.source_admission_loading"||op=="feature.source_admission_pins"||op=="feature.source_admission_release_pins"?Status::READY:Status::INVALID;}
bool SourceAdmissionScopeLedger::allows(uint64_t scope,const std::string&op)const{return permission(scope,op)==Status::READY;}
bool SourceAdmissionScopeLedger::finish(uint64_t scope){if(std::this_thread::get_id()!=owner_)return false;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock()||finished_||(!claimed_&&active_.state!=State::ABORTED)||active_.scope_id!=scope||active_.state==State::PREPARED)return false;retired_scope_=scope;finished_=true;claimed_=false;active_={};return true;}
bool SourceAdmissionScopeLedger::retire_unclaimed_aborted_main(){if(std::this_thread::get_id()!=main_)return false;std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock()||owner_!=std::thread::id{}||claimed_)return false;if(finished_)return true;if(active_.state!=State::ABORTED)return false;retired_scope_=active_.scope_id;active_={};finished_=true;return true;}
bool SourceAdmissionScopeLedger::quiescent()const{std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);return lock.owns_lock()&&finished_;}
}
