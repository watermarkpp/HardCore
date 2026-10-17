#include "simulation_host.h"
#include "feature_live_transport.h"
#include "feature_live_schema.h"
#include "content_value_graph.h"
#include "scene/2d/node_2d.h"
#include "source_admission_opcodes.h"
#include "source_caster_cleanup_policy.h"
#include "core/io/marshalls.h"
#include "core/os/os.h"
#include <algorithm>
#include <cmath>
#include <limits>
#ifdef WINDOWS_ENABLED
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <time.h>
#endif

// Build identity is supplied by SConstruct cppdefines after source sealing.
#define HARDCORE_NATIVE_STRINGIFY_INNER(value) #value
#define HARDCORE_NATIVE_STRINGIFY(value) HARDCORE_NATIVE_STRINGIFY_INNER(value)

using Mailbox=hardcore::simulation::OriginalPrimitiveMailbox;
namespace {
bool plain(const Variant&v,int depth=0){
    if(depth>64)return false;
    switch(v.get_type()){
        case Variant::OBJECT:case Variant::CALLABLE:case Variant::RID:case Variant::SIGNAL:return false;
        case Variant::FLOAT:return std::isfinite(static_cast<double>(v));
        case Variant::VECTOR2:return static_cast<Vector2>(v).is_finite();
        case Variant::VECTOR3:return static_cast<Vector3>(v).is_finite();
        case Variant::VECTOR4:return static_cast<Vector4>(v).is_finite();
        case Variant::ARRAY:{Array a=v;for(int i=0;i<a.size();++i)if(!plain(a[i],depth+1))return false;return true;}
        case Variant::DICTIONARY:{Dictionary d=v;Array keys=d.keys();for(int i=0;i<keys.size();++i)if(!plain(keys[i],depth+1)||!plain(d[keys[i]],depth+1))return false;return true;}
        default:return true;
    }
}
Mailbox::Bytes freeze(const Variant&v){
    if(!plain(v))return {};
    int n=0;if(encode_variant(v,nullptr,n,false)!=OK||n<=0)return {};
    auto b=std::make_shared<std::vector<uint8_t>>();b->resize(n);if(encode_variant(v,b->data(),n,false)!=OK)return {};return b;
}
bool thaw(const Mailbox::Bytes&b,Variant&v){int read=0;return b&&!b->empty()&&b->size()<=INT32_MAX&&decode_variant(v,b->data(),static_cast<int>(b->size()),&read,false)==OK&&read==b->size()&&plain(v);}
// Only a freshly decoded, already validated plain Native prefix reaches
// this seal. Delta events sent to the physical dispatcher remain independent
// mutable decodes, exactly as before; only the framing snapshot is shared.
void seal_main_prefix_value(const Variant &value) {
    if(value.get_type()==Variant::ARRAY){
        Array values=value;const Array &read=values;
        for(int i=0;i<read.size();++i)seal_main_prefix_value(read[i]);
        values.make_read_only();
    }else if(value.get_type()==Variant::DICTIONARY){
        Dictionary values=value;const Array keys=values.keys();
        for(int i=0;i<keys.size();++i){seal_main_prefix_value(keys[i]);seal_main_prefix_value(values.get(keys[i],Variant()));}
        values.make_read_only();
    }
}
bool integer(const Dictionary&d,const char*k,int64_t&v){if(!d.has(k)||d[k].get_type()!=Variant::INT)return false;v=d[k];return true;}
bool identity(const Dictionary&d,Mailbox::Identity&i){int64_t g=0,s=0;if(d.size()!=2||!integer(d,"bridge_generation",g)||g<=0||!integer(d,"op_sequence",s)||s<=0)return false;i={static_cast<uint64_t>(g),static_cast<uint64_t>(s)};return true;}
Dictionary identity(const Mailbox::Identity&i){Dictionary d;d["bridge_generation"]=static_cast<int64_t>(i.generation);d["op_sequence"]=static_cast<int64_t>(i.sequence);return d;}
bool string(const Variant&v){return v.get_type()==Variant::STRING||v.get_type()==Variant::STRING_NAME;}
bool positive_int(const Variant&v){return v.get_type()==Variant::INT&&static_cast<int64_t>(v)>0;}
bool texture_token(const Variant&v){return v.get_type()==Variant::INT&&static_cast<int64_t>(v)!=0;} // RefCounted ObjectID preserves bit63.
bool token_array(const Variant&v,bool receipts=false){if(v.get_type()!=Variant::ARRAY)return false;Array a=v;for(int i=0;i<a.size();++i)if(receipts?!positive_int(a[i]):!texture_token(a[i]))return false;return true;}
bool profile(const Dictionary&d){for(const char*k:{"idle","walk","attack","hit","death"})if(d.has(k)&&d[k].get_type()!=Variant::NIL&&!texture_token(d[k]))return false;return true;}
Mailbox::Bytes site_key(const Dictionary&s){
    // Fixed field order preserves exact Variant types and every identity field;
    // std::map compares all bytes, with no hash-only or delimiter identity.
    Array fields;for(const char*k:{"clock_epoch","domain","entry_id","entry_ordinal","bootstrap","observation_process_epoch"})fields.push_back(s[k]);
    Dictionary w=s["world_context"];Array context;for(const char*k:{"contract_id","world_runtime_id","world_epoch","runtime_map_id","profile_id"})context.push_back(w[k]);
    fields.push_back(context);fields.push_back(s["deadline_usec"]);return freeze(fields);
}
bool world(const Dictionary&d){
    int64_t runtime=0,epoch=0,map=0;
    return d.size()==5&&d.get("contract_id",Variant())==Variant("hardcore.execution.world_context.v1")&&integer(d,"world_runtime_id",runtime)&&runtime>0&&integer(d,"world_epoch",epoch)&&epoch>=0&&integer(d,"runtime_map_id",map)&&(map>=0||(map==-1&&epoch==0))&&d.has("profile_id")&&d["profile_id"].get_type()==Variant::STRING&&!static_cast<String>(d["profile_id"]).is_empty();
}
bool prefix_wire(const Dictionary&p,uint64_t generation,Mailbox::Prefix&prefix){
    int64_t gen=0,journal=0,through=0;
    if(p.size()!=4||!plain(p)||!integer(p,"bridge_generation",gen)||gen!=generation||!integer(p,"journal_generation",journal)||journal<=0||!integer(p,"through_ordinal",through)||through<0||!p.has("events")||p["events"].get_type()!=Variant::ARRAY)return false;
    prefix={generation,static_cast<uint64_t>(journal),static_cast<uint64_t>(through),freeze(p)};if(!prefix.bytes)return false;
    Array events=p["events"];int64_t prior=0;
    for(int n=0;n<events.size();++n){if(events[n].get_type()!=Variant::DICTIONARY)return false;Dictionary event=events[n];int64_t ordinal=0;if(!integer(event,"ordinal",ordinal)||ordinal<=0||(n&&ordinal!=prior+1))return false;auto bytes=freeze(event);if(!bytes)return false;prefix.events.push_back({static_cast<uint64_t>(ordinal),bytes});prior=ordinal;}
    return events.is_empty()||prior==through;
}
hardcore::simulation::SourceAdmissionOpcode admission_opcode(const StringName&op){CharString text=String(op).utf8();return hardcore::simulation::source_admission_opcode(std::string(text.get_data(),text.length()));}
bool source_admission_op(const StringName&op){return admission_opcode(op)!=hardcore::simulation::SourceAdmissionOpcode::INVALID;}
bool source_admission_side_receipts(const Dictionary&r){
 for(const char*k:{"native_observations","retirements","owner_calls"})if(!r.has(k)||r[k].get_type()!=Variant::ARRAY)return false;
 Array observations=r["native_observations"];for(int n=0;n<observations.size();++n)if(observations[n].get_type()!=Variant::DICTIONARY)return false;
 Array calls=r["owner_calls"];for(int n=0;n<calls.size();++n){if(calls[n].get_type()!=Variant::DICTIONARY)return false;Dictionary c=calls[n];if(c.size()!=2||!c.has("method")||!string(c["method"])||(StringName(c["method"])!=SNAME("cancel_all")&&StringName(c["method"])!=SNAME("cancel_code_owner"))||!c.has("arguments")||c["arguments"].get_type()!=Variant::ARRAY)return false;}return true;
}
bool source_admission_args(const StringName&op,const Array&a){
 if(op==SNAME("feature.source_admission_release_pins"))return a.size()==1&&a[0].get_type()==Variant::INT&&static_cast<int64_t>(a[0])>0;
 int count=static_cast<int>(hardcore::simulation::source_admission_arity(admission_opcode(op)));
 if(a.size()!=count)return false;for(int n=0;n<count;++n)if(a[n].get_type()!=Variant::DICTIONARY)return false;
 if(op==SNAME("feature.source_admission_prepare")){Dictionary lease=a[2];int64_t token=0;return lease.size()==5&&lease.get("contract_id",Variant())==Variant("feature.main.reference.v1")&&integer(lease,"token_id",token)&&token>0&&lease.has("object_id")&&lease["object_id"].get_type()==Variant::INT&&static_cast<int64_t>(lease["object_id"])!=0&&lease.has("bridge_generation")&&lease["bridge_generation"].get_type()==Variant::INT&&static_cast<int64_t>(lease["bridge_generation"])>0&&lease.has("native_types")&&lease["native_types"].get_type()==Variant::ARRAY;}
 return true;
}
// Only the actual epoch-zero GameRoot._ready may transfer the existing
// prepared Root's code lease. LIVE keeps its existing fixed whitelist.
bool cold_initial_code_claim_arguments(const StringName &op, const Array &args, const Dictionary &site) {
    if (op != SNAME("feature.object_call") || args.size() != 3 || args[1] != Variant("source_application_call") || args[2].get_type() != Variant::ARRAY) return false;
    Array reference_check; reference_check.push_back(args[0]); reference_check.push_back("source_application_call");
    if (!hardcore::simulation::feature_live_arguments(SNAME("feature.has_method"), reference_check)) return false;
    Array call = args[2];
    if (call.size() != 2 || call[0] != Variant("claim_initial_code_retention") || call[1].get_type() != Variant::ARRAY) return false;
    Array values = call[1];
    if (values.size() != 1 || values[0].get_type() != Variant::DICTIONARY) return false;
    Dictionary context = values[0]; int64_t epoch = -1, map = 0, clock_epoch = -1;
    return world(context) && integer(context, "world_epoch", epoch) && epoch == 0 && integer(context, "runtime_map_id", map) && map == -1
        && integer(site, "clock_epoch", clock_epoch) && clock_epoch == 0 && site.get("bootstrap", Variant()) == Variant(true)
        && site.get("domain", Variant()) == Variant("P") && site.get("entry_id", Variant()) == Variant("res://scripts/game_root.gd:_ready")
        && site.get("world_context", Variant()) == Variant(context);
}
bool typed_arguments(const StringName&op,const Array&a,bool resource,const Dictionary &cold_site=Dictionary()) {
    if(resource&&source_admission_op(op))return source_admission_args(op,a);
    if(resource&&String(op).begins_with("feature."))return hardcore::simulation::feature_live_arguments(op,a)||cold_initial_code_claim_arguments(op,a,cold_site);
    if(resource){
        if(op==SNAME("feature.status")||op==SNAME("feature.get"))return a.size()==1&&string(a[0]);
        if(op==SNAME("status")||op==SNAME("load_threaded_get"))return a.size()==1&&string(a[0]);
        if(op==SNAME("load_threaded_request"))return a.size()==3&&string(a[0])&&string(a[1])&&a[1]==Variant("Texture2D")&&a[2].get_type()==Variant::BOOL;
        if(op==SNAME("test_sync_load_count"))return a.is_empty();
        if(op==SNAME("test_sync_load_texture"))return a.size()==2&&string(a[0])&&a[1].get_type()==Variant::VECTOR2I;
        if(op==SNAME("retire_threaded_resource_claims")||op==SNAME("forget_invalid_claim"))return a.size()==2&&string(a[0])&&a[1].get_type()==Variant::INT&&static_cast<int64_t>(a[1])>0;
        if(op==SNAME("replace_roots"))return a.size()==2&&string(a[0])&&token_array(a[1]);
        if(op==SNAME("close_get_escrow"))return a.size()==1&&token_array(a[0],true);
        if(op==SNAME("observe_binding")||op==SNAME("retire_visual_binding"))return a.size()==1&&a[0].get_type()==Variant::INT&&static_cast<int64_t>(a[0])>0;
        if(op==SNAME("bind_profile")){
            if(a.size()!=3||!positive_int(a[0])||a[1].get_type()!=Variant::DICTIONARY||!profile(a[1])||a[2].get_type()!=Variant::DICTIONARY)return false;
            Dictionary id=a[2];int64_t service=0,generation=0;
            return integer(id,"service_id",service)&&service==static_cast<int64_t>(a[0])&&integer(id,"world_generation",generation)&&generation>=0&&id.has("resource_key")&&string(id["resource_key"]);
        }
        if(op==SNAME("bind_or_clear")){
            if(a.size()!=3||a[0].get_type()!=Variant::INT||static_cast<int64_t>(a[0])<=0||!string(a[1])||a[2].get_type()!=Variant::ARRAY)return false;
            StringName sub=a[1];Array args=a[2];
            if(sub==SNAME("visual_visible"))return args.size()==1&&args[0].get_type()==Variant::BOOL;
            if(sub==SNAME("visual_create_body_sprite"))return args.is_empty();
            if(sub==SNAME("sprite_texture"))return args.size()==1&&(args[0].get_type()==Variant::NIL||texture_token(args[0]));
        }
        return false;
    }
    if(op==SNAME("global_randi")||op==SNAME("global_randf")||op==SNAME("global_randomize"))return a.is_empty();
    if(op==SNAME("global_randi_range"))return a.size()==2&&a[0].get_type()==Variant::INT&&a[1].get_type()==Variant::INT;
    if(op==SNAME("global_randf_range"))return a.size()==2&&a[0].get_type()==Variant::FLOAT&&a[1].get_type()==Variant::FLOAT;
    if(op==SNAME("global_seed"))return a.size()==1&&a[0].get_type()==Variant::INT;
    return false;
}
bool typed_result(const StringName&op,const Variant&r,bool resource,const Array&args,uint64_t sequence){
    if(resource&&source_admission_op(op)){if(r.get_type()!=Variant::DICTIONARY)return false;Dictionary d=r;return d.has("success")&&d["success"].get_type()==Variant::BOOL;}
    if(resource&&String(op).begins_with("feature."))return hardcore::simulation::feature_live_result(op,r);
    if(resource){
        if(op==SNAME("feature.status"))return r.get_type()==Variant::INT&&static_cast<int64_t>(r)>=0&&static_cast<int64_t>(r)<=3;
        if(op==SNAME("feature.get")){
            if(r.get_type()==Variant::NIL)return true;if(r.get_type()!=Variant::DICTIONARY)return false;Dictionary d=r;int64_t token=0,object=0,generation=0;
            return d.size()==5&&d.get("contract_id",Variant())==Variant("feature.main.reference.v1")&&integer(d,"token_id",token)&&token>0&&integer(d,"object_id",object)&&object!=0&&integer(d,"bridge_generation",generation)&&generation>0&&d.has("native_types")&&d["native_types"].get_type()==Variant::ARRAY;
        }
        if(op==SNAME("status"))return r.get_type()==Variant::INT&&static_cast<int64_t>(r)>=0&&static_cast<int64_t>(r)<=3;
        if(op==SNAME("load_threaded_request"))return r.get_type()==Variant::INT;
        if(op==SNAME("load_threaded_get")||op==SNAME("test_sync_load_texture")){
            if(r.get_type()!=Variant::DICTIONARY)return false;Dictionary d=r;int64_t token=0,receipt=0;
            if(!d.has("is_texture")||d["is_texture"].get_type()!=Variant::BOOL||!integer(d,"token",token)||!d.has("size")||d["size"].get_type()!=Variant::VECTOR2)return false;
            return static_cast<bool>(d["is_texture"])?d.size()==4&&token!=0&&integer(d,"receipt",receipt)&&receipt==sequence:d.size()==3&&token==0&&static_cast<Vector2>(d["size"])==Vector2();
        }
        if(op==SNAME("bind_profile")||op==SNAME("bind_or_clear")||op==SNAME("observe_binding")){
            if(r.get_type()!=Variant::DICTIONARY)return false;Dictionary d=r;int64_t service=0,version=0,token=0,covered=0;
            if(d.size()!=9||!integer(d,"service_id",service)||service!=static_cast<int64_t>(args[0])||!integer(d,"binding_version",version)||version<0||!integer(d,"actual_texture_token",token)||!integer(d,"covered_main_mutation_sequence",covered)||covered<0||covered>sequence||!d.has("profile_identity")||d["profile_identity"].get_type()!=Variant::DICTIONARY||!d.has("active_resources")||d["active_resources"].get_type()!=Variant::DICTIONARY||!profile(d["active_resources"]))return false;
            for(const char*k:{"actual_visible","sprite_exists","texture_nonnull"})if(!d.has(k)||d[k].get_type()!=Variant::BOOL)return false;
            return static_cast<bool>(d["texture_nonnull"])?token!=0&&static_cast<bool>(d["sprite_exists"]):token==0;
        }
        return r.get_type()==Variant::BOOL;
    }
    if(op==SNAME("global_randi")||op==SNAME("global_randi_range"))return r.get_type()==Variant::INT;
    if(op==SNAME("global_randf")||op==SNAME("global_randf_range"))return r.get_type()==Variant::FLOAT&&std::isfinite(static_cast<double>(r));
    return r.get_type()==Variant::NIL;
}
}

bool HardCoreSimulationHost::cached_original_published_prefix(const Dictionary &value, OriginalMailbox::Prefix &prefix) const {
    if(!Thread::is_main_thread()||main_published_prefix_value.is_empty()||!value.is_read_only()||value.id()!=main_published_prefix_value.id()||!main_published_prefix_cache.bytes||main_published_prefix_cache.generation!=bridge_generation)return false;
    // Exact collection identity is safe only because the entire decoded tree
    // is read-only and this owner retains it. Mutable/foreign/equal copies use
    // the original full validation and encoding path below, without trust.
    prefix=main_published_prefix_cache;
    return true;
}
int64_t HardCoreSimulationHost::owner_thread_id()const{ERR_FAIL_COND_V(!is_owner(),0);return static_cast<int64_t>(owner.load(std::memory_order_acquire));}
Ref<HardCoreSimulationHost> HardCoreSimulationHost::resource_primitive_transport(){ERR_FAIL_COND_V(!is_owner(),{});return Ref<HardCoreSimulationHost>(this);}
Ref<HardCoreSimulationHost> HardCoreSimulationHost::world_primitive_transport(){ERR_FAIL_COND_V(!is_owner(),{});return Ref<HardCoreSimulationHost>(this);}
Dictionary HardCoreSimulationHost::capabilities()const{
    ERR_FAIL_COND_V((!Thread::is_main_thread()&&!is_owner())||!main_channels_prepared||main_channels_aborted||!original_primitives,Dictionary());Dictionary caps;
#ifdef HARDCORE_NATIVE_SOURCE_SHA256
    caps["native_source_sha256"] = HARDCORE_NATIVE_STRINGIFY(HARDCORE_NATIVE_SOURCE_SHA256);
    caps["native_source_identity_injected"] = true;
#else
    caps["native_source_sha256"] = "";
    caps["native_source_identity_injected"] = false;
#endif
    caps["protocol"]="hardcore.streaming.primitives.v2";caps["world_protocol"]="hardcore.world.primitives.v1";caps["bridge_generation"]=static_cast<int64_t>(bridge_generation);
    for(const char*k:{"original_point_continuation","explicit_observation_process_epoch","exclusive_same_epoch_budget","ordered_main_prefix","deadline_preserves_continuation","abort_owner_on_failure"})caps[k]=true;
    caps["live_resource_protocol"]="hardcore.streaming.live_primitives.v1";caps["live_nonblocking_submit_poll"]=live_resources!=nullptr;caps["main_prefix_delta_claim_required"]=true;caps["live_production_caller_closure"]=false;caps["source_admission_seven_opcodes"]=true;caps["nonzero_loading_nonblocking_scope"]=true;caps["Root_loading_producer_UI_IO_input_closure"]=false;caps["cold_bootstrap_only"]=true;
    caps["source_application_loading_call"]=true;caps["source_application_loading_cps"]=true;
    caps["shared_resource_world_sequence"]=true;caps["main_nonblocking_acquire"]=true;caps["single_reserved_return_slot"]=true;caps["os_suspend_wake"]=false;
    caps["profile_terminal_global_random_return_contract_id"]="hardcore.profile.global_random.return.v1";return caps;
}
int64_t HardCoreSimulationHost::next_original_operation_sequence()const{ERR_FAIL_COND_V(!is_owner()||!original_primitives,0);return static_cast<int64_t>(original_primitives->next_sequence());}
int64_t HardCoreSimulationHost::completed_original_operation_sequence()const{ERR_FAIL_COND_V(!is_owner()||!original_primitives,0);return static_cast<int64_t>(original_primitives->completed_sequence());}
int64_t HardCoreSimulationHost::next_original_call_ordinal(const Dictionary&s)const{ERR_FAIL_COND_V(!is_owner()||!original_primitives||!validate_original_source_site(s),0);return static_cast<int64_t>(original_primitives->next_call_ordinal(site_key(s)));}
bool HardCoreSimulationHost::finish_original_call_site(const Dictionary&s){ERR_FAIL_COND_V(!is_owner()||!original_primitives||!validate_original_source_site(s),false);return original_primitives->finish_call_site(site_key(s));}
Dictionary HardCoreSimulationHost::current_clock_frame()const{
    ERR_FAIL_COND_V(!is_owner(),Dictionary());Dictionary f=original_source_frame.duplicate(true);
    f["epoch"]=static_cast<int64_t>(current_epoch);f["source_process_frame"]=static_cast<int64_t>(source_process_frame);f["source_physics_frame"]=static_cast<int64_t>(source_physics_frame);
    f["paused"]=paused.load(std::memory_order_acquire);if(!f.has("time_scale"))f["time_scale"]=time_scale.load(std::memory_order_acquire);
    f["phase"]=String(current_phase_name);f["source_boundary"]=String(original_source_boundary);f["closing_session"]=closing_session;
    if(active_clock)f["next_release_usec"]=static_cast<int64_t>(active_clock->release_usec(current_epoch+1));
    return f;
}
bool HardCoreSimulationHost::bind_original_world_context(const Dictionary &w) {
    ERR_FAIL_COND_V(!is_owner() || !original_primitives, false);
    if (!world(w) || !plain(w) || original_primitives->in_flight()) return false;
    if (static_cast<int64_t>(w["runtime_map_id"]) == -1) {
        // Original GameRoot exists at epoch 0 before its first map arrival.
        // This is a structural context, never playable geometry or a target
        // map substituted for an already-committed arrival. Only the exact
        // immutable bootstrap identity may enter through this narrow gate.
        if (current_epoch != 0) return false;
        Dictionary expected;
        if (bootstrap.has("first_world_boot")) {
            if (bootstrap["first_world_boot"].get_type() != Variant::DICTIONARY) return false;
            Dictionary first = bootstrap["first_world_boot"];
            if (!first.has("world_identity") || first["world_identity"].get_type() != Variant::DICTIONARY) return false;
            expected = first["world_identity"];
        }
        if (bootstrap.has("world_identity")) {
            if (bootstrap["world_identity"].get_type() != Variant::DICTIONARY) return false;
            Dictionary top = bootstrap["world_identity"];
            if (!expected.is_empty() && expected != top) return false;
            expected = top;
        }
        if (expected.is_empty() || expected != w || (!primitive_world.is_empty() && primitive_world != w)) return false;
    }
    primitive_world = w.duplicate(true);
    return true;
}
bool HardCoreSimulationHost::stage_original_main_prefix(const Dictionary&p){
    ERR_FAIL_COND_V(!is_owner()||!original_primitives,false);int64_t generation=0,journal=0,through=0;
    if(p.size()!=4||!integer(p,"bridge_generation",generation)||generation!=bridge_generation||!integer(p,"journal_generation",journal)||journal<=0||!integer(p,"through_ordinal",through)||through<0||!p.has("events")||p["events"].get_type()!=Variant::ARRAY||!plain(p)){set_fault("invalid_original_main_prefix");return false;}
    Array events=p["events"];uint64_t prior=original_primitives->applied_prefix();
    for(int i=0;i<events.size();++i){if(events[i].get_type()!=Variant::DICTIONARY){set_fault("invalid_original_main_event");return false;}Dictionary event=events[i];int64_t ordinal=0;if(!integer(event,"ordinal",ordinal)||ordinal<=0||ordinal!=prior+1){set_fault("original_main_prefix_gap");return false;}prior=ordinal;}
    if(prior!=through){set_fault("original_main_prefix_not_exact");return false;}
    Mailbox::Prefix prefix;
    if(!prefix_wire(p,bridge_generation,prefix)||!original_primitives->stage_prefix(prefix)){set_fault("original_main_prefix_not_staged");return false;}
    original_main_prefix=p.duplicate(true);return true;
}
bool HardCoreSimulationHost::register_published_original_main_prefix(const Dictionary&p){
    ERR_FAIL_COND_V(!is_owner()||!original_primitives,false);Mailbox::Prefix prefix;
    if(!check_original_terminal_gameplay_random_prefix(p,false)){set_fault("terminal_gameplay_random_publication_mismatch");return false;}
    if(!prefix_wire(p,bridge_generation,prefix)||!original_primitives->register_published_prefix(prefix)){set_fault("published_original_prefix_producer_rejected");return false;}
    if(!check_original_terminal_gameplay_random_prefix(p,true)){set_fault("terminal_gameplay_random_publication_commit_mismatch");return false;}return true;
}
Dictionary HardCoreSimulationHost::try_register_published_original_main_prefix(const Dictionary&p){
    // A full bounded FIFO or contended try-lock is unaccepted work, never a
    // resource wait, Main ACK or transport fault. S retains its sole journal.
    auto invalid=[](const char*reason){Dictionary out;out["status"]="INVALID";out["error"]=reason;return out;};
    if(!is_owner()||!original_primitives)return invalid("actual_Source_publication_owner_required");
    if(!check_original_terminal_gameplay_random_prefix(p,false))return invalid("terminal_gameplay_random_publication_mismatch");
    Mailbox::Prefix prefix;if(!prefix_wire(p,bridge_generation,prefix))return invalid("actual_original_publication_prefix_schema");
    auto admitted=original_primitives->try_register_original_presentation_prefix(prefix);
    if(admitted==Mailbox::MainEventStatus::INVALID)return invalid("actual_original_publication_prefix_rejected");
    Dictionary out;out["status"]=admitted==Mailbox::MainEventStatus::READY?"READY":"PENDING";
    if(admitted==Mailbox::MainEventStatus::READY&&!check_original_terminal_gameplay_random_prefix(p,true)){
        set_fault("terminal_gameplay_random_publication_commit_mismatch");return invalid("terminal_gameplay_random_publication_commit_mismatch");
    }
    return out;
}
bool HardCoreSimulationHost::ack_published_original_main_prefix(const Dictionary&p,const Dictionary&a){
    ERR_FAIL_COND_V(!Thread::is_main_thread()||!original_primitives,false);Mailbox::Prefix prefix;int64_t generation=0,journal=0,through=0;
    if((!cached_original_published_prefix(p,prefix)&&!prefix_wire(p,bridge_generation,prefix))||a.size()!=4||!integer(a,"bridge_generation",generation)||generation!=prefix.generation||!integer(a,"journal_generation",journal)||journal!=prefix.journal_generation||!integer(a,"through_ordinal",through)||through!=prefix.through||!a.has("applied")||a["applied"].get_type()!=Variant::BOOL||!static_cast<bool>(a["applied"])||!original_primitives->ack_published_prefix(prefix)){set_fault("published_original_prefix_actual_ack_rejected");return false;}
    main_published_prefix_value=Dictionary();main_published_prefix_cache=Mailbox::Prefix();
    // A final ordinary ACK may be the only remaining closing progress. Main
    // records it above; only S may consume it and retire its original debt.
    // Serialize the revision update with the same wait mutex, so notification
    // cannot be lost between the close predicate and suspension. No new P/H,
    // IO result, retry or gameplay work is manufactured by this actual ACK.
    if(close_requested.load(std::memory_order_acquire)){
        {std::lock_guard<std::mutex> lock(mailbox_mutex);close_revision.fetch_add(1,std::memory_order_release);}
        wake.notify_all();
    }
    return true;
}
Dictionary HardCoreSimulationHost::completed_original_main_prefix_receipt(){
    ERR_FAIL_COND_V(!is_owner()||!original_primitives,Dictionary());auto receipt=original_primitives->consume_published_receipts();if(!receipt.applied)return {};
    Dictionary r;r["bridge_generation"]=static_cast<int64_t>(receipt.generation);r["journal_generation"]=static_cast<int64_t>(receipt.journal_generation);r["through_ordinal"]=static_cast<int64_t>(receipt.through);r["applied"]=true;return r;
}
Dictionary HardCoreSimulationHost::ordered_main_prefix()const{
    ERR_FAIL_COND_V(!is_owner()||!original_primitives||original_main_prefix.is_empty(),Dictionary());return original_main_prefix.duplicate(true);
}
bool HardCoreSimulationHost::validate_original_source_site(const Dictionary&s)const{
    int64_t epoch=0,entry=0,observation=0,deadline=0;
    if(s.size()!=8||!plain(s)||!integer(s,"clock_epoch",epoch)||epoch<0||!integer(s,"entry_ordinal",entry)||entry<0||!integer(s,"observation_process_epoch",observation)||observation!=source_process_frame||!integer(s,"deadline_usec",deadline)||deadline<=0||!s.has("bootstrap")||s["bootstrap"].get_type()!=Variant::BOOL||!s.has("domain")||!string(s["domain"])||!s.has("entry_id")||!string(s["entry_id"])||static_cast<String>(s["entry_id"]).is_empty()||!s.has("world_context")||s["world_context"].get_type()!=Variant::DICTIONARY||!world(s["world_context"])||s["world_context"]!=primitive_world)return false;
    bool boot=s["bootstrap"];StringName domain=s["domain"];
    if(domain!=SNAME("H")&&domain!=SNAME("P"))return false;
    if(epoch!=current_epoch||boot!=(current_epoch==0))return false;
    if(!boot&&!closing_session){bool h=current_phase==Clock::Phase::H_INPUT||current_phase==Clock::Phase::H_PREPARE||current_phase==Clock::Phase::H_GROUP||current_phase==Clock::Phase::H_AFTER_TIMERS||current_phase==Clock::Phase::H_STEP;
        if((domain==SNAME("H"))!=h)return false;
    }
    return true;
}
bool HardCoreSimulationHost::validate_original_site(const Dictionary&r,bool resource){
    if(!r.has("site")||r["site"].get_type()!=Variant::DICTIONARY)return false;Dictionary s=r["site"],base=s.duplicate(true);int64_t call=0;
    if(s.size()!=9||!integer(s,"call_ordinal",call)||call<=0)return false;base.erase("call_ordinal");if(!validate_original_source_site(base))return false;
    if(!resource&&(!r.has("world")||r["world"]!=s["world_context"]||!r.has("source_site")||r["source_site"]!=s))return false;
    // Full source site fields are checked before the original stack is parked.
    // Exact original entry identity/slot is published by the sole WorldCore;
    // it cannot be synthesized by display Main or a worker.
    auto key=site_key(base);if(!key||call!=original_primitives->next_call_ordinal(key))return false;
    if(!r.has("budget")||r["budget"].get_type()!=Variant::DICTIONARY)return false;
    Dictionary b=r["budget"];int64_t logical=0,ledger=0,started=0,spent=0,service=0,pending=0;
    if(b.size()!=10||!b.has("identity")||b["identity"]!=r["identity"]||!b.has("site")||b["site"]!=s||!integer(b,"logical_process_epoch",logical)||logical!=static_cast<int64_t>(s["observation_process_epoch"])||!integer(b,"ledger_epoch",ledger)||ledger< -1||!integer(b,"started_usec",started)||started<0||!integer(b,"spent_usec",spent)||spent<0||!integer(b,"service_sequence",service)||service<0||!integer(b,"pending_sequence",pending)||pending<0||!b.has("scopes")||b["scopes"].get_type()!=Variant::ARRAY||!b.has("lane_spent")||b["lane_spent"].get_type()!=Variant::ARRAY)return false;
    Array lanes=b["lane_spent"];if(lanes.size()!=3)return false;for(int n=0;n<3;++n)if(lanes[n].get_type()!=Variant::INT||static_cast<int64_t>(lanes[n])<0)return false;
    Array scopes=b["scopes"];int64_t last_token=0;
    for(int n=0;n<scopes.size();++n){
        if(scopes[n].get_type()!=Variant::DICTIONARY)return false;Dictionary scope=scopes[n];int64_t token=0,start=0,child=0,lane=0;
        if(scope.size()!=6||!integer(scope,"token",token)||token<=last_token||!integer(scope,"started_usec",start)||start<0||!integer(scope,"child_usec",child)||child<0||!integer(scope,"lane",lane)||lane<0||lane>2||!scope.has("category")||!string(scope["category"])||!scope.has("necessary")||scope["necessary"].get_type()!=Variant::BOOL)return false;
        last_token=token;
    }
    return true;
}
Dictionary HardCoreSimulationHost::exchange_primitive(const Dictionary&r,bool resource){
    ERR_FAIL_COND_V(!is_owner()||!original_primitives,Dictionary());
    if(current_epoch!=0&&!closing_session){set_fault("live_original_stack_park_forbidden");return {};}
    Mailbox::Identity id;int64_t predecessor=0,slot=0,submitted=0;
    if(r.size()!=(resource?10:12)||!plain(r)||r.get("protocol",Variant())!=Variant(resource?"hardcore.streaming.primitives.v2":"hardcore.world.primitives.v1")||!r.has("identity")||r["identity"].get_type()!=Variant::DICTIONARY||!identity(r["identity"],id)||id.generation!=bridge_generation||id.sequence!=original_primitives->next_sequence()||!integer(r,"predecessor_receipt",predecessor)||predecessor!=id.sequence-1||!integer(r,"output_slot",slot)||slot!=0||!integer(r,"submitted_usec",submitted)||submitted<=0||submitted>now_usec()||!r.has("operation")||!string(r["operation"])||!r.has("arguments")||r["arguments"].get_type()!=Variant::ARRAY||!typed_arguments(r["operation"],r["arguments"],resource,r.get("site",Dictionary()))||!r.has("main_prefix")||r["main_prefix"]!=original_main_prefix||!validate_original_site(r,resource)){
        set_fault("invalid_original_primitive_request");return {};
    }
    Dictionary execution=r;
    if(resource&&!issued_prepare_original_execution(r,execution)){set_fault("issued_claim_original_context_admission_rejected");return {};}
    Dictionary site=r["site"],prefix=r["main_prefix"];auto caller_bytes=freeze(r);auto bytes=freeze(execution);auto prefix_bytes=freeze(prefix);
    if(!caller_bytes||!bytes||!prefix_bytes){set_fault("original_primitive_freeze_failed");return {};}
    Mailbox::Request request;request.identity=id;request.predecessor=predecessor;request.submitted_usec=submitted;request.deadline_usec=static_cast<int64_t>(site["deadline_usec"]);request.channel=resource?Mailbox::Channel::RESOURCE:Mailbox::Channel::WORLD;request.bytes=bytes;
    if(!prefix_wire(prefix,bridge_generation,request.prefix)){set_fault("original_primitive_freeze_prefix_events_failed");return {};}
    request.source_site_bytes=site_key(site);request.call_ordinal=static_cast<int64_t>(site["call_ordinal"]);
    const uint64_t native_exchange_enter_usec=now_usec();
    auto received=original_primitives->exchange(request);
    const uint64_t native_exchange_return_usec=now_usec();
    if(!received.accepted){set_fault("original_primitive_admission_failed");return {};}
    Variant decoded;if(!thaw(received.bytes,decoded)||decoded.get_type()!=Variant::DICTIONARY){set_fault("invalid_accepted_original_result");return {};}
    Dictionary reply=decoded;Variant original_caller;
    if(reply.get("request",Variant())!=Variant(execution)||!thaw(caller_bytes,original_caller)||original_caller.get_type()!=Variant::DICTIONARY){set_fault("original_execution_wire_or_caller_mapping_rejected");return {};}
    reply["request"]=original_caller;
    const uint64_t received_usec=now_usec();bool late=received.late||received_usec>request.deadline_usec;
    if(late){original_deadline_failures.fetch_add(1,std::memory_order_relaxed);reply["disposition"]=SNAME("executed_late");}
    reply["native_received_usec"]=static_cast<int64_t>(received_usec);reply["native_deadline_status"]=late?"FAIL":"PASS";
    reply["native_exchange_enter_usec"]=static_cast<int64_t>(native_exchange_enter_usec);reply["native_exchange_return_usec"]=static_cast<int64_t>(native_exchange_return_usec);
    Dictionary ack;ack["bridge_generation"]=static_cast<int64_t>(received.prefix_ack.identity.generation);ack["journal_generation"]=static_cast<int64_t>(received.prefix_ack.journal_generation);ack["through_ordinal"]=static_cast<int64_t>(received.prefix_ack.through);ack["applied"]=received.prefix_ack.applied;reply["native_main_prefix_receipt"]=ack;
    return reply;
}
Dictionary HardCoreSimulationHost::exchange_original_primitive(const Dictionary&r){return exchange_primitive(r,true);}
Dictionary HardCoreSimulationHost::exchange_world_primitive(const Dictionary&r){return exchange_primitive(r,false);}
Dictionary HardCoreSimulationHost::acquire_pending_original_primitive(){
    ERR_FAIL_COND_V(!Thread::is_main_thread()||!original_primitives,Dictionary());issued_observe_main_io_delivery();auto pending=original_primitives->acquire_pending();if(!pending.valid())return {};
    Variant request,prefix;if(!thaw(pending.request.bytes,request)||!thaw(pending.request.prefix.bytes,prefix)){set_fault("original_packet_decode_failed");return {};}
    Dictionary packet;packet["channel"]=pending.request.channel==Mailbox::Channel::RESOURCE?"resource":"world";packet["request"]=request;packet["identity"]=identity(pending.request.identity);packet["predecessor"]=static_cast<int64_t>(pending.request.predecessor);packet["main_prefix"]=prefix;packet["output_slot"]=0;return packet;
}
bool HardCoreSimulationHost::ack_original_main_prefix(const Dictionary&i,const Dictionary&a){
    ERR_FAIL_COND_V(!Thread::is_main_thread()||!original_primitives,false);Mailbox::Identity id;int64_t generation=0,journal=0,through=0;
    if(a.size()!=5||!identity(i,id)||!integer(a,"bridge_generation",generation)||generation!=id.generation||!integer(a,"journal_generation",journal)||journal<=0||!integer(a,"through_ordinal",through)||through<0||!a.has("applied")||a["applied"].get_type()!=Variant::BOOL||!static_cast<bool>(a["applied"])||!a.has("main_prefix")){set_fault("invalid_original_prefix_ack");return false;}
    auto pending=original_primitives->lookup(id);auto bytes=freeze(a["main_prefix"]);if(!pending.valid()||!bytes||*bytes!=*pending.request.prefix.bytes){set_fault("original_prefix_ack_not_exact");return false;}
    Mailbox::Ack ack{id,static_cast<uint64_t>(journal),static_cast<uint64_t>(through),bytes,true};if(!original_primitives->ack_prefix(ack)){set_fault("original_prefix_ack_rejected");return false;}return true;
}
bool HardCoreSimulationHost::validate_original_primitive_ticket(const Dictionary&r,const StringName&kind){
    // The physical Main vault retains this one Host validator across its cold
    // and asynchronous lifetime. Dispatch only to the existing Native LIVE
    // execution claim, never to a second Main queue or permissive callback.
    if(kind==SNAME("original_live_resource_primitive"))return validate_live_original_resource_ticket(r);
    if(kind==SNAME("close_resource_generation"))return Thread::is_main_thread()&&main_vault_close_active&&r==main_vault_close_ticket&&source_model_close_completed.load(std::memory_order_acquire)&&close_requested.load(std::memory_order_acquire)&&original_primitives&&!original_primitives->in_flight()&&original_primitives->unsettled_published_count()==0&&(!live_resources||live_resources->accepted_count()==0)&&(!close_process_producer_bound.load(std::memory_order_acquire)||(close_process_frames&&close_process_frames->can_close()));
    ERR_FAIL_COND_V(!Thread::is_main_thread()||!original_primitives,false);if(!r.has("identity")||r["identity"].get_type()!=Variant::DICTIONARY)return false;
    Mailbox::Identity id;if(!identity(r["identity"],id))return false;auto pending=original_primitives->lookup(id);Variant actual;if(!pending.valid()||!thaw(pending.request.bytes,actual)||actual!=Variant(r)||!original_primitives->prefix_applied(id))return false;
    return kind==(pending.request.channel==Mailbox::Channel::RESOURCE?SNAME("original_resource_primitive"):SNAME("original_world_primitive"))&&original_primitives->claim_execution(id);
}
bool HardCoreSimulationHost::submit_original_primitive_result(const Dictionary&i,const Dictionary&r){
    ERR_FAIL_COND_V(!Thread::is_main_thread()||!original_primitives,false);Mailbox::Identity id;if(!identity(i,id)){set_fault("invalid_original_result_identity");return false;}
    auto pending=original_primitives->lookup(id);Variant request;if(!pending.valid()||!thaw(pending.request.bytes,request)||request.get_type()!=Variant::DICTIONARY)return false;
    Dictionary actual=request;Dictionary site=actual["site"];int64_t started=0,finished=0,prefix_ordinal=0;
    bool resource=pending.request.channel==Mailbox::Channel::RESOURCE;
    if(resource&&source_admission_op(actual["operation"])&&(r.size()!=10||!source_admission_side_receipts(r))){set_fault("missing_source_admission_side_receipts");return false;}
    bool issued_leaf=resource&&(actual["operation"]==Variant("feature.status")||actual["operation"]==Variant("feature.get"));
    const bool feature_reply = resource && String(actual["operation"]).begins_with("feature.");
    // The actual Feature executor always returns its synchronous retirement,
    // observation and owner-reentry side receipts, including for cold leaves.
    // Preserve all of them; accepting a shortened reply would lose obligations.
    const bool feature_reply_shape = feature_reply && source_admission_side_receipts(r) &&
            (r.size() == 10 || (issued_leaf && r.size() == 11 && r.has("issued_claim_facts")));
    if (feature_reply && !feature_reply_shape) { set_fault("missing_feature_original_side_receipts"); return false; }
    if((r.size()!=7&&!(resource&&r.size()==8&&r.has("native_observation")&&r["native_observation"].get_type()==Variant::DICTIONARY)&&!(resource&&source_admission_op(actual["operation"])&&r.size()==10&&source_admission_side_receipts(r))&&!feature_reply_shape)||!plain(r)||r.get("request",Variant())!=request||!r.has("executed")||r["executed"].get_type()!=Variant::BOOL||!static_cast<bool>(r["executed"])||!r.has("result")||!typed_result(actual["operation"],r["result"],resource,actual["arguments"],id.sequence)||!integer(r,"started_usec",started)||started<pending.request.submitted_usec||!integer(r,"finished_usec",finished)||finished<started||finished>now_usec()||!integer(r,"completed_prefix_ordinal",prefix_ordinal)||prefix_ordinal!=1||r.get("disposition",Variant())!=Variant(finished>static_cast<int64_t>(site["deadline_usec"])?SNAME("executed_late"):SNAME("executed"))){set_fault("invalid_original_primitive_result");return false;}
    if(resource&&StringName(actual["operation"])==SNAME("status")){
        if(!r.has("native_observation")||r["native_observation"].get_type()!=Variant::DICTIONARY){set_fault("missing_native_original_status_receipt");return false;}
        Dictionary observation=r["native_observation"];int64_t epoch=0,generation=0,status=0,native_start=0,native_end=0;
        if(observation.size()!=8||!observation.has("ok")||observation["ok"].get_type()!=Variant::BOOL||!static_cast<bool>(observation["ok"])||!integer(observation,"observation_process_epoch",epoch)||epoch!=static_cast<int64_t>(site["observation_process_epoch"])||!integer(observation,"bridge_generation",generation)||generation!=bridge_generation||!integer(observation,"status",status)||status!=static_cast<int64_t>(r["result"])||!integer(observation,"actual_start_usec",native_start)||native_start<started||!integer(observation,"actual_end_usec",native_end)||native_end<native_start||native_end>finished||!observation.has("progress")||observation["progress"].get_type()!=Variant::FLOAT||!observation.has("progress_ensured")||observation["progress_ensured"].get_type()!=Variant::BOOL){set_fault("invalid_native_original_status_receipt");return false;}
    }
    if(resource&&!issued_fold_original_physical_reply(actual,r)){set_fault("issued_claim_actual_physical_reply_rejected_retained_debt");return false;}
    auto bytes=freeze(r);Mailbox::Reply reply{id,pending.request.bytes,bytes,static_cast<uint64_t>(started),static_cast<uint64_t>(finished)};
    if(!bytes||!original_primitives->submit(reply)){set_fault("original_result_or_applied_prefix_rejected");return false;}
    return true;
}

using LiveMailbox=hardcore::simulation::AsyncLiveResourceMailbox;
bool HardCoreSimulationHost::current_host_paused()const{ERR_FAIL_COND_V(!is_owner(),false);return paused.load(std::memory_order_acquire);}
double HardCoreSimulationHost::current_host_time_scale()const{ERR_FAIL_COND_V(!is_owner(),0.0);return time_scale.load(std::memory_order_acquire);}
bool HardCoreSimulationHost::is_original_operation_completed(const Dictionary&d)const{ERR_FAIL_COND_V(!is_owner()||!original_primitives,false);Mailbox::Identity id;return identity(d,id)&&original_primitives->operation_completed(id);}
Dictionary HardCoreSimulationHost::capture_main_gameplay_random(){
    ERR_FAIL_COND_V(!Thread::is_main_thread()||started||gameplay_random_captured,Dictionary());
    const auto state=Math::capture_default_random_handoff();gameplay_random_captured=true;
    Dictionary d;d["contract_id"]="hardcore.gameplay_global_random.handoff.v1";d["seed"]=static_cast<int64_t>(state.seed);d["state"]=static_cast<int64_t>(state.state);d["increment"]=static_cast<int64_t>(state.increment);return d;
}
Dictionary HardCoreSimulationHost::acquire_original_main_prefix(const Dictionary&p){
    ERR_FAIL_COND_V(!Thread::is_main_thread()||!original_primitives,Dictionary());Mailbox::Prefix prefix;const bool cached=cached_original_published_prefix(p,prefix);if(!cached&&!prefix_wire(p,bridge_generation,prefix))return {};
    auto claim=original_primitives->claim_main_prefix(prefix);if(!claim.ready)return {};
    Array events;for(const auto&e:claim.events){Variant event;if(!thaw(e.bytes,event))return {};events.push_back(event);}
    Dictionary d;d["main_prefix"]=cached?p:p.duplicate(true);d["after_ordinal"]=static_cast<int64_t>(claim.after);d["through_ordinal"]=static_cast<int64_t>(claim.through);d["events"]=events;return d;
}
Dictionary HardCoreSimulationHost::submit_live_original_resource(const Dictionary&p){
    ERR_FAIL_COND_V(!is_owner()||!live_resources||!original_primitives,Dictionary());Dictionary invalid;invalid["status"]="INVALID";
    // Exact accepted preimages remain queryable across later source epochs.
    // Current source qualification applies only to a fresh admission.
    int64_t early_reservation=0,early_session=0;
    if(p.size()!=12||!plain(p)||!p.has("reservation")||p["reservation"].get_type()!=Variant::DICTIONARY||!integer(p["reservation"],"reservation_id",early_reservation)||early_reservation<=0||!integer(p["reservation"],"owner_session_id",early_session)||early_session<=0)return invalid;
    auto prewire=freeze(p);auto probe=live_resources->probe_submission(early_session,early_reservation,prewire);Dictionary duplicate;
    if(probe.status==LiveMailbox::Admission::BUSY){duplicate["status"]="BUSY";return duplicate;}if(probe.status==LiveMailbox::Admission::INVALID)return invalid;
    if(probe.status==LiveMailbox::Admission::DUPLICATE){Variant old;if(!thaw(probe.request.original.bytes,old))return invalid;duplicate["status"]="PENDING";duplicate["request"]=old;return duplicate;}
    int64_t submitted=0,deadline=0,priority=0;
    if(p.size()!=12||!plain(p)||p.get("protocol",Variant())!=Variant("hardcore.streaming.live_primitives.v1")||!p.has("site")||p["site"].get_type()!=Variant::DICTIONARY||!validate_original_source_site(p["site"])||static_cast<bool>(Dictionary(p["site"])["bootstrap"])||!p.has("op")||!string(p["op"])||!p.has("args")||p["args"].get_type()!=Variant::ARRAY||!typed_arguments(p["op"],p["args"],true)||StringName(p["op"])==SNAME("test_sync_load_count")||StringName(p["op"])==SNAME("test_sync_load_texture")||!integer(p,"submitted_usec",submitted)||submitted<=0||submitted>now_usec()||!integer(p,"deadline_usec",deadline)||deadline!=static_cast<int64_t>(Dictionary(p["site"])["deadline_usec"])||!integer(p,"priority",priority)||priority<0||priority>2||!p.has("order_key")||p["order_key"].get_type()!=Variant::STRING||static_cast<String>(p["order_key"]).is_empty()||!p.has("cleanup")||p["cleanup"].get_type()!=Variant::BOOL||!p.has("main_prefix")||p["main_prefix"].get_type()!=Variant::DICTIONARY||!p.has("reservation")||p["reservation"].get_type()!=Variant::DICTIONARY||!p.has("dependencies")||p["dependencies"].get_type()!=Variant::ARRAY)return invalid;
    if(String(p["op"]).begins_with("feature.")&&!source_admission_op(p["op"])&&!live_feature_bound.load(std::memory_order_acquire))return invalid;
    if(String(p["op"]).begins_with("feature.")&&!source_admission_op(p["op"])&&String(Dictionary(p["site"])["domain"])!="P")return invalid;
    Dictionary r=p.duplicate(true),site=r["site"],reservation=r["reservation"];
    if(source_admission_op(p["op"])){
        if(!source_admission_scopes)return invalid;CharString op=String(p["op"]).utf8();auto permission=source_admission_scopes->permission(current_source_scope,std::string(op.get_data(),op.length()));
        if(permission==hardcore::simulation::SourceAdmissionScopeLedger::Status::PENDING){Dictionary busy;busy["status"]="BUSY";return busy;}if(permission!=hardcore::simulation::SourceAdmissionScopeLedger::Status::READY)return invalid;
    }
    if(static_cast<bool>(p["cleanup"])){
        StringName op=p["op"];Array args=p["args"];
        if(op==SNAME("replace_roots")){if(!Array(args[1]).is_empty())return invalid;}
        else if(op==SNAME("bind_profile")){Dictionary profile=args[1];for(const char*key:{"idle","walk","attack","hit","death"})if(profile.has(key)&&profile[key].get_type()!=Variant::NIL)return invalid;}
        else if(op==SNAME("bind_or_clear")){StringName sub=args[1];Array values=args[2];if(!((sub==SNAME("sprite_texture")&&values[0].get_type()==Variant::NIL)||(sub==SNAME("visual_visible")&&!static_cast<bool>(values[0]))))return invalid;}
        else if(!hardcore::simulation::feature_live_cleanup_opcode(op,args)&&op!=SNAME("feature.source_admission_abort")&&op!=SNAME("feature.source_admission_release_pins")&&op!=SNAME("status")&&op!=SNAME("load_threaded_get")&&op!=SNAME("retire_threaded_resource_claims")&&op!=SNAME("forget_invalid_claim")&&op!=SNAME("close_get_escrow")&&op!=SNAME("retire_visual_binding")&&op!=SNAME("observe_binding"))return invalid;
    }
    int64_t rid=0,session=0,epoch=0,lane=0,reserved=0,issued=0;
    if(reservation.size()!=8||reservation.get("contract_id",Variant())!=Variant("hardcore.resource.budget_reservation.v1")||!integer(reservation,"reservation_id",rid)||rid<=0||!integer(reservation,"owner_session_id",session)||session<=0||!integer(reservation,"ledger_epoch",epoch)||epoch<0||!integer(reservation,"lane",lane)||lane<0||lane>2||!integer(reservation,"reserved_usec",reserved)||reserved<0||!integer(reservation,"issued_usec",issued)||issued<0||issued>submitted||!reservation.has("category")||reservation["category"].get_type()!=Variant::STRING||static_cast<String>(reservation["category"]).is_empty())return invalid;
    LiveMailbox::Request request;request.pre_admission_bytes=prewire;request.original.source_site_bytes=site_key(site);auto preview=original_primitives->preview_async(request.original.source_site_bytes);if(!preview.sequence){duplicate["status"]="BUSY";return duplicate;}auto sequence=preview.sequence;request.original.identity={bridge_generation,sequence};request.original.predecessor=sequence-1;request.original.call_ordinal=preview.call_ordinal;request.original.submitted_usec=submitted;request.original.deadline_usec=deadline;
    if(!prefix_wire(p["main_prefix"],bridge_generation,request.original.prefix))return invalid;
    request.order_key=freeze(p["order_key"]);request.priority=static_cast<int>(priority);request.cleanup=p["cleanup"];request.reservation={static_cast<uint64_t>(rid),static_cast<uint64_t>(session),static_cast<uint64_t>(epoch),static_cast<uint8_t>(lane),static_cast<uint64_t>(reserved),static_cast<uint64_t>(issued),freeze(reservation["category"])};
    Array dependencies=p["dependencies"];for(int i=0;i<dependencies.size();++i){if(dependencies[i].get_type()!=Variant::DICTIONARY)return invalid;Dictionary dep=dependencies[i];Mailbox::Identity id;if(dep.size()!=2||!dep.has("identity")||dep["identity"].get_type()!=Variant::DICTIONARY||!identity(dep["identity"],id)||!dep.has("after")||dep["after"].get_type()!=Variant::STRING)return invalid;String after=dep["after"];LiveMailbox::After phase;if(after=="main_executed")phase=LiveMailbox::After::MAIN_EXECUTED;else if(after=="s_committed")phase=LiveMailbox::After::S_COMMITTED;else if(after=="retired")phase=LiveMailbox::After::RETIRED;else return invalid;request.dependencies.push_back({id,phase});}
    site["call_ordinal"]=static_cast<int64_t>(request.original.call_ordinal);r["site"]=site;r["identity"]=identity(request.original.identity);r["admission_predecessor"]=static_cast<int64_t>(sequence-1);r["output_slot"]=static_cast<int64_t>(sequence);request.original.bytes=freeze(r);
    Dictionary issued_context;auto context_status=capture_issued_live_context(r,issued_context);
    if(context_status==hardcore::simulation::SourceEventReplyMailbox::Status::PENDING){duplicate["status"]="BUSY";return duplicate;}
    if(context_status!=hardcore::simulation::SourceEventReplyMailbox::Status::READY)return invalid;
    if(!issued_context.is_empty()){request.issued_claim_context=freeze(issued_context);if(!request.issued_claim_context)return invalid;}
    bool not_admitted_closing=false;
    auto admitted=live_resources->submit(request,&not_admitted_closing);Dictionary result;
    if(admitted==LiveMailbox::Admission::ACCEPTED||admitted==LiveMailbox::Admission::DUPLICATE){result["status"]="PENDING";result["request"]=r;}
    else {
        result["status"]=admitted==LiveMailbox::Admission::BUSY?"BUSY":admitted==LiveMailbox::Admission::BACKPRESSURE?"BACKPRESSURE":"INVALID";
        if(not_admitted_closing)result["error"]="actual_live_mailbox_closing_not_admitted";
    }
    return result;
}
Dictionary HardCoreSimulationHost::acquire_pending_live_original_resource(){
    ERR_FAIL_COND_V(!Thread::is_main_thread()||!live_resources,Dictionary());drain_live_feature_transfer_receipts();auto pending=live_resources->acquire(now_usec());if(!pending.ready)return {};Variant request;if(!thaw(pending.request.original.bytes,request))return {};Dictionary packet;packet["channel"]="resource_live";packet["request"]=request;packet["identity"]=identity(pending.request.original.identity);packet["native_acquired_usec"]=static_cast<int64_t>(pending.acquired_usec);return packet;
}
bool HardCoreSimulationHost::ack_live_original_main_prefix(const Dictionary&i,const Dictionary&p){
    ERR_FAIL_COND_V(!Thread::is_main_thread()||!live_resources,false);Mailbox::Identity id;Mailbox::Prefix prefix;return identity(i,id)&&prefix_wire(p,bridge_generation,prefix)&&live_resources->acknowledge_prefix(id,prefix);
}
bool HardCoreSimulationHost::validate_live_original_resource_ticket(const Dictionary&r){
    ERR_FAIL_COND_V(!Thread::is_main_thread()||!live_resources,false);Mailbox::Identity id;if(!r.has("identity")||r["identity"].get_type()!=Variant::DICTIONARY||!identity(r["identity"],id))return false;
    auto pending=live_resources->lookup(id);auto bytes=freeze(r);return pending.ready&&bytes&&*bytes==*pending.request.original.bytes&&live_resources->claim_execution(id);
}
bool HardCoreSimulationHost::submit_live_original_resource_result(const Dictionary&i,const Dictionary&r){
    ERR_FAIL_COND_V(!Thread::is_main_thread()||!live_resources,false);Mailbox::Identity id;if(!identity(i,id))return false;auto pending=live_resources->lookup(id);Variant actual;if(!pending.ready||!thaw(pending.request.original.bytes,actual))return false;
    int64_t started=0,finished=0,cpu=0,prefix_ordinal=0;Dictionary request=actual;
    if(source_admission_op(request["op"])&&(r.size()!=12||!source_admission_side_receipts(r)))return false;
    bool feature_leaf=hardcore::simulation::feature_live_arity(std::string(String(request["op"]).utf8().get_data()))>=0;
    if(feature_leaf&&!live_feature_reply_actual(r))return false;
    if((r.size()!=9&&r.size()!=10&&!(source_admission_op(request["op"])&&r.size()==12&&source_admission_side_receipts(r))&&!(feature_leaf&&source_admission_side_receipts(r)&&(r.size()==12||(r.size()==13&&r.has("issued_claim_facts")&&pending.request.issued_claim_context&&live_feature_issued_folded))))||!plain(r)||r.get("request",Variant())!=actual||r.get("executed",Variant())!=Variant(true)||!r.has("result")||!typed_result(request["op"],r["result"],true,request["args"],id.sequence)||!integer(r,"started_usec",started)||started<pending.request.original.submitted_usec||!integer(r,"finished_usec",finished)||finished<started||finished>now_usec()||!integer(r,"main_cpu_usec",cpu)||cpu<0||!integer(r,"completed_prefix_ordinal",prefix_ordinal)||prefix_ordinal!=1||r.get("disposition",Variant())!=Variant(finished>static_cast<int64_t>(pending.request.original.deadline_usec)?SNAME("executed_late"):SNAME("executed"))||!r.has("actual_lease_obligations")||r["actual_lease_obligations"].get_type()!=Variant::ARRAY)return false;
    // A status observation is factual at its actual Main execution process frame,
    // never relabeled as the earlier S admission frame.
    if(StringName(request["op"])==SNAME("status")){
        if(!r.has("native_observation")||r["native_observation"].get_type()!=Variant::DICTIONARY)return false;Dictionary observation=r["native_observation"];int64_t g=0,e=0,s=0,a=0,b=0;
        if(observation.size()!=8||observation.get("ok",Variant())!=Variant(true)||!integer(observation,"bridge_generation",g)||g!=bridge_generation||!integer(observation,"observation_process_epoch",e)||e<0||!integer(observation,"status",s)||s!=static_cast<int64_t>(r["result"])||!integer(observation,"actual_start_usec",a)||a<started||!integer(observation,"actual_end_usec",b)||b<a||b>finished||!observation.has("progress")||observation["progress"].get_type()!=Variant::FLOAT||!observation.has("progress_ensured")||observation["progress_ensured"].get_type()!=Variant::BOOL)return false;
    }else if(r.has("native_observation"))return false;
    Array leases=r["actual_lease_obligations"];auto witness=leases.is_empty()?std::make_shared<const std::vector<uint8_t>>():freeze(leases);auto reply=freeze(r);
    if(!reply||!witness||!live_resources->submit_result({{id,pending.request.original.bytes,reply,static_cast<uint64_t>(started),static_cast<uint64_t>(finished)},static_cast<uint64_t>(cpu),witness}))return false;
    close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return true;
}
Dictionary HardCoreSimulationHost::poll_live_original_resource(const Dictionary&i){
    ERR_FAIL_COND_V(!is_owner()||!live_resources,Dictionary());Mailbox::Identity id;if(!identity(i,id))return {};auto completion=live_resources->poll(id,now_usec(),current_epoch);Dictionary pending;pending["status"]="PENDING";if(!completion.ready)return pending;
    Variant decoded;if(!thaw(completion.reply.original.bytes,decoded)||decoded.get_type()!=Variant::DICTIONARY)return {};Dictionary reply=decoded;
    reply["native_received_usec"]=static_cast<int64_t>(completion.receipt_received_usec);reply["native_s_poll_epoch"]=static_cast<int64_t>(completion.s_poll_epoch);reply["native_queue_wait_usec"]=static_cast<int64_t>(completion.queue_wait_usec);reply["native_main_elapsed_usec"]=static_cast<int64_t>(completion.charged_usec);reply["native_deadline_status"]=completion.late?"FAIL":"PASS";
    reply["native_acquired_usec"]=static_cast<int64_t>(completion.acquired_usec);reply["native_queue_residence_usec"]=static_cast<int64_t>(completion.queue_residence_usec);reply["native_dispatch_wait_usec"]=static_cast<int64_t>(completion.dispatch_wait_usec);
    Dictionary receipt;receipt["bridge_generation"]=static_cast<int64_t>(id.generation);receipt["journal_generation"]=static_cast<int64_t>(completion.request.original.prefix.journal_generation);receipt["through_ordinal"]=static_cast<int64_t>(completion.request.original.prefix.through);receipt["applied"]=true;reply["native_main_prefix_receipt"]=receipt;
    Dictionary ready;ready["status"]="READY";ready["reply"]=reply;return ready;
}
bool HardCoreSimulationHost::settle_live_original_resource(const Dictionary&s){
    return settle_live_original_resource_status(s).get("status",Variant())==Variant("SETTLED");
}
Dictionary HardCoreSimulationHost::settle_live_original_resource_status(const Dictionary&s){
    Dictionary result;result["status"]="INVALID";
    if(!is_owner()||!live_resources){result["error"]="owner_or_transport";return result;}
    if(s.size()!=11||s.get("contract_id",Variant())!=Variant("hardcore.resource.budget_settlement.v1")||!s.has("identity")||s["identity"].get_type()!=Variant::DICTIONARY){result["error"]="schema";return result;}
    LiveMailbox::Settlement v;if(!identity(s["identity"],v.identity)){result["error"]="identity";return result;}int64_t n=0;
    uint64_t*values[]={&v.reservation_id,&v.owner_session_id,&v.s_commit_epoch,&v.started_usec,&v.finished_usec,&v.charged_usec,&v.received_usec,&v.queue_wait_usec,&v.overrun_usec};
    const char*keys[]={"reservation_id","owner_session_id","s_commit_epoch","main_started_usec","main_finished_usec","charged_usec","receipt_received_usec","queue_wait_usec","overrun_usec"};
    for(int k=0;k<9;++k){if(!integer(s,keys[k],n)||n<0){result["error"]=String("field_")+keys[k];return result;}*values[k]=static_cast<uint64_t>(n);}if(v.s_commit_epoch>current_epoch){result["error"]="epoch_future";return result;}
    auto settled=live_resources->settle_status(v);result["status"]=settled==LiveMailbox::SettlementStatus::SETTLED?"SETTLED":settled==LiveMailbox::SettlementStatus::PENDING?"PENDING":"INVALID";result["error"]=settled==LiveMailbox::SettlementStatus::PENDING?"contention":settled==LiveMailbox::SettlementStatus::INVALID?"receipt_conflict_or_unknown":"";return result;
}
bool HardCoreSimulationHost::ack_live_original_resource_retirement(const Dictionary&i,const Array&leases){
    ERR_FAIL_COND_V(!Thread::is_main_thread()||!live_resources,false);Mailbox::Identity id;if(!identity(i,id)||!plain(leases))return false;auto witness=leases.is_empty()?std::make_shared<const std::vector<uint8_t>>():freeze(leases);
    if(!live_resources->acknowledge_actual_lease_retirement(id,witness))return false;close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return true;
}
bool HardCoreSimulationHost::retire_live_original_resource(const Dictionary&i){ERR_FAIL_COND_V(!is_owner()||!live_resources,false);Mailbox::Identity id;return identity(i,id)&&live_resources->retire(id);}


namespace {
bool actual_vault_script(const Ref<RefCounted>&v,const String&sha){
 if(v.is_null())return false;Ref<Script>s=v->get_script();return s.is_valid()&&s->get_path()==String("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd")&&sha.length()==64&&s->get_source_code().sha256_text()==sha;
}
bool actual_vault_dictionary(const Ref<RefCounted>&v,const char*field,Dictionary&d){Variant value=v->get(field);if(value.get_type()!=Variant::DICTIONARY)return false;d=value;return true;}
bool actual_vault_lease(const Ref<RefCounted>&v,const Dictionary&lease){
 String kind=lease.get("kind",String());Dictionary owned;int64_t id=0,count=0,token=0,version=0;
 if(kind=="loader_claim"){
  if(lease.size()!=3||!lease.has("path")||lease["path"].get_type()!=Variant::STRING||!integer(lease,"count",count)||count<=0||!actual_vault_dictionary(v,"_accepted_claims",owned))return false;
  Variant actual=owned.get(lease["path"],Variant());return actual.get_type()==Variant::INT&&static_cast<int64_t>(actual)>=count;
 }
 if(kind=="get_escrow"){
  if(lease.size()!=3||!integer(lease,"receipt",id)||id<=0||!integer(lease,"token",token)||token==0||!actual_vault_dictionary(v,"_get_escrow",owned)||owned.get(id,Variant())!=Variant(token))return false;
  Dictionary textures;if(!actual_vault_dictionary(v,"_texture_references",textures)||textures.get(token,Variant()).get_type()!=Variant::OBJECT)return false;
  Object*texture=textures[token];return texture&&static_cast<int64_t>(texture->get_instance_id())==token&&texture->is_class("Texture2D");
 }
 if(kind=="texture_roots"){
  if(lease.size()!=3||!lease.has("scope")||lease["scope"].get_type()!=Variant::STRING||!token_array(lease.get("tokens",Variant()))||!actual_vault_dictionary(v,"_texture_roots",owned))return false;
  return owned.get(lease["scope"],Variant())==lease["tokens"];
 }
 if(kind=="renderer_binding"){
  if(lease.size()!=4||!integer(lease,"service_id",id)||id<=0||!integer(lease,"binding_version",version)||version<=0||!token_array(lease.get("tokens",Variant()))||!actual_vault_dictionary(v,"_binding_versions",owned)||owned.get(id,Variant())!=Variant(version))return false;
  Dictionary renderers,roots;if(!actual_vault_dictionary(v,"_renderers",renderers)||!actual_vault_dictionary(v,"_texture_roots",roots)||renderers.get(id,Variant()).get_type()!=Variant::OBJECT)return false;
  Object*weak=renderers[id];if(!weak||!weak->has_method(SNAME("get_ref")))return false;Variant value=weak->call(SNAME("get_ref"));Object*renderer=value;
  if(!renderer||renderer->get("canonical_service_id")!=Variant(id))return false;
  Array tokens=lease["tokens"];return tokens.is_empty()? !roots.has(String("visual_profile:")+String::num_int64(id)):roots.get(String("visual_profile:")+String::num_int64(id),Variant())==lease["tokens"];
 }
 return false;
}
}
bool HardCoreSimulationHost::bind_live_original_resource_vault(const Ref<RefCounted>&v,const String&sha){
 if(!Thread::is_main_thread()||!live_resources||live_resource_vault.is_valid()||!actual_vault_script(v,sha)||v->get("_configured")!=Variant(true)||v->get("_bridge_generation")!=Variant(static_cast<int64_t>(bridge_generation))||v->get("_generation_closed")!=Variant(false))return false;
 live_resource_vault=v;live_resource_vault_sha=sha;live_resource_vault_closed.store(false,std::memory_order_release);return true;
}
Dictionary HardCoreSimulationHost::transfer_live_original_resource_obligations(const Dictionary&i,const Array&leases,const Dictionary&r){
 Dictionary out;out["status"]="INVALID";Mailbox::Identity id;int64_t incarnation=0,sequence=0,generation=0;
 if(!Thread::is_main_thread()||!live_resources||!identity(i,id)||id.generation!=bridge_generation||leases.is_empty()||!plain(leases)||!plain(r)||r.size()!=7||!actual_vault_script(live_resource_vault,live_resource_vault_sha)||live_resource_vault_closed.load(std::memory_order_acquire))return out;
 if(r.get("contract_id",Variant())!=Variant("hardcore.resource.actual_vault_transfer.v1")||!integer(r,"bridge_generation",generation)||generation!=bridge_generation||!integer(r,"owner_incarnation",incarnation)||incarnation!=static_cast<int64_t>(live_resource_vault->get_instance_id())||r.get("identity",Variant())!=Variant(i)||r.get("lease_ids",Variant())!=Variant(leases)||!integer(r,"actual_main_op_sequence",sequence)||sequence!=id.sequence||!r.has("actual_operation")||!string(r["actual_operation"]))return out;
 auto pending=live_resources->lookup(id);Variant request;if(!pending.ready||!thaw(pending.request.original.bytes,request)||request.get_type()!=Variant::DICTIONARY)return out;Dictionary actual=request;
 if(actual.get("op",Variant())!=r["actual_operation"]||live_resource_vault->get("_bridge_generation")!=Variant(generation))return out;
 Dictionary last;if(!actual_vault_dictionary(live_resource_vault,"_last_request",last)||last.get("identity",Variant())!=Variant(i))return out;
 // The exact original Main operation has already created every referenced
 // physical entry. Native inspects that same vault; a token handed to S alone
 // is never an ownership transfer and does not release a transport slot.
 for(int n=0;n<leases.size();++n)if(leases[n].get_type()!=Variant::DICTIONARY||!actual_vault_lease(live_resource_vault,leases[n]))return out;
 auto witness=freeze(leases);if(!witness)return out;auto transferred=live_resources->acknowledge_actual_lease_transfer_status(id,witness);
 if(transferred==LiveMailbox::TransferStatus::PENDING){out["status"]="PENDING";return out;}if(transferred!=LiveMailbox::TransferStatus::TRANSFERRED)return out;
 out["status"]="TRANSFERRED";out["receipt"]=r.duplicate(true);close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return out;
}
bool HardCoreSimulationHost::certify_live_original_resource_vault_closed(const Dictionary&r){
 if(!Thread::is_main_thread()||!actual_vault_script(live_resource_vault,live_resource_vault_sha)||!plain(r)||r.get("ok",Variant())!=Variant(true)||r.get("bridge_generation",Variant())!=Variant(static_cast<int64_t>(bridge_generation))||live_resource_vault->get("_generation_closed")!=Variant(true)||live_resource_vault->get("_configured")!=Variant(false))return false;
 for(const char*key:{"_accepted_claims","_texture_roots","_get_escrow","_texture_references","_renderers"}){Dictionary entries;if(!actual_vault_dictionary(live_resource_vault,key,entries)||!entries.is_empty())return false;}
 // Actor inputs share this same physical texture vault. Audio/material/font
 // roots are held by its actual sub-ledger and must not escape Native's final
 // physical close check merely because the original five dictionaries drained.
 Variant actor_value=live_resource_vault->get("_actor_assets");
 if(actor_value.get_type()!=Variant::NIL){
  if(actor_value.get_type()!=Variant::OBJECT)return false;
  Ref<RefCounted> actors=actor_value;if(actors.is_null())return false;Ref<Script> actor_script=actors->get_script();if(actor_script.is_null()||actor_script->get_path()!=String("res://scripts/gameplay/presentation/actor_asset_main_ledger.gd"))return false;
  Variant parent_value=actors->get("_vault");if(parent_value.get_type()!=Variant::OBJECT)return false;
  Ref<WeakRef> parent=parent_value;if(parent.is_null())return false;Object* parent_object=parent->get_ref();if(parent_object!=live_resource_vault.ptr())return false;
  for(const char*key:{"_templates","_owners","_audio_references","_aux_references"}){Dictionary entries;if(!actual_vault_dictionary(actors,key,entries)||!entries.is_empty())return false;}
 }
 // Original close_generation additionally verifies the actual source ticket
 // and ContentLayers/native observation retirement. The physical vault pin
 // stays alive until Host's Main-owned lifetime ends.
 live_resource_vault_closed.store(true,std::memory_order_release);close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();return true;
}
Dictionary HardCoreSimulationHost::finalize_original_main_resource_vault(){
 Dictionary out;out["status"]="PENDING";
 if(!Thread::is_main_thread()||main_vault_close_active){out["status"]="INVALID";out["error"]="actual_Main_finalizer_required";return out;}
 if(!actual_vault_script(live_resource_vault,live_resource_vault_sha)){out["status"]="MISSING";out["error"]="actual_bound_physical_vault_required";return out;}
 if(live_resource_vault_closed.load(std::memory_order_acquire)){out["status"]="READY";out["actual_native_vault_closed"]=true;return out;}
 if(!close_requested.load(std::memory_order_acquire)||!source_model_close_completed.load(std::memory_order_acquire)||!original_primitives||original_primitives->in_flight()||original_primitives->unsettled_published_count()!=0||(live_resources&&live_resources->accepted_count()!=0)||(close_process_producer_bound.load(std::memory_order_acquire)&&(!close_process_frames||!close_process_frames->can_close())))return out;
 main_vault_close_ticket["contract_id"]="hardcore.resource.Native_final_vault_close.v1";
 main_vault_close_ticket["bridge_generation"]=static_cast<int64_t>(bridge_generation);
 main_vault_close_ticket["vault_object_id"]=static_cast<int64_t>(live_resource_vault->get_instance_id());
 main_vault_close_ticket["actual_source_model_closed"]=true;
 main_vault_close_active=true;
 Variant value=live_resource_vault->call(SNAME("close_generation"),main_vault_close_ticket);
 main_vault_close_active=false;main_vault_close_ticket=Dictionary();
 if(value.get_type()!=Variant::DICTIONARY){out["status"]="INVALID";out["error"]="actual_vault_close_result_required";return out;}
 Dictionary receipt=value;out["actual_close_receipt"]=receipt;
 if(receipt.get("ok",Variant())!=Variant(true))return out;
 if(!certify_live_original_resource_vault_closed(receipt)){out["status"]="INVALID";out["error"]="actual_physical_close_certificate_rejected";return out;}
 out["status"]="READY";out["actual_native_vault_closed"]=true;return out;
}
bool HardCoreSimulationHost::live_original_resource_transport_releasable(const Dictionary&i)const{
 if(!is_owner()||!live_resources)return false;Mailbox::Identity id;return identity(i,id)&&live_resources->transport_releasable(id);
}

int64_t HardCoreSimulationHost::sample_main_thread_cpu_usec()const{
    ERR_FAIL_COND_V(!Thread::is_main_thread(),-1);
#ifdef WINDOWS_ENABLED
    FILETIME creation,exit,kernel,user;if(!GetThreadTimes(GetCurrentThread(),&creation,&exit,&kernel,&user))return -1;
    ULARGE_INTEGER k,u;k.LowPart=kernel.dwLowDateTime;k.HighPart=kernel.dwHighDateTime;u.LowPart=user.dwLowDateTime;u.HighPart=user.dwHighDateTime;return static_cast<int64_t>((k.QuadPart+u.QuadPart)/10);
#else
    timespec t;if(clock_gettime(CLOCK_THREAD_CPUTIME_ID,&t)!=0)return -1;return static_cast<int64_t>(t.tv_sec)*1000000+t.tv_nsec/1000;
#endif
}

using AdmissionScope=hardcore::simulation::SourceAdmissionScopeLedger;
bool HardCoreSimulationHost::bind_original_source_admission_producer(const Ref<RefCounted>&p,const String&source_sha){
 ERR_FAIL_COND_V(!Thread::is_main_thread()||p.is_null()||main_source_admission.is_valid(),false);
 Ref<Script> script=p->get_script();if(script.is_null()||script->get_path()!=String("res://scripts/gameplay/source/main_source_admission.gd")||source_sha.length()!=64||script->get_source_code().sha256_text()!=source_sha)return false;
 main_source_admission=p;main_source_admission_sha=source_sha;return true;
}
Dictionary HardCoreSimulationHost::publish_original_source_admission_scope(const Dictionary&s){
 Dictionary out;out["status"]="INVALID";out["error"]="source_scope_schema_or_producer";
 if(!Thread::is_main_thread()||!source_admission_scopes||main_source_admission.is_null()||s.size()!=9||!plain(s)||s.get("contract_id",Variant())!=Variant("hardcore.main.source.admission_scope.v1"))return out;
 Ref<Script> script=main_source_admission->get_script();if(script.is_null()||script->get_path()!=String("res://scripts/gameplay/source/main_source_admission.gd")||script->get_source_code().sha256_text()!=main_source_admission_sha)return out;
 int64_t generation=0,id=0,producer=0;if(!integer(s,"bridge_generation",generation)||generation!=bridge_generation||!integer(s,"scope_id",id)||id<=0||!integer(s,"producer_runtime_id",producer)||producer!=static_cast<int64_t>(main_source_admission->get_instance_id())||!s.has("profile_id")||s["profile_id"].get_type()!=Variant::STRING||static_cast<String>(s["profile_id"]).is_empty()||!s.has("state")||s["state"].get_type()!=Variant::STRING||!s.has("world_context")||s["world_context"].get_type()!=Variant::DICTIONARY||!world(s["world_context"])||Dictionary(s["world_context"])["profile_id"]!=s["profile_id"]||!s.has("receipt")||s["receipt"].get_type()!=Variant::DICTIONARY||!s.has("publication")||s["publication"].get_type()!=Variant::DICTIONARY)return out;
 Object*gate=main_source_admission->get("_gate");Object*facade=main_source_admission->get("_facade");if(!gate||!facade)return out;
 Variant actual_gate=gate->call(SNAME("state"));Dictionary receipt=s["receipt"];bool committed=main_source_admission->get("_committed");Dictionary actual=main_source_admission->get("_prepared");
 AdmissionScope::State state;String label=s["state"];
 if(label=="PREPARED"){if(actual_gate!=Variant("PREPARED")||committed||actual!=receipt||main_source_admission->get("_source_state")!=s["publication"])return out;state=AdmissionScope::State::PREPARED;}
 else if(label=="COMMITTED"){if(actual_gate!=Variant("S")||!committed||actual!=receipt||main_source_admission->get("_source_state")!=s["publication"])return out;state=AdmissionScope::State::COMMITTED;}
 else if(label=="ABORTED"){if(actual_gate!=Variant("MAIN")||committed||!actual.is_empty())return out;state=AdmissionScope::State::ABORTED;}
 else return out;
 int64_t serial=0,facade_id=0,model_id=0;Object*model=facade->get("_model");
 if(receipt.get("contract_id",Variant())!=Variant("hardcore.main.profile_source.prepared.v1")||!integer(receipt,"serial",serial)||serial!=id||!integer(receipt,"facade_id",facade_id)||facade_id!=static_cast<int64_t>(facade->get_instance_id())||!model||!integer(receipt,"model_id",model_id)||model_id!=static_cast<int64_t>(model->get_instance_id())||receipt.get("profile_id",Variant())!=s["profile_id"])return out;
 // These are exact producer-owned receipts, never booleans inferred from an
 // empty queue, pause or absent World. Native does not certify their IO/UI body.
 for(const char*k:{"original_checkpoint","deferred_receipt","receiver_receipt","ui_receipt"})if(!receipt.has(k)||receipt[k].get_type()!=Variant::DICTIONARY||Dictionary(receipt[k]).is_empty())return out;
 auto world_bytes=freeze(s["world_context"]),receipt_bytes=freeze(s["receipt"]),publication=freeze(s["publication"]);auto wire=freeze(s);if(!wire||wire->size()>source_scope_capacity)return out;
 CharString profile=String(s["profile_id"]).utf8();AdmissionScope::Snapshot scope{bridge_generation,static_cast<uint64_t>(id),static_cast<uint64_t>(producer),std::string(profile.get_data(),profile.length()),state,world_bytes,receipt_bytes,publication};
 auto result=source_admission_scopes->publish(scope);out["status"]=result==AdmissionScope::Status::READY?"READY":result==AdmissionScope::Status::PENDING?"PENDING":"INVALID";out["error"]=result==AdmissionScope::Status::PENDING?"contention":result==AdmissionScope::Status::INVALID?"scope_transition_or_exact_receipt":"";return out;
}
namespace {Dictionary scope_read(const AdmissionScope::Read&r){Dictionary out;out["status"]=r.status==AdmissionScope::Status::READY?"READY":r.status==AdmissionScope::Status::PENDING?"PENDING":"INVALID";if(r.status!=AdmissionScope::Status::READY)return out;Variant world_value,receipt,publication;if(!thaw(r.snapshot.world,world_value)||!thaw(r.snapshot.receipt,receipt)||!thaw(r.snapshot.publication,publication)){out["status"]="INVALID";return out;}Dictionary scope;scope["contract_id"]="hardcore.main.source.admission_scope.v1";scope["bridge_generation"]=static_cast<int64_t>(r.snapshot.generation);scope["scope_id"]=static_cast<int64_t>(r.snapshot.scope_id);scope["producer_runtime_id"]=static_cast<int64_t>(r.snapshot.producer);scope["profile_id"]=String(r.snapshot.profile.c_str());scope["state"]=r.snapshot.state==AdmissionScope::State::PREPARED?"PREPARED":r.snapshot.state==AdmissionScope::State::COMMITTED?"COMMITTED":"ABORTED";scope["world_context"]=world_value;scope["receipt"]=receipt;scope["publication"]=publication;out["scope"]=scope;return out;}}
Dictionary HardCoreSimulationHost::claim_original_source_admission_scope(int64_t id){ERR_FAIL_COND_V(!is_owner()||!source_admission_scopes||id<=0,Dictionary());auto inspected=source_admission_scopes->poll(id);if(inspected.status!=AdmissionScope::Status::READY)return scope_read(inspected);auto bound=freeze(primitive_world);if(!bound||*inspected.snapshot.world!=*bound){Dictionary out;out["status"]="INVALID";return out;}auto read=source_admission_scopes->claim(id);if(read.status==AdmissionScope::Status::READY)current_source_scope=id;return scope_read(read);}
Dictionary HardCoreSimulationHost::poll_original_source_admission_scope(int64_t id){ERR_FAIL_COND_V(!is_owner()||!source_admission_scopes||id<=0,Dictionary());return scope_read(source_admission_scopes->poll(id));}
bool HardCoreSimulationHost::finish_original_source_admission_scope(int64_t id){ERR_FAIL_COND_V(!is_owner()||!source_admission_scopes||id<=0,false);if(!source_admission_scopes->finish(id))return false;current_source_scope=0;return true;}

namespace {
using EventReplies=hardcore::simulation::SourceEventReplyMailbox;
EventReplies::Bytes event_wire(const Variant&v){HardCoreContentValueGraph graph;if(!static_cast<bool>(graph.validate(v,false).get("success",false)))return {};int n=0;if(encode_variant(v,nullptr,n,false)!=OK||n<0)return {};auto b=std::make_shared<std::vector<uint8_t>>(n);if(encode_variant(v,b->data(),n,false)!=OK)return {};return b;}
bool event_value(const EventReplies::Bytes&b,Variant&v){return b&&decode_variant(v,b->data(),static_cast<int>(b->size()),nullptr,false)==OK;}
bool event_identity(const Dictionary&d,EventReplies::Identity&id){if(d.size()!=3)return false;const char*k[]={"bridge_generation","journal_generation","event_ordinal"};uint64_t*v[]={&id.generation,&id.journal,&id.ordinal};for(int n=0;n<3;++n){if(!d.has(k[n])||d[k[n]].get_type()!=Variant::INT||static_cast<int64_t>(d[k[n]])<=0)return false;*v[n]=static_cast<int64_t>(d[k[n]]);}return true;}
Dictionary event_identity(const EventReplies::Identity&id){Dictionary d;d["bridge_generation"]=static_cast<int64_t>(id.generation);d["journal_generation"]=static_cast<int64_t>(id.journal);d["event_ordinal"]=static_cast<int64_t>(id.ordinal);return d;}
Dictionary event_status(EventReplies::Status s){Dictionary d;d["status"]=s==EventReplies::Status::READY?"READY":s==EventReplies::Status::PENDING?"PENDING":s==EventReplies::Status::BACKPRESSURE?"BACKPRESSURE":"INVALID";return d;}
bool caster_event(const Dictionary&e,const EventReplies::Identity&id){if(!e.has("ordinal")||e["ordinal"].get_type()!=Variant::INT||static_cast<int64_t>(e["ordinal"])!=static_cast<int64_t>(id.ordinal)||e.get("kind",Variant())!=Variant("original_world_presentation")||e.get("operation",Variant())!=Variant(SNAME("caster_presentation"))||!e.has("arguments")||e["arguments"].get_type()!=Variant::ARRAY||Array(e["arguments"]).size()!=1||Array(e["arguments"])[0].get_type()!=Variant::DICTIONARY||e.get("reply_identity",Variant())!=Variant(event_identity(id)))return false;Dictionary command=Array(e["arguments"])[0];if(command.get("contract_id",Variant())!=Variant("world.caster.presentation.command.v1")||command.size()!=8||!command.has("operation")||!string(command["operation"])||!command.has("payload")||command["payload"].get_type()!=Variant::DICTIONARY||!command.has("source_clock")||command["source_clock"].get_type()!=Variant::DICTIONARY||!command.has("world_context")||command["world_context"].get_type()!=Variant::DICTIONARY||!world(command["world_context"]))return false;int64_t n=0;if(!integer(command,"command_id",n)||n<=0||!integer(command,"closure_id",n)||n<=0||!integer(command,"main_executor_id",n)||n==0)return false;Dictionary clock=command["source_clock"];if(!integer(clock,"epoch",n)||n<0||!integer(clock,"next_release_usec",n)||n<=0||!integer(clock,"presentation_submitted_usec",n)||n<=0)return false;StringName op=command["operation"];if(String(op).begins_with("source_interactable::")){
 Dictionary p=command["payload"];
 if(op==SNAME("source_interactable::session_diagnostics")){if(p.size()!=1||!p.has("facts")||p["facts"].get_type()!=Variant::DICTIONARY)return false;}
 else {
  if(!p.has("identity")||p["identity"].get_type()!=Variant::DICTIONARY)return false;Dictionary ident=p["identity"];int64_t actor_id=0,life=0;if(ident.size()!=3||!ident.has("world")||ident["world"].get_type()!=Variant::DICTIONARY||ident["world"]!=command["world_context"]||!world(ident["world"])||!integer(ident,"runtime_id",actor_id)||actor_id<=0||!integer(ident,"life_generation",life)||life<=0)return false;
  if(op==SNAME("source_interactable::retire")){if(p.size()!=1)return false;}
  else if(op==SNAME("source_interactable::face_npc")){if(p.size()!=3||!p.has("facing")||p["facing"].get_type()!=Variant::VECTOR2||!p.has("default_facing")||p["default_facing"].get_type()!=Variant::VECTOR2)return false;}
  else {if(p.size()!=2||!p.has("state")||p["state"].get_type()!=Variant::DICTIONARY)return false;Dictionary state=p["state"];if(!state.has("position_screen_px")||state["position_screen_px"].get_type()!=Variant::VECTOR2)return false;
   if(op==SNAME("source_interactable::spawn_npc")){if(state.size()!=7||!state.has("npc_name")||!string(state["npc_name"])||!state.has("npc_kind")||!string(state["npc_kind"])||!integer(state,"appearance",n)||n<0||!state.has("facing")||state["facing"].get_type()!=Variant::VECTOR2||!state.has("default_facing")||state["default_facing"].get_type()!=Variant::VECTOR2||!state.has("service_identity_id")||!string(state["service_identity_id"]))return false;}
   else if(op==SNAME("source_interactable::spawn_portal")){if(state.size()!=6||!state.has("target_zone")||!string(state["target_zone"])||!integer(state,"target_map_id",n)||!state.has("display_name")||!string(state["display_name"])||!state.has("portal_role")||!string(state["portal_role"])||!state.has("portal_data")||state["portal_data"].get_type()!=Variant::DICTIONARY)return false;}
   else return false;
  }
 }
}if(String(op).begins_with("source_caster_warm::")){
 Dictionary p=command["payload"];int64_t root=0,sequence=0,frame=0;if(p.size()!=7||p.get("contract_id",Variant())!=Variant("source.caster.warm.request.v1")||!integer(p,"source_root_id",root)||!root||!integer(p,"request_sequence",sequence)||sequence<=0||!integer(p,"source_process_frame",frame)||frame<0||p.get("world_context",Variant())!=command["world_context"]||!p.has("reservation")||p["reservation"].get_type()!=Variant::DICTIONARY||!p.has("arguments")||p["arguments"].get_type()!=Variant::ARRAY)return false;
 Dictionary b=p["reservation"];int64_t v=0;if(b.size()!=8||b.get("contract_id",Variant())!=Variant("hardcore.resource.budget_reservation.v1")||!integer(b,"reservation_id",v)||v<=0||!integer(b,"owner_session_id",v)||v<=0||!integer(b,"ledger_epoch",v)||v<0||!integer(b,"lane",v)||v<0||v>2||!integer(b,"reserved_usec",v)||v<0||!integer(b,"issued_usec",v)||v<0||!b.has("category")||b["category"].get_type()!=Variant::STRING||static_cast<String>(b["category"]).is_empty())return false;
 Array a=p["arguments"];if(op==SNAME("source_caster_warm::loading_state")){if(a.size()!=1||a[0].get_type()!=Variant::BOOL)return false;}else if(!a.is_empty())return false;
 }for(const char*name:{"create_visual_model","bind_projectile","bind_ground","redraw_cast","projectile_audio_phase","prepare_projectile_visual","set_cast_y_sort","create_fire_wall_cell","fire_wall_animation_diagnostics","activate_fire_wall_cells","synchronize_fire_wall_cells","cast_has_visual","prepare_ground_visual","sync_cast","retire_cast","discard_visual","refresh_cell_lifetime","monster_audio","player_physical_contact_audio","source_interactable::spawn_npc","source_interactable::spawn_portal","source_interactable::face_npc","source_interactable::retire","source_interactable::session_diagnostics","source_caster_warm::collect_admit","source_caster_warm::retire","source_caster_warm::loading_state","source_caster_warm::loading_claim_retire"})if(op==StringName(name))return true;return false;}
}
bool HardCoreSimulationHost::bind_main_caster_reply_producer(const Ref<RefCounted>&p,const String&sha){ERR_FAIL_COND_V(!Thread::is_main_thread()||main_caster_reply_producer.is_valid()||p.is_null(),false);Ref<Script>s=p->get_script();if(s.is_null()||s->get_path()!=String("res://scripts/gameplay/world/world_caster_main_executor.gd")||sha.length()!=64||s->get_source_code().sha256_text()!=sha)return false;main_caster_reply_producer=p;main_caster_reply_sha=sha;main_caster_reply_id.store(static_cast<int64_t>(p->get_instance_id()),std::memory_order_release);return true;}
Dictionary HardCoreSimulationHost::reserve_original_caster_event(const Dictionary&i,const Dictionary&e){ERR_FAIL_COND_V(!is_owner()||!caster_event_replies,Dictionary());EventReplies::Identity id;if(!event_identity(i,id)||id.generation!=bridge_generation||!caster_event(e,id))return event_status(EventReplies::Status::INVALID);Dictionary c=Array(e["arguments"])[0];if(c.get("world_context",Variant())!=Variant(primitive_world)||c.get("main_executor_id",Variant())!=Variant(main_caster_reply_id.load(std::memory_order_acquire))||!e.has("source_site")||e["source_site"].get_type()!=Variant::DICTIONARY||!validate_original_source_site(e["source_site"]))return event_status(EventReplies::Status::INVALID);StringName op=c.get("operation",Variant());CharString operation_name=String(op).utf8();bool cleanup=hardcore::simulation::is_original_caster_cleanup_operation(std::string_view(operation_name.get_data(),operation_name.length()));return event_status(caster_event_replies->reserve(id,event_wire(e),cleanup));}
Dictionary HardCoreSimulationHost::accept_original_caster_event(const Dictionary&i,const Dictionary&e,const Dictionary&p){
    ERR_FAIL_COND_V(!is_owner()||!caster_event_replies||!original_primitives,Dictionary());
    auto invalid=[](const char*reason){auto out=event_status(EventReplies::Status::INVALID);out["error"]=reason;return out;};
    EventReplies::Identity id;hardcore::simulation::OriginalPrimitiveMailbox::Prefix prefix;
    if(!event_identity(i,id)||id.generation!=bridge_generation||!caster_event(e,id)||!prefix_wire(p,bridge_generation,prefix)||prefix.journal_generation!=id.journal)return invalid("actual_caster_event_or_prefix_schema");
    auto bytes=event_wire(e);bool found=false;
    for(const auto&item:prefix.events)if(item.ordinal==id.ordinal&&bytes&&item.bytes&&*bytes==*item.bytes)found=true;
    if(!found)return invalid("actual_caster_event_not_identical_to_journal_wire");
    auto registered=original_primitives->try_register_original_presentation_prefix(prefix);
    if(registered==hardcore::simulation::OriginalPrimitiveMailbox::MainEventStatus::PENDING)return event_status(EventReplies::Status::PENDING);
    if(registered!=hardcore::simulation::OriginalPrimitiveMailbox::MainEventStatus::READY)return invalid("actual_caster_original_prefix_registration");
    auto accepted=caster_event_replies->accept(id,bytes,event_wire(p));
    return accepted==EventReplies::Status::INVALID?invalid("actual_caster_reserved_event_acceptance"):event_status(accepted);
}
bool HardCoreSimulationHost::cancel_unaccepted_original_caster_event(const Dictionary&i){ERR_FAIL_COND_V(!is_owner()||!caster_event_replies,false);EventReplies::Identity id;if(event_identity(i,id)&&map_loading_state&&map_loading_state->used&&map_loading_state->identity==id)return false;return event_identity(i,id)&&caster_event_replies->cancel_unaccepted(id);}
Dictionary HardCoreSimulationHost::acquire_original_caster_prefix(){ERR_FAIL_COND_V(!Thread::is_main_thread()||!caster_event_replies,Dictionary());issued_observe_main_io_delivery();auto r=caster_event_replies->acquire_prefix();auto out=event_status(r.status);if(r.status==EventReplies::Status::READY){Variant p;if(!event_value(r.prefix,p))return event_status(EventReplies::Status::INVALID);out["prefix"]=p;}return out;}
Dictionary HardCoreSimulationHost::claim_original_caster_event(const Dictionary&i,const Dictionary&e){ERR_FAIL_COND_V(!Thread::is_main_thread()||!caster_event_replies||!original_primitives,Dictionary());EventReplies::Identity id;if(!event_identity(i,id)||!caster_event(e,id))return event_status(EventReplies::Status::INVALID);auto bytes=event_wire(e);auto proof=original_primitives->claimed_main_event_status(id.journal,id.ordinal,bytes);if(proof!=hardcore::simulation::OriginalPrimitiveMailbox::MainEventStatus::READY)return event_status(proof==hardcore::simulation::OriginalPrimitiveMailbox::MainEventStatus::PENDING?EventReplies::Status::PENDING:EventReplies::Status::INVALID);return event_status(caster_event_replies->claim(id,bytes));}
Dictionary HardCoreSimulationHost::submit_original_caster_event_reply(const Dictionary&i,const Dictionary&r){ERR_FAIL_COND_V(!Thread::is_main_thread()||!caster_event_replies,Dictionary());EventReplies::Identity id;if(!event_identity(i,id)||main_caster_reply_producer.is_null())return event_status(EventReplies::Status::INVALID);Ref<Script>s=main_caster_reply_producer->get_script();if(s.is_null()||s->get_source_code().sha256_text()!=main_caster_reply_sha)return event_status(EventReplies::Status::INVALID);auto read=caster_event_replies->inspect_main(id);if(read.status!=EventReplies::Status::READY)return event_status(read.status);Variant decoded;if(!event_value(read.event,decoded))return event_status(EventReplies::Status::INVALID);Dictionary e=decoded,c=Array(e["arguments"])[0];if(r.get("contract_id",Variant())!=Variant("world.caster.presentation.receipt.v1")||r.get("source_command",Variant())!=Variant(c)||r.get("main_executor_id",Variant())!=Variant(static_cast<int64_t>(main_caster_reply_producer->get_instance_id()))||!r.has("actual_node_id")||r["actual_node_id"].get_type()!=Variant::INT)return event_status(EventReplies::Status::INVALID);int64_t node=r["actual_node_id"];if(node<0||main_caster_reply_producer->call(SNAME("verify_actual_original_caster_reply"),i,r)!=Variant(true))return event_status(EventReplies::Status::INVALID);if(node&&ObjectDB::get_instance(ObjectID(static_cast<uint64_t>(node)))&&!Object::cast_to<Node2D>(ObjectDB::get_instance(ObjectID(static_cast<uint64_t>(node)))))return event_status(EventReplies::Status::INVALID);auto result=caster_event_replies->submit(id,event_wire(r),static_cast<uint64_t>(node));if(result==EventReplies::Status::READY){close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();}return event_status(result);}
Dictionary HardCoreSimulationHost::poll_original_caster_event_reply(const Dictionary&i){ERR_FAIL_COND_V(!is_owner()||!caster_event_replies,Dictionary());EventReplies::Identity id;if(!event_identity(i,id))return event_status(EventReplies::Status::INVALID);auto r=caster_event_replies->poll_with_observation(id,now_usec(),current_epoch);auto out=event_status(r.status);Array claim_transfers;for(const auto&bytes:r.claim_transfers){Variant value;if(!event_value(bytes,value)||value.get_type()!=Variant::DICTIONARY)return event_status(EventReplies::Status::INVALID);claim_transfers.push_back(value);}out["claim_transfers"]=claim_transfers;if(r.status==EventReplies::Status::READY){Variant value;if(!event_value(r.reply,value))return event_status(EventReplies::Status::INVALID);out["reply"]=value;out["consumed"]=r.consumed;out["actual_node_retired"]=r.retired;out["native_received_usec"]=static_cast<int64_t>(r.received_usec);out["native_s_poll_epoch"]=static_cast<int64_t>(r.s_poll_epoch);}return out;}
Dictionary HardCoreSimulationHost::consume_original_caster_event_reply(const Dictionary&i){ERR_FAIL_COND_V(!is_owner()||!caster_event_replies,Dictionary());EventReplies::Identity id;if(event_identity(i,id)&&map_loading_state&&map_loading_state->used&&map_loading_state->identity==id)return event_status(EventReplies::Status::INVALID);return event_identity(i,id)?event_status(caster_event_replies->consume(id)):event_status(EventReplies::Status::INVALID);}
Dictionary HardCoreSimulationHost::ack_original_caster_node_retired(const Dictionary&i){ERR_FAIL_COND_V(!Thread::is_main_thread()||!caster_event_replies,Dictionary());EventReplies::Identity id;if(!event_identity(i,id))return event_status(EventReplies::Status::INVALID);auto r=caster_event_replies->inspect_main(id);if(r.status!=EventReplies::Status::READY)return event_status(r.status);if(r.node&&ObjectDB::get_instance(ObjectID(r.node)))return event_status(EventReplies::Status::PENDING);auto result=caster_event_replies->acknowledge_retired(id,r.node);if(result==EventReplies::Status::READY){close_revision.fetch_add(1,std::memory_order_release);wake.notify_all();}return event_status(result);}
Dictionary HardCoreSimulationHost::retire_original_caster_event_reply(const Dictionary&i){ERR_FAIL_COND_V(!is_owner()||!caster_event_replies,Dictionary());EventReplies::Identity id;if(event_identity(i,id)&&map_loading_state&&map_loading_state->used&&map_loading_state->identity==id)return event_status(EventReplies::Status::INVALID);return event_identity(i,id)?event_status(caster_event_replies->retire(id)):event_status(EventReplies::Status::INVALID);}

Dictionary HardCoreSimulationHost::inspect_next_original_published_prefix(){
    Dictionary out;
    if(!Thread::is_main_thread()){out["status"]="INVALID";out["error"]="actual_Main_required";return out;}
    // A configured Main driver may process before Host.start. There is no
    // accepted journal yet; no fake generation, prefix or effect is supplied.
    if(!original_primitives){out["status"]="PENDING";return out;}
    auto read=original_primitives->inspect_next_published_prefix();
    using State=Mailbox::PublishedReadStatus;
    out["status"]=read.status==State::READY?"READY":read.status==State::BUSY?"BUSY":read.status==State::PENDING?"PENDING":"INVALID";
    if(read.status==State::READY){
        if(main_published_prefix_cache.bytes!=read.prefix.bytes){
            Variant prefix;
            if(!thaw(read.prefix.bytes,prefix)||prefix.get_type()!=Variant::DICTIONARY){out["status"]="INVALID";out["error"]="registered_prefix_wire_invalid";return out;}
            seal_main_prefix_value(prefix);
            main_published_prefix_value=prefix;
            main_published_prefix_cache=read.prefix;
        }
        out["prefix"]=main_published_prefix_value;
    }
    return out;
}
