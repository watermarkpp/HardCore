#pragma once
#include <atomic>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace hardcore::simulation {
// Transport only. Main attests actual SceneTree phases in Host; this class
// does not manufacture frames, budgets, physics work or gameplay callbacks.
class CloseProcessMailbox {
public:
 using Bytes=std::shared_ptr<const std::vector<uint8_t>>;
 enum class Phase { SIGNAL,SERVICE };
 enum class Status { ACCEPTED,DUPLICATE,PENDING,BUSY,BACKPRESSURE,CONSUMED,STOPPED,INVALID };
 struct Read { Status status=Status::PENDING;uint64_t sequence=0,frame=0,source_frame=0;Phase phase=Phase::SIGNAL;Bytes bytes; };
 CloseProcessMailbox(uint64_t generation,size_t capacity):generation_(generation),capacity_(capacity),main_(std::this_thread::get_id()){}
 bool bind_owner(){if(std::this_thread::get_id()==main_||owner_!=std::thread::id{})return false;owner_=std::this_thread::get_id();return true;}
 void observe_actual_signal(uint64_t frame){if(std::this_thread::get_id()!=main_)return;uint64_t old=highwater_.load(std::memory_order_relaxed);if(frame>old)highwater_.store(frame,std::memory_order_release);}
 uint64_t signal_highwater()const{return highwater_.load(std::memory_order_acquire);}
 uint64_t published_sequence()const{return published_.load(std::memory_order_acquire);}
 bool stop_requested()const{return stop_requested_.load(std::memory_order_acquire);}
 bool stopped()const{return stopped_.load(std::memory_order_acquire);}
 Status publish(uint64_t generation,uint64_t sequence,uint64_t frame,Phase phase,const Bytes&bytes){
  if(std::this_thread::get_id()!=main_||generation!=generation_||!sequence||!bytes||bytes->empty())return Status::INVALID;
  std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::BUSY;
  if(stopped())return Status::STOPPED;
  for(auto &p:pairs_)for(auto &e:p.events)if(e.sequence==sequence)return e.bytes&&e.frame==frame&&e.phase==phase&&*e.bytes==*bytes?Status::DUPLICATE:Status::INVALID;
  if(sequence!=published_.load(std::memory_order_relaxed)+1)return Status::INVALID;
  if(phase==Phase::SIGNAL){
   if(!pairs_.empty()&&!pairs_.back().events[1].sequence)return Status::INVALID;
   if(frame<=last_frame_||frame>signal_highwater())return Status::INVALID;
   if(pairs_.size()>=capacity_)return Status::BACKPRESSURE;
   Pair pair;pair.events[0]={Status::ACCEPTED,sequence,frame,0,phase,bytes};pairs_.push_back(std::move(pair));last_frame_=frame;
  }else{
   if(pairs_.empty()||pairs_.back().events[1].sequence||pairs_.back().events[0].frame!=frame)return Status::INVALID;
   pairs_.back().events[1]={Status::ACCEPTED,sequence,frame,0,phase,bytes};
  }
  published_.store(sequence,std::memory_order_release);return Status::ACCEPTED;
 }
 Read acquire(){
  if(std::this_thread::get_id()!=owner_)return {Status::INVALID};
  std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {Status::BUSY};
  for(auto&p:pairs_)for(int i=0;i<2;++i){auto&e=p.events[i];if(e.sequence&&e.sequence==consumed_+1){if(p.state[i])return {Status::INVALID};p.state[i]=1;return e;}}
  return {};
 }
 Status complete(uint64_t sequence,uint64_t source_frame){
  if(std::this_thread::get_id()!=owner_||!source_frame)return Status::INVALID;
  std::lock_guard<std::mutex>lock(mutex_);
  for(auto&p:pairs_)for(int i=0;i<2;++i)if(p.events[i].sequence==sequence){
   if(p.state[i]!=1||sequence!=consumed_+1||(i==1&&p.events[0].source_frame!=source_frame))return Status::INVALID;
   p.events[i].source_frame=source_frame;p.state[i]=2;consumed_=sequence;return Status::CONSUMED;
  }return Status::INVALID;
 }
 Read receipt()const{
  if(std::this_thread::get_id()!=main_)return {Status::INVALID};
  std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return {Status::BUSY};
  for(const auto&p:pairs_)for(int i=0;i<2;++i)if(p.state[i]==2){Read r=p.events[i];r.status=Status::CONSUMED;return r;}
  return {};
 }
 bool ack(uint64_t sequence,uint64_t source_frame){
  if(std::this_thread::get_id()!=main_)return false;
  std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return false;
  for(auto&p:pairs_)for(int i=0;i<2;++i)if(p.events[i].sequence==sequence){if(p.state[i]!=2||p.events[i].source_frame!=source_frame)return false;p.state[i]=3;while(!pairs_.empty()&&pairs_.front().state[0]==3&&pairs_.front().state[1]==3)pairs_.pop_front();return true;}
  return false;
 }
 bool request_stop(){if(std::this_thread::get_id()!=owner_)return false;stop_requested_.store(true,std::memory_order_release);return true;}
 Status confirm_stopped(uint64_t watermark){
  if(std::this_thread::get_id()!=main_||!stop_requested())return Status::INVALID;
  std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);if(!lock.owns_lock())return Status::BUSY;
  if(watermark!=published_sequence()||(!pairs_.empty()&&!pairs_.back().events[1].sequence))return Status::INVALID;
  stopped_.store(true,std::memory_order_release);return Status::STOPPED;
 }
 bool can_close()const{
  std::unique_lock<std::mutex>lock(mutex_,std::try_to_lock);return lock.owns_lock()&&stopped()&&pairs_.empty()&&consumed_==published_sequence();
 }
private:
 struct Pair{Read events[2];uint8_t state[2]={0,0};};
 const uint64_t generation_;const size_t capacity_;const std::thread::id main_;std::thread::id owner_;
 mutable std::mutex mutex_;std::deque<Pair>pairs_;uint64_t last_frame_=0,consumed_=0;
 std::atomic<uint64_t>highwater_{0},published_{0};std::atomic<bool>stop_requested_{false},stopped_{false};
};
}
