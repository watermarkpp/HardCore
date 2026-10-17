#include "map_loading_provenance.h"
namespace hardcore::simulation {
bool MapLoadingProvenance::same(const Bytes&a,const Bytes&b){return a&&b&&*a==*b;}
bool MapLoadingProvenance::bind_owner(){if(std::this_thread::get_id()==main_||owner_!=std::thread::id{})return false;owner_=std::this_thread::get_id();return true;}
bool MapLoadingProvenance::bind_main_owner(uint64_t p){if(std::this_thread::get_id()!=main_||!p||producer_)return false;producer_=p;owner_open_.store(true,std::memory_order_release);return true;}
bool MapLoadingProvenance::publish(const Snapshot&s){
 if(std::this_thread::get_id()!=main_||!producer_||s.producer!=producer_||s.generation!=generation_||!s.scope||s.map<0||s.transition.empty()||!s.scope_wire||!s.descriptor||!s.world||s.scope_wire->empty()||s.scope_wire->size()+s.descriptor->size()+s.world->size()>capacity_||!owner_open_.load(std::memory_order_acquire))return false;
 std::unique_lock<std::mutex>lock(mutation_mutex_,std::try_to_lock);if(!lock.owns_lock())return false;
 auto old=std::atomic_load_explicit(&current_,std::memory_order_acquire);
 if(old){
  if(old->scope==s.scope){if(old->coordinator!=s.coordinator||old->map!=s.map||old->transition!=s.transition||!same(old->descriptor,s.descriptor)||!same(old->world,s.world))return false;
   if(old->state==s.state)return same(old->scope_wire,s.scope_wire);
   if(old->state!=State::LOADING||s.state!=State::RETAINED)return false;
  }else if(s.scope<=old->scope||old->state==State::LOADING||s.state!=State::LOADING)return false;
 }else if(s.state!=State::LOADING)return false;
 std::atomic_store_explicit(&current_,std::make_shared<const Snapshot>(s),std::memory_order_release);return true;
}
std::shared_ptr<const MapLoadingProvenance::Snapshot> MapLoadingProvenance::read_owner()const{if(std::this_thread::get_id()!=owner_)return {};return std::atomic_load_explicit(&current_,std::memory_order_acquire);}
bool MapLoadingProvenance::permits(const Snapshot&s,bool cleanup)const{
 auto a=read_owner();return a&&owner_open_.load(std::memory_order_acquire)&&a->generation==s.generation&&a->scope==s.scope&&a->producer==s.producer&&a->coordinator==s.coordinator&&a->map==s.map&&a->transition==s.transition&&same(a->scope_wire,s.scope_wire)&&same(a->descriptor,s.descriptor)&&same(a->world,s.world)&&((a->state==State::LOADING&&(cleanup||arrived_scope_.load(std::memory_order_acquire)!=a->scope))||(cleanup&&a->state==State::RETAINED));
}
bool MapLoadingProvenance::commit_arrival(const Snapshot&s){
 std::unique_lock<std::mutex>lock(mutation_mutex_,std::try_to_lock);if(!lock.owns_lock())return false;
 if(!permits(s,false)||s.state!=State::LOADING)return false;
 uint64_t previous=arrived_scope_.load(std::memory_order_acquire);
 if(previous>=s.scope)return false;
 return arrived_scope_.compare_exchange_strong(previous,s.scope,std::memory_order_acq_rel);
}
bool MapLoadingProvenance::certify_owner_closed(const Bytes&r){
 if(std::this_thread::get_id()!=main_||!producer_||!r||r->empty()||r->size()>capacity_)return false;
 if(!owner_open_.load(std::memory_order_acquire))return same(terminal_,r);
 auto a=std::atomic_load_explicit(&current_,std::memory_order_acquire);if(a&&a->state==State::LOADING)return false;
 terminal_=r;owner_open_.store(false,std::memory_order_release);return true;
}
bool MapLoadingProvenance::can_close()const{return !owner_open_.load(std::memory_order_acquire);}
}
