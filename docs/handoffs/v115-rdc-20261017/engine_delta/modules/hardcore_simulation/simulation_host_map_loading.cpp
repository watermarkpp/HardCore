#include "simulation_host.h"
#include "content_value_graph.h"
#include "core/io/marshalls.h"
#include "scene/2d/node_2d.h"
#include <algorithm>
#include <cmath>
#include <limits>
namespace {
using Replies=hardcore::simulation::SourceEventReplyMailbox;
using Provenance=hardcore::simulation::MapLoadingProvenance;
using PrefixBox=hardcore::simulation::OriginalPrimitiveMailbox;
bool map_number(const Dictionary&d,const char*k,int64_t&v){if(!d.has(k)||d[k].get_type()!=Variant::INT)return false;v=d[k];return true;}
bool map_text(const Variant&v){return v.get_type()==Variant::STRING||v.get_type()==Variant::STRING_NAME;}
Replies::Bytes map_wire(const Variant&v){HardCoreContentValueGraph g;if(g.validate(v,false).get("success",false)!=Variant(true))return {};int n=0;if(encode_variant(v,nullptr,n,false)!=OK||n<=0)return {};auto b=std::make_shared<std::vector<uint8_t>>(n);if(encode_variant(v,b->data(),n,false)!=OK)return {};return b;}
bool map_value(const Replies::Bytes&b,Variant&v){return b&&decode_variant(v,b->data(),static_cast<int>(b->size()),nullptr,false)==OK;}
bool map_identical(const Replies::Bytes&a,const Replies::Bytes&b){return a&&b&&*a==*b;}
Dictionary map_status(const char*s,const char*error=""){Dictionary d;d["status"]=s;if(*error)d["error"]=error;return d;}
Dictionary map_status(Replies::Status s){return map_status(s==Replies::Status::READY?"READY":s==Replies::Status::PENDING?"PENDING":s==Replies::Status::BACKPRESSURE?"BACKPRESSURE":"INVALID");}
bool map_arrival_player_is_actual(const Ref<RefCounted>&core,const Ref<RefCounted>&root,const Ref<RefCounted>&registry,int64_t id,const Dictionary&before,const Dictionary&after,const Dictionary&identity){
 int64_t life=0,runtime=0;
 if(identity.size()!=3||!map_number(identity,"runtime_id",runtime)||runtime!=id||!map_number(identity,"life_generation",life)||life<=0||identity.get("world",Variant())!=Variant(after)||core->get(SNAME("_player_id"))!=Variant(id))return false;
 Ref<Script> registry_source=registry->get_script();
 if(registry_source.is_null()||registry_source->get_path()!=String("res://scripts/gameplay/foundation/actor_registry.gd"))return false;
 Variant handle_value=registry->call(SNAME("resolve_runtime_actor"),id);
 Object*handle=handle_value.get_type()==Variant::OBJECT?static_cast<Object*>(handle_value):nullptr;
 if(!handle||core->call(SNAME("actor_handle_for_runtime_id"),id)!=handle_value)return false;
 Ref<Script> handle_source=handle->get_script();
 if(handle_source.is_null()||handle_source->get_path()!=String("res://scripts/gameplay/foundation/actor_handle.gd"))return false;
 if(handle->call(SNAME("kind"))!=Variant(SNAME("player"))||handle->call(SNAME("is_registered"))!=Variant(true)||handle->call(SNAME("is_inside_world"))!=Variant(true)||handle->call(SNAME("is_queued_for_retirement"))!=Variant(false)||handle->call(SNAME("original_world_context"))!=Variant(before))return false;
 Ref<RefCounted> player=handle->call(SNAME("model"));
 if(player.is_null()||root->get(SNAME("player"))!=Variant(player))return false;
 Ref<Script> player_source=player->get_script();
 if(player_source.is_null()||player_source->get_path()!=String("res://scripts/gameplay/actors/player_actor_model.gd")||player->call(SNAME("runtime_actor_id"))!=Variant(id)||player->call(SNAME("current_life"))!=Variant(life))return false;
 Dictionary original=identity.duplicate(true);original["world"]=before;
 return handle->call(SNAME("identity"))==Variant(original);
}
bool map_identity(const Dictionary&d,Replies::Identity&i){int64_t g=0,j=0,o=0;if(d.size()!=3||!map_number(d,"bridge_generation",g)||g<=0||!map_number(d,"journal_generation",j)||j<=0||!map_number(d,"event_ordinal",o)||o<=0)return false;i={static_cast<uint64_t>(g),static_cast<uint64_t>(j),static_cast<uint64_t>(o)};return true;}
Dictionary map_identity(const Replies::Identity&i){Dictionary d;d["bridge_generation"]=static_cast<int64_t>(i.generation);d["journal_generation"]=static_cast<int64_t>(i.journal);d["event_ordinal"]=static_cast<int64_t>(i.ordinal);return d;}
// A Loading owner is born on the actual Root before first map arrival. This
// bounded constructor context does not make its target map active: scope.map_id
// below remains nonnegative and every scope still needs real Main provenance.
bool map_world(const Dictionary&w){int64_t root=0,epoch=0,map=-2;return w.size()==5&&w.get("contract_id",Variant())==Variant("hardcore.execution.world_context.v1")&&map_number(w,"world_runtime_id",root)&&root>0&&map_number(w,"world_epoch",epoch)&&epoch>=0&&map_number(w,"runtime_map_id",map)&&(map>=0||(map==-1&&epoch==0))&&w.has("profile_id")&&w["profile_id"].get_type()==Variant::STRING&&!String(w["profile_id"]).is_empty();}
bool map_owner(const Dictionary&d){int64_t n=0;return d.size()==5&&d.get("contract_id",Variant())==Variant("source.map.loading.owner.v1")&&map_number(d,"source_root_id",n)&&n!=0&&map_number(d,"owner_session_id",n)&&n>0&&map_number(d,"main_executor_id",n)&&n!=0&&d.has("world_context")&&d["world_context"].get_type()==Variant::DICTIONARY&&map_world(d["world_context"]);}
bool map_scope(const Dictionary&s,Provenance::Snapshot&out){
 int64_t g=0,id=0,p=0,c=0,m=0;if(s.size()!=10||s.get("contract_id",Variant())!=Variant("source.map.loading.scope.v1")||!map_number(s,"bridge_generation",g)||g<=0||!map_number(s,"scope_id",id)||id<=0||!map_number(s,"producer_runtime_id",p)||p==0||!map_number(s,"coordinator_generation",c)||c<0||!map_number(s,"map_id",m)||m<0||!s.has("transition_id")||s["transition_id"].get_type()!=Variant::STRING||String(s["transition_id"]).is_empty()||!s.has("owner_descriptor")||s["owner_descriptor"].get_type()!=Variant::DICTIONARY||!map_owner(s["owner_descriptor"])||!s.has("state")||s["state"].get_type()!=Variant::STRING||!s.has("actual_provenance")||s["actual_provenance"].get_type()!=Variant::DICTIONARY||Dictionary(s["actual_provenance"]).is_empty())return false;
 String state=s["state"];if(state!="LOADING"&&state!="RETAINED")return false;CharString t=String(s["transition_id"]).utf8();Dictionary desc=s["owner_descriptor"];
 out={static_cast<uint64_t>(g),static_cast<uint64_t>(id),static_cast<uint64_t>(p),static_cast<uint64_t>(c),m,std::string(t.get_data(),t.length()),state=="LOADING"?Provenance::State::LOADING:Provenance::State::RETAINED,map_wire(s),map_wire(desc),map_wire(desc["world_context"])};return out.scope_wire&&out.descriptor&&out.world;
}
bool map_reservation(const Dictionary&b){int64_t n=0;return b.size()==8&&b.get("contract_id",Variant())==Variant("hardcore.resource.budget_reservation.v1")&&map_number(b,"reservation_id",n)&&n>0&&map_number(b,"owner_session_id",n)&&n>0&&map_number(b,"ledger_epoch",n)&&n>=0&&map_number(b,"lane",n)&&n>=0&&n<=2&&map_number(b,"reserved_usec",n)&&n>=0&&map_number(b,"issued_usec",n)&&n>=0&&b.has("category")&&b["category"].get_type()==Variant::STRING&&!String(b["category"]).is_empty();}
bool map_request(const Dictionary&r){
 int64_t n=0;if(r.size()!=8||r.get("contract_id",Variant())!=Variant("source.map.loading.request.v1")||!r.has("owner_descriptor")||r["owner_descriptor"].get_type()!=Variant::DICTIONARY||!map_owner(r["owner_descriptor"])||!r.has("scope")||r["scope"].get_type()!=Variant::DICTIONARY||!r.has("reservation")||r["reservation"].get_type()!=Variant::DICTIONARY||!map_reservation(r["reservation"])||!map_number(r,"request_sequence",n)||n<=0||!r.has("operation")||!map_text(r["operation"])||!r.has("arguments")||r["arguments"].get_type()!=Variant::ARRAY||!r.has("source_clock")||r["source_clock"].get_type()!=Variant::DICTIONARY)return false;
 Provenance::Snapshot snapshot;if(!map_scope(r["scope"],snapshot)||Dictionary(r["scope"])["owner_descriptor"]!=r["owner_descriptor"]||Dictionary(r["reservation"])["owner_session_id"]!=Dictionary(r["owner_descriptor"])["owner_session_id"])return false;
 Dictionary clock=r["source_clock"];if(!map_number(clock,"epoch",n)||n<0||!map_number(clock,"next_release_usec",n)||n<=0)return false;
 Array a=r["arguments"];String op=r["operation"];
 if(op=="prepare")return a.size()==3&&a[0].get_type()==Variant::INT&&a[1].get_type()==Variant::INT&&a[2].get_type()==Variant::DICTIONARY&&a[0]==Dictionary(r["scope"])["map_id"]&&a[1]==Dictionary(r["scope"])["coordinator_generation"];
 if(op=="request_resources")return a.size()==1&&a[0].get_type()==Variant::DICTIONARY;
 if(op=="build_item")return a.size()==1&&a[0].get_type()==Variant::DICTIONARY;
 if(op=="zone")return a.size()==2&&a[0].get_type()==Variant::STRING&&a[1].get_type()==Variant::DICTIONARY;
 if(op=="focus")return a.size()==1&&a[0].get_type()==Variant::VECTOR2&&Vector2(a[0]).is_finite();
 return (op=="poll_resources"||op=="select_descriptors"||op=="capture_environment"||op=="finish_visual"||op=="retire_claims")&&a.is_empty();
}
bool map_event(const Dictionary&e,const Replies::Identity&i,Dictionary&r){int64_t ordinal=0;if(e.size()!=6||e.get("kind",Variant())!=Variant("original_world_presentation")||e.get("operation",Variant())!=Variant(SNAME("map_loading"))||!map_number(e,"ordinal",ordinal)||ordinal!=static_cast<int64_t>(i.ordinal)||e.get("reply_identity",Variant())!=Variant(map_identity(i))||!e.has("source_site")||e["source_site"].get_type()!=Variant::DICTIONARY||!e.has("arguments")||e["arguments"].get_type()!=Variant::ARRAY)return false;Array a=e["arguments"];if(a.size()!=1||a[0].get_type()!=Variant::DICTIONARY)return false;r=a[0];return map_request(r)&&map_wire(e);}
bool map_prefix(const Dictionary&p,uint64_t generation,PrefixBox::Prefix&out){int64_t g=0,j=0,t=0;if(p.size()!=4||!map_number(p,"bridge_generation",g)||g!=static_cast<int64_t>(generation)||!map_number(p,"journal_generation",j)||j<=0||!map_number(p,"through_ordinal",t)||t<0||!p.has("events")||p["events"].get_type()!=Variant::ARRAY)return false;out.generation=g;out.journal_generation=j;out.through=t;out.bytes=map_wire(p);if(!out.bytes)return false;Array events=p["events"];uint64_t prior=0;for(int k=0;k<events.size();++k){if(events[k].get_type()!=Variant::DICTIONARY)return false;Dictionary e=events[k];int64_t o=0;if(!map_number(e,"ordinal",o)||o<=0||static_cast<uint64_t>(o)>out.through||(prior&&static_cast<uint64_t>(o)!=prior+1))return false;auto b=map_wire(e);if(!b)return false;out.events.push_back({static_cast<uint64_t>(o),b});prior=o;}return true;}
bool map_ack(const Dictionary&a,const PrefixBox::Prefix&p){int64_t g=0,j=0,t=0;return a.size()==4&&map_number(a,"bridge_generation",g)&&g==static_cast<int64_t>(p.generation)&&map_number(a,"journal_generation",j)&&j==static_cast<int64_t>(p.journal_generation)&&map_number(a,"through_ordinal",t)&&t==static_cast<int64_t>(p.through)&&a.has("applied")&&a["applied"].get_type()==Variant::BOOL&&static_cast<bool>(a["applied"]);}
bool map_script(const Ref<RefCounted>&p,const char*path,const String&sha){if(p.is_null()||sha.length()!=64)return false;Ref<Script>s=p->get_script();return s.is_valid()&&s->get_path()==String(path)&&s->get_source_code().sha256_text()==sha;}
}

bool HardCoreSimulationHost::bind_original_map_loading_producer(const Ref<RefCounted>&p,const String&sha,const Ref<RefCounted>&x,const String&xsha){
 ERR_FAIL_COND_V(!Thread::is_main_thread()||!map_loading_state||main_map_loading_producer.is_valid()||!map_script(p,"res://scripts/gameplay/source/main_map_loading_producer.gd",sha)||!map_script(x,"res://scripts/gameplay/world/world_map_event_main.gd",xsha),false);
 if(p->call(SNAME("verify_actual_original_map_executor"),x)!=Variant(true))return false;
 if(!map_loading_state->provenance.bind_main_owner(static_cast<uint64_t>(p->get_instance_id())))return false;
 main_map_loading_producer=p;main_map_loading_producer_sha=sha;main_map_event_executor=x;main_map_event_executor_sha=xsha;return true;
}
Dictionary HardCoreSimulationHost::publish_original_map_loading_scope(const Dictionary&s){
 if(!Thread::is_main_thread()||!map_loading_state||!map_script(main_map_loading_producer,"res://scripts/gameplay/source/main_map_loading_producer.gd",main_map_loading_producer_sha))return map_status("INVALID","actual_Map_Main_producer_required");
 Provenance::Snapshot snap;if(!map_scope(s,snap)||snap.generation!=bridge_generation||snap.producer!=static_cast<uint64_t>(main_map_loading_producer->get_instance_id())||Dictionary(s["owner_descriptor"])["main_executor_id"]!=Variant(static_cast<int64_t>(main_map_event_executor->get_instance_id()))||main_map_loading_producer->call(SNAME("verify_actual_original_map_scope"),s)!=Variant(true))return map_status("INVALID","actual_Map_Loading_provenance_mismatch");
 return map_status(map_loading_state->provenance.publish(snap)?"READY":"INVALID");
}
bool HardCoreSimulationHost::verify_original_map_loading_scope(const Dictionary&s,const Dictionary&d,const String&t,int64_t generation,int64_t map){
 if(!is_owner()||!map_loading_state||!map_owner(d)||generation<0||map<0)return false;Provenance::Snapshot snap;
 if(!map_scope(s,snap))return false;
 auto arrival=std::atomic_load_explicit(&map_loading_state->arrival,std::memory_order_acquire);
 bool current_world=Dictionary(d["world_context"])==primitive_world;
 bool arrived_world=arrival&&arrival->scope_id==snap.scope&&map_identical(map_wire(d["world_context"]),arrival->before)&&map_identical(map_wire(primitive_world),arrival->after);
 return snap.generation==bridge_generation&&s["owner_descriptor"]==Variant(d)&&snap.transition==std::string(t.utf8().get_data())&&snap.coordinator==static_cast<uint64_t>(generation)&&snap.map==map&&(current_world||arrived_world)&&map_loading_state->provenance.permits(snap,true);
}
Dictionary HardCoreSimulationHost::publish_original_map_loading_publication(const Dictionary&s,const Dictionary&p,const Dictionary&r){
 if(!Thread::is_main_thread()||!map_loading_state||!map_script(main_map_loading_producer,"res://scripts/gameplay/source/main_map_loading_producer.gd",main_map_loading_producer_sha)||main_map_loading_producer->call(SNAME("verify_actual_original_map_publication"),s,p,r)!=Variant(true))return map_status("INVALID","actual_MapService_pin_publication_required");
 Provenance::Snapshot snap;if(!map_scope(s,snap)||snap.generation!=bridge_generation)return map_status("INVALID");auto sw=map_wire(s),pw=map_wire(p),rw=map_wire(r);if(!sw||!pw||!rw||pw->size()+rw->size()>source_scope_capacity)return map_status("INVALID");
 using Published=hardcore::simulation::MapLoadingHostState::Publication;std::atomic_store_explicit(&map_loading_state->publication,std::make_shared<const Published>(Published{sw,pw,rw}),std::memory_order_release);return map_status("READY");
}
bool HardCoreSimulationHost::verify_original_map_loading_publication(const Dictionary&s,const Dictionary&d,const Dictionary&p,const Dictionary&r){
 if(!is_owner()||!map_loading_state||!map_owner(d)||!s.has("owner_descriptor")||s["owner_descriptor"]!=Variant(d))return false;Provenance::Snapshot snap;if(!map_scope(s,snap)||!map_loading_state->provenance.permits(snap))return false;
 auto published=std::atomic_load_explicit(&map_loading_state->publication,std::memory_order_acquire);return published&&map_identical(map_wire(s),published->scope)&&map_identical(map_wire(p),published->value)&&map_identical(map_wire(r),published->receipt);
}
Dictionary HardCoreSimulationHost::reserve_original_map_loading_event(const Dictionary&i,const Dictionary&e){
 if(!is_owner()||!map_loading_state||!caster_event_replies)return map_status("INVALID");Replies::Identity id;Dictionary r;Provenance::Snapshot snap;
 if(!map_identity(i,id)||id.generation!=bridge_generation||!map_event(e,id,r)||!map_scope(r["scope"],snap))return map_status("INVALID","actual_map_request_site_scope");
 bool cleanup=String(r["operation"])=="retire_claims";auto arrival=std::atomic_load_explicit(&map_loading_state->arrival,std::memory_order_acquire);
 bool current_world=Dictionary(r["owner_descriptor"])["world_context"]==Variant(primitive_world);
 bool arrived_cleanup=cleanup&&arrival&&snap.scope==arrival->scope_id&&map_identical(map_wire(r["scope"]),arrival->scope)&&map_identical(map_wire(Dictionary(r["owner_descriptor"])["world_context"]),arrival->before)&&map_identical(map_wire(primitive_world),arrival->after);
 if(Dictionary(r["source_clock"]).get("epoch",Variant())!=Variant(static_cast<int64_t>(current_epoch))||!validate_original_source_site(e["source_site"])||(!current_world&&!arrived_cleanup)||!map_loading_state->provenance.permits(snap,cleanup))return map_status("INVALID","actual_map_request_site_scope");
 std::unique_lock<std::mutex>lock(map_loading_state->facts_mutex,std::try_to_lock);if(!lock.owns_lock())return map_status("PENDING","contention");auto bytes=map_wire(e);
 if(map_loading_state->used){if(!(map_loading_state->identity==id)||!map_identical(map_loading_state->event,bytes))return map_status("BACKPRESSURE","one_actual_map_continuation");return map_status(caster_event_replies->reserve(id,bytes,String(r["operation"])=="retire_claims"));}
 auto reserved=caster_event_replies->reserve(id,bytes,String(r["operation"])=="retire_claims");if(reserved==Replies::Status::READY){map_loading_state->used=true;map_loading_state->accepted=false;map_loading_state->identity=id;map_loading_state->event=bytes;map_loading_state->submitted_usec=now_usec();map_loading_state->admission_epoch=current_epoch;map_loading_state->settlement.reset();map_loading_state->claimed_usec.store(0,std::memory_order_relaxed);map_loading_state->late_recorded.store(false,std::memory_order_relaxed);}return map_status(reserved);
}
Dictionary HardCoreSimulationHost::accept_original_map_loading_event(const Dictionary&i,const Dictionary&e,const Dictionary&p){
 if(!is_owner()||!map_loading_state||!caster_event_replies||!original_primitives)return map_status("INVALID");Replies::Identity id;Dictionary r;PrefixBox::Prefix pp;
 if(!map_identity(i,id)||!map_event(e,id,r)||!map_prefix(p,bridge_generation,pp)||pp.journal_generation!=id.journal)return map_status("INVALID");auto bytes=map_wire(e);bool found=false;for(const auto&v:pp.events)if(v.ordinal==id.ordinal&&map_identical(v.bytes,bytes))found=true;if(!found)return map_status("INVALID","map_event_not_in_actual_prefix");
 std::unique_lock<std::mutex>lock(map_loading_state->facts_mutex,std::try_to_lock);if(!lock.owns_lock())return map_status("PENDING","contention");if(!map_loading_state->used||!(map_loading_state->identity==id)||!map_identical(map_loading_state->event,bytes))return map_status("INVALID");
 auto registered=original_primitives->try_register_original_presentation_prefix(pp);if(registered!=PrefixBox::MainEventStatus::READY)return map_status(registered==PrefixBox::MainEventStatus::PENDING?"PENDING":"INVALID");auto sealed=caster_event_replies->accept(id,bytes,map_wire(p));if(sealed==Replies::Status::READY)map_loading_state->accepted=true;return map_status(sealed);
}
Dictionary HardCoreSimulationHost::cancel_unaccepted_original_map_loading_event(const Dictionary&i){
 if(!is_owner()||!map_loading_state||!caster_event_replies)return map_status("INVALID");Replies::Identity id;if(!map_identity(i,id))return map_status("INVALID");std::unique_lock<std::mutex>lock(map_loading_state->facts_mutex,std::try_to_lock);if(!lock.owns_lock())return map_status("PENDING","contention");if(!map_loading_state->used||!(id==map_loading_state->identity))return map_status("INVALID");
 if(map_loading_state->accepted)return map_status("INVALID","accepted_map_event_cannot_cancel");if(!caster_event_replies->cancel_unaccepted(id))return map_status("PENDING","unaccepted_cancel_not_yet_confirmed");map_loading_state->used=false;map_loading_state->event.reset();return map_status("READY");
}
Dictionary HardCoreSimulationHost::claim_original_map_loading_event(const Dictionary&i,const Dictionary&e){
 if(!Thread::is_main_thread()||!caster_event_replies||!original_primitives)return map_status("INVALID");Replies::Identity id;Dictionary r;if(!map_identity(i,id)||!map_event(e,id,r))return map_status("INVALID");auto bytes=map_wire(e);auto proof=original_primitives->claimed_main_event_status(id.journal,id.ordinal,bytes);if(proof!=PrefixBox::MainEventStatus::READY)return map_status(proof==PrefixBox::MainEventStatus::PENDING?"PENDING":"INVALID");auto read=caster_event_replies->inspect_main(id);if(read.status!=Replies::Status::READY)return map_status(read.status);Variant accepted;if(!map_value(read.prefix,accepted)||accepted.get_type()!=Variant::DICTIONARY)return map_status("INVALID","accepted_map_prefix_missing");auto claimed=caster_event_replies->claim(id,bytes);auto out=map_status(claimed);if(claimed==Replies::Status::READY){map_loading_state->claimed_usec.store(now_usec(),std::memory_order_release);out["main_prefix"]=accepted;}return out;
}
Dictionary HardCoreSimulationHost::submit_original_map_loading_reply(const Dictionary&i,const Dictionary&r){
 if(!Thread::is_main_thread()||!map_loading_state||!caster_event_replies||!original_primitives||!map_script(main_map_event_executor,"res://scripts/gameplay/world/world_map_event_main.gd",main_map_event_executor_sha))return map_status("INVALID");Replies::Identity id;if(!map_identity(i,id))return map_status("INVALID");auto read=caster_event_replies->inspect_main(id);if(read.status!=Replies::Status::READY)return map_status(read.status);Variant ev,pv;if(!map_value(read.event,ev)||!map_value(read.prefix,pv))return map_status("INVALID");Dictionary source;PrefixBox::Prefix pp;if(!map_event(ev,id,source)||!map_prefix(pv,bridge_generation,pp)||r.size()!=9||r.get("contract_id",Variant())!=Variant("source.map.loading.reply.v1")||!map_identical(map_wire(r.get("source_request",Variant())),map_wire(source))||r.get("identity",Variant())!=Variant(i)||(!r.has("executed")||r["executed"].get_type()!=Variant::BOOL||!static_cast<bool>(r["executed"]))||!r.has("result")||r["result"].get_type()!=Variant::DICTIONARY||!r.has("native_main_prefix_receipt")||r["native_main_prefix_receipt"].get_type()!=Variant::DICTIONARY||!map_ack(r["native_main_prefix_receipt"],pp))return map_status("INVALID","exact_map_reply_required");
 int64_t started=0,finished=0,cpu=0;if(!map_number(r,"started_usec",started)||started<=0||!map_number(r,"finished_usec",finished)||finished<started||finished>static_cast<int64_t>(now_usec())||started<static_cast<int64_t>(map_loading_state->claimed_usec.load(std::memory_order_acquire))||!map_number(r,"actual_Main_CPU_usec",cpu)||cpu<0||main_map_event_executor->call(SNAME("verify_actual_original_map_reply"),i,r)!=Variant(true))return map_status("INVALID","actual_map_Main_cost_or_effect_receipt");
 auto applied=original_primitives->actual_published_prefix_status(pp);if(applied!=PrefixBox::MainEventStatus::READY)return map_status(applied==PrefixBox::MainEventStatus::PENDING?"PENDING":"INVALID","actual_prefix_not_acknowledged");
 auto result=caster_event_replies->submit(id,map_wire(r),0);if(result==Replies::Status::READY){Dictionary site=Dictionary(ev)["source_site"];int64_t deadline=0;if(map_number(site,"deadline_usec",deadline)&&finished>deadline&&!map_loading_state->late_recorded.exchange(true,std::memory_order_acq_rel))map_loading_state->late_results.fetch_add(1,std::memory_order_relaxed);close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();}return map_status(result);
}
Dictionary HardCoreSimulationHost::poll_original_map_loading_event(const Dictionary&i){
 if(!is_owner()||!map_loading_state||!caster_event_replies)return map_status("INVALID");Replies::Identity id;if(!map_identity(i,id))return map_status("INVALID");auto read=caster_event_replies->poll_with_observation(id,now_usec(),current_epoch);auto out=map_status(read.status);if(read.status!=Replies::Status::READY)return out;
 std::unique_lock<std::mutex>lock(map_loading_state->facts_mutex,std::try_to_lock);if(!lock.owns_lock())return map_status("PENDING","contention");if(!map_loading_state->used||!(id==map_loading_state->identity))return map_status("INVALID");Variant raw;if(!map_value(read.reply,raw)||raw.get_type()!=Variant::DICTIONARY)return map_status("INVALID");Dictionary reply=Dictionary(raw).duplicate(true),request=Dictionary(reply["source_request"]).duplicate(true);request["identity"]=i;request["submitted_usec"]=static_cast<int64_t>(map_loading_state->submitted_usec);reply["request"]=request;reply["native_s_poll_epoch"]=static_cast<int64_t>(read.s_poll_epoch);
 Variant observed_event;if(map_value(read.event,observed_event)&&observed_event.get_type()==Variant::DICTIONARY){Dictionary observed_site=Dictionary(observed_event)["source_site"];int64_t deadline=0;if(map_number(observed_site,"deadline_usec",deadline)&&read.received_usec>static_cast<uint64_t>(deadline)&&!map_loading_state->late_recorded.exchange(true,std::memory_order_acq_rel))map_loading_state->late_results.fetch_add(1,std::memory_order_relaxed);}int64_t started=reply["started_usec"];auto claimed=map_loading_state->claimed_usec.load(std::memory_order_acquire);out["actual_queue_residence_usec"]=static_cast<int64_t>(claimed-map_loading_state->submitted_usec);out["actual_dispatch_wait_usec"]=started-static_cast<int64_t>(claimed);out["deadline_status"]=map_loading_state->late_recorded.load(std::memory_order_acquire)?"FAIL":"PASS";out["late_result_count"]=static_cast<int64_t>(map_loading_state->late_results.load(std::memory_order_acquire));out["reply"]=reply;out["native_received_usec"]=static_cast<int64_t>(read.received_usec);out["native_s_poll_epoch"]=static_cast<int64_t>(read.s_poll_epoch);return out;
}
Dictionary HardCoreSimulationHost::settle_original_map_loading_event_status(const Dictionary&i,const Dictionary&s){
 if(!is_owner()||!map_loading_state||!caster_event_replies)return map_status("INVALID");Replies::Identity id;if(!map_identity(i,id))return map_status("INVALID");std::unique_lock<std::mutex>lock(map_loading_state->facts_mutex,std::try_to_lock);if(!lock.owns_lock())return map_status("PENDING","contention");auto bytes=map_wire(s);if(!bytes)return map_status("INVALID");if(!map_loading_state->used){return id==map_loading_state->last_settlement_identity&&map_identical(bytes,map_loading_state->last_settlement)?map_status("SETTLED"):map_status("INVALID");}if(!(id==map_loading_state->identity))return map_status("INVALID");if(map_loading_state->settlement)return map_identical(bytes,map_loading_state->settlement)?map_status("SETTLED"):map_status("INVALID","changed_map_settlement");
 auto read=caster_event_replies->poll(id);Variant raw,ev;if(read.status!=Replies::Status::READY||!read.received_usec||!map_value(read.reply,raw)||!map_value(read.event,ev))return map_status(read.status==Replies::Status::PENDING?"PENDING":"INVALID");Dictionary reply=raw,req=Array(Dictionary(ev)["arguments"])[0],b=req["reservation"];int64_t rid=0,session=0,epoch=0,start=0,end=0,charge=0,received=0,queue=0,over=0;int64_t reserve=0;
 if(s.size()!=11||s.get("contract_id",Variant())!=Variant("hardcore.resource.budget_settlement.v1")||s.get("identity",Variant())!=Variant(i)||!map_number(s,"reservation_id",rid)||b["reservation_id"]!=Variant(rid)||!map_number(s,"owner_session_id",session)||b["owner_session_id"]!=Variant(session)||!map_number(s,"s_commit_epoch",epoch)||epoch<static_cast<int64_t>(read.s_poll_epoch)||epoch>static_cast<int64_t>(current_epoch)||!map_number(s,"main_started_usec",start)||reply["started_usec"]!=Variant(start)||!map_number(s,"main_finished_usec",end)||reply["finished_usec"]!=Variant(end)||!map_number(s,"charged_usec",charge)||charge!=end-start||!map_number(s,"receipt_received_usec",received)||received!=static_cast<int64_t>(read.received_usec)||!map_number(s,"queue_wait_usec",queue)||queue!=start-static_cast<int64_t>(map_loading_state->submitted_usec)||queue<0||!map_number(s,"overrun_usec",over)||!map_number(b,"reserved_usec",reserve)||over!=std::max<int64_t>(0,charge-reserve))return map_status("INVALID","actual_map_budget_settlement_mismatch");
 map_loading_state->settlement=bytes;return map_status("SETTLED");
}
bool HardCoreSimulationHost::retire_original_map_loading_event(const Dictionary&i,const Dictionary&r){
 if(!is_owner()||!map_loading_state||!caster_event_replies)return false;Replies::Identity id;if(!map_identity(i,id))return false;std::unique_lock<std::mutex>lock(map_loading_state->facts_mutex,std::try_to_lock);if(!lock.owns_lock()||!map_loading_state->used||!(id==map_loading_state->identity)||!map_loading_state->settlement)return false;auto read=caster_event_replies->poll(id);Variant raw;if(read.status!=Replies::Status::READY||!map_value(read.reply,raw))return false;Dictionary normalized=Dictionary(raw).duplicate(true),request=Dictionary(normalized["source_request"]).duplicate(true);request["identity"]=i;request["submitted_usec"]=static_cast<int64_t>(map_loading_state->submitted_usec);normalized["request"]=request;normalized["native_s_poll_epoch"]=static_cast<int64_t>(read.s_poll_epoch);if(!map_identical(map_wire(normalized),map_wire(r)))return false;
 if(caster_event_replies->consume(id)!=Replies::Status::READY||caster_event_replies->retire(id)!=Replies::Status::READY)return false;
 if(Dictionary(normalized["source_request"]).get("operation",Variant())==Variant("finish_visual")&&Dictionary(normalized["result"]).get("ok",Variant())==Variant(true)){
  map_loading_state->last_finish_identity=id;map_loading_state->last_finish_event=map_loading_state->event;map_loading_state->last_finish_reply=map_wire(normalized);map_loading_state->last_finish_settlement=map_loading_state->settlement;
 }
 map_loading_state->last_settlement_identity=id;map_loading_state->last_settlement=map_loading_state->settlement;map_loading_state->event.reset();map_loading_state->settlement.reset();map_loading_state->used=false;return true;
}

Dictionary HardCoreSimulationHost::commit_original_map_arrival(const Ref<RefCounted>&core,const Dictionary&t){
 if(!is_owner()||!map_loading_state||!original_primitives||model.is_null()||core.is_null())return map_status("INVALID","actual_Source_map_arrival_owner_required");
 auto bytes=map_wire(t);if(!bytes)return map_status("INVALID","plain_exact_arrival_transaction_required");
 auto previous=std::atomic_load_explicit(&map_loading_state->arrival,std::memory_order_acquire);
 if(previous&&map_identical(previous->transaction,bytes)){
  Ref<RefCounted> actual_core=model->call(SNAME("current_original_world_core"));
  return actual_core==core&&t.get("world_core_id",Variant())==Variant(static_cast<int64_t>(core->get_instance_id()))&&map_identical(map_wire(primitive_world),previous->after)?map_status("READY"):map_status("INVALID","exact_arrival_retry_owner_required");
 }
 int64_t root_id=0,core_id=0,registry_id=0,session_id=0,player_id=0,coordinator=0;
 if(t.size()!=14||t.get("contract_id",Variant())!=Variant("hardcore.source.map_arrival.v2")||!map_number(t,"source_root_id",root_id)||root_id==0||!map_number(t,"world_core_id",core_id)||core_id!=static_cast<int64_t>(core->get_instance_id())||!map_number(t,"registry_id",registry_id)||registry_id==0||!map_number(t,"owner_session_id",session_id)||session_id<=0||!map_number(t,"player_runtime_id",player_id)||player_id<=0||!map_number(t,"coordinator_generation",coordinator)||coordinator<0||!t.has("transition_id")||t["transition_id"].get_type()!=Variant::STRING||!t.has("before_world")||t["before_world"].get_type()!=Variant::DICTIONARY||!t.has("after_world")||t["after_world"].get_type()!=Variant::DICTIONARY||!t.has("player_identity")||t["player_identity"].get_type()!=Variant::DICTIONARY||!t.has("loading_scope")||t["loading_scope"].get_type()!=Variant::DICTIONARY||!t.has("finish_identity")||t["finish_identity"].get_type()!=Variant::DICTIONARY||!t.has("finish_reply")||t["finish_reply"].get_type()!=Variant::DICTIONARY)return map_status("INVALID","exact_arrival_transaction_schema");
 Dictionary before=t["before_world"],after=t["after_world"],scope=t["loading_scope"];Provenance::Snapshot snap;Replies::Identity finish;
 if(!map_world(before)||!map_world(after)||before!=primitive_world||before["world_runtime_id"]!=after["world_runtime_id"]||before["profile_id"]!=after["profile_id"]||int64_t(before["world_epoch"])==std::numeric_limits<int64_t>::max()||int64_t(after["world_epoch"])!=int64_t(before["world_epoch"])+1||int64_t(after["runtime_map_id"])<0||!map_scope(scope,snap)||snap.generation!=bridge_generation||snap.coordinator!=static_cast<uint64_t>(coordinator)||snap.map!=int64_t(after["runtime_map_id"])||scope["transition_id"]!=t["transition_id"]||Dictionary(scope["owner_descriptor"])["world_context"]!=Variant(before)||Dictionary(scope["owner_descriptor"])["source_root_id"]!=Variant(root_id)||Dictionary(scope["owner_descriptor"])["owner_session_id"]!=Variant(session_id)||!map_identity(t["finish_identity"],finish)||!map_loading_state->provenance.permits(snap,false))return map_status("INVALID","actual_map_arrival_CAS_scope_or_epoch");
 Ref<Script> source=core->get_script();Ref<RefCounted> actual_core=model->call(SNAME("current_original_world_core"));Ref<RefCounted> session=model->call(SNAME("source_session"));Ref<RefCounted> root=core->call(SNAME("original_root_owner"));Ref<RefCounted> registry=core->get(SNAME("registry"));
 if(source.is_null()||source->get_path()!=String("res://scripts/gameplay/world/world_simulation_core.gd")||actual_core!=core||session.is_null()||root.is_null()||registry.is_null()||core->call(SNAME("original_source_session"))!=Variant(session)||static_cast<int64_t>(root->get_instance_id())!=root_id||static_cast<int64_t>(registry->get_instance_id())!=registry_id||session->call(SNAME("original_budget_session_id"))!=Variant(session_id)||core->call(SNAME("current_world_identity"))!=Variant(before)||registry->call(SNAME("capture_world"))!=Variant(before)||root->get(SNAME("current_map_id"))!=after["runtime_map_id"]||root->get(SNAME("_zone_generation"))!=after["world_epoch"]||root->call(SNAME("original_map_coordinator_generation"))!=Variant(coordinator)||root->call(SNAME("original_map_coordinator_is_current"),coordinator)!=Variant(true)||root->get(SNAME("_active_map_transition_id"))!=t["transition_id"]||core->call(SNAME("current_original_source_site"))!=Variant(Dictionary())||original_primitives->in_flight()||core->call(SNAME("validate_original_map_arrival_transaction"),t)!=Variant(true)||session->call(SNAME("validate_original_map_arrival_transaction"),core,t)!=Variant(true))return map_status("INVALID","actual_model_Core_Session_Root_registry_arrival_required");
 // Independently resolve the actual canonical Player after Core validation.
 // The frozen after-world identity carries its real original combat life.
 if(!map_arrival_player_is_actual(core,root,registry,player_id,before,after,t["player_identity"]))return map_status("INVALID","actual_canonical_Player_arrival_life_required");
 std::unique_lock<std::mutex>lock(map_loading_state->facts_mutex,std::try_to_lock);if(!lock.owns_lock())return map_status("PENDING","contention");
 Variant retired_event;Dictionary request;
 if(map_loading_state->used||!(finish==map_loading_state->last_finish_identity)||!map_loading_state->last_finish_settlement||!map_identical(map_wire(t["finish_reply"]),map_loading_state->last_finish_reply)||!map_value(map_loading_state->last_finish_event,retired_event)||retired_event.get_type()!=Variant::DICTIONARY||!map_event(retired_event,finish,request)||request["operation"]!=Variant("finish_visual")||request["scope"]!=Variant(scope)||request["owner_descriptor"]!=scope["owner_descriptor"])return map_status("INVALID","actual_settled_retired_finish_visual_required");
 auto before_bytes=map_wire(before),after_bytes=map_wire(after),scope_bytes=map_wire(scope);
 if(!before_bytes||!after_bytes||!scope_bytes)return map_status("INVALID","actual_map_arrival_freeze_failed");
 Dictionary next_world=after.duplicate(true);
 using Arrival=hardcore::simulation::MapLoadingHostState::Arrival;
 auto next_arrival=std::make_shared<const Arrival>(Arrival{bytes,before_bytes,after_bytes,scope_bytes,snap.scope});
 if(!map_loading_state->provenance.commit_arrival(snap))return map_status("INVALID","actual_map_arrival_provenance_CAS_failed");
 // One S owner: all validation and allocations precede this sole mutation.
 primitive_world=next_world;
 std::atomic_store_explicit(&map_loading_state->arrival,next_arrival,std::memory_order_release);
 return map_status("READY");
}

bool HardCoreSimulationHost::verify_committed_original_map_arrival(const Dictionary&t)const{
 if((!Thread::is_main_thread()&&!is_owner())||!map_loading_state)return false;
 auto arrival=std::atomic_load_explicit(&map_loading_state->arrival,std::memory_order_acquire);
 return arrival&&map_identical(arrival->transaction,map_wire(t));
}
Dictionary HardCoreSimulationHost::certify_original_map_loading_owner_closed(const Dictionary&r){
 if(!Thread::is_main_thread()||!map_loading_state||!map_script(main_map_loading_producer,"res://scripts/gameplay/source/main_map_loading_producer.gd",main_map_loading_producer_sha)||main_map_loading_producer->call(SNAME("verify_actual_original_map_owner_terminal"),r)!=Variant(true))return map_status("INVALID","actual_Map_IO_pin_terminal_or_transfer_receipt_required");
 if(!map_loading_state->provenance.certify_owner_closed(map_wire(r)))return map_status("INVALID");close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return map_status("READY");
}
