#pragma once
#include "core/math/random_pcg.h"
#include <thread>
#include <cstdlib>
namespace hardcore::simulation {
// Session owns one instance, across World changes. No access to Math.default_rand.
class SOwnedGameplayRandom {
public:
  struct Snapshot{uint64_t seed=0,state=0,increment=0;};
  bool import(const Snapshot&s){if(imported_||s.increment!=RandomPCG::DEFAULT_INC)return false;owner_=std::this_thread::get_id();rng_.seed(s.seed);rng_.set_state(s.state);imported_=true;return true;}
  bool is_owner()const{return imported_&&std::this_thread::get_id()==owner_;}
  uint64_t randi(){require_owner();return rng_.rand();}
  int64_t randi_range(int64_t from,int64_t to){require_owner();return rng_.random(static_cast<int>(from),static_cast<int>(to));}
  double randf(){require_owner();return static_cast<double>(static_cast<float>(rng_.rand())/static_cast<float>(UINT32_MAX));}
  double randf_range(double from,double to){require_owner();return rng_.random(from,to);}
  void seed(int64_t value){require_owner();rng_.seed(static_cast<uint64_t>(value));}
  void randomize_at(uint64_t unix_time,uint64_t ticks_usec){require_owner();rng_.seed((unix_time+ticks_usec)*rng_.get_state()+PCG_DEFAULT_INC_64);}
  uint64_t state()const{require_owner();return rng_.get_state();}
  uint64_t seed_value(){require_owner();return rng_.get_seed();}
private:
  void require_owner()const{if(!is_owner())std::abort();}
  RandomPCG rng_;std::thread::id owner_;bool imported_=false;
};
}
