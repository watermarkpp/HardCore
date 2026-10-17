#include "main_source_deferred.h"
#include "content_value_graph.h"
#include "core/object/class_db.h"
#include "core/object/message_queue.h"
#include "core/object/script_language.h"
#include "core/os/os.h"
#include "core/os/thread.h"
#include "core/config/engine.h"
#include "scene/main/node.h"
namespace {Dictionary missing(const String&code){Dictionary r;r["success"]=false;Array errors;errors.push_back(code);r["errors"]=errors;r["details"]=Dictionary();return r;}bool plain_receipt(const Dictionary&d){HardCoreContentValueGraph graph;Dictionary v=graph.validate(d,false);return static_cast<bool>(v.get("success",false));}}
void HardCoreMainSourceDeferred::_bind_methods(){
 ClassDB::bind_method(D_METHOD("configure_original_checkpoint_producer","producer","actual_script_path","actual_source_sha256"),&HardCoreMainSourceDeferred::configure_original_checkpoint_producer);
 ClassDB::bind_method(D_METHOD("flush_original_main_source_checkpoint","checkpoint","facade","content","legacy_resources"),&HardCoreMainSourceDeferred::flush_original_main_source_checkpoint);
 ClassDB::bind_method(D_METHOD("observe_original_main_source_receivers","checkpoint","facade","content","legacy_resources"),&HardCoreMainSourceDeferred::observe_original_main_source_receivers);
 ClassDB::bind_method(D_METHOD("capabilities"),&HardCoreMainSourceDeferred::capabilities);
}
bool HardCoreMainSourceDeferred::configure_original_checkpoint_producer(const Ref<RefCounted>&p,const String&path,const String&digest){
 ERR_FAIL_COND_V(!Thread::is_main_thread()||producer.is_valid()||p.is_null()||path.is_empty()||digest.length()!=64,false);
 Ref<Script> script=p->get_script();if(script.is_null()||script->get_path()!=path||script->get_source_code().sha256_text()!=digest)return false;
 // Method presence does not grant cold scope. Actual Root code identity and
 // its returned current checkpoint/receiver facts are required every time.
 if(!p->has_method(SNAME("verify_original_main_source_checkpoint"))||!p->has_method(SNAME("observe_original_main_source_receiver_checkpoint")))return false;
 producer=p;producer_path=path;producer_sha256=digest;return true;
}
Dictionary HardCoreMainSourceDeferred::validate_checkpoint(const Dictionary&checkpoint,Node*facade,Node*content,Node*legacy)const{
 if(!Thread::is_main_thread()||producer.is_null())return missing("MISSING:actual_Root_Main_checkpoint_producer");
 if(!facade||!content||!legacy||!facade->is_inside_tree()||!content->is_inside_tree()||!legacy->is_inside_tree()||!plain_receipt(checkpoint))return missing("invalid_actual_Main_source_nodes_or_checkpoint");
 Ref<Script> script=producer->get_script();if(script.is_null()||script->get_path()!=producer_path||script->get_source_code().sha256_text()!=producer_sha256)return missing("Main_checkpoint_producer_source_changed");
 Variant reply=producer->call(SNAME("verify_original_main_source_checkpoint"),checkpoint,facade,content,legacy);
 if(reply.get_type()!=Variant::DICTIONARY)return missing("MISSING:original_legal_Main_checkpoint_receipt");Dictionary checked=reply;
 if(!plain_receipt(checked)||checked.get("success",Variant())!=Variant(true)||checked.get("checkpoint",Variant())!=Variant(checkpoint)||checked.get("producer_runtime_id",Variant())!=Variant(static_cast<int64_t>(producer->get_instance_id())))return missing("original_Main_checkpoint_identity_or_fact_rejected");
 return checked;
}
Dictionary HardCoreMainSourceDeferred::observe_queue(const Dictionary&checkpoint,Node*facade,Node*content,Node*legacy,bool flush){
 Dictionary verified=validate_checkpoint(checkpoint,facade,content,legacy);if(verified.get("success",Variant())!=Variant(true))return verified;
 CallQueue*queue=MessageQueue::get_main_singleton();if(!queue||MessageQueue::get_singleton()!=queue||queue->is_flushing())return missing("original_Main_queue_reentrant_or_foreign");
 uint64_t start=OS::get_singleton()->get_ticks_usec();bool before=queue->has_messages();Error error=flush?queue->flush():OK;bool after=queue->has_messages();uint64_t end=OS::get_singleton()->get_ticks_usec();
 Dictionary fact;fact["contract_id"]="hardcore.main.call_queue.observation.v1";fact["checkpoint"]=checkpoint.duplicate(true);fact["producer_runtime_id"]=static_cast<int64_t>(producer->get_instance_id());fact["facade_id"]=static_cast<int64_t>(facade->get_instance_id());fact["content_id"]=static_cast<int64_t>(content->get_instance_id());fact["legacy_resources_id"]=static_cast<int64_t>(legacy->get_instance_id());fact["actual_start_usec"]=static_cast<int64_t>(start);fact["actual_finish_usec"]=static_cast<int64_t>(end);fact["process_frame"]=static_cast<int64_t>(Engine::get_singleton()->get_process_frames());fact["physics_frame"]=static_cast<int64_t>(Engine::get_singleton()->get_physics_frames());fact["flush_invoked"]=flush;fact["flush_error"]=static_cast<int64_t>(error);fact["before_has_messages"]=before;fact["after_has_messages"]=after;fact["all_io_completed"]=false; // Queue observation cannot attest IO.
 Dictionary r;r["success"]=error==OK&&!after;r["receipt"]=fact;r["details"]=verified;Array errors;if(error!=OK)errors.push_back("actual_Main_CallQueue_flush_failed");if(after)errors.push_back("actual_Main_queue_nonterminal");r["errors"]=errors;
 if(!flush){Variant terminal=producer->call(SNAME("observe_original_main_source_receiver_checkpoint"),checkpoint,facade,content,legacy);if(terminal.get_type()!=Variant::DICTIONARY||!plain_receipt(terminal)||Dictionary(terminal).get("success",Variant())!=Variant(true)){r["success"]=false;errors.push_back("MISSING:actual_original_IO_UI_writer_receiver_terminal_receipt");r["errors"]=errors;}else r["receiver_receipt"]=terminal;
  // The real IO/receiver observer may uncover or deliver source callbacks.
  // Sample the original queue again after that actual terminal checkpoint.
  fact["terminal_has_messages"]=queue->has_messages();fact["terminal_is_flushing"]=queue->is_flushing();fact["actual_finish_usec"]=static_cast<int64_t>(OS::get_singleton()->get_ticks_usec());r["receipt"]=fact;
  if(static_cast<bool>(fact["terminal_has_messages"])||static_cast<bool>(fact["terminal_is_flushing"])){r["success"]=false;errors.push_back("IO_or_receiver_produced_nonterminal_original_Main_callbacks");r["errors"]=errors;}}
 return r;
}
Dictionary HardCoreMainSourceDeferred::flush_original_main_source_checkpoint(const Dictionary&c,Node*f,Node*d,Node*l){return observe_queue(c,f,d,l,true);}
Dictionary HardCoreMainSourceDeferred::observe_original_main_source_receivers(const Dictionary&c,Node*f,Node*d,Node*l){return observe_queue(c,f,d,l,false);}
Dictionary HardCoreMainSourceDeferred::capabilities()const{ERR_FAIL_COND_V(!Thread::is_main_thread(),Dictionary());Dictionary d;d["actual_Main_only_queue_observation"]=true;d["checkpoint_producer_bound"]=producer.is_valid();d["queue_empty_proves_io_or_ui"]=false;d["production_Root_checkpoint_receiver_closure"]=false;return d;}
