#pragma once
#include "gameplay_global_random.h"
#include "core/object/ref_counted.h"
class HardCoreGameplayGlobalRandom:public RefCounted {
  GDCLASS(HardCoreGameplayGlobalRandom,RefCounted);
  hardcore::simulation::SOwnedGameplayRandom random;
  uint64_t actual_owner_thread=0;
  void require_owner()const;
  friend class HardCoreSimulationHost;
  bool terminal_sealed=false;
  void require_mutable_owner()const;
  Dictionary seal_original_terminal_handoff();
protected:static void _bind_methods();
public:
  bool initialize_handoff(const Dictionary&);
  int64_t owner_thread_id()const;bool is_initialized()const;
  int64_t randi();int64_t randi_range(int64_t,int64_t);int64_t draw(int64_t,int64_t);
  double randf();double randf_range(double,double);void seed(int64_t);void randomize();
};
