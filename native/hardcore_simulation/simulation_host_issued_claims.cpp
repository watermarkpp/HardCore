#include "simulation_host.h"
#include "core/config/engine.h"
#include "content_value_graph.h"
#include "core/io/marshalls.h"
#include "scene/main/node.h"
#include <cmath>

using ClaimBox=hardcore::simulation::SourceEventReplyMailbox;
namespace {
constexpr const char*FEATURE_PATH="res://scripts/features/runtime/feature_resource_main_primitives.gd";
constexpr const char*ORIGIN_PATH="res://scripts/gameplay/source/main_source_closing_io_producer.gd";
constexpr const char*SOURCE_PATH="res://scripts/features/runtime/feature_resource_owner_coordinator.gd";
constexpr const char*SESSION_PATH="res://scripts/gameplay/source/source_session.gd";
constexpr const char*WARM_PATH="res://scripts/gameplay/world/world_caster_warm_main.gd";
// This attachment is pinned to the reviewed immutable Gd overlay. Rebase these
// only with a new exact source manifest and actual semantic review.
constexpr const char*FEATURE_SHA="e6ed41a4444084e8892818c68adb96a3c5895559774d88b7b210b41461d509e6";
constexpr const char*ORIGIN_SHA="8884d1b1ebe232f10605cdea0eced15b686244c45f677ebfb59fd078387bfae1";
constexpr const char*SOURCE_SHA="6ba6941921d31088d12ad4233697336ec839ea65c79f307b4c69d38de8bc9efa";
constexpr const char*WARM_SHA="5cae0c8d8e39d93fa5230bd9ca2543b43512acbecafa13c41f27e36cc9fff65c";
constexpr const char*WARM_PORT_SHA="148c2e8d4c3e7dc8ccac844426e37014022a1304b2e9fe2185f0cad9b733a3d5";
bool ci(const Dictionary&d,const char*k,int64_t&n){if(!d.has(k)||d[k].get_type()!=Variant::INT)return false;n=d[k];return true;}
bool cs(const Variant&v){return v.get_type()==Variant::STRING||v.get_type()==Variant::STRING_NAME;}
bool cd(const Variant&v,Dictionary&d){if(v.get_type()!=Variant::DICTIONARY)return false;d=v;return true;}
bool cid(const Dictionary&d,ClaimBox::TransferIdentity&id){
 if(d.size()!=4)return false;int64_t n[4]={};const char*k[]={"bridge_generation","journal_generation","event_ordinal","transfer_sequence"};for(int j=0;j<4;++j)if(!ci(d,k[j],n[j])||n[j]<=0)return false;id={{uint64_t(n[0]),uint64_t(n[1]),uint64_t(n[2])},uint64_t(n[3])};return true;
}
Dictionary cid(const ClaimBox::TransferIdentity&id){Dictionary d;d["bridge_generation"]=int64_t(id.parent.generation);d["journal_generation"]=int64_t(id.parent.journal);d["event_ordinal"]=int64_t(id.parent.ordinal);d["transfer_sequence"]=int64_t(id.transfer);return d;}
String ckey(const ClaimBox::TransferIdentity&id){return String::num_uint64(id.parent.generation)+":"+String::num_uint64(id.parent.journal)+":"+String::num_uint64(id.parent.ordinal)+":"+String::num_uint64(id.transfer);}
ClaimBox::Bytes cfreeze(const Variant&v){HardCoreContentValueGraph graph;if(graph.validate(v,false).get("success",Variant())!=Variant(true))return {};int n=0;if(encode_variant(v,nullptr,n,false)!=OK||n<=0)return {};auto b=std::make_shared<std::vector<uint8_t>>(n);if(encode_variant(v,b->data(),n,false)!=OK)return {};return b;}
bool cthaw(const ClaimBox::Bytes&b,Dictionary&d){if(!b||b->empty()||b->size()>INT32_MAX)return false;Variant v;int n=0;if(decode_variant(v,b->data(),int(b->size()),&n,false)!=OK||n!=int(b->size())||v.get_type()!=Variant::DICTIONARY)return false;d=v;return true;}
Dictionary cstatus(ClaimBox::Status s){Dictionary d;d["status"]=s==ClaimBox::Status::READY?"OK":s==ClaimBox::Status::PENDING?"BUSY":s==ClaimBox::Status::BACKPRESSURE?"BACKPRESSURE":"INVALID";return d;}
Object*cobject(const Variant&v){return v.get_type()==Variant::OBJECT?static_cast<Object*>(v):nullptr;}
bool cobservation(const Dictionary&d,uint64_t generation,int64_t epoch){
 int64_t g=0,e=0,status=0,start=0,end=0;return d.size()==8&&d.get("ok",Variant())==Variant(true)&&ci(d,"bridge_generation",g)&&g==int64_t(generation)&&ci(d,"observation_process_epoch",e)&&e==epoch&&ci(d,"status",status)&&status>=0&&status<=3&&ci(d,"actual_start_usec",start)&&start>0&&ci(d,"actual_end_usec",end)&&end>=start&&d.has("progress")&&d["progress"].get_type()==Variant::FLOAT&&std::isfinite(double(d["progress"]))&&d.has("progress_ensured")&&d["progress_ensured"].get_type()==Variant::BOOL;
}
bool cqueue(const Dictionary&d,const Dictionary&identity,const Dictionary&evidence,uint64_t source,uint64_t session,ClaimBox::ClaimQueue&q){
 int64_t entry=0,location=0,count=0,remaining=0,owner=0,sid=0;
 if(d.size()!=10||d.get("success",Variant())!=Variant(true)||d.get("identity",Variant())!=Variant(identity)||d.get("path",Variant())!=evidence.get("path",Variant())||!ci(d,"original_entry_id",entry)||entry<0||!ci(d,"current_queue_location",location)||!ci(d,"claim_count",count)||count<=0||d["claim_count"]!=evidence["claim_count"]||!ci(d,"remaining_count",remaining)||remaining<0||remaining>count||!ci(d,"owner_session_id",sid)||sid!=int64_t(session)||!ci(d,"actual_source_owner_id",owner)||uint64_t(owner)!=source)return false;
 Variant insertion=d.get("insertion",Variant());q.insertion=insertion==Variant("EXACT")?ClaimBox::Insertion::EXACT:insertion==Variant("REMOVED")?ClaimBox::Insertion::REMOVED:ClaimBox::Insertion::UNKNOWN;q.entry=entry;q.location=location;q.count=count;q.remaining=remaining;q.session=sid;q.owner=uint64_t(owner);return q.insertion!=ClaimBox::Insertion::UNKNOWN;
}
}

bool HardCoreSimulationHost::issued_binding_valid(const IssuedClaimBinding&b)const{
 if(!b.object||Thread::get_caller_id()!=b.thread)return false;Object*o=ObjectDB::get_instance(ObjectID(b.object));if(!o||reinterpret_cast<uintptr_t>(o->get_script_instance())!=b.instance)return false;
 Ref<Script>s=o->get_script();return s.is_valid()&&uint64_t(s->get_instance_id())==b.script&&s->is_valid()&&s->get_source_code()==b.source;
 // Godot String is immutable COW: unchanged source returns the same storage.
 // Exact source comparison also invalidates in-place set_source_code, which
 // Godot 4.7 does not emit as a Resource::changed signal. No per-claim SHA/scan.
}
bool HardCoreSimulationHost::bind_original_main_feature_claim_producer(const Ref<RefCounted>&p,const String&sha){
 if(!Thread::is_main_thread()||issued_main_feature.is_valid()||p.is_null()||!caster_event_replies)return false;Ref<Script>s=p->get_script();
 if(s.is_null()||s->get_path()!=FEATURE_PATH||sha!=FEATURE_SHA||s->get_source_code().sha256_text()!=sha||!p->has_method(SNAME("verify_original_main_issued_claim_offer")))return false;
 issued_main_feature=p;issued_feature_binding={uint64_t(p->get_instance_id()),uint64_t(s->get_instance_id()),reinterpret_cast<uintptr_t>(p->get_script_instance()),Thread::get_caller_id(),s->get_source_code(),sha};return true;
}
bool HardCoreSimulationHost::bind_original_main_warm_claim_origin_producer(const Ref<RefCounted>&p,const String&sha){
 if(!Thread::is_main_thread()||issued_main_origin.is_valid()||p.is_null()||!caster_event_replies||!issued_binding_valid(issued_feature_binding))return false;Ref<Script>s=p->get_script();
 if(s.is_null()||s->get_path()!=ORIGIN_PATH||sha!=ORIGIN_SHA||s->get_source_code().sha256_text()!=sha||cobject(p->get("_host"))!=this||cobject(p->get("_feature"))!=issued_main_feature.ptr()||!p->has_method(SNAME("verify_original_warm_claim_offer_origin"))||!p->has_method(SNAME("verify_original_warm_claim_origin_released")))return false;
 issued_main_origin=p;issued_origin_binding={uint64_t(p->get_instance_id()),uint64_t(s->get_instance_id()),reinterpret_cast<uintptr_t>(p->get_script_instance()),Thread::get_caller_id(),s->get_source_code(),sha};return true;
}
bool HardCoreSimulationHost::bind_original_source_feature_claim_owner(const Ref<RefCounted>&p,const String&sha){
 if(!is_owner()||issued_source_binding.object||p.is_null()||!caster_event_replies)return false;Ref<Script>s=p->get_script();Object*budget=cobject(p->get("Budget")),*primitives=cobject(p->get("_primitives"));
 if(s.is_null()||s->get_path()!=SOURCE_PATH||sha!=SOURCE_SHA||s->get_source_code().sha256_text()!=sha||!budget||!primitives||cobject(primitives->get("_budget"))!=budget||p->call(SNAME("owner_thread_id"))!=Variant(int64_t(Thread::get_caller_id()))||budget->call(SNAME("owner_thread_id"))!=Variant(int64_t(Thread::get_caller_id())))return false;
 Variant gate=budget->get("_cold_gate");if(gate.get_type()!=Variant::CALLABLE)return false;Callable actual_gate=gate;Object*session=actual_gate.get_object();Ref<Script>ss=session?session->get_script():Variant();
 if(!session||ss.is_null()||ss->get_path()!=SESSION_PATH||cobject(session->get("_host"))!=this||cobject(session->get("_budget"))!=budget||session->call(SNAME("owner_thread_id"))!=Variant(int64_t(Thread::get_caller_id())))return false;
 Dictionary feature;if(!cd(session->get("_feature"),feature)||cobject(feature.get("coordinator",Variant()))!=p.ptr())return false;int64_t session_id=0;Dictionary value;value["id"]=session->get("_id");if(!ci(value,"id",session_id)||session_id<=0||budget->get("_session_id")!=Variant(session_id))return false;
 issued_source_binding={uint64_t(p->get_instance_id()),uint64_t(s->get_instance_id()),reinterpret_cast<uintptr_t>(p->get_script_instance()),Thread::get_caller_id(),s->get_source_code(),sha};
 issued_session_binding={uint64_t(session->get_instance_id()),uint64_t(ss->get_instance_id()),reinterpret_cast<uintptr_t>(session->get_script_instance()),Thread::get_caller_id(),ss->get_source_code(),ss->get_source_code().sha256_text()};issued_source_budget=uint64_t(budget->get_instance_id());issued_source_session=uint64_t(session_id);
 // Source pins remain in the original Session. This Host stores identities,
 // never a Source Ref that its Main-owned destructor would release.
 return true;
}

Dictionary HardCoreSimulationHost::issued_claim_result(const ClaimBox::TransferRead&r)const{
 Dictionary out=cstatus(r.status);if(r.status!=ClaimBox::Status::READY||!r.evidence)return out;Dictionary evidence;if(!cthaw(r.evidence,evidence))return cstatus(ClaimBox::Status::INVALID);
 out["identity"]=cid(r.identity);out["evidence"]=evidence;out["state"]=r.state==ClaimBox::TransferState::OFFERED?"OFFERED":r.state==ClaimBox::TransferState::ACCEPTED?"ACCEPTED":r.state==ClaimBox::TransferState::ORIGIN_RELEASED?"ORIGIN_RELEASED":"TERMINAL";
 if(r.state!=ClaimBox::TransferState::OFFERED){Dictionary ack;if(!cthaw(r.acceptance,ack))return cstatus(ClaimBox::Status::INVALID);out["acceptance_receipt"]=ack;}
 if(r.state==ClaimBox::TransferState::TERMINAL){Array facts;for(const auto&b:r.facts){Dictionary f;if(!cthaw(b,f))return cstatus(ClaimBox::Status::INVALID);facts.push_back(f);}Dictionary t;t["contract_id"]="hardcore.caster.issued_claim.terminal.v1";t["identity"]=cid(r.identity);t["original_entry_id"]=int64_t(r.entry);t["claim_count"]=int64_t(r.count);t["physical_facts"]=facts;t["actual_origin_released"]=true;t["exact_queue_removed"]=r.queue_removed;t["physical_leaves_in_flight"]=r.in_flight?1:0;out["terminal_receipt"]=t;}return out;
}

Dictionary HardCoreSimulationHost::offer_claim_transfer(const Dictionary&i,const Dictionary&e){
 if(!Thread::is_main_thread()||!caster_event_replies)return cstatus(ClaimBox::Status::INVALID);
 // An attachment admitted before a refused observation must never later return
 // INVALID as if no new Main bookkeeping had been admitted. A changed producer
 // invalidates progression while the original responsibility remains frozen.
 ClaimBox::TransferIdentity existing_id;if(cid(i,existing_id)){auto existing=caster_event_replies->inspect_transfer(existing_id);if(existing.status==ClaimBox::Status::READY){auto bytes=cfreeze(e);if(!bytes||*existing.evidence!=*bytes)return cstatus(ClaimBox::Status::INVALID);auto out=issued_claim_result(existing);if(!issued_binding_valid(issued_feature_binding)||!issued_binding_valid(issued_origin_binding)){out["status"]="BUSY";out["error"]="issued_claim_producer_changed_retained_debt";}return out;}if(existing.status==ClaimBox::Status::PENDING)return cstatus(existing.status);}
 if(!issued_binding_valid(issued_feature_binding)||!issued_binding_valid(issued_origin_binding))return cstatus(ClaimBox::Status::INVALID);
 ClaimBox::TransferIdentity id;int64_t count=0,root_id=0,content_id=0,helper_id=0,feature_id=0,frame=0;if(!cid(i,id)||id.parent.generation!=bridge_generation||e.size()!=11||e.get("contract_id",Variant())!=Variant("hardcore.caster.issued_claim.offer.v1")||e.get("identity",Variant())!=Variant(i)||!e.has("path")||e["path"].get_type()!=Variant::STRING||String(e["path"]).is_empty()||!ci(e,"claim_count",count)||count<=0||!ci(e,"actual_main_root_id",root_id)||root_id<=0||!ci(e,"actual_content_id",content_id)||content_id<=0||!ci(e,"actual_helper_id",helper_id)||!helper_id||!ci(e,"actual_feature_main_id",feature_id)||uint64_t(feature_id)!=issued_feature_binding.object||!ci(e,"actual_Main_process_frame",frame)||frame<0)return cstatus(ClaimBox::Status::INVALID);
 auto immutable=cfreeze(e);if(!immutable)return cstatus(ClaimBox::Status::INVALID);auto old=caster_event_replies->inspect_transfer(id);
 if(old.status==ClaimBox::Status::READY){if(*old.evidence!=*immutable)return cstatus(ClaimBox::Status::INVALID);return issued_claim_result(old);}if(old.status==ClaimBox::Status::PENDING)return cstatus(old.status);
 auto parent=caster_event_replies->inspect_main(id.parent);Dictionary event;if(parent.status!=ClaimBox::Status::READY||!cthaw(parent.event,event))return cstatus(parent.status==ClaimBox::Status::PENDING?parent.status:ClaimBox::Status::INVALID);
 Variant args=event.get("arguments",Variant());if(args.get_type()!=Variant::ARRAY||Array(args).size()!=1||Array(args)[0].get_type()!=Variant::DICTIONARY)return cstatus(ClaimBox::Status::INVALID);Dictionary command=Array(args)[0],payload,descriptor,observation;
 int64_t source_frame=0,session=0,source_root=0,executor=0;if(command.get("operation",Variant())!=Variant("source_caster_warm::loading_claim_retire")||!cd(command.get("payload",Variant()),payload)||!cd(e.get("owner_descriptor",Variant()),descriptor)||descriptor.size()!=5||descriptor.get("contract_id",Variant())!=Variant("source.caster.warm.owner.v1")||!ci(descriptor,"owner_session_id",session)||session<=0||!ci(descriptor,"source_root_id",source_root)||!source_root||!ci(descriptor,"main_executor_id",executor)||!executor||descriptor.get("world_context",Variant())!=command.get("world_context",Variant())||payload.get("source_root_id",Variant())!=Variant(source_root)||command.get("main_executor_id",Variant())!=Variant(executor)||!ci(payload,"source_process_frame",source_frame)||!cd(e.get("loader_observation",Variant()),observation)||!cobservation(observation,bridge_generation,source_frame)||int64_t(observation["actual_end_usec"])>int64_t(now_usec()))return cstatus(ClaimBox::Status::INVALID);
 Dictionary reservation;if(!cd(payload.get("reservation",Variant()),reservation)||reservation.get("owner_session_id",Variant())!=Variant(session))return cstatus(ClaimBox::Status::INVALID);
 Object*helper=ObjectDB::get_instance(ObjectID(uint64_t(helper_id)));Node*root=Object::cast_to<Node>(ObjectDB::get_instance(ObjectID(uint64_t(root_id))));Node*content=Object::cast_to<Node>(ObjectDB::get_instance(ObjectID(uint64_t(content_id))));Object*observer=cobject(issued_main_origin->get("_observer"));
 if(!helper||!Object::cast_to<RefCounted>(helper)||!root||!content||!root->is_inside_tree()||!content->is_inside_tree()||!observer||!observer->is_class("HardCoreResourceObservation")||cobject(issued_main_origin->get("_content"))!=content||cobject(helper->get("_content"))!=content||helper->get("_owner_descriptor")!=Variant(descriptor)||helper->get("_original_main_root_id")!=Variant(root_id))return cstatus(ClaimBox::Status::INVALID);
 Ref<Script>content_script=content->get_script();if(content_script.is_null()||content_script->get_path()!=String("res://scripts/layers/runtime/content_layer_registry.gd"))return cstatus(ClaimBox::Status::INVALID);
 Dictionary bound,row;if(!cd(issued_main_origin->get("_bound"),bound)||!cd(bound.get(helper_id,Variant()),row)||cobject(row.get("helper",Variant()))!=helper||row.get("descriptor",Variant())!=Variant(descriptor)||row.get("sha256",Variant())!=Variant(WARM_SHA))return cstatus(ClaimBox::Status::INVALID);
 auto found=issued_helper_bindings.find(uint64_t(helper_id));if(found==issued_helper_bindings.end()){if(issued_helper_bindings.size()>=caster_event_replies->attached_record_capacity())return cstatus(ClaimBox::Status::BACKPRESSURE);Ref<Script>s=helper->get_script();if(s.is_null()||s->get_path()!=WARM_PATH||s->get_source_code().sha256_text()!=WARM_SHA)return cstatus(ClaimBox::Status::INVALID);IssuedClaimBinding b{uint64_t(helper_id),uint64_t(s->get_instance_id()),reinterpret_cast<uintptr_t>(helper->get_script_instance()),Thread::get_caller_id(),s->get_source_code(),WARM_SHA};found=issued_helper_bindings.emplace(uint64_t(helper_id),b).first;}if(!issued_binding_valid(found->second))return cstatus(ClaimBox::Status::INVALID);
 Dictionary parent_identity=i.duplicate(true);parent_identity.erase("transfer_sequence");if(helper->get("_active_ticket")!=Variant(parent_identity))return cstatus(ClaimBox::Status::INVALID);
 Dictionary origin_proof,physical_proof;if(!cd(issued_main_origin->call(SNAME("verify_original_warm_claim_offer_origin"),i,e),origin_proof)||origin_proof.get("success",Variant())!=Variant(true)||origin_proof.get("identity",Variant())!=Variant(i)||origin_proof.get("evidence",Variant())!=Variant(e)||!cd(issued_main_feature->call(SNAME("verify_original_main_issued_claim_offer"),i,e),physical_proof)||physical_proof.size()!=5||physical_proof.get("success",Variant())!=Variant(true)||physical_proof.get("identity",Variant())!=Variant(i)||physical_proof.get("evidence",Variant())!=Variant(e)||physical_proof.get("actual_feature_main_id",Variant())!=Variant(feature_id)||physical_proof.get("physical_remaining",Variant())!=Variant(count))return cstatus(ClaimBox::Status::INVALID);
 auto status=caster_event_replies->offer_transfer(id,immutable,uint64_t(count));if(status!=ClaimBox::Status::READY)return cstatus(status);close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();auto observed=caster_event_replies->inspect_transfer(id);
 if(observed.status==ClaimBox::Status::PENDING){Dictionary retained=cstatus(ClaimBox::Status::PENDING);retained["state"]="OFFERED";retained["identity"]=i;retained["evidence"]=e;return retained;}return issued_claim_result(observed);
}

Dictionary HardCoreSimulationHost::accept_claim_transfer(const Dictionary&i){
 if(!is_owner()||!caster_event_replies||!issued_binding_valid(issued_source_binding)||!issued_binding_valid(issued_session_binding))return cstatus(ClaimBox::Status::INVALID);ClaimBox::TransferIdentity id;if(!cid(i,id)||id.parent.generation!=bridge_generation)return cstatus(ClaimBox::Status::INVALID);
 bool ordinary=!closing_session&&current_epoch>0&&current_phase==Clock::Phase::P_GROUP;bool closing=closing_session&&current_phase_name==SNAME("P_CLOSE_SERVICE")&&original_source_boundary==SNAME("NODE_PROCESS_SERVICE");if(!ordinary&&!closing)return cstatus(ClaimBox::Status::INVALID);
 Object*source=ObjectDB::get_instance(ObjectID(issued_source_binding.object)),*session=ObjectDB::get_instance(ObjectID(issued_session_binding.object));Object*budget=source?cobject(source->get("Budget")):nullptr;Object*primitives=source?cobject(source->get("_primitives")):nullptr;
 if(!session||!budget||!primitives||uint64_t(budget->get_instance_id())!=issued_source_budget||cobject(primitives->get("_budget"))!=budget||cobject(session->get("_host"))!=this||session->get("_id")!=Variant(int64_t(issued_source_session))||session->get("_budget")!=Variant(budget))return cstatus(ClaimBox::Status::INVALID);
 auto inspected=caster_event_replies->inspect_transfer(id);Dictionary evidence,descriptor;if(inspected.status!=ClaimBox::Status::READY)return cstatus(inspected.status);if(!cthaw(inspected.evidence,evidence)||!cd(evidence.get("owner_descriptor",Variant()),descriptor)||descriptor.get("owner_session_id",Variant())!=Variant(int64_t(issued_source_session)))return cstatus(ClaimBox::Status::INVALID);
 if(inspected.state==ClaimBox::TransferState::TERMINAL)return issued_claim_result(inspected);
 if(inspected.state==ClaimBox::TransferState::OFFERED){
  int64_t source_root_id=0;if(!ci(descriptor,"source_root_id",source_root_id)||!source_root_id)return cstatus(ClaimBox::Status::INVALID);Object*root=ObjectDB::get_instance(ObjectID(uint64_t(source_root_id)));Object*ports=root?cobject(root->get("_ports")):nullptr;Object*caster=ports?cobject(ports->call(SNAME("required_owner_service"),SNAME("CasterPresentation"))):nullptr;Object*warm=caster?cobject(caster->get("_warm_consumer")):nullptr;
  if(!root||!warm||cobject(warm->get("_root"))!=root||cobject(warm->get("_caster"))!=caster||cobject(warm->get("_host"))!=this||cobject(warm->get("_budget"))!=budget||warm->get("_owner_descriptor")!=Variant(descriptor))return cstatus(ClaimBox::Status::INVALID);
  auto found=issued_warm_bindings.find(uint64_t(warm->get_instance_id()));if(found==issued_warm_bindings.end()){
   // Lifetime cache pruning occurs only for a new actual Warm owner, never a
   // per-claim hash or scan of the resource retirement FIFO.
   for(auto it=issued_warm_bindings.begin();it!=issued_warm_bindings.end();){Object*old=ObjectDB::get_instance(ObjectID(it->first));if(!old||cobject(old->get("_host"))!=this)it=issued_warm_bindings.erase(it);else ++it;}
   if(issued_warm_bindings.size()>=caster_event_replies->attached_record_capacity())return cstatus(ClaimBox::Status::BACKPRESSURE);Ref<Script>s=warm->get_script();if(s.is_null()||s->get_path()!=String("res://scripts/gameplay/world/world_caster_warm_port.gd")||s->get_source_code().sha256_text()!=WARM_PORT_SHA)return cstatus(ClaimBox::Status::INVALID);IssuedClaimBinding b{uint64_t(warm->get_instance_id()),uint64_t(s->get_instance_id()),reinterpret_cast<uintptr_t>(warm->get_script_instance()),Thread::get_caller_id(),s->get_source_code(),WARM_PORT_SHA};found=issued_warm_bindings.emplace(uint64_t(warm->get_instance_id()),b).first;
  }
  if(!issued_binding_valid(found->second))return cstatus(ClaimBox::Status::INVALID);
  if(warm->get("_commit_open")!=Variant(true)||warm->get("_commit_source_p")!=Variant(int64_t(source_process_frame.load(std::memory_order_acquire))))return cstatus(ClaimBox::Status::PENDING);
  Dictionary job;if(!cd(warm->get("_job"),job))return cstatus(ClaimBox::Status::INVALID);Dictionary parent=i.duplicate(true);parent.erase("transfer_sequence");if(job.get("ticket",Variant())!=Variant(parent))return cstatus(ClaimBox::Status::INVALID);
 }
 auto transaction=caster_event_replies->begin_transfer_accept(id);if(transaction.status!=ClaimBox::Status::READY)return cstatus(transaction.status);
 if(transaction.state==ClaimBox::TransferState::OFFERED){
  // No cross-thread mutex is held during these two arbitrary Script calls.
  Dictionary admission;bool admission_returned=false;if(transaction.admit)admission_returned=cd(source->call(SNAME("admit_original_issued_claim_responsibility"),i,evidence),admission);
  Dictionary exact;ClaimBox::ClaimQueue queue;Variant captured=source->call(SNAME("capture_original_issued_claim_queue_state"),i);bool valid=cd(captured,exact)&&cqueue(exact,i,evidence,issued_source_binding.object,issued_source_session,queue);
  if(!issued_binding_valid(issued_source_binding)||!issued_binding_valid(issued_session_binding))valid=false;
  if(!valid){queue={};if(transaction.admit&&admission_returned&&admission.get("success",Variant())==Variant(false)&&admission.get("insertion",Variant())==Variant("NONE")&&exact.get("insertion",Variant())==Variant("NONE"))queue.insertion=ClaimBox::Insertion::NONE;}
  auto status=caster_event_replies->finish_transfer_accept(id,queue,valid?cfreeze(exact):ClaimBox::Bytes{});if(status!=ClaimBox::Status::READY){if(status==ClaimBox::Status::INVALID)set_fault("issued_claim_original_insertion_unknown_retained_debt");return cstatus(status);}
 }else{
  Dictionary exact;ClaimBox::ClaimQueue queue;
  if(!cd(source->call(SNAME("capture_original_issued_claim_queue_state"),i),exact)||!cqueue(exact,i,evidence,issued_source_binding.object,issued_source_session,queue)){set_fault("issued_claim_exact_original_queue_state_rejected");return cstatus(ClaimBox::Status::INVALID);}
  if(queue.remaining!=inspected.count-inspected.terminal_count){
   // Main may have consumed a physical ordinal whose exact accepted LIVE
   // reply has not reached the S suffix. This exception requires that slot,
   // its Native-sealed pre-consumption range, and that slot's actual fact.
   Dictionary live_identity;int64_t g=0,op=0;
   if(!live_resources||!cd(source->call(SNAME("capture_original_issued_claim_live_leaf"),i),live_identity)||live_identity.size()!=2||!ci(live_identity,"bridge_generation",g)||uint64_t(g)!=bridge_generation||!ci(live_identity,"op_sequence",op)||op<=0)return cstatus(ClaimBox::Status::INVALID);
   auto live=live_resources->lookup({uint64_t(g),uint64_t(op)});Dictionary context;
   if(!live.ready||!cthaw(live.request.issued_claim_context,context)||context.get("identity",Variant())!=Variant(i)||context.get("original_entry_id",Variant())!=Variant(int64_t(queue.entry))||context.get("remaining_count",Variant())!=Variant(int64_t(queue.remaining))||queue.insertion!=ClaimBox::Insertion::EXACT||queue.location<0)return cstatus(ClaimBox::Status::INVALID);
   int64_t first=0;if(!ci(context,"original_first_claim_ordinal",first)||first<0||uint64_t(first)>=inspected.terminal_count)return cstatus(ClaimBox::Status::INVALID);
   bool proved=false;for(const auto&bytes:inspected.facts){Dictionary fact,identity;if(cthaw(bytes,fact)&&cd(fact.get("operation_identity",Variant()),identity)&&identity==live_identity&&fact.get("original_first_claim_ordinal",Variant())==Variant(first)&&fact.get("claim_count",Variant())==Variant(int64_t(inspected.terminal_count)-first)&&fact.get("identity",Variant())==Variant(i))proved=true;}
   if(!proved)return cstatus(ClaimBox::Status::INVALID);
   Dictionary held=issued_claim_result(inspected);held["range_commit_status"]="PENDING";return held;
  }
  if(caster_event_replies->observe_transfer_queue(id,queue)!=ClaimBox::Status::READY){set_fault("issued_claim_exact_original_queue_state_rejected");return cstatus(ClaimBox::Status::INVALID);}
 }
 close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return issued_claim_result(caster_event_replies->inspect_transfer(id));
}

Dictionary HardCoreSimulationHost::confirm_origin_released(const Dictionary&i){
 if(!Thread::is_main_thread()||!caster_event_replies||!issued_binding_valid(issued_origin_binding))return cstatus(ClaimBox::Status::INVALID);ClaimBox::TransferIdentity id;if(!cid(i,id))return cstatus(ClaimBox::Status::INVALID);auto record=caster_event_replies->inspect_transfer(id);if(record.status!=ClaimBox::Status::READY||record.state==ClaimBox::TransferState::OFFERED)return cstatus(record.status==ClaimBox::Status::PENDING?record.status:ClaimBox::Status::INVALID);
 if(record.state==ClaimBox::TransferState::ORIGIN_RELEASED||record.state==ClaimBox::TransferState::TERMINAL)return issued_claim_result(record);Dictionary evidence,proof;if(!cthaw(record.evidence,evidence)||!cd(issued_main_origin->call(SNAME("verify_original_warm_claim_origin_released"),i,evidence),proof)||proof.get("success",Variant())!=Variant(true)||proof.get("identity",Variant())!=Variant(i)||proof.get("evidence",Variant())!=Variant(evidence))return cstatus(ClaimBox::Status::INVALID);
 auto status=caster_event_replies->release_transfer_origin(id);if(status!=ClaimBox::Status::READY)return cstatus(status);close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return issued_claim_result(caster_event_replies->inspect_transfer(id));
}

// Capture only on S while the original FIFO row is selected. No claim is
// marked in-flight until Main actually owns the admitted LIVE execution slot.
ClaimBox::Status HardCoreSimulationHost::capture_issued_live_context(const Dictionary&request,Dictionary&context){
 if(!is_owner()||!caster_event_replies||request.has("native_issued_claim_responsibility")||request.has("native_issued_claim_status_observation"))return ClaimBox::Status::INVALID;
 context={};if(!issued_source_binding.object)return ClaimBox::Status::READY;
 if(!issued_binding_valid(issued_source_binding)||!issued_binding_valid(issued_session_binding))return ClaimBox::Status::INVALID;
 Object*source=ObjectDB::get_instance(ObjectID(issued_source_binding.object));Object*session=ObjectDB::get_instance(ObjectID(issued_session_binding.object));
 if(!source||!session||cobject(source->get("Budget"))!=cobject(session->get("_budget"))||cobject(session->get("_host"))!=this||session->get("_id")!=Variant(int64_t(issued_source_session)))return ClaimBox::Status::INVALID;
 if(!cd(source->call(SNAME("capture_original_issued_claim_leaf_context")),context))return ClaimBox::Status::INVALID;
 if(context.is_empty())return ClaimBox::Status::READY;
 Dictionary i;ClaimBox::TransferIdentity id;int64_t entry=0,first=0,remaining=0,sid=0,owner_id=0;
 if(context.size()!=7||!cd(context.get("identity",Variant()),i)||!cid(i,id)||!ci(context,"original_entry_id",entry)||entry<0||!ci(context,"original_first_claim_ordinal",first)||first<0||!ci(context,"remaining_count",remaining)||remaining<=0||!ci(context,"owner_session_id",sid)||sid!=int64_t(issued_source_session)||!ci(context,"actual_source_owner_id",owner_id)||uint64_t(owner_id)!=issued_source_binding.object||(request.get("op",Variant())!=Variant("feature.status")&&request.get("op",Variant())!=Variant("feature.get"))||request.get("cleanup",Variant())!=Variant(true))return ClaimBox::Status::INVALID;
 Array args=request["args"];if(args.size()!=1||args[0]!=context.get("path",Variant()))return ClaimBox::Status::INVALID;
 auto actual=caster_event_replies->inspect_transfer(id);if(actual.status!=ClaimBox::Status::READY)return actual.status;
 Dictionary evidence,queue_wire;ClaimBox::ClaimQueue queue;
 if(!cthaw(actual.evidence,evidence)||evidence.get("path",Variant())!=context.get("path",Variant())||actual.state==ClaimBox::TransferState::OFFERED||actual.state==ClaimBox::TransferState::TERMINAL||actual.fault||actual.in_flight||actual.queue_removed||actual.entry!=uint64_t(entry)||actual.terminal_count!=uint64_t(first)||actual.count-actual.terminal_count!=uint64_t(remaining)||actual.session!=uint64_t(sid)||actual.source_owner!=uint64_t(owner_id)||!cd(source->call(SNAME("capture_original_issued_claim_queue_state"),i),queue_wire)||!cqueue(queue_wire,i,evidence,issued_source_binding.object,issued_source_session,queue)||queue.insertion!=ClaimBox::Insertion::EXACT||queue.entry!=uint64_t(entry)||queue.remaining!=uint64_t(remaining))return ClaimBox::Status::INVALID;
 context=context.duplicate(true);context.make_read_only();return ClaimBox::Status::READY;
}
ClaimBox::Status HardCoreSimulationHost::prepare_issued_live_execution(const hardcore::simulation::AsyncLiveResourceMailbox::Request&request,Dictionary&execution){
 if(!Thread::is_main_thread())return ClaimBox::Status::INVALID;
 if(!request.issued_claim_context)return ClaimBox::Status::READY;
 if(!issued_binding_valid(issued_feature_binding)||issued_main_feature!=live_feature_main)return ClaimBox::Status::INVALID;
 Dictionary context,i;ClaimBox::TransferIdentity id;int64_t entry=0,first=0,remaining=0,sid=0,owner_id=0;
 if(!cthaw(request.issued_claim_context,context)||context.size()!=7||!cd(context.get("identity",Variant()),i)||!cid(i,id)||!ci(context,"original_entry_id",entry)||!ci(context,"original_first_claim_ordinal",first)||!ci(context,"remaining_count",remaining)||!ci(context,"owner_session_id",sid)||!ci(context,"actual_source_owner_id",owner_id))return ClaimBox::Status::INVALID;
 auto actual=caster_event_replies->inspect_transfer(id);if(actual.status!=ClaimBox::Status::READY)return actual.status;
 Dictionary observation;
 if(execution.get("operation",Variant())==Variant("feature.get")){
  if(!cthaw(actual.observation,observation)||(observation.get("status",Variant())!=Variant(2)&&observation.get("status",Variant())!=Variant(3))||actual.observation_first!=uint64_t(first)||!actual.observation_operation)return ClaimBox::Status::INVALID;
  bool matched=false;for(const auto&dep:request.dependencies){if(dep.after==hardcore::simulation::AsyncLiveResourceMailbox::After::S_COMMITTED&&dep.identity.generation==bridge_generation&&dep.identity.sequence==actual.observation_operation){auto state=original_primitives->read_operation_state_try(dep.identity);if(!state.available)return ClaimBox::Status::PENDING;if(state.completed)matched=true;}}
  if(!matched)return ClaimBox::Status::INVALID;
 }
 auto begun=caster_event_replies->begin_live_transfer_leaf(id,uint64_t(entry),uint64_t(first),uint64_t(remaining),request.original.identity.sequence,uint64_t(sid),uint64_t(owner_id));if(begun!=ClaimBox::Status::READY)return begun;
 execution["native_issued_claim_responsibility"]=context;
 if(!observation.is_empty())execution["native_issued_claim_status_observation"]=observation;
 return ClaimBox::Status::READY;
}

bool HardCoreSimulationHost::issued_prepare_original_execution(const Dictionary&caller,Dictionary&execution){
 execution=caller; // No context is trusted from the caller, even on other paths.
 if(caller.has("native_issued_claim_responsibility"))return false;if(!issued_source_binding.object)return true;if(!is_owner()||!issued_binding_valid(issued_source_binding)||!issued_binding_valid(issued_session_binding))return false;
 Object*source=ObjectDB::get_instance(ObjectID(issued_source_binding.object));Dictionary context;if(!cd(source->call(SNAME("capture_original_issued_claim_leaf_context")),context))return false;if(context.is_empty())return true;
 Dictionary identity;ClaimBox::TransferIdentity id;int64_t entry=0,first=0,remaining=0,sid=0,owner_id=0,sequence=0;Dictionary operation=caller["identity"];Array args=caller["arguments"];
 if(context.size()!=7||!cd(context.get("identity",Variant()),identity)||!cid(identity,id)||!ci(context,"original_entry_id",entry)||entry<0||!ci(context,"original_first_claim_ordinal",first)||first<0||!ci(context,"remaining_count",remaining)||remaining<=0||!ci(context,"owner_session_id",sid)||sid!=int64_t(issued_source_session)||!ci(context,"actual_source_owner_id",owner_id)||uint64_t(owner_id)!=issued_source_binding.object||!ci(operation,"op_sequence",sequence)||sequence<=0||args.size()!=1||args[0]!=context.get("path",Variant())||(caller.get("operation",Variant())!=Variant("feature.status")&&caller.get("operation",Variant())!=Variant("feature.get")))return false;
 auto record=caster_event_replies->inspect_transfer(id);Dictionary evidence;if(record.status!=ClaimBox::Status::READY||!cthaw(record.evidence,evidence)||context["path"]!=evidence["path"])return false;
 if(caster_event_replies->begin_transfer_leaf(id,uint64_t(entry),uint64_t(first),uint64_t(remaining),uint64_t(sequence),uint64_t(sid),uint64_t(owner_id))!=ClaimBox::Status::READY)return false;
 execution=caller.duplicate(true);execution["native_issued_claim_responsibility"]=context.duplicate(true);return true;
}

bool HardCoreSimulationHost::issued_fold_original_physical_reply(const Dictionary&execution,const Dictionary&reply,const ClaimBox::TransferRead*live_record){
 if(!execution.has("native_issued_claim_responsibility"))return !reply.has("issued_claim_facts");
 if(!Thread::is_main_thread()||!issued_binding_valid(issued_feature_binding)||reply.get("request",Variant())!=Variant(execution)||reply.get("executed",Variant())!=Variant(true))return false;
 Dictionary context=execution["native_issued_claim_responsibility"],i=context["identity"],operation=execution["identity"];ClaimBox::TransferIdentity id;int64_t sequence=0,first=0,remaining=0;if(!cid(i,id)||!ci(operation,"op_sequence",sequence)||!ci(context,"original_first_claim_ordinal",first)||!ci(context,"remaining_count",remaining))return false;
 auto record=live_record?*live_record:caster_event_replies->inspect_transfer(id);if(record.status!=ClaimBox::Status::READY||!record.in_flight)return false;Dictionary observation;String op=execution["operation"];int64_t terminal_count=0;ClaimBox::Bytes fact;
 if(op=="feature.status"){
  if(!reply.has("native_observations")||reply["native_observations"].get_type()!=Variant::ARRAY)return false;Array observations=reply["native_observations"];if(observations.size()!=1||!cd(observations[0],observation))return false;Dictionary site=execution["site"];int64_t epoch=0;if(!ci(site,"observation_process_epoch",epoch)||!cobservation(observation,bridge_generation,live_record?int64_t(live_feature_execution_process_frame):epoch)||observation.get("status",Variant())!=reply.get("result",Variant())||int64_t(observation["actual_start_usec"])<int64_t(reply["started_usec"])||int64_t(observation["actual_end_usec"])>int64_t(reply["finished_usec"]))return false;
  if(caster_event_replies->remember_transfer_observation(id,uint64_t(sequence),cfreeze(observation))!=ClaimBox::Status::READY)return false;
  if(observation["status"]==Variant(0))terminal_count=remaining;
 }else if(op=="feature.get"){
  if(!cthaw(record.observation,observation)||observation.get("status",Variant())!=Variant(2)&&observation.get("status",Variant())!=Variant(3))return false;Dictionary site=execution["site"];if(live_record){if(execution.get("native_issued_claim_status_observation",Variant())!=Variant(observation)||record.observation_first!=uint64_t(first))return false;}else if(observation.get("observation_process_epoch",Variant())!=site.get("observation_process_epoch",Variant()))return false;terminal_count=1;
 }else return false;
 Array facts;if(reply.has("issued_claim_facts")){if(reply["issued_claim_facts"].get_type()!=Variant::ARRAY)return false;facts=reply["issued_claim_facts"];}
 if(facts.size()!=(terminal_count?1:0))return false;
 if(terminal_count){Dictionary f;if(!cd(facts[0],f)||f.size()!=10||f.get("contract_id",Variant())!=Variant("hardcore.feature.issued_claim.physical_terminal.v1")||f.get("identity",Variant())!=Variant(i)||f.get("original_first_claim_ordinal",Variant())!=Variant(first)||f.get("claim_count",Variant())!=Variant(terminal_count)||f.get("kind",Variant())!=Variant(op=="feature.get"?"GET":"INVALID_RESOURCE")||f.get("path",Variant())!=context.get("path",Variant())||f.get("operation_identity",Variant())!=Variant(operation)||f.get("source_site",Variant())!=execution.get("site",Variant())||f.get("actual_feature_main_id",Variant())!=Variant(int64_t(issued_feature_binding.object)))return false;
  Dictionary actual_observation;if(!cd(f.get("observation",Variant()),actual_observation)||actual_observation.size()!=2||actual_observation.get("status",Variant())!=observation.get("status",Variant())||actual_observation.get("process_epoch",Variant())!=observation.get("observation_process_epoch",Variant()))return false;
  Dictionary ledger,row;if(!cd(issued_main_feature->get("_issued_claim_records"),ledger)||!cd(ledger.get(ckey(id),Variant()),row)||row.get("consumed",Variant())!=Variant(int64_t(record.terminal_count)+terminal_count)||!row.has("terminal_facts")||row["terminal_facts"].get_type()!=Variant::ARRAY||!Array(row["terminal_facts"]).has(f))return false;
  Dictionary claims;if(!cd(issued_main_feature->get("_claims"),claims))return false;uint64_t remaining_on_path=0;for(const auto&attached:caster_event_replies->inspect_main_transfers()){Dictionary other;if(!cthaw(attached.evidence,other))return false;if(other.get("path",Variant())==context.get("path",Variant())){uint64_t left=attached.count-attached.terminal_count;if(attached.identity==id)left-=uint64_t(terminal_count);remaining_on_path+=left;}}
  Variant actual_remaining=claims.get(context["path"],Variant(0));if(actual_remaining.get_type()!=Variant::INT||int64_t(actual_remaining)<0||uint64_t(int64_t(actual_remaining))<remaining_on_path)return false;
  fact=cfreeze(f);if(!fact)return false;
 }
 auto status=caster_event_replies->finish_transfer_leaf(id,uint64_t(sequence),uint64_t(first),uint64_t(terminal_count),fact);if(status!=ClaimBox::Status::READY)return false;close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return true;
}

void HardCoreSimulationHost::issued_observe_main_io_delivery(){
 if(!Thread::is_main_thread()||!caster_event_replies||!issued_binding_valid(issued_feature_binding)||!issued_binding_valid(issued_origin_binding))return;
 Dictionary delivered,bound,feature_records;if(!cd(issued_main_origin->get("_terminal_delivered"),delivered)||!cd(issued_main_origin->get("_bound"),bound)||!cd(issued_main_feature->get("_issued_claim_records"),feature_records))return;
 // Producer release is witnessed at the existing Main observation boundary.
 // Prune only cached Script provenance; attached debt remains in the mailbox.
 for(auto it=issued_helper_bindings.begin();it!=issued_helper_bindings.end();){if(!bound.has(int64_t(it->first)))it=issued_helper_bindings.erase(it);else ++it;}
 for(const auto&r:caster_event_replies->inspect_main_transfers()){
  if(r.state!=ClaimBox::TransferState::TERMINAL)continue;Dictionary evidence;if(!cthaw(r.evidence,evidence))continue;String key=ckey(r.identity);if(feature_records.has(key))continue;
  Dictionary retained;bool actual=false;
  if(cd(delivered.get(key,Variant()),retained)){Dictionary transfer,native;if(retained.get("status",Variant())==Variant("READY")&&retained.get("actual_claims_terminal",Variant())==Variant(true)&&cd(retained.get("actual_transfer",Variant()),transfer)&&transfer.get("issued_claim_identity",Variant())==Variant(cid(r.identity))&&transfer.get("issued_claim_evidence",Variant())==Variant(evidence)&&cd(retained.get("native_retirement_receipt",Variant()),native)&&native==Dictionary(issued_claim_result(r)["terminal_receipt"]))actual=true;}
  else if(!bound.has(evidence["actual_helper_id"])){
   // The pinned original release callback is the sole _bound.erase writer;
   // it validates empty real IO maps first. Read its actual producer observation
   // at the existing Main caster/primitive polling boundary before releasing.
   Dictionary io;if(cd(issued_main_origin->call(SNAME("inspect_actual_original_main_warm_io")),io)&&io.get("status",Variant())==Variant("READY")&&io.get("actual_producer_id",Variant())==Variant(int64_t(issued_origin_binding.object)))actual=true;
  }
  if(actual&&caster_event_replies->ack_transfer_delivery(r.identity)==ClaimBox::Status::READY){if(!bound.has(evidence["actual_helper_id"]))issued_helper_bindings.erase(uint64_t(int64_t(evidence["actual_helper_id"])));close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();}
 }
}
