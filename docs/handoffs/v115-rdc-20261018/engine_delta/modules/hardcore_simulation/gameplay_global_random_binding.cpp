#include "gameplay_global_random_binding.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/os/thread.h"
void HardCoreGameplayGlobalRandom::_bind_methods(){
  ClassDB::bind_method(D_METHOD("initialize_handoff","handoff"),&HardCoreGameplayGlobalRandom::initialize_handoff);
  ClassDB::bind_method(D_METHOD("owner_thread_id"),&HardCoreGameplayGlobalRandom::owner_thread_id);
  ClassDB::bind_method(D_METHOD("is_initialized"),&HardCoreGameplayGlobalRandom::is_initialized);
  ClassDB::bind_method(D_METHOD("randi"),&HardCoreGameplayGlobalRandom::randi);
  ClassDB::bind_method(D_METHOD("randi_range","from","to"),&HardCoreGameplayGlobalRandom::randi_range);
  ClassDB::bind_method(D_METHOD("draw","from","to"),&HardCoreGameplayGlobalRandom::draw);
  ClassDB::bind_method(D_METHOD("randf"),&HardCoreGameplayGlobalRandom::randf);
  ClassDB::bind_method(D_METHOD("randf_range","from","to"),&HardCoreGameplayGlobalRandom::randf_range);
  ClassDB::bind_method(D_METHOD("seed","value"),&HardCoreGameplayGlobalRandom::seed);
  ClassDB::bind_method(D_METHOD("randomize"),&HardCoreGameplayGlobalRandom::randomize);
}
void HardCoreGameplayGlobalRandom::require_owner()const{CRASH_COND_MSG(Thread::is_main_thread()||!random.is_owner(),"Gameplay global RNG accessed outside its single S session owner.");}
void HardCoreGameplayGlobalRandom::require_mutable_owner()const{require_owner();CRASH_COND_MSG(terminal_sealed,"Gameplay RNG draw/seed after its actual terminal authority export.");}
Dictionary HardCoreGameplayGlobalRandom::seal_original_terminal_handoff(){
  require_owner();Dictionary d;d["contract_id"]="hardcore.gameplay_global_random.handoff.v1";d["seed"]=static_cast<int64_t>(random.seed_value());d["state"]=static_cast<int64_t>(random.state());d["increment"]=static_cast<int64_t>(RandomPCG::DEFAULT_INC);d.make_read_only();terminal_sealed=true;return d;
}
bool HardCoreGameplayGlobalRandom::initialize_handoff(const Dictionary&d){
  ERR_FAIL_COND_V(Thread::is_main_thread()||d.size()!=4||d.get("contract_id",Variant())!=Variant("hardcore.gameplay_global_random.handoff.v1"),false);
  for(const char*k:{"seed","state","increment"})ERR_FAIL_COND_V(!d.has(k)||d[k].get_type()!=Variant::INT,false);
  if(!random.import({static_cast<uint64_t>(static_cast<int64_t>(d["seed"])),static_cast<uint64_t>(static_cast<int64_t>(d["state"])),static_cast<uint64_t>(static_cast<int64_t>(d["increment"]))}))return false;actual_owner_thread=Thread::get_caller_id();return true;
}
int64_t HardCoreGameplayGlobalRandom::owner_thread_id()const{require_owner();return static_cast<int64_t>(actual_owner_thread);}
bool HardCoreGameplayGlobalRandom::is_initialized()const{ERR_FAIL_COND_V(Thread::is_main_thread(),false);return random.is_owner()&&actual_owner_thread==Thread::get_caller_id();}
int64_t HardCoreGameplayGlobalRandom::randi(){require_mutable_owner();return static_cast<int64_t>(random.randi());}
int64_t HardCoreGameplayGlobalRandom::randi_range(int64_t a,int64_t b){require_mutable_owner();return random.randi_range(a,b);}
int64_t HardCoreGameplayGlobalRandom::draw(int64_t a,int64_t b){return randi_range(a,b);}
double HardCoreGameplayGlobalRandom::randf(){require_mutable_owner();return random.randf();}
double HardCoreGameplayGlobalRandom::randf_range(double a,double b){require_mutable_owner();return random.randf_range(a,b);}
void HardCoreGameplayGlobalRandom::seed(int64_t value){require_mutable_owner();random.seed(value);}
void HardCoreGameplayGlobalRandom::randomize(){require_mutable_owner();auto*os=OS::get_singleton();const uint64_t unix_time=static_cast<uint64_t>(os->get_unix_time());const uint64_t ticks=os->get_ticks_usec();random.randomize_at(unix_time,ticks);}
