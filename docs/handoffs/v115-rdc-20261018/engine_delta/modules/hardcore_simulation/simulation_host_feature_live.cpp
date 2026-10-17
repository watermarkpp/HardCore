#include "simulation_host.h"
#include "core/config/engine.h"
#include "feature_live_transport.h"
#include "feature_live_schema.h"
#include "feature_live_source_seal.h"
#include "content_value_graph.h"
#include "core/io/marshalls.h"
#include "scene/main/node.h"

using FeatureLive=hardcore::simulation::AsyncLiveResourceMailbox;
namespace {
bool str(const Variant&v){return v.get_type()==Variant::STRING||v.get_type()==Variant::STRING_NAME;}
bool dict(const Variant&v){return v.get_type()==Variant::DICTIONARY;}
bool arr(const Variant&v){return v.get_type()==Variant::ARRAY;}
bool pos(const Variant&v){return v.get_type()==Variant::INT&&int64_t(v)>0;}
bool ref(const Variant&v){if(!dict(v))return false;Dictionary d=v;return d.size()==5&&d.get("contract_id",Variant())==Variant("feature.main.reference.v1")&&pos(d.get("token_id",Variant()))&&d.get("object_id",Variant()).get_type()==Variant::INT&&int64_t(d["object_id"])!=0&&pos(d.get("bridge_generation",Variant()))&&arr(d.get("native_types",Variant()));}
bool nullable_ref(const Variant&v){return v.get_type()==Variant::NIL||ref(v);}
bool original_retiring_world(const Variant&value){
 if(!dict(value))return false;Dictionary w=value;
 if(w.size()!=5||w.get("contract_id",Variant())!=Variant("hardcore.execution.world_context.v1")||!pos(w.get("world_runtime_id",Variant()))||w.get("world_epoch",Variant()).get_type()!=Variant::INT||int64_t(w["world_epoch"])<0||w.get("runtime_map_id",Variant()).get_type()!=Variant::INT||w.get("profile_id",Variant()).get_type()!=Variant::STRING||String(w["profile_id"]).is_empty())return false;
 return int64_t(w["runtime_map_id"])>=0||(int64_t(w["runtime_map_id"])==-1&&int64_t(w["world_epoch"])==0);
}
bool original_retiring_actor(const Variant&value){
 if(!dict(value))return false;Dictionary actor=value;
 if(actor.size()!=3||!original_retiring_world(actor.get("world",Variant()))||!pos(actor.get("runtime_id",Variant()))||actor.get("life_generation",Variant()).get_type()!=Variant::INT)return false;
 Dictionary w=actor["world"];return int64_t(actor["life_generation"])>=(int64_t(w["runtime_map_id"])==-1?0:1);
}
bool original_map_warm_request(const Variant&value){
 if(!dict(value))return false;Dictionary r=value;
 if(r.size()!=12||r.get("contract_id",Variant())!=Variant("hardcore.source.map_warm_request.v1")||!dict(r.get("world_context",Variant()))||r.get("source_root_id",Variant()).get_type()!=Variant::INT||int64_t(r["source_root_id"])==0||!pos(r.get("owner_session_id",Variant()))||r.get("transition_id",Variant()).get_type()!=Variant::STRING||String(r["transition_id"]).is_empty()||r.get("coordinator_generation",Variant()).get_type()!=Variant::INT||int64_t(r["coordinator_generation"])<0||r.get("map_id",Variant()).get_type()!=Variant::INT||int64_t(r["map_id"])<0||r.get("operation",Variant()).get_type()!=Variant::STRING||!arr(r.get("workset",Variant()))||!arr(r.get("item_names",Variant()))||r.get("facing",Variant()).get_type()!=Variant::VECTOR2||!Vector2(r["facing"]).is_finite()||r.get("player_position_px",Variant()).get_type()!=Variant::VECTOR2||!Vector2(r["player_position_px"]).is_finite())return false;
 Dictionary w=r["world_context"];if(w.size()!=5||w.get("contract_id",Variant())!=Variant("hardcore.execution.world_context.v1")||!pos(w.get("world_runtime_id",Variant()))||w.get("world_epoch",Variant()).get_type()!=Variant::INT||int64_t(w["world_epoch"])<0||w.get("runtime_map_id",Variant()).get_type()!=Variant::INT||w.get("profile_id",Variant()).get_type()!=Variant::STRING||String(w["profile_id"]).is_empty())return false;
 if(int64_t(w["runtime_map_id"])<0&&!(int64_t(w["runtime_map_id"])==-1&&int64_t(w["world_epoch"])==0))return false;
 String operation=r["operation"];if(operation!="loot_icons"&&operation!="workset"&&operation!="render")return false;
 Array workset=r["workset"],items=r["item_names"],seen;if(workset.size()>7)return false;
 for(int n=0;n<workset.size();++n){if(workset[n].get_type()!=Variant::STRING||String(workset[n]).is_empty()||seen.has(workset[n]))return false;seen.push_back(workset[n]);}
 for(int n=0;n<items.size();++n)if(items[n].get_type()!=Variant::STRING||String(items[n]).is_empty())return false;
 return operation=="loot_icons"?workset.is_empty():items.is_empty();
}
std::string opname(const StringName&op){CharString c=String(op).utf8();return std::string(c.get_data(),c.length());}
FeatureLive::Bytes wire(const Variant&v){HardCoreContentValueGraph graph;if(graph.validate(v,false).get("success",Variant())!=Variant(true))return {};int n=0;if(encode_variant(v,nullptr,n,false)!=OK||n<=0)return {};auto b=std::make_shared<std::vector<uint8_t>>(n);if(encode_variant(v,b->data(),n,false)!=OK)return {};return b;}
bool decode(const FeatureLive::Bytes&b,Dictionary&out){if(!b||b->empty()||b->size()>INT32_MAX)return false;Variant v;int n=0;if(decode_variant(v,b->data(),int(b->size()),&n,false)!=OK||n!=int(b->size())||!dict(v))return false;out=v;return true;}
Dictionary invalid(const char*error){Dictionary d;d["status"]="INVALID";d["error"]=error;return d;}
bool actual_id(const Dictionary&i,FeatureLive::Identity&id){if(i.size()!=2||!pos(i.get("bridge_generation",Variant()))||!pos(i.get("op_sequence",Variant())))return false;id={uint64_t(int64_t(i["bridge_generation"])),uint64_t(int64_t(i["op_sequence"]))};return true;}
bool physical_refs(const Ref<RefCounted>&main,const Variant&value,int depth=0){
 if(depth>64)return false;if(ref(value)){Dictionary d=value;Variant vault_value=main->get("_vault");if(!dict(vault_value))return false;Dictionary vault=vault_value;Variant entry=vault.get(d["token_id"],Variant());if(!dict(entry)||Dictionary(entry).get("descriptor",Variant())!=value)return false;Array types=d["native_types"];return types.has("Callable")?Dictionary(entry).get("value",Variant()).get_type()==Variant::CALLABLE:ObjectDB::get_instance(ObjectID(uint64_t(int64_t(d["object_id"]))))!=nullptr;}
 if(arr(value)){Array a=value;for(int n=0;n<a.size();++n)if(!physical_refs(main,a[n],depth+1))return false;}
 if(dict(value)){Dictionary d=value;Array keys=d.keys();for(int n=0;n<keys.size();++n)if(!physical_refs(main,d[keys[n]],depth+1))return false;}return true;
}
}
namespace hardcore::simulation {
bool feature_live_cleanup_opcode(const StringName&op,const Array&args){
 if(feature_live_cleanup(opname(op)))return true;
 if(op!=SNAME("feature.object_call")||args.size()!=3||!feature_live_arguments(op,args)||args[1]!=Variant("source_application_call"))return false;
 Array call=args[2];return call[0]==Variant("panel_state")||call[0]==Variant("release_map_scope")||call[0]==Variant("map_warm_state")||call[0]==Variant("world_view_exit_state")||call[0]==Variant("actor_view_free_state");
}
bool feature_live_arguments(const StringName&op,const Array&a){
 int count=feature_live_arity(opname(op));if(count<0||a.size()!=count)return false;String s=op;
 if(s=="feature.object_get"){if(!ref(a[0])||!str(a[1]))return false;for(const char*p:{"root","current_scene","resource_path","scene_file_path","_launch_code_generation","launch_loading_overlay","_retained_code_resource"})if(a[1]==Variant(p))return true;return false;}
 if(s=="feature.object_call"){
  if(!ref(a[0])||!str(a[1])||!arr(a[2]))return false;Array call=a[2];if(feature_live_method_arity(opname(StringName(a[1])))!=call.size())return false;
  if(a[1]!=Variant("source_application_call"))return true;
  if(!str(call[0])||!arr(call[1]))return false;String leaf=call[0];Array args=call[1];
  if(leaf=="prepare_directory")return args.size()==1&&args[0].get_type()==Variant::STRING&&!String(args[0]).is_empty();
  if(leaf=="world_view_exit_state")return args.size()==1&&original_retiring_world(args[0]);
  if(leaf=="actor_view_free_state")return args.size()==1&&original_retiring_actor(args[0]);
  if(leaf=="view_ready")return args.size()==2&&dict(args[0])&&pos(args[1]);
  if(leaf=="panel_state")return args.size()==1&&pos(args[0]);
  if(leaf=="prewarm_panels"||leaf=="budgeted_panels")return args.size()==2&&pos(args[0])&&pos(args[1]);
  if(leaf=="catalog_icons")return args.size()==2&&pos(args[0])&&args[1].get_type()==Variant::BOOL;
  if(leaf=="map_scope")return args.size()==4&&dict(args[0])&&args[1].get_type()==Variant::STRING&&!String(args[1]).is_empty()&&args[2].get_type()==Variant::INT&&int64_t(args[2])>=0&&args[3].get_type()==Variant::INT&&int64_t(args[3])>=0;
  if(leaf=="map_warm_start"||leaf=="map_warm_state")return args.size()==1&&original_map_warm_request(args[0]);
  return leaf=="release_map_scope"&&args.size()==1&&dict(args[0]);
 }
 if(s=="feature.object_script"||s=="feature.object_valid"||s=="feature.callback_valid")return nullable_ref(a[0]);
 if(s=="feature.release_reference")return ref(a[0]);
 if(s=="feature.has_method")return nullable_ref(a[0])&&str(a[1])&&!String(a[1]).is_empty();
 if(s=="feature.callback_invoke")return ref(a[0])&&dict(a[1]);
 if(s=="feature.get_cached_ref"||s=="feature.status"||s=="feature.get")return str(a[0])&&!String(a[0]).is_empty();
 if(s=="feature.exists")return str(a[0])&&!String(a[0]).is_empty()&&str(a[1]);
 if(s=="feature.request")return str(a[0])&&!String(a[0]).is_empty()&&str(a[1])&&(a[1]==Variant("Texture2D")||a[1]==Variant("AudioStream")||a[1]==Variant("Script"))&&a[2]==Variant(false);
 if(s=="feature.adopt_claims")return str(a[0])&&!String(a[0]).is_empty()&&pos(a[1]);
 if(s=="feature.valid_resource")return str(a[0])&&nullable_ref(a[1]);
 if(s=="feature.open_image")return str(a[0])&&!String(a[0]).is_empty()&&a[1]==Variant(1); // Original READ; never authoring writes.
 if(s=="feature.issue_resource_lease")return dict(a[0])&&dict(a[1])&&ref(a[2])&&dict(a[3]);
 if(s=="feature.retain_publication")return dict(a[0]);
 if(s=="feature.release_retention")return pos(a[0])&&pos(a[1]);
 if(s=="feature.retention_supports_path")return pos(a[0])&&pos(a[1])&&str(a[2]);
 if(s=="feature.issue_code_inputs")return ref(a[0])&&dict(a[1])&&ref(a[2])&&dict(a[3]);
 if(s=="feature.begin_code_verification")return dict(a[0])&&str(a[1])&&ref(a[2])&&ref(a[3]);
 if(s=="feature.begin_export_verification")return dict(a[0])&&str(a[1])&&a[2].get_type()==Variant::BOOL;
 if(s=="feature.code_scope_check")return ref(a[0])&&ref(a[1])&&a[2].get_type()==Variant::INT&&int64_t(a[2])>=0;
 if(s=="feature.code_inputs_admit")return dict(a[0])&&str(a[1])&&!String(a[1]).is_empty()&&ref(a[2])&&ref(a[3])&&ref(a[4])&&a[5].get_type()==Variant::INT&&int64_t(a[5])>=0;
 if(s=="feature.code_publication_admit")return a[0].get_type()==Variant::STRING&&String(a[0]).length()==64&&pos(a[1])&&int64_t(a[1])<=268435456&&ref(a[2])&&ref(a[3])&&ref(a[4])&&a[5].get_type()==Variant::INT&&int64_t(a[5])>=0&&a[6].get_type()==Variant::INT&&int64_t(a[6])>=0&&dict(a[7]);
 if(s=="feature.code_publication_owner")return ref(a[0])&&ref(a[1])&&ref(a[2])&&a[3].get_type()==Variant::INT&&int64_t(a[3])>=0&&a[4].get_type()==Variant::INT&&int64_t(a[4])>=0;
 if(s=="feature.code_publication_apply"){
  if(!ref(a[0])||!dict(a[1])||!ref(a[2])||a[3].get_type()!=Variant::INT||int64_t(a[3])<0)return false;Dictionary f=a[1];
  return f.size()==8&&pos(f.get("request_id",Variant()))&&f.get("kind",Variant())==Variant("code_publication")&&ref(f.get("scope",Variant()))&&ref(f.get("consumer",Variant()))&&f.get("generation",Variant()).get_type()==Variant::INT&&int64_t(f["generation"])>=0&&f.get("image_sha256",Variant()).get_type()==Variant::STRING&&f.get("expected_sha256",Variant()).get_type()==Variant::STRING&&String(f["expected_sha256"]).length()==64&&nullable_ref(f.get("export_verifier",Variant()));
 }
 if(s=="feature.code_target_admission"||s=="feature.code_target_deliver")return ref(a[0])&&ref(a[1])&&ref(a[2])&&a[3].get_type()==Variant::INT&&int64_t(a[3])>=0&&ref(a[4])&&(s=="feature.code_target_admission"?(a[5].get_type()==Variant::STRING&&String(a[5]).begins_with("res://")&&String(a[5]).ends_with(".gd")):nullable_ref(a[5]));
 if(s=="feature.code_image_chunk")return ref(a[0])&&pos(a[1])&&int64_t(a[1])<=268435456&&a[2]==Variant(262144);
 if(s=="feature.code_image_close"||s=="feature.code_scope_cancel")return ref(a[0]);
 if(s=="feature.acquire_shader")return ref(a[0])&&ref(a[1])&&ref(a[2])&&a[3].get_type()==Variant::INT&&int64_t(a[3])>=0&&str(a[4])&&dict(a[5]);
 return false;
}
bool feature_live_result(const StringName&op,const Variant&r){
 if(feature_live_arity(opname(op))<0)return false;String s=op;
 if(s=="feature.status")return r.get_type()==Variant::INT&&int64_t(r)>=0&&int64_t(r)<=3;
 if(s=="feature.request")return r.get_type()==Variant::INT;
 if(s=="feature.exists"||s=="feature.object_valid"||s=="feature.has_method"||s=="feature.callback_valid"||s=="feature.adopt_claims"||s=="feature.valid_resource"||s=="feature.release_retention"||s=="feature.retention_supports_path"||s=="feature.release_reference")return r.get_type()==Variant::BOOL;
 if(s=="feature.get"||s=="feature.get_cached_ref"||s=="feature.object_script"||s=="feature.open_image"||s=="feature.issue_code_inputs"||s=="feature.begin_export_verification")return nullable_ref(r);
 if(s=="feature.code_scope_check"||s=="feature.code_publication_owner"||s=="feature.code_publication_apply"||s=="feature.code_target_deliver"||s=="feature.code_image_close"||s=="feature.code_scope_cancel")return r.get_type()==Variant::BOOL;
 if(s=="feature.code_inputs_admit"){if(!dict(r))return false;Dictionary d=r;return d.size()==3&&d.get("success",Variant()).get_type()==Variant::BOOL&&arr(d.get("errors",Variant()))&&nullable_ref(d.get("plan",Variant()));}
 if(s=="feature.code_publication_admit"){if(!dict(r))return false;Dictionary d=r;Variant ok=d.get("success",Variant());if(ok.get_type()!=Variant::BOOL||!arr(d.get("errors",Variant())))return false;return bool(ok)?(d.size()==4&&ref(d.get("publisher",Variant()))&&nullable_ref(d.get("export_verifier",Variant()))):d.size()==2;}
 if(s=="feature.code_target_admission"){if(!dict(r))return false;Dictionary d=r;return d.size()==6&&d.get("success",Variant()).get_type()==Variant::BOOL&&nullable_ref(d.get("resource",Variant()))&&d.get("started",Variant()).get_type()==Variant::BOOL&&d.get("mode",Variant()).get_type()==Variant::STRING&&d.get("error",Variant()).get_type()==Variant::STRING&&d.get("admission_usec",Variant()).get_type()==Variant::INT&&int64_t(d["admission_usec"])>=0;}
 if(s=="feature.code_image_chunk"){if(!dict(r))return false;Dictionary d=r;Variant b=d.get("bytes",Variant());return d.size()==3&&d.get("success",Variant()).get_type()==Variant::BOOL&&b.get_type()==Variant::PACKED_BYTE_ARRAY&&PackedByteArray(b).size()<=262144&&d.get("done",Variant()).get_type()==Variant::BOOL;}
 if(s=="feature.begin_code_verification")return dict(r); // Actual Guard.begin_verification returns its admission Dictionary.
 if(s=="feature.retain_publication"){if(!dict(r))return false;Dictionary d=r;return d.size()==2&&d.get("success",Variant()).get_type()==Variant::BOOL&&d.get("retention_id",Variant()).get_type()==Variant::INT&&int64_t(d["retention_id"])>=0;}
 if(s=="feature.issue_resource_lease"){if(!dict(r))return false;Dictionary d=r;return d.size()==2&&nullable_ref(d.get("main_lease",Variant()))&&dict(d.get("resource_publication",Variant()));}
 if(s=="feature.acquire_shader")return dict(r); // Actual pinned Acquire implementation checks its exact result contract.
 return bool(wire(r)); // Plain native values or verified Main tokens, including original callback return.
}
}

bool HardCoreSimulationHost::live_feature_main_valid()const{
 if(!Thread::is_main_thread()||live_feature_main.is_null()||!live_feature_bound.load(std::memory_order_acquire))return false;Ref<Script>s=live_feature_main->get_script();return s.is_valid()&&s->get_instance_id()==live_feature_script_id&&s->is_valid()&&s->get_source_code()==live_feature_source&&reinterpret_cast<uintptr_t>(live_feature_main->get_script_instance())==live_feature_instance;
}
bool HardCoreSimulationHost::bind_live_original_feature_main_executor(const Ref<RefCounted>&p,const String&sha){
 if(!Thread::is_main_thread()||p.is_null()||live_feature_main.is_valid()||!live_resources||sha!=FEATURE_LIVE_SOURCE_SHA)return false;Ref<Script>s=p->get_script();Variant f=p->get("_facade");Node*facade=f.get_type()==Variant::OBJECT?Object::cast_to<Node>(static_cast<Object*>(f)):nullptr;
 if(s.is_null()||s->get_path()!=String("res://scripts/features/runtime/feature_resource_main_primitives.gd")||s->get_source_code().sha256_text()!=sha||!facade||!facade->is_inside_tree()||p->get("_generation")!=Variant(int64_t(bridge_generation))||p->call(SNAME("bind_original_live_feature_native"),this)!=Variant(true))return false;
 live_feature_main=p;live_feature_script_id=s->get_instance_id();live_feature_instance=reinterpret_cast<uintptr_t>(p->get_script_instance());live_feature_source=s->get_source_code();live_feature_bound.store(true,std::memory_order_release);live_feature_closed.store(false,std::memory_order_release);return true;
}
bool HardCoreSimulationHost::validate_live_original_feature_execution(const Dictionary&r){
 if(!live_feature_main_valid()||live_feature_execution.is_empty()||live_feature_execution_claimed||r!=live_feature_execution)return false;live_feature_execution_claimed=true;return true;
}
bool HardCoreSimulationHost::live_feature_reply_actual(const Dictionary&r)const{return live_feature_main_valid()&&!live_feature_execution.is_empty()&&live_feature_execution_claimed&&r==live_feature_actual_reply;}
void HardCoreSimulationHost::drain_live_feature_transfer_receipts(){
 if(!live_feature_main_valid())return;for(auto it=live_feature_transfers.begin();it!=live_feature_transfers.end();){FeatureLive::Identity id{bridge_generation,it->first};auto state=live_resources->acknowledge_actual_lease_transfer_status(id,it->second);if(state==FeatureLive::TransferStatus::TRANSFERRED){it=live_feature_transfers.erase(it);close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();}else ++it;}
}
Dictionary HardCoreSimulationHost::execute_pending_live_original_feature(const Dictionary&packet){
 if(!live_feature_main_valid()||!live_resources||packet.get("channel",Variant())!=Variant("resource_live")||!dict(packet.get("request",Variant())))return invalid("actual_Feature_Main_executor_required");
 Dictionary caller=packet["request"];FeatureLive::Identity id;
 if(!dict(caller.get("identity",Variant()))||!actual_id(caller["identity"],id)||id.generation!=bridge_generation)return invalid("actual_Feature_operation_identity_required");
 auto pending=live_resources->lookup(id);Dictionary original;
 if(!pending.ready||!decode(pending.request.original.bytes,original)||original!=caller||!dict(caller.get("site",Variant()))||!arr(caller.get("args",Variant()))||!hardcore::simulation::feature_live_arguments(caller["op"],caller["args"]))return invalid("actual_Feature_admitted_wire_required");
 String op=caller["op"];Array args=caller["args"];
 if(live_feature_execution.is_empty()){
  if((op=="feature.status"||op=="feature.get")&&!pending.request.issued_claim_context){
   Variant indexed=live_feature_main->call(SNAME("original_live_feature_path_has_issued_responsibility"),args[0]);
   if(indexed.get_type()!=Variant::BOOL)return invalid("actual_Feature_issued_range_context_required");
   if(bool(indexed)){
    // Same-path normal jobs must prove their own actual request and terminal
    // status dependencies. This read-only Main check never borrows an issued
    // range or consumes its physical claim; frozen Native admission owns caller.
    Variant normal=live_feature_main->call(SNAME("verify_actual_original_normal_job_execution"),caller);
    if(normal.get_type()!=Variant::BOOL||!bool(normal))return invalid("actual_Feature_issued_range_context_required");
   }
  }
  if(!live_resources->claim_execution(id))return invalid("actual_Feature_prefix_or_unique_execution_required");
  Dictionary execution;execution["protocol"]="hardcore.streaming.primitives.v2";execution["identity"]=caller["identity"];execution["site"]=caller["site"];execution["operation"]=caller["op"];execution["arguments"]=caller["args"];execution["main_prefix"]=caller["main_prefix"];execution["budget"]=caller["reservation"];execution["predecessor_receipt"]=caller["admission_predecessor"];execution["output_slot"]=caller["output_slot"];execution["submitted_usec"]=caller["submitted_usec"];
  live_feature_execution=execution;live_feature_execution_claimed=false;live_feature_issued_prepared=false;live_feature_issued_folded=false;
 }else if(live_feature_execution.get("identity",Variant())!=caller.get("identity",Variant()))return invalid("actual_Feature_other_execution_still_held");
 Dictionary waiting;waiting["status"]="PENDING";waiting["identity"]=caller["identity"];
 if(!live_feature_issued_prepared){
  auto ready=prepare_issued_live_execution(pending.request,live_feature_execution);
  if(ready==hardcore::simulation::SourceEventReplyMailbox::Status::PENDING)return waiting;
  if(ready!=hardcore::simulation::SourceEventReplyMailbox::Status::READY){set_fault("Feature_live_issued_execution_range_rejected");return invalid("actual_Feature_issued_range_rejected_retained_debt");}
  live_feature_issued_prepared=true;
 }
 if(live_feature_executed_body.is_empty()){
  live_feature_execution_process_frame=Engine::get_singleton()->get_process_frames();int64_t cpu_start=sample_main_thread_cpu_usec();Variant executed=live_feature_main->call(SNAME("execute_original_live_feature"),live_feature_execution,caller);int64_t cpu_end=sample_main_thread_cpu_usec();
  if(!dict(executed)||cpu_start<0||cpu_end<cpu_start){set_fault("Feature_live_actual_execution_or_CPU_evidence_missing");return invalid("actual_Feature_execution_unproved_retained_debt");}
  Dictionary body=executed;
  if(body.get("executed",Variant())!=Variant(true)||body.get("request",Variant())!=Variant(live_feature_execution)||!hardcore::simulation::feature_live_result(caller["op"],body.get("result",Variant()))||!physical_refs(live_feature_main,body.get("result",Variant()))||(!pending.request.issued_claim_context&&body.has("issued_claim_facts"))){set_fault("Feature_live_actual_reply_or_physical_owner_rejected");return invalid("actual_Feature_reply_unproved_retained_debt");}
  // The real physical API has executed once. Keep its body across a busy fold;
  // another service turn may only complete this same body's transport stages.
  live_feature_executed_body=body.duplicate(true);live_feature_cpu_usec=cpu_end-cpu_start;
 }
 if(!live_feature_issued_folded){
  hardcore::simulation::SourceEventReplyMailbox::TransferRead record;
  if(pending.request.issued_claim_context){
   Dictionary context; if(!decode(pending.request.issued_claim_context,context))return invalid("actual_Feature_frozen_context_unreadable");
   Dictionary identity=context["identity"];hardcore::simulation::SourceEventReplyMailbox::TransferIdentity transfer{{uint64_t(int64_t(identity["bridge_generation"])),uint64_t(int64_t(identity["journal_generation"])),uint64_t(int64_t(identity["event_ordinal"]))},uint64_t(int64_t(identity["transfer_sequence"]))};
   record=caster_event_replies->inspect_transfer(transfer);
   if(record.status==hardcore::simulation::SourceEventReplyMailbox::Status::PENDING)return waiting;
   if(record.status!=hardcore::simulation::SourceEventReplyMailbox::Status::READY){set_fault("Feature_live_actual_issued_record_missing");return invalid("actual_Feature_issued_record_retained_debt");}
  }
  if(!issued_fold_original_physical_reply(live_feature_execution,live_feature_executed_body,pending.request.issued_claim_context?&record:nullptr)){set_fault("Feature_live_actual_issued_fold_rejected");return invalid("actual_Feature_issued_fold_retained_debt");}
  live_feature_issued_folded=true;
 }
 Dictionary owner;owner["kind"]="feature_main_owner";owner["actual_feature_main_id"]=int64_t(live_feature_main->get_instance_id());owner["bridge_generation"]=int64_t(bridge_generation);Array obligations;obligations.push_back(owner);
 Dictionary reply=live_feature_executed_body.duplicate(true);reply["request"]=caller;reply["main_cpu_usec"]=live_feature_cpu_usec;reply["actual_lease_obligations"]=obligations;reply["disposition"]=int64_t(reply["finished_usec"])>int64_t(caller["deadline_usec"])?SNAME("executed_late"):SNAME("executed");live_feature_actual_reply=reply;
 if(!submit_live_original_resource_result(caller["identity"],reply)){set_fault("Feature_live_original_reply_submission_rejected");return invalid("actual_Feature_result_not_submitted_retained_debt");}
 live_feature_transfers[id.sequence]=wire(obligations);
 live_feature_execution={};live_feature_actual_reply={};live_feature_executed_body={};live_feature_execution_claimed=false;live_feature_issued_prepared=false;live_feature_issued_folded=false;live_feature_cpu_usec=0;
 drain_live_feature_transfer_receipts();Dictionary out;out["status"]="READY";out["identity"]=caller["identity"];out["reply"]=reply;return out;
}

bool HardCoreSimulationHost::certify_live_original_feature_main_closed(){
 if(!live_feature_main_valid()||!close_requested.load(std::memory_order_acquire)||!live_feature_execution.is_empty())return false;drain_live_feature_transfer_receipts();if(!live_feature_transfers.empty()||live_resources->accepted_count()!=0||live_feature_main->call(SNAME("close_main"))!=Variant(true))return false;
 live_feature_closed.store(true,std::memory_order_release);close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return true;
}
