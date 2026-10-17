#include "simulation_host.h"
#include "gameplay_global_random_binding.h"
#include "gameplay_random_return_math.h"
#include "core/object/class_db.h"
#include "core/object/script_language.h"
#include "core/math/random_pcg.h"
namespace {
Dictionary rejected_rng(const char *error){Dictionary d;d["success"]=false;d["status"]="INVALID";d["error"]=error;return d;}
bool rng_integer(const Dictionary &d,const char *key,int64_t &out){if(!d.has(key)||d[key].get_type()!=Variant::INT)return false;out=d[key];return true;}
}
Dictionary HardCoreSimulationHost::capture_original_terminal_gameplay_random(Object *actual_random,const Dictionary &next_event){
    if(!is_owner()||!started||fixture_mode||!closing_session||!gameplay_random_captured||model.is_null()||!original_primitives||source_model_close_completed.load(std::memory_order_acquire))return rejected_rng("actual_closing_production_Source_required");
    auto *random=Object::cast_to<HardCoreGameplayGlobalRandom>(actual_random);
    if(!random||!random->is_initialized())return rejected_rng("actual_initialized_Source_gameplay_random_required");
    Ref<Script> runtime_script=model->get_script();
    if(runtime_script.is_null()||runtime_script->get_path()!=String("res://scripts/gameplay/source/source_session_runtime.gd")||!model->has_method(SNAME("source_session")))return rejected_rng("actual_Source_Runtime_required");
    Variant session_value=model->call(SNAME("source_session"));
    Object *session=session_value.get_type()==Variant::OBJECT?static_cast<Object*>(session_value):nullptr;
    Ref<Script> session_script=session?Ref<Script>(session->get_script()):Ref<Script>();
    if(!session||session_script.is_null()||session_script->get_path()!=String("res://scripts/gameplay/source/source_session.gd")||session->get("_host")!=Variant(this)||session->get("_global_random")!=Variant(random))return rejected_rng("actual_same_Session_random_required");
    Variant current_world=model->get("_world");
    if((current_world.get_type()==Variant::OBJECT&&static_cast<Object*>(current_world)!=nullptr)||(current_world.get_type()!=Variant::OBJECT&&current_world.get_type()!=Variant::NIL))return rejected_rng("actual_World_release_before_terminal_RNG_required");
    Variant intent=session->get("_profile_return_intent");
    if(intent.get_type()!=Variant::DICTIONARY||Dictionary(intent).is_empty())return rejected_rng("actual_CHARACTER_SELECT_Source_intent_required");
    Variant journal_value=session->call(SNAME("original_event_journal"));
    Object *journal=journal_value.get_type()==Variant::OBJECT?static_cast<Object*>(journal_value):nullptr;
    int64_t generation=0,journal_generation=0,ordinal=0,session_id=0;
    if(!journal||!rng_integer(next_event,"bridge_generation",generation)||generation!=int64_t(bridge_generation)||!rng_integer(next_event,"journal_generation",journal_generation)||journal_generation<=0||!rng_integer(next_event,"event_ordinal",ordinal)||ordinal<=0||next_event.size()!=3||journal->call(SNAME("next_original_event_identity"))!=Variant(next_event))return rejected_rng("actual_next_terminal_journal_event_required");
    Variant id=session->get("_id");if(id.get_type()!=Variant::INT||(session_id=int64_t(id))<=0)return rejected_rng("actual_Source_Session_budget_identity_required");
    Dictionary actual_intent=intent;int64_t intent_ordinal=0;
    if(!rng_integer(actual_intent,"intent_event_ordinal",intent_ordinal)||intent_ordinal<=0||intent_ordinal>=ordinal||original_primitives->applied_prefix()<uint64_t(intent_ordinal)||actual_intent.get("owner_session_id",Variant())!=Variant(session_id)||actual_intent.get("world_context",Variant())!=Variant(primitive_world))return rejected_rng("actual_same_world_acknowledged_CHARACTER_SELECT_intent_required");
    std::lock_guard<std::mutex> lock(mailbox_mutex);
    if(!terminal_gameplay_random_handoff.is_empty()){
        if(terminal_gameplay_random_handoff.get("source_random_id",Variant())!=Variant(int64_t(random->get_instance_id()))||terminal_gameplay_random_handoff.get("source_session_object_id",Variant())!=Variant(int64_t(session->get_instance_id()))||terminal_gameplay_random_handoff.get("event_identity",Variant())!=Variant(next_event))return rejected_rng("terminal_RNG_capture_identity_changed");
    }else{
        Dictionary token;token["contract_id"]="hardcore.profile.global_random.return.v1";token["host_object_id"]=int64_t(get_instance_id());token["owner_session_id"]=session_id;token["source_runtime_id"]=int64_t(model->get_instance_id());token["source_session_object_id"]=int64_t(session->get_instance_id());token["source_random_id"]=int64_t(random->get_instance_id());
        Dictionary identity=next_event.duplicate(true);identity.make_read_only();token["event_identity"]=identity;token["handoff"]=random->seal_original_terminal_handoff();token.make_read_only();terminal_gameplay_random_handoff=token;
    }
    Dictionary out;out["success"]=true;out["terminal_handoff"]=terminal_gameplay_random_handoff;return out;
}
bool HardCoreSimulationHost::check_original_terminal_gameplay_random_prefix(const Dictionary &prefix,bool admitted){
    std::lock_guard<std::mutex> lock(mailbox_mutex);
    if(terminal_gameplay_random_handoff.is_empty())return true;
    Dictionary identity=terminal_gameplay_random_handoff["event_identity"];
    int64_t generation=0,journal=0,through=0;
    if(!rng_integer(prefix,"bridge_generation",generation)||generation!=int64_t(bridge_generation)||!rng_integer(prefix,"journal_generation",journal)||journal!=int64_t(identity["journal_generation"])||!rng_integer(prefix,"through_ordinal",through)||!prefix.has("events")||prefix["events"].get_type()!=Variant::ARRAY)return false;
    const int64_t expected=identity["event_ordinal"];
    if(through<expected)return true;
    Array events=prefix["events"];
    for(int n=0;n<events.size();++n){
        if(events[n].get_type()!=Variant::DICTIONARY)return false;Dictionary event=events[n];int64_t ordinal=0;if(!rng_integer(event,"ordinal",ordinal))return false;if(ordinal!=expected)continue;
        Variant operation=event.get("operation",Variant());
        if(event.get("kind",Variant())!=Variant("original_profile_transport")||(operation.get_type()!=Variant::STRING&&operation.get_type()!=Variant::STRING_NAME)||String(operation)!=String("original_profile_terminal_export")||!event.has("arguments")||event["arguments"].get_type()!=Variant::ARRAY)return false;
        Array arguments=event["arguments"];if(arguments.size()!=1||arguments[0].get_type()!=Variant::DICTIONARY)return false;Dictionary envelope=arguments[0];
        for(const char *key:{"owner_session_id","source_runtime_id","source_session_object_id"})if(envelope.get(key,Variant())!=terminal_gameplay_random_handoff.get(key,Variant()))return false;
        if(envelope.get("actual_host_id",Variant())!=Variant(int64_t(get_instance_id()))||envelope.get("global_random_terminal",Variant())!=Variant(terminal_gameplay_random_handoff))return false;
        if(admitted)terminal_gameplay_random_event_registered=true;
        return true;
    }
    return terminal_gameplay_random_event_registered; // Only a prior actual admission permits a pruned suffix.
}
Dictionary HardCoreSimulationHost::restore_original_terminal_gameplay_random(const Dictionary &handoff){
    if(!Thread::is_main_thread()||!started||fixture_mode||!main_channels_unbound_after_close.load(std::memory_order_acquire)||!source_model_close_completed.load(std::memory_order_acquire)||!close_quiescent.load(std::memory_order_acquire)||!join_complete.load(std::memory_order_acquire)||running.load(std::memory_order_acquire)||owner.load(std::memory_order_acquire)!=Thread::UNASSIGNED_ID||!model.is_null()||!original_primitives||!original_primitives->can_join()||original_primitives->unsettled_published_count()!=0)return rejected_rng("actual_joined_Source_and_nine_Main_owner_return_required");
    std::lock_guard<std::mutex> lock(mailbox_mutex);
    if(!fault_reason.is_empty()||close_failed.load(std::memory_order_acquire)||!terminal_gameplay_random_event_registered||handoff.is_empty()||handoff!=terminal_gameplay_random_handoff)return rejected_rng("actual_same_registered_terminal_RNG_required");
    Dictionary identity=handoff["event_identity"];
    if(original_primitives->applied_prefix()<uint64_t(int64_t(identity["event_ordinal"])))return rejected_rng("actual_terminal_RNG_prefix_ACK_required");
    for(const char *key:{"source_runtime_id","source_session_object_id","source_random_id"}){
        int64_t id=0;if(!rng_integer(handoff,key,id)||id==0||ObjectDB::get_instance(ObjectID(uint64_t(id)))!=nullptr)return rejected_rng("actual_Source_RNG_objects_must_be_destroyed");
    }
    if(terminal_gameplay_random_restored)return terminal_gameplay_random_restore_receipt;
    Dictionary state=handoff["handoff"];int64_t seed=0,value=0,increment=0;
    if(state.size()!=4||state.get("contract_id",Variant())!=Variant("hardcore.gameplay_global_random.handoff.v1")||!rng_integer(state,"seed",seed)||!rng_integer(state,"state",value)||!rng_integer(state,"increment",increment)||uint64_t(increment)!=RandomPCG::DEFAULT_INC)return rejected_rng("actual_exact_terminal_PCG_stream_required");
    if(!Math::restore_default_random_handoff({uint64_t(seed),uint64_t(value),uint64_t(increment)}))return rejected_rng("actual_Main_PCG_restore_failed");
    Dictionary out;out["success"]=true;out["status"]="RESTORED";out["terminal_handoff"]=terminal_gameplay_random_handoff;out.make_read_only();terminal_gameplay_random_restore_receipt=out;terminal_gameplay_random_restored=true;return out;
}
