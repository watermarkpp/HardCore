#pragma once
#include "crowd_geometry_kernel.h"
#include "batch_executor.h"
#include "godot_worker_pool_adapter.h"
#include "core/object/ref_counted.h"
#include "core/os/thread.h"
#include "core/variant/dictionary.h"
#include "core/variant/array.h"
#include <memory>
#include <unordered_map>

// The Object is S-local; its methods are never worker callbacks. Only frozen
// native byte buffers enter BatchExecutor/GodotWorkerPoolAdapter.
class HardCoreCrowdGeometry final:public RefCounted {
    GDCLASS(HardCoreCrowdGeometry,RefCounted);
    Thread::ID owner=Thread::get_caller_id();
    bool configured=false;
    uint32_t peer_capacity=0,query_capacity=0;
    int tasks=0;
    double epsilon=0.0001;
    std::unique_ptr<hardcore::simulation::GodotWorkerPoolAdapter> adapter;
    std::unique_ptr<hardcore::simulation::BatchExecutor> executor;
    std::vector<hardcore::simulation::crowd::Input> inputs;
    std::vector<hardcore::simulation::crowd::Output> outputs;
    std::unordered_map<uint64_t,size_t> peer_slots;
    Dictionary scope;
    uint64_t cache_hits=0,serial_repairs=0;
    bool owned()const;
    bool parse_query(const Dictionary&,hardcore::simulation::crowd::Query&)const;
    bool parse_peer(const Dictionary&,hardcore::simulation::crowd::Peer&,bool full)const;
    const hardcore::simulation::crowd::Row *cached(const hardcore::simulation::crowd::Query&,const hardcore::simulation::crowd::Peer&,const Dictionary&);
protected:
    static void _bind_methods();
public:
    bool configure_owner(int64_t max_peers,int64_t max_queries,int64_t worker_tasks,double source_epsilon);
    int64_t owner_thread_id()const{return static_cast<int64_t>(owner);}
    Dictionary prepare(const Array&queries,const Array&peers,const Dictionary&read_scope,int64_t epoch,int64_t generation,int64_t deadline_usec);
    Dictionary motion_row(Vector2 a,Vector2 b,Vector2 center,double own_radius,double peer_radius,const Dictionary&stamp,const Dictionary&read_scope);
    bool destination_row(Vector2 point,Vector2 center,double own_radius,double peer_radius,const Dictionary&stamp,const Dictionary&read_scope);
    double contact_limit(Vector2 origin,Vector2 direction,Vector2 center,double radius,const Dictionary&stamp,const Dictionary&read_scope);
    Dictionary diagnostics()const;
    bool close_owner();
};
