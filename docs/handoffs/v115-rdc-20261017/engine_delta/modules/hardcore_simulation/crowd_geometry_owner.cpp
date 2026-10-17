#include "crowd_geometry_owner.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include <cmath>
#include <mutex>
#include <set>
#include <thread>

using namespace hardcore::simulation;
using namespace hardcore::simulation::crowd;
namespace {
bool integer(const Dictionary&d,const char*name,int64_t&v){if(!d.has(name)||d[name].get_type()!=Variant::INT)return false;v=d[name];return true;}
bool number(const Dictionary&d,const char*name,double&v){if(!d.has(name)||(d[name].get_type()!=Variant::FLOAT&&d[name].get_type()!=Variant::INT))return false;v=d[name];return std::isfinite(v);}
bool vector(const Dictionary&d,const char*name,Vector2&v){if(!d.has(name)||d[name].get_type()!=Variant::VECTOR2)return false;v=d[name];return v.is_finite();}
// No gameplay object, mutable input, Callable, RID or Godot API in this context.
struct Telemetry{std::mutex mutex;std::set<std::thread::id> threads;std::thread::id caller;uint64_t calls=0,caller_calls=0;};
void measured_kernel(const FrozenInput&i,std::vector<uint8_t>&out,void*u){
    auto*t=static_cast<Telemetry*>(u);
    {std::lock_guard<std::mutex> lock(t->mutex);++t->calls;if(std::this_thread::get_id()==t->caller)++t->caller_calls;else t->threads.insert(std::this_thread::get_id());}
    batch_kernel(i,out,nullptr);
}
bool plain_identity(const Variant&v,int depth=0){
    if(depth>32)return false;
    switch(v.get_type()){
        case Variant::NIL:case Variant::BOOL:case Variant::INT:case Variant::STRING:case Variant::STRING_NAME:return true;
        case Variant::FLOAT:return std::isfinite(static_cast<double>(v));
        case Variant::DICTIONARY:{Dictionary d=v;Array keys=d.keys();for(int i=0;i<keys.size();++i)if(!plain_identity(keys[i],depth+1)||!plain_identity(d[keys[i]],depth+1))return false;return true;}
        case Variant::ARRAY:{Array a=v;for(int i=0;i<a.size();++i)if(!plain_identity(a[i],depth+1))return false;return true;}
        default:return false;
    }
}
bool valid_scope(const Dictionary&s){
    // The full original world and map-instance identities stay on S. They are
    // used for cache equality; worker inputs need no Object/Variant identities.
    return plain_identity(s)&&s.has("world_context")&&s["world_context"].get_type()==Variant::DICTIONARY&&s.has("world_generation")&&s["world_generation"].get_type()==Variant::INT&&s.has("map_instance_identity")&&s.has("geometry_generation")&&s["geometry_generation"].get_type()==Variant::INT;
}
bool stamp_scope_matches(const Dictionary&stamp,const Dictionary&read_scope){return valid_scope(read_scope)&&stamp.has("world_context")&&stamp["world_context"]==read_scope["world_context"]&&stamp.has("map_instance_identity")&&stamp["map_instance_identity"]==read_scope["map_instance_identity"];}
}
bool HardCoreCrowdGeometry::owned()const{return configured&&Thread::get_caller_id()==owner&&!Thread::is_main_thread();}
bool HardCoreCrowdGeometry::configure_owner(int64_t max_peers,int64_t max_queries,int64_t worker_tasks,double eps){
    ERR_FAIL_COND_V(configured||Thread::is_main_thread()||Thread::get_caller_id()!=owner||max_peers<=0||max_peers>INT32_MAX||max_queries<=0||max_queries>INT32_MAX||worker_tasks<=0||worker_tasks>INT32_MAX||!std::isfinite(eps)||eps<=0.0,false);
    WorkerThreadPool*p=WorkerThreadPool::get_singleton();ERR_FAIL_NULL_V(p,false);
    peer_capacity=static_cast<uint32_t>(max_peers);query_capacity=static_cast<uint32_t>(max_queries);tasks=static_cast<int>(worker_tasks);epsilon=eps;
    adapter=std::make_unique<GodotWorkerPoolAdapter>(*p);configured=true;return true;
}
bool HardCoreCrowdGeometry::parse_query(const Dictionary&d,Query&q)const{
    int64_t kind=0;if(!integer(d,"kind",kind)||kind<0||kind>2||!vector(d,"a",q.a)||!vector(d,"b",q.b)||!number(d,"own_radius",q.own_radius)||!number(d,"own_margin",q.own_margin))return false;
    q.kind=static_cast<Kind>(kind);q.epsilon=epsilon;
    return q.kind!=Kind::CONTACT||q.b.length_squared()>0.0f;
}
bool HardCoreCrowdGeometry::parse_peer(const Dictionary&d,Peer&p,bool full)const{
    int64_t id=0,life=0,pose=0,radius=0,map=0;
    if(!integer(d,"runtime_id",id)||id<=0||!integer(d,"life",life)||life<=0||!integer(d,"pose_revision",pose)||pose<=0||!integer(d,"radius_revision",radius)||radius<=0||!integer(d,"map",map)||map<0)return false;
    p.runtime_id=id;p.life=life;p.pose_revision=pose;p.radius_revision=radius;p.map=map;
    if(!full)return true;
    return vector(d,"position",p.center)&&number(d,"radius",p.radius)&&number(d,"margin",p.margin);
}
void HardCoreCrowdGeometry::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure_owner","max_peers","max_queries","worker_tasks","source_epsilon"),&HardCoreCrowdGeometry::configure_owner);
    ClassDB::bind_method(D_METHOD("owner_thread_id"),&HardCoreCrowdGeometry::owner_thread_id);
    ClassDB::bind_method(D_METHOD("prepare","queries","peers","read_scope","epoch","generation","deadline_usec"),&HardCoreCrowdGeometry::prepare);
    ClassDB::bind_method(D_METHOD("motion_row","a","b","center","own_radius","peer_radius","stamp","read_scope"),&HardCoreCrowdGeometry::motion_row);
    ClassDB::bind_method(D_METHOD("destination_row","point","center","own_radius","peer_radius","stamp","read_scope"),&HardCoreCrowdGeometry::destination_row);
    ClassDB::bind_method(D_METHOD("contact_limit","origin","direction","center","radius","stamp","read_scope"),&HardCoreCrowdGeometry::contact_limit);
    ClassDB::bind_method(D_METHOD("diagnostics"),&HardCoreCrowdGeometry::diagnostics);
    ClassDB::bind_method(D_METHOD("close_owner"),&HardCoreCrowdGeometry::close_owner);
}
Dictionary HardCoreCrowdGeometry::prepare(const Array&queries,const Array&peers,const Dictionary&read_scope,int64_t epoch,int64_t generation,int64_t deadline){
    Dictionary receipt;receipt["success"]=false;receipt["status"]="FAIL";
    ERR_FAIL_COND_V(!owned(),receipt);
    if(queries.is_empty()||queries.size()>query_capacity||peers.size()>peer_capacity||epoch<0||generation<=0||deadline<=0||!valid_scope(read_scope)){receipt["reason"]="crowd_capacity_or_readset_invalid";return receipt;}
    if(executor&&executor->in_flight()!=0){receipt["reason"]="accepted_crowd_work_not_retired";return receipt;}
    std::vector<Peer> parsed_peers;std::unordered_map<uint64_t,size_t> slots;
    for(int i=0;i<peers.size();++i){Peer p;if(peers[i].get_type()!=Variant::DICTIONARY||!parse_peer(peers[i],p,true)||!stamp_scope_matches(peers[i],read_scope)||slots.count(p.runtime_id)){receipt["reason"]="crowd_peer_invalid_or_duplicate";return receipt;}slots[p.runtime_id]=parsed_peers.size();parsed_peers.push_back(p);}
    std::vector<Input> parsed_inputs;std::vector<std::shared_ptr<const FrozenInput>> frozen;
    for(int i=0;i<queries.size();++i){Input in;if(queries[i].get_type()!=Variant::DICTIONARY||!parse_query(queries[i],in.query)){receipt["reason"]="crowd_query_invalid";return receipt;}in.peers=parsed_peers;auto f=freeze_input(in,static_cast<uint64_t>(generation));if(!f){receipt["reason"]="crowd_freeze_failed";return receipt;}parsed_inputs.push_back(std::move(in));frozen.push_back(f);}
    const uint64_t started=OS::get_singleton()->get_ticks_usec();
    Telemetry telemetry;telemetry.caller=std::this_thread::get_id();
    // telemetry and immutable inputs outlive every accepted callback including
    // late outputs and failure. Only S can enter this synchronous suffix.
    executor=std::make_unique<BatchExecutor>(*adapter,1,measured_kernel,&telemetry);
    BatchTicket ticket{static_cast<uint64_t>(epoch),static_cast<uint64_t>(generation)};
    auto accepted=executor->dispatch_ready(ticket,frozen,tasks,false,{static_cast<uint64_t>(epoch),false});
    if(accepted!=BatchExecutor::DispatchResult::ACCEPTED){executor.reset();receipt["reason"]="crowd_dispatch_failed";return receipt;}
    // These rows are needed by the current original consumer. Park S on
    // the actual group instead of burning a core while W computes them.
    if(!executor->wait_for_published(ticket)){executor.reset();receipt["reason"]="crowd_group_wait_failed";return receipt;}
    std::vector<Output> parsed_outputs(frozen.size());std::vector<bool> consumed(frozen.size(),false);size_t count=0;bool invalid_output=false;
    while(count<frozen.size()){
        for(uint32_t id:executor->poll_published(ticket).block_ids){
            if(consumed[id])continue;
            const auto output=executor->acquire_output(ticket,id);
            if(!output.valid()||!decode_output(*output.bytes,parsed_outputs[id])||parsed_outputs[id].rows.size()!=parsed_peers.size())invalid_output=true;
            if(!executor->consume_block(ticket,id,{1}))invalid_output=true;
            consumed[id]=true;++count;
        }
        // Deadline failure never frees/cancels a RUNNING necessary input and
        // never turns a late result into a completed-on-time receipt.
        if(count<frozen.size())std::this_thread::yield();
    }
    // READY does not mean native group retirement. poll precedes retire; S is
    // also the sole destructor owner. M has no path to any pool wait here.
    while(!executor->retire_completed(ticket)){executor->poll_published(ticket);std::this_thread::yield();}
    executor.reset();const uint64_t finished=OS::get_singleton()->get_ticks_usec();
    if(invalid_output){receipt["reason"]="crowd_worker_output_invalid";return receipt;}
    inputs=std::move(parsed_inputs);outputs=std::move(parsed_outputs);peer_slots=std::move(slots);scope=read_scope.duplicate(true);
    receipt["success"]=true;receipt["status"]=finished>static_cast<uint64_t>(deadline)?"FAIL":"PASS";receipt["deadline_missed"]=finished>static_cast<uint64_t>(deadline);
    receipt["epoch"]=epoch;receipt["generation"]=generation;receipt["dispatch_usec"]=static_cast<int64_t>(started);receipt["finished_usec"]=static_cast<int64_t>(finished);receipt["deadline_usec"]=deadline;
    receipt["blocks"]=queries.size();receipt["peer_count"]=peers.size();receipt["worker_thread_count"]=static_cast<int64_t>(telemetry.threads.size());receipt["worker_kernel_calls"]=static_cast<int64_t>(telemetry.calls-telemetry.caller_calls);receipt["serial_kernel_calls"]=static_cast<int64_t>(telemetry.caller_calls);
    return receipt;
}
const Row*HardCoreCrowdGeometry::cached(const Query&q,const Peer&p,const Dictionary&read_scope){
    if(read_scope!=scope)return nullptr;
    auto it=peer_slots.find(p.runtime_id);if(it==peer_slots.end())return nullptr;
    for(size_t i=0;i<inputs.size();++i){if(same_query(inputs[i].query,q)&&it->second<inputs[i].peers.size()&&same_peer(inputs[i].peers[it->second],p)){++cache_hits;return &outputs[i].rows[it->second];}}
    return nullptr;
}
Dictionary HardCoreCrowdGeometry::motion_row(Vector2 a,Vector2 b,Vector2 c,double ra,double rb,const Dictionary&stamp,const Dictionary&read_scope){
    Dictionary result;ERR_FAIL_COND_V(!owned(),result);
    Query q;q.kind=Kind::MOTION;q.a=a;q.b=b;q.own_radius=ra;q.epsilon=epsilon;
    Peer p;bool stamp_ok=parse_peer(stamp,p,false)&&stamp_scope_matches(stamp,read_scope);p.center=c;p.radius=rb;
    // Margin is not an input of either motion/destination predicate. Exact
    // cache comparison uses its snapshot value without extra source reads.
    auto slot=peer_slots.find(p.runtime_id);if(slot!=peer_slots.end()&&!inputs.empty())p.margin=inputs[0].peers[slot->second].margin;
    const Row*prepared=stamp_ok?cached(q,p,read_scope):nullptr;Row repaired;
    if(!prepared){repaired=evaluate(q,p);prepared=&repaired;++serial_repairs;}
    result["envelope"]=prepared->envelope;result["crossed"]=prepared->crossed;return result;
}
bool HardCoreCrowdGeometry::destination_row(Vector2 point,Vector2 c,double ra,double rb,const Dictionary&stamp,const Dictionary&read_scope){
    ERR_FAIL_COND_V(!owned(),true);Query q;q.kind=Kind::DESTINATION;q.a=point;q.b=point;q.own_radius=ra;q.epsilon=epsilon;
    Peer p;bool stamp_ok=parse_peer(stamp,p,false)&&stamp_scope_matches(stamp,read_scope);p.center=c;p.radius=rb;auto slot=peer_slots.find(p.runtime_id);if(slot!=peer_slots.end()&&!inputs.empty())p.margin=inputs[0].peers[slot->second].margin;
    const Row*row=stamp_ok?cached(q,p,read_scope):nullptr;if(row)return row->crossed;++serial_repairs;return evaluate(q,p).crossed;
}
double HardCoreCrowdGeometry::contact_limit(Vector2 origin,Vector2 direction,Vector2 c,double radius,const Dictionary&stamp,const Dictionary&read_scope){
    ERR_FAIL_COND_V(!owned(),0.0);Peer p;bool stamp_ok=parse_peer(stamp,p,false)&&stamp_scope_matches(stamp,read_scope);p.center=c;
    if(stamp_ok&&read_scope==scope){auto slot=peer_slots.find(p.runtime_id);if(slot!=peer_slots.end())for(size_t i=0;i<inputs.size();++i){const Query&q=inputs[i].query;const Peer&old=inputs[i].peers[slot->second];p.radius=old.radius;p.margin=old.margin;
        if(q.kind==Kind::CONTACT&&q.a==origin&&q.b==direction&&q.own_radius+old.radius+q.own_margin+old.margin==radius&&same_peer(old,p)){++cache_hits;return outputs[i].rows[slot->second].limit;}
    }}
    ++serial_repairs;return free_ray_extent(origin,direction,c,radius,1.0,epsilon);
}
Dictionary HardCoreCrowdGeometry::diagnostics()const{Dictionary d;ERR_FAIL_COND_V(!owned(),d);d["cache_hits"]=static_cast<int64_t>(cache_hits);d["serial_repairs"]=static_cast<int64_t>(serial_repairs);d["in_flight"]=executor?static_cast<int64_t>(executor->in_flight()):0;return d;}
bool HardCoreCrowdGeometry::close_owner(){ERR_FAIL_COND_V(!owned(),false);if(executor&&executor->in_flight()!=0)return false;executor.reset();adapter.reset();inputs.clear();outputs.clear();peer_slots.clear();scope.clear();configured=false;return true;}
