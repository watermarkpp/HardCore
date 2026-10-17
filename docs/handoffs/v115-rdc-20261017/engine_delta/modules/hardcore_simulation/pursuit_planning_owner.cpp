#include "pursuit_planning_owner.h"
#include "simulation_host.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <set>
using namespace hardcore::simulation::pursuit;
static uint64_t now_usec() { return OS::get_singleton()->get_ticks_usec(); }
static void maximum(std::atomic<uint64_t> &dst,uint64_t value) { uint64_t old=dst.load(); while (old<value&&!dst.compare_exchange_weak(old,value)) {} }
static bool integer(const Dictionary &d,const char *key,int64_t &out) { Variant v=d.get(key,Variant()); if (v.get_type()!=Variant::INT) return false; out=v; return true; }
static bool scalar(const Dictionary &d,const char *key,double &out) { Variant v=d.get(key,Variant()); if (v.get_type()!=Variant::FLOAT) return false; out=v; return std::isfinite(out); }
static bool vector2(const Dictionary &d,const char *key,Vector2 &out) { Variant v=d.get(key,Variant()); if (v.get_type()!=Variant::VECTOR2) return false; out=v; return out.is_finite(); }
static bool polygons(const Variant &v,std::vector<Polygon> &out) {
    if (v.get_type()!=Variant::ARRAY) return false; Array a=v;
    for (int i=0;i<a.size();++i) { if (a[i].get_type()!=Variant::PACKED_VECTOR2_ARRAY) return false; PackedVector2Array p=a[i]; if (p.size()<3||p.size()>128) return false; Polygon row; for (int j=0;j<p.size();++j) { if (!p[j].is_finite()) return false; row.push_back(p[j]); } out.push_back(std::move(row)); } return true;
}
static bool buckets(const Variant &v,std::map<Vector2i,std::vector<int>,CellLess> &out,size_t count) {
    if (v.get_type()!=Variant::DICTIONARY) return false; Dictionary d=v; Array keys=d.keys();
    for (int i=0;i<keys.size();++i) { if (keys[i].get_type()!=Variant::VECTOR2I||d[keys[i]].get_type()!=Variant::ARRAY) return false; Array row=d[keys[i]]; std::vector<int> ids; for (int j=0;j<row.size();++j) { if (row[j].get_type()!=Variant::INT) return false; int64_t id=row[j]; if (id<0||uint64_t(id)>=count) return false; ids.push_back(int(id)); } out[Vector2i(keys[i])]=std::move(ids); } return true;
}
static bool parse_navigation(const Dictionary &d,Navigation &n) {
    if (d.get("valid",false)!=Variant(true)||d.get("design_size",Variant()).get_type()!=Variant::VECTOR2I||d.get("build_sha256",Variant()).get_type()!=Variant::STRING) return false;
    n.design_size=d["design_size"]; n.build_sha256=String(d["build_sha256"]).utf8().get_data();
    if (n.design_size.x<=0||n.design_size.y<=0||n.build_sha256.size()!=64) return false;
    String kind=d.get("kind",String()); n.polygon=kind=="polygon";
    if (n.polygon) {
        if (d.get("index",Variant()).get_type()!=Variant::DICTIONARY||d.get("graph",Variant()).get_type()!=Variant::DICTIONARY) return false;
        Dictionary index=d["index"],graph=d["graph"];
        if (!polygons(index.get("parts",Variant()),n.parts)||!polygons(graph.get("faces",Variant()),n.faces)||!scalar(graph,"radius_gu",n.radius)) return false;
        n.radius_key=String(graph.get("radius_key",String())).utf8().get_data();
        if (n.radius<0||n.radius_key.size()!=16||n.parts.size()>16384||n.faces.size()>32768) return false;
        if (!buckets(index.get("buckets",Variant()),n.part_buckets,n.parts.size())||!buckets(graph.get("buckets",Variant()),n.face_buckets,n.faces.size())) return false;
        Variant first=index.get("first_buckets",Variant()), bounds=index.get("padded_boxes",Variant()), centers=graph.get("centers",Variant()), links=graph.get("links",Variant());
        if (first.get_type()!=Variant::ARRAY||bounds.get_type()!=Variant::ARRAY||centers.get_type()!=Variant::PACKED_VECTOR2_ARRAY||links.get_type()!=Variant::ARRAY) return false;
        Array fa=first,ba=bounds,la=links; PackedVector2Array ca=centers;
        if (fa.size()!=int(n.parts.size())||ba.size()!=fa.size()||ca.size()!=int(n.faces.size())||la.size()!=ca.size()) return false;
        for (int i=0;i<fa.size();++i) { if (fa[i].get_type()!=Variant::VECTOR2I||ba[i].get_type()!=Variant::RECT2) return false; n.first_buckets.push_back(Vector2i(fa[i])); n.padded_bounds.push_back(Rect2(ba[i])); }
        for (int i=0;i<ca.size();++i) { if (!ca[i].is_finite()||la[i].get_type()!=Variant::ARRAY) return false; n.centers.push_back(ca[i]); Array row=la[i]; std::vector<Link> decoded; for (int j=0;j<row.size();++j) { if (row[j].get_type()!=Variant::DICTIONARY) return false; Dictionary r=row[j]; Link l; int64_t to; if (!integer(r,"to",to)||to<0||to>=ca.size()||!scalar(r,"cost",l.cost)||l.cost<0||!vector2(r,"portal",l.portal)) return false; l.to=int(to); decoded.push_back(l); } n.links.push_back(std::move(decoded)); }
    } else {
        if (kind!="legacy_grid"||d.get("blocked_cells",Variant()).get_type()!=Variant::DICTIONARY) return false;
        Dictionary blocked=d["blocked_cells"]; Array keys=blocked.keys();
        for (int i=0;i<keys.size();++i) { if (keys[i].get_type()!=Variant::VECTOR2I||blocked[keys[i]]!=Variant(true)) return false; Vector2i c=keys[i]; if (c.x<0||c.y<0||c.x>=n.design_size.x||c.y>=n.design_size.y) return false; n.blocked_cells.insert(c); }
    }
    return true;
}
bool HardCorePursuitPlanning::owned() const { return owner_==Thread::get_caller_id()&&owner_!=Thread::get_main_id(); }
bool HardCorePursuitPlanning::bind_original_completion_host(const Ref<HardCoreSimulationHost>&host){
    if(!owned()||active_||close_progress_||host.is_null()||host->owner_thread_id()!=int64_t(owner_))return false;
    close_progress_=host->original_worker_close_progress();return bool(close_progress_);
}
bool HardCorePursuitPlanning::configure_owner(int actors,int peers,int workers,int slice,int waves) {
    if (!owned()||configured_||actors<=0||peers<=0||workers<=0||slice<=0||slice>384||waves<=0||!WorkerThreadPool::get_singleton()) return false;
    if (workers>int(WorkerThreadPool::get_singleton()->get_thread_count())) return false;
    max_actors_=actors; max_peers_=peers; worker_cap_=workers; slice_work_=slice; wave_capacity_=waves; configured_=true; return true;
}
Dictionary HardCorePursuitPlanning::capabilities() const {
    Dictionary d; if (!configured_||!owned()) return d;
    for (const char *s:{"immutable_numeric_snapshots","nonblocking_submit","nonblocking_poll","no_S_M_worker_join","bounded_planning_slices","shared_short_geometry_pool","worker_only_numeric","actual_completed_worker_reclamation"}) d[s]=true;
    d["actual_worker_cap"]=worker_cap_; d["slice_work_units"]=slice_work_; d["actual_actor_capacity"]=max_actors_; d["actual_peer_capacity"]=max_peers_; d["actual_wave_capacity"]=wave_capacity_; d["world_predicates_are_preparation_hints"]=true; return d;
}
Dictionary HardCorePursuitPlanning::publish_static_navigation(const Dictionary &values,const Dictionary &predicates,const Dictionary &world,int64_t revision,const Dictionary &admission) {
    Dictionary reply; reply["ok"]=false;
    // A descriptor is admitted only from the actual same-owner Loading source
    // service. Root must verify this source barrier and publication fingerprint;
    // text flags alone never certify the physical lease/writer barrier.
    if (!configured_||!owned()||active_||publication_id_||values.is_empty()||revision<0||admission.get("contract_id",String())!="hardcore.pursuit.actual_loading_admission.v1"||admission.get("source_owner_thread_id",int64_t(0))!=Variant(int64_t(owner_))||admission.get("source_static_sha256",String())!=predicates.get("source_sha256",String())) return reply;
    if (world.get("contract_id",String())!="hardcore.execution.world_context.v1"||predicates.get("contract_id",String())!="hardcore.pursuit.frozen_static_hints.v1"||predicates.get("ok",false)!=Variant(true)) return reply;
    auto frozen=std::make_shared<FrozenWorld>();
    if (!polygons(predicates.get("world_parts_ground_gu",Variant()),frozen->world_parts)||!polygons(predicates.get("safe_zone_polygons_ground_gu",Variant()),frozen->safe_zone_polygons)||predicates.get("safe_zone_circles",Variant()).get_type()!=Variant::ARRAY) return reply;
    Array circles=predicates["safe_zone_circles"];
    for (int i=0;i<circles.size();++i) { if (circles[i].get_type()!=Variant::DICTIONARY) return reply; Dictionary d=circles[i]; Vector2 c; double r; if (!vector2(d,"center_ground_gu",c)||!scalar(d,"radius_gu",r)||r<=0) return reply; frozen->safe_zone_circles.push_back({c,r}); }
    std::map<std::string,std::shared_ptr<const Navigation>> decoded; Array keys=values.keys(),radius_keys; String build;
    for (int i=0;i<keys.size();++i) {
        if (keys[i].get_type()!=Variant::STRING||values[keys[i]].get_type()!=Variant::DICTIONARY) return reply;
        auto n=std::make_shared<Navigation>(); if (!parse_navigation(values[keys[i]],*n)) return reply;
        String k=keys[i]; if (n->polygon && k!=String(n->radius_key.c_str())) return reply;
        if (build.is_empty()) build=String(n->build_sha256.c_str()); else if (build!=String(n->build_sha256.c_str())) return reply;
        decoded[k.utf8().get_data()]=n; radius_keys.push_back(k);
    }
    navigation_=std::move(decoded); static_world_=frozen; world_identity_=world.duplicate(true); ++publication_id_;
    static_descriptor_["contract_id"]="hardcore.pursuit.static_navigation.v1"; static_descriptor_["publication_id"]=int64_t(publication_id_); static_descriptor_["static_revision"]=revision; static_descriptor_["radius_keys"]=radius_keys; static_descriptor_["build_sha256"]=build; static_descriptor_["source_sha256"]=predicates["source_sha256"]; static_descriptor_["world_context"]=world_identity_;
    reply["ok"]=true; reply["descriptor"]=static_descriptor_.duplicate(true); return reply;
}
void HardCorePursuitPlanning::dispatch_wave(const std::shared_ptr<State> &state) {
    std::lock_guard<std::mutex> guard(state->mutex);
    if (state->stop_requested.load(std::memory_order_acquire)) { state->ready_usec=now_usec(); state->ready.store(true,std::memory_order_release); return; }
    // Reclaim older completed groups on the current worker continuation as
    // well as S polls. Otherwise a small wave bound accidentally throttles
    // numeric work to one or two waves per display/process clock period.
    // This current Wave is not completed until its callback returns, so its
    // userdata remains pinned; completed older Waves have no callbacks left.
    for (auto it=state->waves.begin();it!=state->waves.end();) {
        if ((*it)->group==WorkerThreadPool::INVALID_TASK_ID || state->pool->try_reclaim_completed_group_task((*it)->group)) {
            if((*it)->close_debt){state->close_progress->accepted_groups.fetch_sub(1,std::memory_order_acq_rel);state->close_progress->notify();}
            it=state->waves.erase(it);
        } else ++it;
    }
    if (state->waves.size()>=state->wave_capacity) { state->dispatch_pending=true; return; }
    state->dispatch_pending=false;
    auto wave=std::make_unique<Wave>(); wave->state=state;
    for (size_t scanned=0;scanned<state->searches.size()&&wave->actors.size()<state->worker_cap;++scanned) {
        size_t id=state->cursor++%state->searches.size(); if (!state->finished[id]) wave->actors.push_back(id);
    }
    if (wave->actors.empty()) { state->ready_usec=now_usec(); state->ready.store(true,std::memory_order_release); return; }
    Wave *payload=wave.get(); state->waves.push_back(std::move(wave));
    payload->group=state->pool->add_native_group_task(&HardCorePursuitPlanning::worker_slice,payload,int(payload->actors.size()),int(payload->actors.size()),false,"HardCore ordinary pursuit slice");
    if (payload->group==WorkerThreadPool::INVALID_TASK_ID) state->dispatch_failed.store(true,std::memory_order_release);
    else if(state->close_progress){
        state->close_progress->accepted_groups.fetch_add(1,std::memory_order_acq_rel);payload->close_debt=true;
        // State mutex prevents callback completion until registration returns.
        bool registered=state->pool->set_native_group_completion_callback(payload->group,&hardcore::simulation::CloseProgressSignal::formal_group_completed,state->close_progress.get());
        CRASH_COND_MSG(!registered,"Accepted pursuit group completion witness registration failed.");
    }
}
void HardCorePursuitPlanning::worker_slice(void *data,uint32_t index) {
    Wave *wave=static_cast<Wave *>(data); auto state=wave->state; size_t actor=wave->actors[index];
    uint64_t start=now_usec(); maximum(state->maximum_active_workers,state->active_workers.fetch_add(1)+1);
    bool done=state->searches[actor]->advance(state->slice_work);
    state->active_workers.fetch_sub(1); maximum(state->maximum_slice_usec,now_usec()-start);
    // Different slots are updated under the state mutex; vector<bool> is never
    // raced across bits. No gameplay object or Godot Variant enters W.
    { std::lock_guard<std::mutex> guard(state->mutex); state->finished[actor]=done; }
    if (wave->callbacks_done.fetch_add(1,std::memory_order_acq_rel)+1==wave->actors.size()) dispatch_wave(state);
}
Dictionary HardCorePursuitPlanning::submit_planning_batch(const Dictionary &snapshot,int64_t deadline) {
    Dictionary reply; reply["accepted"]=false;
    if (!configured_||!owned()||active_||!publication_id_||deadline<=0||snapshot.get("contract_id",String())!="hardcore.pursuit.planning.snapshot.v1"||snapshot.get("world_context",Variant())!=world_identity_||snapshot.get("static_navigation",Variant())!=static_descriptor_||snapshot.get("actors",Variant()).get_type()!=Variant::ARRAY||snapshot.get("peers",Variant()).get_type()!=Variant::ARRAY) return reply;
    Array actors=snapshot["actors"],peers=snapshot["peers"]; int64_t release,sequence;
    if (!integer(snapshot,"released_usec",release)||!integer(snapshot,"sequence",sequence)||release<=0||sequence<=int64_t(next_sequence_)||deadline<release||actors.is_empty()||actors.size()>max_actors_||peers.size()>max_peers_) return reply;
    auto frozen_peers=std::make_shared<std::vector<Peer>>(); std::set<uint64_t> peer_ids;
    for (int i=0;i<peers.size();++i) {
        if (peers[i].get_type()!=Variant::DICTIONARY) return reply; Dictionary d=peers[i]; Peer p; int64_t id,life,shape;
        if (!integer(d,"runtime_id",id)||!integer(d,"life",life)||!integer(d,"radius_revision",shape)||id<=0||life<=0||shape<=0||!peer_ids.insert(uint64_t(id)).second||!vector2(d,"position",p.position)||!scalar(d,"radius",p.radius)||!scalar(d,"margin",p.margin)||!integer(d,"stable_combat_order",p.stable_order)||p.radius<0||p.margin<0) return reply;
        for (const char *key:{"enemy","damage_eligible","world_collision"}) if (d.get(key,Variant()).get_type()!=Variant::BOOL) return reply;
        p.id=id; p.life=life; p.shape_revision=shape; p.enemy=d["enemy"]; p.damage_eligible=d["damage_eligible"]; p.world_collision=d["world_collision"]; frozen_peers->push_back(p);
    }
    auto state=std::make_shared<State>(); state->pool=WorkerThreadPool::get_singleton();state->close_progress=close_progress_; state->release_usec=release; state->deadline_usec=deadline; state->worker_cap=worker_cap_; state->slice_work=slice_work_; state->wave_capacity=wave_capacity_; std::set<uint64_t> ids;
    for (int i=0;i<actors.size();++i) {
        if (actors[i].get_type()!=Variant::DICTIONARY) return reply; Dictionary d=actors[i]; Actor a; int64_t id,life,target,tlife,shape,order;
        if (!integer(d,"runtime_id",id)||!integer(d,"life",life)||!integer(d,"target_runtime_id",target)||!integer(d,"target_life",tlife)||!integer(d,"radius_revision",shape)||!integer(d,"stable_combat_order",order)||id<=0||life<=0||target<=0||tlife<=0||shape<=0||!ids.insert(id).second||!vector2(d,"position",a.position)||!vector2(d,"historical_target",a.target)||!scalar(d,"radius",a.radius)||!scalar(d,"target_radius",a.target_radius)||!scalar(d,"margin",a.margin)||!scalar(d,"target_margin",a.target_margin)||a.radius<0||a.target_radius<0||a.margin<0||a.target_margin<0||d.get("side_retry_due",Variant()).get_type()!=Variant::BOOL) return reply;
        a.side_retry_due=d["side_retry_due"];
        String key=d.get("navigation_key",String()); auto found=navigation_.find(key.utf8().get_data()); if (found==navigation_.end()||(found->second->polygon&&found->second->radius!=a.radius)) return reply;
        a.id=id; a.life=life; a.target_id=target; a.target_life=tlife; a.shape_revision=shape; a.stable_order=order;
        Variant surround=d.get("source_surround_goal",Variant()); if (surround.get_type()!=Variant::NIL) { if (surround.get_type()!=Variant::VECTOR2||!Vector2(surround).is_finite()) return reply; a.surround_present=true; a.surround=surround; a.surround_slot=int(d.get("source_surround_slot",int64_t(-1))); }
        Variant flank=d.get("source_flank_waypoint",Variant()); if (flank.get_type()!=Variant::NIL) { if (flank.get_type()!=Variant::VECTOR2||!Vector2(flank).is_finite()) return reply; a.flank_present=true; a.flank=flank; }
        if (d.get("source_route",Variant()).get_type()!=Variant::PACKED_VECTOR2_ARRAY) return reply; PackedVector2Array route=d["source_route"]; int64_t route_index; if (!integer(d,"source_route_index",route_index)||route_index<0||route_index>route.size()) return reply; a.route_index=size_t(route_index); for (int j=0;j<route.size();++j) { if (!route[j].is_finite()) return reply; a.retained_route.push_back(route[j]); }
        // Failed edges are copied after the original source time filter. W has
        // no timer/callback; already-expired edges do not enter this buffer.
        if (d.get("active_failed_edges",Variant()).get_type()!=Variant::ARRAY) return reply; Array failed=d["active_failed_edges"];
        for (int j=0;j<failed.size();++j) { if (failed[j].get_type()!=Variant::ARRAY) return reply; Array edge=failed[j]; if (edge.size()!=2||edge[0].get_type()!=Variant::VECTOR2I||edge[1].get_type()!=Variant::VECTOR2I) return reply; a.failed_edges.insert({Vector2i(edge[0]),Vector2i(edge[1])}); }
        state->searches.push_back(std::make_unique<Search>(found->second,static_world_,std::move(a),frozen_peers)); state->finished.push_back(false);
    }
    active_ticket_["contract_id"]="hardcore.pursuit.batch_ticket.v1"; active_ticket_["sequence"]=sequence; active_ticket_["publication_id"]=int64_t(publication_id_); active_ticket_["world_context"]=world_identity_; next_sequence_=sequence; active_=state;
    dispatch_wave(state); reply["accepted"]=true; reply["ticket"]=active_ticket_.duplicate(true); return reply;
}
bool HardCorePursuitPlanning::reclaim_completed_waves() {
    std::unique_lock<std::mutex> guard(active_->mutex,std::try_to_lock); if (!guard.owns_lock()) return false;
    for (auto it=active_->waves.begin();it!=active_->waves.end();) {
        if ((*it)->group==WorkerThreadPool::INVALID_TASK_ID || active_->pool->try_reclaim_completed_group_task((*it)->group)) {
            if((*it)->close_debt){active_->close_progress->accepted_groups.fetch_sub(1,std::memory_order_acq_rel);active_->close_progress->notify();}
            it=active_->waves.erase(it);
        } else ++it;
    }
    bool all=active_->waves.empty(); bool resume=active_->dispatch_pending && active_->waves.size()<active_->wave_capacity;
    guard.unlock(); if (resume) dispatch_wave(active_);
    return all && active_->ready.load(std::memory_order_acquire);
}
Dictionary HardCorePursuitPlanning::poll_planning_batch(const Dictionary &ticket) {
    Dictionary reply; reply["ok"]=false;
    if (!configured_||!owned()||!active_||ticket!=active_ticket_) return reply;
    if (active_->dispatch_failed.load(std::memory_order_acquire)&&!active_->stop_requested.load(std::memory_order_acquire)) { reply["reason"]="actual_worker_dispatch_failed_retained_batch"; return reply; }
    reclaim_completed_waves(); reply["ok"]=true; reply["ready"]=active_->ready.load(std::memory_order_acquire); if (reply["ready"]!=Variant(true)) return reply;
    Array rows; uint64_t checks=0,expansions=0,slices=0;
    for (const auto &search:active_->searches) {
        const Output &o=search->output(); Dictionary row; row["runtime_id"]=int64_t(o.id); row["life"]=int64_t(o.life); row["status"]=String(o.status.c_str()); PackedVector2Array route; for (Vector2 p:o.route) route.push_back(p); row["route"]=route; row["surround_goal"]=o.surround_present?Variant(o.surround):Variant(); row["surround_slot"]=o.surround_slot; row["flank_waypoint"]=o.flank_present?Variant(o.flank):Variant(); row["expansions"]=int64_t(o.expansions); row["slices"]=int64_t(o.slices); row["numeric_checks"]=int64_t(o.numeric_checks); rows.push_back(row); checks+=o.numeric_checks; expansions+=o.expansions; slices+=o.slices;
    }
    Dictionary receipt; receipt["actual_worker_cap"]=worker_cap_; receipt["observed_maximum_active_workers"]=int64_t(active_->maximum_active_workers.load()); receipt["maximum_slice_usec"]=int64_t(active_->maximum_slice_usec.load()); receipt["numeric_checks"]=int64_t(checks); receipt["path_expansions"]=int64_t(expansions); receipt["slices"]=int64_t(slices); receipt["S_worker_joins"]=0; receipt["M_worker_joins"]=0; receipt["required_rows"]=int64_t(active_->searches.size());
    reply["ticket"]=active_ticket_.duplicate(true); reply["rows"]=rows; reply["all_ready_usec"]=int64_t(active_->ready_usec); reply["receipt"]=receipt; return reply;
}
bool HardCorePursuitPlanning::retire_planning_batch(const Dictionary &ticket) {
    if (!configured_||!owned()||!active_||ticket!=active_ticket_||!active_->ready.load(std::memory_order_acquire)||!reclaim_completed_waves()) return false;
    // Every callback returned before its group's completed flag. Reclaim has
    // consumed only the actual pool's one consumer user; worker tail refs are
    // left to the original pool. No callback uses Wave userdata now.
    active_->waves.clear(); active_.reset(); active_ticket_.clear(); return true;
}
bool HardCorePursuitPlanning::cancel_planning_batch(const Dictionary &ticket) {
    if (!configured_||!owned()||!active_||ticket!=active_ticket_) return false;
    active_->stop_requested.store(true,std::memory_order_release);
    // No further numeric preparation is submitted. In-flight source slices
    // still return normally and every actual pool group is reclaimed.
    std::unique_lock<std::mutex> guard(active_->mutex,std::try_to_lock);
    if (guard.owns_lock() && (active_->dispatch_pending || active_->dispatch_failed.load())) {
        active_->dispatch_pending=false;
        active_->ready_usec=now_usec(); active_->ready.store(true,std::memory_order_release);
    }
    return true;
}
bool HardCorePursuitPlanning::has_pending_planning_batches() const { return !owned()||bool(active_); }
bool HardCorePursuitPlanning::close_owner() { if (!configured_||!owned()||active_) return false; navigation_.clear(); static_world_.reset(); static_descriptor_.clear(); world_identity_.clear(); configured_=false; return true; }
HardCorePursuitPlanning::~HardCorePursuitPlanning() {
    // The S world/session lifetime must retain this object until close succeeds.
    // Wave payloads pin State after an invalid destruction, preventing worker
    // UAF without joining hot S/M. This misuse is a fault and is not certified
    // successful retirement; Root fault cleanup must keep the owner alive.
    if (active_) ERR_PRINT("HardCorePursuitPlanning destroyed with unreclaimed accepted work");
}
void HardCorePursuitPlanning::_bind_methods() {
    ClassDB::bind_method(D_METHOD("owner_thread_id"),&HardCorePursuitPlanning::owner_thread_id);
    ClassDB::bind_method(D_METHOD("bind_original_completion_host","host"),&HardCorePursuitPlanning::bind_original_completion_host);
    ClassDB::bind_method(D_METHOD("configure_owner","max_actors","max_peers","worker_cap","slice_work","wave_capacity"),&HardCorePursuitPlanning::configure_owner);
    ClassDB::bind_method(D_METHOD("capabilities"),&HardCorePursuitPlanning::capabilities);
    ClassDB::bind_method(D_METHOD("publish_static_navigation","values","predicates","world","revision","loading_admission"),&HardCorePursuitPlanning::publish_static_navigation);
    ClassDB::bind_method(D_METHOD("submit_planning_batch","snapshot","deadline_usec"),&HardCorePursuitPlanning::submit_planning_batch);
    ClassDB::bind_method(D_METHOD("poll_planning_batch","ticket"),&HardCorePursuitPlanning::poll_planning_batch);
    ClassDB::bind_method(D_METHOD("retire_planning_batch","ticket"),&HardCorePursuitPlanning::retire_planning_batch);
    ClassDB::bind_method(D_METHOD("cancel_planning_batch","ticket"),&HardCorePursuitPlanning::cancel_planning_batch);
    ClassDB::bind_method(D_METHOD("has_pending_planning_batches"),&HardCorePursuitPlanning::has_pending_planning_batches);
    ClassDB::bind_method(D_METHOD("close_owner"),&HardCorePursuitPlanning::close_owner);
}
