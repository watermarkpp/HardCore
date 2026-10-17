#include "simulation_host.h"
#include "content_value_graph.h"
#include "core/config/engine.h"
#include "core/io/marshalls.h"
#include "core/os/os.h"
#include "scene/main/node.h"
#include "scene/main/scene_tree.h"
#include <cmath>

using CloseBox=hardcore::simulation::CloseProcessMailbox;
namespace {
bool number(const Dictionary&d,const char*key,int64_t&v){if(!d.has(key)||d[key].get_type()!=Variant::INT)return false;v=d[key];return true;}
bool actual_producer(const Ref<RefCounted>&p,const String&sha){
 if(p.is_null())return false;Ref<Script>s=p->get_script();
 return s.is_valid()&&s->get_path()=="res://scripts/gameplay/source/main_close_process_frame_producer.gd"&&s->get_source_code().sha256_text()==sha;
}
CloseBox::Bytes encode(const Variant&v){
 int n=0;if(encode_variant(v,nullptr,n,false)!=OK||n<=0)return {};
 auto b=std::make_shared<std::vector<uint8_t>>(n);if(encode_variant(v,b->data(),n,false)!=OK)return {};return b;
}
bool decode(const CloseBox::Bytes&b,Dictionary&d){Variant v;int n=0;if(!b||b->empty()||b->size()>INT32_MAX||decode_variant(v,b->data(),static_cast<int>(b->size()),&n,false)!=OK||n!=static_cast<int>(b->size())||v.get_type()!=Variant::DICTIONARY)return false;d=v;return true;}
const char*status_name(CloseBox::Status s){switch(s){case CloseBox::Status::ACCEPTED:return "ACCEPTED";case CloseBox::Status::DUPLICATE:return "DUPLICATE";case CloseBox::Status::PENDING:return "PENDING";case CloseBox::Status::BUSY:return "BUSY";case CloseBox::Status::BACKPRESSURE:return "BACKPRESSURE";case CloseBox::Status::CONSUMED:return "CONSUMED";case CloseBox::Status::STOPPED:return "STOPPED";default:return "INVALID";}}
Dictionary reply(CloseBox::Status s){Dictionary d;d["status"]=status_name(s);return d;}
Dictionary consumption(const CloseBox::Read&r){
 Dictionary d=reply(r.status),p;if(r.status!=CloseBox::Status::CONSUMED||!decode(r.bytes,p))return d;
 d["publication"]=p;d["source_process_frame"]=static_cast<int64_t>(r.source_frame);d["source_hook_completed"]=true;return d;
}
}
bool HardCoreSimulationHost::bind_original_close_process_producer(const Ref<RefCounted>&p,const String&sha){
 if(!Thread::is_main_thread()||(!started&&!main_channels_prepared)||main_channels_aborted||close_quiescent.load(std::memory_order_acquire)||source_model_close_completed.load(std::memory_order_acquire)||close_process_producer_bound.load(std::memory_order_acquire)||!close_process_frames||!actual_producer(p,sha))return false;
 if(p->get("_host")!=Variant(this)||p->get("_bridge_generation")!=Variant(static_cast<int64_t>(bridge_generation)))return false;
 Variant capacity=p->get("_capacity");if(capacity.get_type()!=Variant::INT||int64_t(capacity)<=0||uint64_t(int64_t(capacity))>input_capacity)return false;
 int64_t generation=0,id=0;Variant gv=p->get("_generation");if(gv.get_type()!=Variant::INT||(generation=gv)<=0)return false;
 Variant lw=p->get("_listener");Object*o=lw;WeakRef*weak=Object::cast_to<WeakRef>(o);if(!weak)return false;Variant linked=weak->get_ref();Node*listener=Object::cast_to<Node>(static_cast<Object*>(linked));
 if(!listener||!listener->is_inside_tree()||listener->get_process_mode()!=Node::PROCESS_MODE_ALWAYS||!listener->is_processing())return false;
 Ref<Script>s=listener->get_script();if(s.is_null()||s->get_path()!="res://scripts/gameplay/source/main_close_process_frame_listener.gd")return false;
 id=static_cast<int64_t>(listener->get_instance_id());close_process_listener_id=id;close_process_generation=generation;
 main_close_process_producer=p;main_close_process_producer_sha=sha;close_process_producer_bound.store(true,std::memory_order_release);close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return true;
}
Dictionary HardCoreSimulationHost::enqueue_original_close_process_frame(const Dictionary&p){
 if(!Thread::is_main_thread()||!close_requested.load(std::memory_order_acquire)||!close_process_producer_bound.load(std::memory_order_acquire)||!actual_producer(main_close_process_producer,main_close_process_producer_sha))return reply(CloseBox::Status::INVALID);
 const bool io_service=p.get("phase",Variant())==Variant("NODE_PROCESS_SERVICE")&&p.has("main_io");
 if(p.size()!=(io_service?15:14))return reply(CloseBox::Status::INVALID);
 int64_t generation=0,bridge_id=0,producer=0,listener_id=0,sequence=0,frame=0,physics_frame=0,wall=0;
 if(p.get("contract_id",Variant())!=Variant("hardcore.source.closing_process_frame.v1")||!number(p,"bridge_generation",bridge_id)||bridge_id!=static_cast<int64_t>(bridge_generation)||!number(p,"generation",generation)||generation!=close_process_generation||!number(p,"producer_runtime_id",producer)||producer!=static_cast<int64_t>(main_close_process_producer->get_instance_id())||!number(p,"listener_runtime_id",listener_id)||listener_id!=close_process_listener_id||!number(p,"sequence",sequence)||sequence<=0||!number(p,"main_process_frame",frame)||frame<0||!number(p,"main_physics_frame",physics_frame)||physics_frame<0||!number(p,"wall_usec",wall)||wall<=0||static_cast<uint64_t>(wall)>OS::get_singleton()->get_ticks_usec())return reply(CloseBox::Status::INVALID);
 if(p.get("delta",Variant()).get_type()!=Variant::FLOAT||!std::isfinite(static_cast<double>(p["delta"]))||static_cast<double>(p["delta"])<0||p.get("time_scale",Variant()).get_type()!=Variant::FLOAT||!std::isfinite(static_cast<double>(p["time_scale"]))||static_cast<double>(p["time_scale"])<0||p.get("tree_paused",Variant()).get_type()!=Variant::BOOL||p.get("phase",Variant()).get_type()!=Variant::STRING)return reply(CloseBox::Status::INVALID);
 String phase=p["phase"];if(phase!="PROCESS_SIGNAL"&&phase!="NODE_PROCESS_SERVICE")return reply(CloseBox::Status::INVALID);
 Node*listener=Object::cast_to<Node>(ObjectDB::get_instance(ObjectID(static_cast<uint64_t>(listener_id))));if(!listener||!listener->is_inside_tree()||listener->get_process_mode()!=Node::PROCESS_MODE_ALWAYS||!listener->is_processing())return reply(CloseBox::Status::INVALID);
 Ref<Script>s=listener->get_script();if(s.is_null()||s->get_path()!="res://scripts/gameplay/source/main_close_process_frame_listener.gd"||p.get("listener_script_sha256",Variant())!=Variant(s->get_source_code().sha256_text()))return reply(CloseBox::Status::INVALID);
 // The fixed producer verifies the actual recorded callback, not caller flags.
 Variant proof=main_close_process_producer->call(SNAME("verify_original_close_process_frame_publication"),p);
 if(proof.get_type()!=Variant::DICTIONARY||Dictionary(proof).get("success",Variant())!=Variant(true)||Dictionary(proof).get("publication",Variant())!=Variant(p))return reply(CloseBox::Status::INVALID);
 const bool production_session=factory.is_valid()&&factory->get_path()==String("res://scripts/gameplay/source/source_session_runtime.gd");
 if(phase=="NODE_PROCESS_SERVICE"&&production_session&&!io_service)return reply(CloseBox::Status::INVALID);
 if(io_service){
  if(phase!="NODE_PROCESS_SERVICE"||p["main_io"].get_type()!=Variant::DICTIONARY)return reply(CloseBox::Status::INVALID);
  Variant actual_io_value=main_close_process_producer->get("_session_io");if(actual_io_value.get_type()!=Variant::OBJECT)return reply(CloseBox::Status::INVALID);
  Ref<RefCounted> actual_io=actual_io_value;if(actual_io.is_null()||actual_io!=issued_main_origin)return reply(CloseBox::Status::INVALID);
  Ref<Script> io_script=actual_io->get_script();if(io_script.is_null()||io_script->get_path()!=String("res://scripts/gameplay/source/main_source_closing_io_producer.gd"))return reply(CloseBox::Status::INVALID);
  Dictionary io=p["main_io"];int64_t io_session=0,io_root=0,io_id=0,io_frame=0,io_wall=0,io_generation=0;
  if(io.get("contract_id",Variant())!=Variant("hardcore.source.main_io_observation.v1")||!number(io,"owner_session_id",io_session)||io_session<=0||io_session!=int64_t(actual_io->get("_session_id"))||!number(io,"world_runtime_id",io_root)||io_root<=0||io_root!=int64_t(actual_io->get("_session_root_id"))||!number(io,"actual_io_producer_id",io_id)||io_id!=int64_t(actual_io->get_instance_id())||!number(io,"actual_main_process_frame",io_frame)||io_frame!=frame||!number(io,"actual_wall_usec",io_wall)||io_wall<=0||io_wall>wall||!number(io,"bridge_generation",io_generation)||io_generation!=bridge_id||io.get("physical_owners_retained",Variant())!=Variant(true)||io.get("status",Variant()).get_type()!=Variant::STRING||(io["status"]!=Variant("OWNERS_RETAINED")&&io["status"]!=Variant("BUSINESS_DRAINED")))return reply(CloseBox::Status::INVALID);
  // The producer's exact captured SERVICE (above) is the witness. In a
  // BACKPRESSURE retry this remains the original sample, not a new observation
  // relabeled with an old sequence, timestamp or process-frame identity.
  HardCoreContentValueGraph graph;if(graph.validate(io,false).get("success",Variant())!=Variant(true))return reply(CloseBox::Status::INVALID);
 }
 if(phase=="PROCESS_SIGNAL"){
  if(static_cast<uint64_t>(frame)!=Engine::get_singleton()->get_process_frames()||static_cast<uint64_t>(physics_frame)!=Engine::get_singleton()->get_physics_frames()||p["tree_paused"]!=Variant(listener->get_tree()->is_paused())||p["time_scale"]!=Variant(Engine::get_singleton()->get_time_scale()))return reply(CloseBox::Status::INVALID);
  // Observe before capacity try-lock. A missed actual signal is never replayed.
  close_process_frames->observe_actual_signal(frame);
 }
 auto wire=encode(p);if(!wire)return reply(CloseBox::Status::INVALID);
 auto status=close_process_frames->publish(bridge_generation,sequence,frame,phase=="PROCESS_SIGNAL"?CloseBox::Phase::SIGNAL:CloseBox::Phase::SERVICE,wire);
 Dictionary result=reply(status);if(status==CloseBox::Status::ACCEPTED||status==CloseBox::Status::DUPLICATE){result["publication"]=p.duplicate(true);close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();}return result;
}
Dictionary HardCoreSimulationHost::acquire_original_close_process_frame_receipt(){
 if(!Thread::is_main_thread()||!close_process_frames||!close_process_producer_bound.load(std::memory_order_acquire))return reply(CloseBox::Status::INVALID);
 return consumption(close_process_frames->receipt());
}
bool HardCoreSimulationHost::ack_original_close_process_frame_receipt(const Dictionary&r){
 if(!Thread::is_main_thread()||!close_process_frames)return false;auto actual=close_process_frames->receipt();if(consumption(actual)!=r)return false;
 if(!close_process_frames->ack(actual.sequence,actual.source_frame))return false;close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return true;
}
int64_t HardCoreSimulationHost::original_close_process_signal_highwater()const{return close_process_frames?static_cast<int64_t>(close_process_frames->signal_highwater()):0;}
bool HardCoreSimulationHost::original_close_process_producer_drained()const{
 return is_owner()&&(!close_process_producer_bound.load(std::memory_order_acquire)||(close_process_frames&&close_process_frames->can_close()));
}
bool HardCoreSimulationHost::request_original_close_process_producer_stop(){
 if(!is_owner()||!closing_session||!close_process_producer_bound.load(std::memory_order_acquire)||!close_process_frames)return false;
 return close_process_frames->request_stop();
}
Dictionary HardCoreSimulationHost::acquire_original_close_process_producer_stop_request(){
 if(!Thread::is_main_thread()||!close_process_frames)return reply(CloseBox::Status::INVALID);Dictionary d;
 d["status"]=close_process_frames->stop_requested()?"STOP_REQUESTED":"PENDING";
 d["bridge_generation"]=static_cast<int64_t>(bridge_generation);d["generation"]=close_process_generation;return d;
}
bool HardCoreSimulationHost::confirm_original_close_process_producer_stopped(const Dictionary&r){
 if(!Thread::is_main_thread()||!actual_producer(main_close_process_producer,main_close_process_producer_sha)||!close_process_frames||r.size()!=5)return false;
 int64_t bridge_id=0,generation=0,producer=0,watermark=0;
 if(r.get("contract_id",Variant())!=Variant("hardcore.source.closing_process_stop.v1")||!number(r,"bridge_generation",bridge_id)||bridge_id!=static_cast<int64_t>(bridge_generation)||!number(r,"generation",generation)||generation!=close_process_generation||!number(r,"producer_runtime_id",producer)||producer!=static_cast<int64_t>(main_close_process_producer->get_instance_id())||!number(r,"last_published_sequence",watermark)||watermark<0)return false;
 Variant proof=main_close_process_producer->call(SNAME("verify_original_close_process_producer_stopped"),r);
 if(proof.get_type()!=Variant::DICTIONARY||Dictionary(proof).get("success",Variant())!=Variant(true)||Dictionary(proof).get("receipt",Variant())!=Variant(r))return false;
 if(close_process_frames->confirm_stopped(watermark)!=CloseBox::Status::STOPPED)return false;
 close_process_stop_receipt=r.duplicate(true);close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return true;
}
bool HardCoreSimulationHost::verify_original_close_process_producer_terminal_receipt(const Dictionary&r){
 return Thread::is_main_thread()&&close_quiescent.load(std::memory_order_acquire)&&close_process_frames&&close_process_frames->can_close()&&r==close_process_stop_receipt;
}
bool HardCoreSimulationHost::service_original_close_process_frames(){
 if(!close_process_producer_bound.load(std::memory_order_acquire))return true;
 for(size_t count=0;count<input_capacity*2;++count){
  auto event=close_process_frames->acquire();if(event.status==CloseBox::Status::PENDING||event.status==CloseBox::Status::BUSY)return true;
  Dictionary publication;if(event.status!=CloseBox::Status::ACCEPTED||!decode(event.bytes,publication)){set_fault("invalid_actual_closing_process_frame");return false;}
  if(event.phase==CloseBox::Phase::SIGNAL)source_deferred_flush_mask=0;
  // Normal PUBLISH already advanced the next Source P slot. First closing
  // SIGNAL uses that slot; only a completed SERVICE advances to the next one.
  // Keep the previous H epoch, physics count and simulation elapsed. Only the
  // actual accepted P opportunity advances; no timers, inputs or physics step.
  original_source_frame["closing_session"]=true;
  original_source_frame["closing_process_publication"]=publication;
  original_source_frame["actual_main_process_frame"]=static_cast<int64_t>(event.frame);
  original_source_frame["published_signal_highwater"]=static_cast<int64_t>(close_process_frames->signal_highwater());
  original_source_frame["source_process_frame"]=static_cast<int64_t>(source_process_frame.load(std::memory_order_acquire));
  original_source_frame["observed_usec"]=static_cast<int64_t>(now_usec());
  original_source_boundary=event.phase==CloseBox::Phase::SIGNAL?SNAME("PROCESS_SIGNAL"):SNAME("NODE_PROCESS_SERVICE");
  current_phase_name=event.phase==CloseBox::Phase::SIGNAL?SNAME("P_CLOSE_SIGNAL"):SNAME("P_CLOSE_SERVICE");
  current_phase=event.phase==CloseBox::Phase::SIGNAL?Clock::Phase::P_INPUT:Clock::Phase::P_GROUP;
  Array args;args.push_back(current_clock_frame());
  if(!call_model(SNAME("on_original_close_process_phase"),args))return false;
  if(close_process_frames->complete(event.sequence,source_process_frame.load(std::memory_order_acquire))!=CloseBox::Status::CONSUMED){set_fault("closing_process_completion_rejected");return false;}
  if(event.phase==CloseBox::Phase::SERVICE)source_process_frame.fetch_add(1,std::memory_order_release);
 }return true;
}
