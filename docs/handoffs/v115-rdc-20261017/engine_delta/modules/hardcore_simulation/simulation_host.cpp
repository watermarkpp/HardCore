#include "simulation_host.h"
#include "content_value_graph.h"

#include "physics_port.h"
#include "godot_physics_backend.h"
#include "core/io/marshalls.h"
#include "core/object/class_db.h"
#include "core/object/message_queue.h"
#include "core/os/os.h"

#include <chrono>
#include <cmath>
#include <limits>

namespace {
bool plain_value(const Variant &value, int depth, std::size_t &visited) {
	if (depth > 64 || ++visited > 1000000) return false;
	switch (value.get_type()) {
		case Variant::OBJECT: case Variant::CALLABLE: case Variant::SIGNAL: case Variant::RID: return false;
		case Variant::FLOAT: return std::isfinite(static_cast<double>(value));
		case Variant::ARRAY: {
			Array array = value;
			for (int i = 0; i < array.size(); ++i) if (!plain_value(array[i], depth + 1, visited)) return false;
			return true;
		}
		case Variant::DICTIONARY: {
			Dictionary dictionary = value;
			Array keys = dictionary.keys();
			for (int i = 0; i < keys.size(); ++i) {
				if (!plain_value(keys[i], depth + 1, visited) || !plain_value(dictionary[keys[i]], depth + 1, visited)) return false;
			}
			return true;
		}
		default: return true;
	}
}
bool encode_plain(const Variant &value, std::vector<uint8_t> &bytes) {
	std::size_t visited = 0;
	if (!plain_value(value, 0, visited)) return false;
	int length = 0;
	if (encode_variant(value, nullptr, length, false) != OK || length <= 0) return false;
	bytes.resize(length);
	return encode_variant(value, bytes.data(), length, false) == OK;
}
bool decode_plain(const std::vector<uint8_t> &bytes, Variant &value) {
	if (bytes.empty() || bytes.size() > static_cast<std::size_t>(INT32_MAX)) return false;
	int read = 0;
	return decode_variant(value, bytes.data(), static_cast<int>(bytes.size()), &read, false) == OK && read == static_cast<int>(bytes.size());
}
const char *phase_name(hardcore::simulation::SimulationClock::Phase phase) {
	using Phase = hardcore::simulation::SimulationClock::Phase;
	switch (phase) {
		case Phase::U_BEGIN: return "U_BEGIN"; case Phase::H_INPUT: return "H_INPUT";
		case Phase::H_PREPARE: return "H_PREPARE"; case Phase::H_GROUP: return "H_GROUP";
		case Phase::H_AFTER_TIMERS: return "H_AFTER_TIMERS"; case Phase::H_STEP: return "H_STEP";
		case Phase::P_INPUT: return "P_INPUT"; case Phase::P_GROUP: return "P_GROUP";
		case Phase::P_AFTER_TIMERS: return "P_AFTER_TIMERS"; case Phase::U_END: return "U_END";
		case Phase::PUBLISH: return "PUBLISH"; case Phase::U_WAKE: return "U_WAKE";
	}
	return "INVALID";
}
}

void HardCoreSimulationTimer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_time_left"), &HardCoreSimulationTimer::get_time_left);
	ClassDB::bind_method(D_METHOD("set_time_left", "seconds"), &HardCoreSimulationTimer::set_time_left);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "time_left"), "set_time_left", "get_time_left");
	ADD_SIGNAL(MethodInfo("timeout"));
}
void HardCoreSimulationTimer::detach(double p_time_left) { detached_time_left = p_time_left; host = nullptr; }
double HardCoreSimulationTimer::get_time_left() const {
	// ClassDB/editor default-property introspection constructs a prototype with
	// no Host, timer ID or Source owner. It contains no simulation timer state.
	// Detached REAL timers retain their nonzero ID/owner and still hit the guard.
	if (owner == Thread::UNASSIGNED_ID && host == nullptr && timer_id == 0) return detached_time_left;
	CRASH_COND_MSG(Thread::get_caller_id() != owner, "Simulation timer read outside its S owner.");
	return host ? host->read_timer(timer_id, detached_time_left) : detached_time_left;
}
void HardCoreSimulationTimer::set_time_left(double p_seconds) {
	CRASH_COND_MSG(Thread::get_caller_id() != owner || !std::isfinite(p_seconds), "Invalid simulation timer mutation.");
	if (host) host->write_timer(timer_id, p_seconds); else detached_time_left = p_seconds;
}

void HardCoreSimulationHost::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind_original_main_source_fault_owner", "owner", "source_sha256"), &HardCoreSimulationHost::bind_original_main_source_fault_owner);
	ClassDB::bind_method(D_METHOD("report_original_main_source_fault", "owner", "fact"), &HardCoreSimulationHost::report_original_main_source_fault);
    ClassDB::bind_method(D_METHOD("bind_original_map_loading_producer","producer","source_sha256","executor","executor_sha256"),&HardCoreSimulationHost::bind_original_map_loading_producer);
    ClassDB::bind_method(D_METHOD("publish_original_map_loading_scope","scope"),&HardCoreSimulationHost::publish_original_map_loading_scope);
    ClassDB::bind_method(D_METHOD("verify_original_map_loading_scope","scope","descriptor","transition_id","coordinator_generation","map_id"),&HardCoreSimulationHost::verify_original_map_loading_scope);
    ClassDB::bind_method(D_METHOD("commit_original_map_arrival","core","transaction"),&HardCoreSimulationHost::commit_original_map_arrival);
    ClassDB::bind_method(D_METHOD("verify_committed_original_map_arrival","transaction"),&HardCoreSimulationHost::verify_committed_original_map_arrival);
    ClassDB::bind_method(D_METHOD("publish_original_map_loading_publication","scope","publication","receipt"),&HardCoreSimulationHost::publish_original_map_loading_publication);
    ClassDB::bind_method(D_METHOD("verify_original_map_loading_publication","scope","descriptor","publication","receipt"),&HardCoreSimulationHost::verify_original_map_loading_publication);
    ClassDB::bind_method(D_METHOD("reserve_original_map_loading_event","identity","event"),&HardCoreSimulationHost::reserve_original_map_loading_event);
    ClassDB::bind_method(D_METHOD("accept_original_map_loading_event","identity","event","prefix"),&HardCoreSimulationHost::accept_original_map_loading_event);
    ClassDB::bind_method(D_METHOD("cancel_unaccepted_original_map_loading_event","identity"),&HardCoreSimulationHost::cancel_unaccepted_original_map_loading_event);
    ClassDB::bind_method(D_METHOD("claim_original_map_loading_event","identity","event"),&HardCoreSimulationHost::claim_original_map_loading_event);
    ClassDB::bind_method(D_METHOD("submit_original_map_loading_reply","identity","reply"),&HardCoreSimulationHost::submit_original_map_loading_reply);
    ClassDB::bind_method(D_METHOD("poll_original_map_loading_event","identity"),&HardCoreSimulationHost::poll_original_map_loading_event);
    ClassDB::bind_method(D_METHOD("settle_original_map_loading_event_status","identity","settlement"),&HardCoreSimulationHost::settle_original_map_loading_event_status);
    ClassDB::bind_method(D_METHOD("retire_original_map_loading_event","identity","reply"),&HardCoreSimulationHost::retire_original_map_loading_event);
    ClassDB::bind_method(D_METHOD("certify_original_map_loading_owner_closed","receipt"),&HardCoreSimulationHost::certify_original_map_loading_owner_closed);

    ClassDB::bind_method(D_METHOD("bind_original_close_process_producer","producer","actual_source_sha256"),&HardCoreSimulationHost::bind_original_close_process_producer);
    ClassDB::bind_method(D_METHOD("enqueue_original_close_process_frame","publication"),&HardCoreSimulationHost::enqueue_original_close_process_frame);
    ClassDB::bind_method(D_METHOD("acquire_original_close_process_frame_receipt"),&HardCoreSimulationHost::acquire_original_close_process_frame_receipt);
    ClassDB::bind_method(D_METHOD("ack_original_close_process_frame_receipt","receipt"),&HardCoreSimulationHost::ack_original_close_process_frame_receipt);
    ClassDB::bind_method(D_METHOD("original_close_process_signal_highwater"),&HardCoreSimulationHost::original_close_process_signal_highwater);
    ClassDB::bind_method(D_METHOD("original_close_process_producer_drained"),&HardCoreSimulationHost::original_close_process_producer_drained);
    ClassDB::bind_method(D_METHOD("request_original_close_process_producer_stop"),&HardCoreSimulationHost::request_original_close_process_producer_stop);
    ClassDB::bind_method(D_METHOD("acquire_original_close_process_producer_stop_request"),&HardCoreSimulationHost::acquire_original_close_process_producer_stop_request);
    ClassDB::bind_method(D_METHOD("confirm_original_close_process_producer_stopped","receipt"),&HardCoreSimulationHost::confirm_original_close_process_producer_stopped);
    ClassDB::bind_method(D_METHOD("verify_original_close_process_producer_terminal_receipt","receipt"),&HardCoreSimulationHost::verify_original_close_process_producer_terminal_receipt);
    ClassDB::bind_method(D_METHOD("bind_main_caster_reply_producer","producer","source_sha256"),&HardCoreSimulationHost::bind_main_caster_reply_producer);
    ClassDB::bind_method(D_METHOD("reserve_original_caster_event","identity","event"),&HardCoreSimulationHost::reserve_original_caster_event);
    ClassDB::bind_method(D_METHOD("accept_original_caster_event","identity","event","prefix"),&HardCoreSimulationHost::accept_original_caster_event);
    ClassDB::bind_method(D_METHOD("cancel_unaccepted_original_caster_event","identity"),&HardCoreSimulationHost::cancel_unaccepted_original_caster_event);
    ClassDB::bind_method(D_METHOD("acquire_original_caster_prefix"),&HardCoreSimulationHost::acquire_original_caster_prefix);
    ClassDB::bind_method(D_METHOD("inspect_next_original_published_prefix"),&HardCoreSimulationHost::inspect_next_original_published_prefix);
    ClassDB::bind_method(D_METHOD("claim_original_caster_event","identity","event"),&HardCoreSimulationHost::claim_original_caster_event);
    ClassDB::bind_method(D_METHOD("submit_original_caster_event_reply","identity","reply"),&HardCoreSimulationHost::submit_original_caster_event_reply);
    ClassDB::bind_method(D_METHOD("poll_original_caster_event_reply","identity"),&HardCoreSimulationHost::poll_original_caster_event_reply);
    ClassDB::bind_method(D_METHOD("bind_original_main_feature_claim_producer","producer","actual_source_sha256"),&HardCoreSimulationHost::bind_original_main_feature_claim_producer);
    ClassDB::bind_method(D_METHOD("bind_original_main_warm_claim_origin_producer","producer","actual_source_sha256"),&HardCoreSimulationHost::bind_original_main_warm_claim_origin_producer);
    ClassDB::bind_method(D_METHOD("bind_original_source_feature_claim_owner","coordinator","actual_source_sha256"),&HardCoreSimulationHost::bind_original_source_feature_claim_owner);
    ClassDB::bind_method(D_METHOD("offer_claim_transfer","identity","evidence"),&HardCoreSimulationHost::offer_claim_transfer);
    ClassDB::bind_method(D_METHOD("accept_claim_transfer","identity"),&HardCoreSimulationHost::accept_claim_transfer);
    ClassDB::bind_method(D_METHOD("confirm_origin_released","identity"),&HardCoreSimulationHost::confirm_origin_released);
    ClassDB::bind_method(D_METHOD("bind_live_original_feature_main_executor","producer","actual_source_sha256"),&HardCoreSimulationHost::bind_live_original_feature_main_executor);
    ClassDB::bind_method(D_METHOD("execute_pending_live_original_feature","actual_packet"),&HardCoreSimulationHost::execute_pending_live_original_feature);
    ClassDB::bind_method(D_METHOD("validate_live_original_feature_execution","actual_execution_wire"),&HardCoreSimulationHost::validate_live_original_feature_execution);
    ClassDB::bind_method(D_METHOD("certify_live_original_feature_main_closed"),&HardCoreSimulationHost::certify_live_original_feature_main_closed);
    ClassDB::bind_method(D_METHOD("consume_original_caster_event_reply","identity"),&HardCoreSimulationHost::consume_original_caster_event_reply);
    ClassDB::bind_method(D_METHOD("ack_original_caster_node_retired","identity"),&HardCoreSimulationHost::ack_original_caster_node_retired);
    ClassDB::bind_method(D_METHOD("retire_original_caster_event_reply","identity"),&HardCoreSimulationHost::retire_original_caster_event_reply);

    ClassDB::bind_method(D_METHOD("bind_original_source_admission_producer","producer","actual_source_sha256"),&HardCoreSimulationHost::bind_original_source_admission_producer);
    ClassDB::bind_method(D_METHOD("publish_original_source_admission_scope","scope"),&HardCoreSimulationHost::publish_original_source_admission_scope);
    ClassDB::bind_method(D_METHOD("claim_original_source_admission_scope","scope_id"),&HardCoreSimulationHost::claim_original_source_admission_scope);
    ClassDB::bind_method(D_METHOD("poll_original_source_admission_scope","scope_id"),&HardCoreSimulationHost::poll_original_source_admission_scope);
    ClassDB::bind_method(D_METHOD("finish_original_source_admission_scope","scope_id"),&HardCoreSimulationHost::finish_original_source_admission_scope);
	ClassDB::bind_method(D_METHOD("current_host_paused"), &HardCoreSimulationHost::current_host_paused);
	ClassDB::bind_method(D_METHOD("current_host_time_scale"), &HardCoreSimulationHost::current_host_time_scale);
	ClassDB::bind_method(D_METHOD("capture_main_gameplay_random"), &HardCoreSimulationHost::capture_main_gameplay_random);
	ClassDB::bind_method(D_METHOD("is_original_operation_completed", "identity"), &HardCoreSimulationHost::is_original_operation_completed);
	ClassDB::bind_method(D_METHOD("acquire_original_main_prefix", "prefix"), &HardCoreSimulationHost::acquire_original_main_prefix);
	ClassDB::bind_method(D_METHOD("submit_live_original_resource", "request"), &HardCoreSimulationHost::submit_live_original_resource);
	ClassDB::bind_method(D_METHOD("acquire_pending_live_original_resource"), &HardCoreSimulationHost::acquire_pending_live_original_resource);
	ClassDB::bind_method(D_METHOD("ack_live_original_main_prefix", "identity", "prefix"), &HardCoreSimulationHost::ack_live_original_main_prefix);
	ClassDB::bind_method(D_METHOD("validate_live_original_resource_ticket", "request"), &HardCoreSimulationHost::validate_live_original_resource_ticket);
	ClassDB::bind_method(D_METHOD("finalize_original_main_resource_vault"), &HardCoreSimulationHost::finalize_original_main_resource_vault);
	ClassDB::bind_method(D_METHOD("submit_live_original_resource_result", "identity", "reply"), &HardCoreSimulationHost::submit_live_original_resource_result);
	ClassDB::bind_method(D_METHOD("poll_live_original_resource", "identity"), &HardCoreSimulationHost::poll_live_original_resource);
	ClassDB::bind_method(D_METHOD("settle_live_original_resource", "settlement"), &HardCoreSimulationHost::settle_live_original_resource);
	ClassDB::bind_method(D_METHOD("settle_live_original_resource_status", "settlement"), &HardCoreSimulationHost::settle_live_original_resource_status);
	ClassDB::bind_method(D_METHOD("ack_live_original_resource_retirement", "identity", "actual_lease_obligations"), &HardCoreSimulationHost::ack_live_original_resource_retirement);
    ClassDB::bind_method(D_METHOD("bind_live_original_resource_vault","vault","actual_source_sha256"),&HardCoreSimulationHost::bind_live_original_resource_vault);
    ClassDB::bind_method(D_METHOD("transfer_live_original_resource_obligations","identity","actual_lease_obligations","receipt"),&HardCoreSimulationHost::transfer_live_original_resource_obligations);
    ClassDB::bind_method(D_METHOD("certify_live_original_resource_vault_closed","actual_close_receipt"),&HardCoreSimulationHost::certify_live_original_resource_vault_closed);
    ClassDB::bind_method(D_METHOD("live_original_resource_transport_releasable","identity"),&HardCoreSimulationHost::live_original_resource_transport_releasable);
	ClassDB::bind_method(D_METHOD("retire_live_original_resource", "identity"), &HardCoreSimulationHost::retire_live_original_resource);
	ClassDB::bind_method(D_METHOD("sample_main_thread_cpu_usec"), &HardCoreSimulationHost::sample_main_thread_cpu_usec);
	ClassDB::bind_method(D_METHOD("source_deferred_queue_configured"), &HardCoreSimulationHost::source_deferred_queue_configured);
	ClassDB::bind_method(D_METHOD("has_original_deferred_calls"), &HardCoreSimulationHost::has_original_deferred_calls);
	ClassDB::bind_method(D_METHOD("flush_source_deferred", "domain", "boundary"), &HardCoreSimulationHost::flush_source_deferred);
	ClassDB::bind_method(D_METHOD("owner_thread_id"), &HardCoreSimulationHost::owner_thread_id);
	ClassDB::bind_method(D_METHOD("resource_primitive_transport"), &HardCoreSimulationHost::resource_primitive_transport);
	ClassDB::bind_method(D_METHOD("world_primitive_transport"), &HardCoreSimulationHost::world_primitive_transport);
	ClassDB::bind_method(D_METHOD("capabilities"), &HardCoreSimulationHost::capabilities);
	ClassDB::bind_method(D_METHOD("prepare_original_main_channels", "config"), &HardCoreSimulationHost::prepare_original_main_channels);
	ClassDB::bind_method(D_METHOD("abort_prepared_original_main_channels", "retained_owners"), &HardCoreSimulationHost::abort_prepared_original_main_channels);
	ClassDB::bind_method(D_METHOD("next_original_operation_sequence"), &HardCoreSimulationHost::next_original_operation_sequence);
	ClassDB::bind_method(D_METHOD("completed_original_operation_sequence"), &HardCoreSimulationHost::completed_original_operation_sequence);
	ClassDB::bind_method(D_METHOD("next_original_call_ordinal", "source_site"), &HardCoreSimulationHost::next_original_call_ordinal);
	ClassDB::bind_method(D_METHOD("finish_original_call_site", "source_site"), &HardCoreSimulationHost::finish_original_call_site);
	ClassDB::bind_method(D_METHOD("current_clock_frame"), &HardCoreSimulationHost::current_clock_frame);
	ClassDB::bind_method(D_METHOD("bind_original_world_context", "world"), &HardCoreSimulationHost::bind_original_world_context);
	ClassDB::bind_method(D_METHOD("stage_original_main_prefix", "prefix"), &HardCoreSimulationHost::stage_original_main_prefix);
	ClassDB::bind_method(D_METHOD("register_published_original_main_prefix", "prefix"), &HardCoreSimulationHost::register_published_original_main_prefix);
    ClassDB::bind_method(D_METHOD("try_register_published_original_main_prefix","prefix"),&HardCoreSimulationHost::try_register_published_original_main_prefix);
	ClassDB::bind_method(D_METHOD("ack_published_original_main_prefix", "prefix", "ack"), &HardCoreSimulationHost::ack_published_original_main_prefix);
	ClassDB::bind_method(D_METHOD("completed_original_main_prefix_receipt"), &HardCoreSimulationHost::completed_original_main_prefix_receipt);
	ClassDB::bind_method(D_METHOD("ordered_main_prefix"), &HardCoreSimulationHost::ordered_main_prefix);
	ClassDB::bind_method(D_METHOD("exchange_original_primitive", "request"), &HardCoreSimulationHost::exchange_original_primitive);
	ClassDB::bind_method(D_METHOD("exchange_world_primitive", "request"), &HardCoreSimulationHost::exchange_world_primitive);
	ClassDB::bind_method(D_METHOD("acquire_pending_original_primitive"), &HardCoreSimulationHost::acquire_pending_original_primitive);
	ClassDB::bind_method(D_METHOD("ack_original_main_prefix", "identity", "ack"), &HardCoreSimulationHost::ack_original_main_prefix);
	ClassDB::bind_method(D_METHOD("validate_original_primitive_ticket", "request", "kind"), &HardCoreSimulationHost::validate_original_primitive_ticket);
	ClassDB::bind_method(D_METHOD("submit_original_primitive_result", "identity", "reply"), &HardCoreSimulationHost::submit_original_primitive_result);
	ClassDB::bind_method(D_METHOD("start", "factory", "bootstrap", "config"), &HardCoreSimulationHost::start);
#ifdef DEBUG_ENABLED
	ClassDB::bind_method(D_METHOD("start_clock_fixture", "factory", "bootstrap", "config"), &HardCoreSimulationHost::start_clock_fixture);
#endif
	ClassDB::bind_method(D_METHOD("submit_input", "packet"), &HardCoreSimulationHost::submit_input);
	ClassDB::bind_method(D_METHOD("acquire_presentation", "min_tick", "event_capacity"), &HardCoreSimulationHost::acquire_presentation);
	ClassDB::bind_method(D_METHOD("ack_events", "through_ordinal"), &HardCoreSimulationHost::ack_events);
	ClassDB::bind_method(D_METHOD("status"), &HardCoreSimulationHost::status);
	ClassDB::bind_method(D_METHOD("request_close"), &HardCoreSimulationHost::request_close);
	ClassDB::bind_method(D_METHOD("close_and_join"), &HardCoreSimulationHost::close_and_join);
	ClassDB::bind_method(D_METHOD("retire_started_original_main_channels", "owners"), &HardCoreSimulationHost::retire_started_original_main_channels);
    ClassDB::bind_method(D_METHOD("capture_original_terminal_gameplay_random","actual_random","next_event_identity"),&HardCoreSimulationHost::capture_original_terminal_gameplay_random);
    ClassDB::bind_method(D_METHOD("restore_original_terminal_gameplay_random","terminal_handoff"),&HardCoreSimulationHost::restore_original_terminal_gameplay_random);
	ClassDB::bind_method(D_METHOD("create_timer", "delay_seconds", "process_always", "process_in_physics", "ignore_time_scale"), &HardCoreSimulationHost::create_timer, DEFVAL(true), DEFVAL(false), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("publish_snapshot", "frame", "events"), &HardCoreSimulationHost::publish_snapshot);
	ClassDB::bind_method(D_METHOD("set_simulation_paused", "paused"), &HardCoreSimulationHost::set_simulation_paused);
	ClassDB::bind_method(D_METHOD("set_simulation_time_scale", "scale"), &HardCoreSimulationHost::set_simulation_time_scale);
}
bool HardCoreSimulationHost::start(const Ref<Script> &p_factory, const Dictionary &p_bootstrap, const Dictionary &p_config) {
	return start_impl(p_factory, p_bootstrap, p_config, false);
}
#ifdef DEBUG_ENABLED
bool HardCoreSimulationHost::start_clock_fixture(const Ref<Script> &p_factory, const Dictionary &p_bootstrap, const Dictionary &p_config) {
	return start_impl(p_factory, p_bootstrap, p_config, true);
}
#endif
namespace {
bool normalize_main_channel_config(const Dictionary &input, Dictionary &out) {
	for (const char *key : {"bridge_generation", "primitive_request_capacity", "primitive_result_capacity", "input_capacity", "event_capacity"}) {
		if (!input.has(key) || input[key].get_type() != Variant::INT || int64_t(input[key]) <= 0) return false;
		if (String(key) != "bridge_generation" && uint64_t(int64_t(input[key])) > SIZE_MAX) return false;
		out[key] = input[key];
	}
	const int64_t events = out["event_capacity"];
	if (uint64_t(events) > SIZE_MAX / 3) return false;
	int64_t live = 0;
	if (input.has("live_primitive_capacity")) {
		if (input["live_primitive_capacity"].get_type() != Variant::INT) return false;
		live = input["live_primitive_capacity"];
		if (live <= 0 || live > events) return false;
	}
	out["live_primitive_capacity"] = live; out.make_read_only(); return true;
}
bool main_script_current(const Ref<RefCounted> &object, const char *path, const String &sha) {
	if (object.is_null()) return false;
	Ref<Script> script = object->get_script();
	return script.is_valid() && script->get_path() == String(path) && sha.length() == 64 && script->get_source_code().sha256_text() == sha;
}
}
bool HardCoreSimulationHost::prepare_main_channels_impl(const Dictionary &config) {
	if (!Thread::is_main_thread() || started || main_channels_aborted || close_requested.load(std::memory_order_acquire) || session_faulted.load(std::memory_order_acquire) || !original_main_source_fault_receipt.is_empty()) return false;
	Dictionary normalized; if (!normalize_main_channel_config(config, normalized)) return false;
	if (main_channels_prepared) return normalized == prepared_main_channel_config;
	if (original_primitives || caster_event_replies || source_admission_scopes || map_loading_state || live_resources || close_process_frames) return false;
	const uint64_t generation = uint64_t(int64_t(normalized["bridge_generation"]));
	const std::size_t requests = std::size_t(int64_t(normalized["primitive_request_capacity"])), results = std::size_t(int64_t(normalized["primitive_result_capacity"]));
	const std::size_t events = std::size_t(int64_t(normalized["event_capacity"])), inputs_limit = std::size_t(int64_t(normalized["input_capacity"])), live = std::size_t(int64_t(normalized["live_primitive_capacity"]));
	auto primitives = std::make_unique<OriginalMailbox>(generation, requests, results, events);
	auto caster = std::make_unique<hardcore::simulation::SourceEventReplyMailbox>(generation, events, requests, results);
	auto admission = std::make_unique<hardcore::simulation::SourceAdmissionScopeLedger>(generation, requests);
	auto maps = std::make_unique<hardcore::simulation::MapLoadingHostState>(generation, requests);
	auto closing = std::make_unique<hardcore::simulation::CloseProcessMailbox>(generation, inputs_limit);
	std::unique_ptr<hardcore::simulation::AsyncLiveResourceMailbox> live_box;
	if (live > 0) live_box = std::make_unique<hardcore::simulation::AsyncLiveResourceMailbox>(*primitives, generation, live, requests, results);
	original_primitives = std::move(primitives); caster_event_replies = std::move(caster);
	source_admission_scopes = std::move(admission); map_loading_state = std::move(maps);
	close_process_frames = std::move(closing); live_resources = std::move(live_box);
	bridge_generation = generation; input_capacity = inputs_limit; source_scope_capacity = requests;
	prepared_main_channel_config = normalized; main_channels_prepared = true; return true;
}
Dictionary HardCoreSimulationHost::prepare_original_main_channels(const Dictionary &config) {
	Dictionary out; const bool ok = prepare_main_channels_impl(config);
	out["success"] = ok; out["status"] = ok ? "PREPARED" : "INVALID";
	if (ok) {out["host_object_id"] = int64_t(get_instance_id()); out["channel_config"] = prepared_main_channel_config;}
	else out["error"] = "original_main_channel_preparation_rejected";
	return out;
}
bool HardCoreSimulationHost::actual_production_main_bindings_ready(const Dictionary &boot) const {
	if (!Thread::is_main_thread() || !live_resources || !close_process_producer_bound.load(std::memory_order_acquire) || !live_feature_main_valid() || issued_main_feature != live_feature_main || !issued_binding_valid(issued_feature_binding) || !issued_binding_valid(issued_origin_binding)) return false;
	if (!main_script_current(main_source_admission, "res://scripts/gameplay/source/main_source_admission.gd", main_source_admission_sha) || !main_script_current(main_caster_reply_producer, "res://scripts/gameplay/world/world_caster_main_executor.gd", main_caster_reply_sha) || !main_script_current(live_resource_vault, "res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd", live_resource_vault_sha) || !main_script_current(main_close_process_producer, "res://scripts/gameplay/source/main_close_process_frame_producer.gd", main_close_process_producer_sha)) return false;
	if (live_resource_vault->get("_configured") != Variant(true) || live_resource_vault->get("_generation_closed") != Variant(false) || live_resource_vault->get("_bridge_generation") != Variant(int64_t(bridge_generation))) return false;
	if (!boot.has("session_id") || boot["session_id"].get_type() != Variant::INT || int64_t(boot["session_id"]) <= 0 || issued_main_origin->get("_session_id") != boot["session_id"] || main_close_process_producer->get("_finished") != Variant(false) || main_close_process_producer->get("_capture_stopped") != Variant(false) || main_close_process_producer->get("_session_io") != Variant(issued_main_origin)) return false;
	Variant actual = main_close_process_producer->call(SNAME("_actual_listener"));
	Object *listener = actual.get_type() == Variant::OBJECT ? static_cast<Object *>(actual) : nullptr;
	return listener && int64_t(listener->get_instance_id()) == close_process_listener_id;
}
Dictionary HardCoreSimulationHost::abort_prepared_original_main_channels(const Dictionary &owners) {
	Dictionary out; out["success"] = false; out["status"] = "INVALID";
	if (!Thread::is_main_thread() || !main_channels_prepared || main_channels_aborted || started || thread.is_started() || running.load(std::memory_order_acquire) || owner.load(std::memory_order_acquire) != Thread::UNASSIGNED_ID || physics_handoff_prepared || model.is_valid() || original_deferred_queue || close_progress->accepted_groups.load(std::memory_order_acquire) != 0 || issued_source_binding.object || issued_session_binding.object || !live_feature_execution.is_empty() || !live_feature_transfers.empty()) return out;
	if (!original_primitives || original_primitives->in_flight() || original_primitives->unsettled_published_count() || !caster_event_replies || !caster_event_replies->can_close() || (live_resources && live_resources->accepted_count()) || !close_process_frames || close_process_frames->published_sequence() || !map_loading_state || !map_loading_state->provenance.can_close()) return out;
	// The caller strongly retains these exact Main objects. Unbinding never
	// clears resources, closes a physical vault, invents STOP, or clears faults.
	const std::pair<const char *, Ref<RefCounted>> expected[] = {{"admission", main_source_admission}, {"claim_feature", issued_main_feature}, {"claim_origin", issued_main_origin}, {"live_feature", live_feature_main}, {"streaming", live_resource_vault}, {"caster", main_caster_reply_producer}, {"closing", main_close_process_producer}};
	if (owners.size() != 7) return out;
	for (const auto &row : expected) {
		if (!owners.has(row.first)) {out["error"] = "actual_retained_owner_missing:" + String(row.first); return out;}
		Variant value = owners[row.first];
		Object *actual = value.get_type() == Variant::OBJECT ? static_cast<Object *>(value) : nullptr;
		if ((value.get_type() != Variant::NIL && value.get_type() != Variant::OBJECT) || actual != row.second.ptr()) {out["error"] = "actual_retained_owner_mismatch:" + String(row.first); return out;}
	}
	if (main_source_admission.is_valid()) {
		if (!main_script_current(main_source_admission, "res://scripts/gameplay/source/main_source_admission.gd", main_source_admission_sha) || main_source_admission->get("_committed") != Variant(false)) return out;
		Variant handoff = main_source_admission->get("_physical_handoff"), prepared = main_source_admission->get("_prepared");
		if (handoff.get_type() != Variant::DICTIONARY || !Dictionary(handoff).is_empty() || prepared.get_type() != Variant::DICTIONARY || !Dictionary(prepared).is_empty()) return out;
		Variant gate_value = main_source_admission->get("_gate"); Object *gate = gate_value.get_type() == Variant::OBJECT ? static_cast<Object *>(gate_value) : nullptr;
		if (!gate || gate->call(SNAME("state")) != Variant("MAIN")) return out;
	}
	if (!source_admission_scopes || !source_admission_scopes->retire_unclaimed_aborted_main()) return out;
	main_source_admission.unref(); main_source_admission_sha = String();
	issued_main_feature.unref(); issued_main_origin.unref(); issued_feature_binding = {}; issued_origin_binding = {}; issued_helper_bindings.clear();
	live_feature_main.unref(); live_feature_bound.store(false, std::memory_order_release); live_feature_script_id = ObjectID(); live_feature_instance = 0; live_feature_source = String();
	live_resource_vault.unref(); live_resource_vault_sha = String();
	main_caster_reply_producer.unref(); main_caster_reply_sha = String(); main_caster_reply_id.store(0, std::memory_order_release);
	main_close_process_producer.unref(); main_close_process_producer_sha = String(); close_process_listener_id = 0; close_process_generation = 0; close_process_producer_bound.store(false, std::memory_order_release);
	live_resources.reset(); caster_event_replies.reset(); source_admission_scopes.reset(); map_loading_state.reset(); close_process_frames.reset(); original_primitives.reset();
	main_channels_aborted = true; out["success"] = true; out["status"] = "ABORTED_BEFORE_START"; out["host_object_id"] = int64_t(get_instance_id()); return out;
}

Dictionary HardCoreSimulationHost::retire_started_original_main_channels(const Dictionary &owners) {
	Dictionary out; out["success"] = false; out["status"] = "INVALID";
	if (!Thread::is_main_thread()) { out["error"] = "actual_Main_thread_required"; return out; }
	Ref<HardCoreSimulationHost> keep_alive(this);
	using Guard = hardcore::simulation::TerminalOwnerUnbindGuard;
	using Fact = Guard::Fact;
	if (terminal_owner_unbind_guard.phase() == Guard::Phase::RETIRING) { out["error"] = "actual_owner_unbind_reentry"; return out; }
	const bool repeated = terminal_owner_unbind_guard.phase() == Guard::Phase::RETIRED;
	// Acquire the actual completed S/TLS join before inspecting any S-owned
	// non-atomic model/deferred/cache fields or invoking Main owner inspectors.
	if (!started || !main_channels_prepared || main_channels_aborted || fixture_mode || !close_requested.load(std::memory_order_acquire) || !source_model_close_completed.load(std::memory_order_acquire) || !close_quiescent.load(std::memory_order_acquire) || !join_complete.load(std::memory_order_acquire) || running.load(std::memory_order_acquire) || owner.load(std::memory_order_acquire) != Thread::UNASSIGNED_ID) { out["error"] = "actual_started_joined_terminal_required"; return out; }

	const char *roles[] = {"admission", "claim_feature", "claim_origin", "live_feature", "streaming", "caster", "closing", "map_producer", "map_executor"};
	const char *paths[] = {"res://scripts/gameplay/source/main_source_admission.gd", "res://scripts/features/runtime/feature_resource_main_primitives.gd", "res://scripts/gameplay/source/main_source_closing_io_producer.gd", "res://scripts/features/runtime/feature_resource_main_primitives.gd", "res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd", "res://scripts/gameplay/world/world_caster_main_executor.gd", "res://scripts/gameplay/source/main_close_process_frame_producer.gd", "res://scripts/gameplay/source/main_map_loading_producer.gd", "res://scripts/gameplay/world/world_map_event_main.gd"};
	if (owners.size() != 9) { out["error"] = "actual_nine_owner_roles_required"; return out; }
	// These local Refs and the caller's exact Dictionary keep every Main owner
	// alive across member unref. No Script PREDELETE can re-enter mid-detach.
	std::array<Ref<RefCounted>, 9> provided;
	Guard::OwnerIds ids{};
	for (std::size_t i = 0; i < provided.size(); ++i) {
		if (!owners.has(roles[i])) { out["error"] = "actual_owner_missing:" + String(roles[i]); return out; }
		Variant value = owners[roles[i]];
		Object *object = value.get_type() == Variant::OBJECT ? static_cast<Object *>(value) : nullptr;
		RefCounted *counted = object ? Object::cast_to<RefCounted>(object) : nullptr;
		if (!counted) { out["error"] = "actual_retained_RefCounted_owner_required:" + String(roles[i]); return out; }
		provided[i] = Ref<RefCounted>(counted); ids[i] = uint64_t(counted->get_instance_id());
	}
	const std::array<Ref<RefCounted>, 9> expected = {main_source_admission, issued_main_feature, issued_main_origin, live_feature_main, live_resource_vault, main_caster_reply_producer, main_close_process_producer, main_map_loading_producer, main_map_event_executor};
	std::array<IssuedClaimBinding, 9> captured_bindings;
	bool bindings_current = ids[1] == ids[3];
	for (std::size_t i = 0; i < provided.size(); ++i) {
		Ref<Script> script = provided[i]->get_script();
		if (script.is_null() || !script->is_valid() || script->get_path() != String(paths[i]) || !provided[i]->get_script_instance()) { bindings_current = false; continue; }
		if (repeated) {
			const auto &binding = terminal_owner_unbound_bindings[i];
			bindings_current = bindings_current && binding.object == ids[i] && issued_binding_valid(binding);
		} else {
			bindings_current = bindings_current && provided[i] == expected[i];
			captured_bindings[i] = {ids[i], uint64_t(script->get_instance_id()), reinterpret_cast<uintptr_t>(provided[i]->get_script_instance()), Thread::get_caller_id(), script->get_source_code(), script->get_source_code().sha256_text()};
		}
	}
	if (!repeated) {
		bindings_current = bindings_current && live_feature_main_valid() && issued_main_feature == live_feature_main && issued_binding_valid(issued_feature_binding) && issued_binding_valid(issued_origin_binding)
			&& main_script_current(main_source_admission, paths[0], main_source_admission_sha)
			&& main_script_current(issued_main_feature, paths[1], issued_feature_binding.sha)
			&& main_script_current(issued_main_origin, paths[2], issued_origin_binding.sha)
			&& main_script_current(live_resource_vault, paths[4], live_resource_vault_sha)
			&& main_script_current(main_caster_reply_producer, paths[5], main_caster_reply_sha)
			&& main_script_current(main_close_process_producer, paths[6], main_close_process_producer_sha)
			&& main_script_current(main_map_loading_producer, paths[7], main_map_loading_producer_sha)
			&& main_script_current(main_map_event_executor, paths[8], main_map_event_executor_sha);
	}
	bool no_fault = !session_faulted.load(std::memory_order_acquire), inputs_empty = false;
	{
		std::lock_guard<std::mutex> lock(mailbox_mutex);
		no_fault = no_fault && fault_reason.is_empty() && original_main_source_fault_receipt.is_empty();
		inputs_empty = inputs.empty();
	}
	bool map_drained = false;
	if (map_loading_state && map_loading_state->provenance.can_close()) {
		std::unique_lock<std::mutex> lock(map_loading_state->facts_mutex, std::try_to_lock);
		map_drained = lock.owns_lock() && !map_loading_state->used && !map_loading_state->event && !map_loading_state->settlement;
	}
	auto collection_empty = [](const Ref<RefCounted> &object, const char *field) {
		Variant value = object->get(StringName(field));
		return (value.get_type() == Variant::DICTIONARY && Dictionary(value).is_empty()) || (value.get_type() == Variant::ARRAY && Array(value).is_empty());
	};
	bool main_debts_drained = bindings_current;
	if (bindings_current && !repeated) {
		for (const char *field : {"_claims", "_retirements", "_owner_calls", "_retentions", "_issued_claim_records", "_issued_live_pending_paths", "_issued_claim_facts", "_command_reference_loans", "_normal_live_jobs", "_source_request"}) main_debts_drained = main_debts_drained && collection_empty(provided[1],field);
		for (const char *field : {"_accepted_claims", "_get_escrow", "_texture_roots", "_texture_references", "_renderers"}) main_debts_drained = main_debts_drained && collection_empty(provided[4],field);
		for (const char *field : {"_casts", "_visuals", "_cells", "_batches", "_cell_controller", "_created_nodes", "_live_reply_nodes", "_claimed_event", "_claimed_ticket", "_paths", "_textures", "_code_objects", "_code_result"}) main_debts_drained = main_debts_drained && collection_empty(provided[5],field);
		for (const char *field : {"_accepted", "_accepted_signal", "_pending_service", "_fault"}) main_debts_drained = main_debts_drained && collection_empty(provided[6],field);
		for (const char *field : {"_effect", "_reply", "_fault"}) main_debts_drained = main_debts_drained && collection_empty(provided[8],field);
		// The exact sealed Feature script close_main() is a read-only inspector:
		// it checks jobs/loans/claims/retirements/retentions and weak vault entries.
		// It does not execute cleanup, issue commands, or mutate owner state.
		main_debts_drained = main_debts_drained && provided[1]->get("_failed") == Variant(false) && provided[1]->call(SNAME("close_main")) == Variant(true)
			&& provided[4]->get("_generation_closed") == Variant(true) && provided[4]->get("_live_transfer_completed") == Variant(true)
			&& provided[5]->get("_closed") == Variant(true) && provided[5]->get("_awaiting_reply") == Variant(false) && provided[5]->get("_loading_sequence_lease_held") == Variant(false);
		// Map's real terminal was certified before Root/HUD final-free. Never
		// call its inside_tree-dependent verifier at this later lifetime point.
		Variant terminal_value = provided[7]->get("_terminal");
		Dictionary terminal = terminal_value.get_type() == Variant::DICTIONARY ? Dictionary(terminal_value) : Dictionary();
		Variant descriptor_value = terminal.get("owner_descriptor",Variant());
		Dictionary descriptor = descriptor_value.get_type() == Variant::DICTIONARY ? Dictionary(descriptor_value) : Dictionary();
		map_drained = map_drained && terminal.get("contract_id",Variant()) == Variant("hardcore.main.map_owner.terminal.v1") && terminal.get("producer_runtime_id",Variant()) == Variant(int64_t(ids[7])) && terminal.get("actual_remaining_pin_count",Variant()) == Variant(int64_t(0)) && descriptor.get("main_executor_id",Variant()) == Variant(int64_t(ids[8]));
	}
	// The session transport's actual listener has also been retired by Main,
	// independently of the closing-frame listener covered by Native STOP.
	if (bindings_current && !repeated) {
		Variant transport_value = provided[2]->get("_session_transport");
		Object *transport = transport_value.get_type() == Variant::OBJECT ? static_cast<Object *>(transport_value) : nullptr;
		Ref<Script> transport_script = transport ? Ref<Script>(transport->get_script()) : Ref<Script>();
		main_debts_drained = main_debts_drained && transport && transport_script.is_valid() && transport_script->get_path() == String("res://scripts/gameplay/source/main_session_transport.gd") && transport->get("_host") == Variant(this) && transport->get("_state") == Variant("CLOSED") && transport->get("_actual_terminal_listener_retired") == Variant(true) && transport->get("_listener").get_type() == Variant::NIL;
	}
	// First retirement verifies the live producer and actual STOP proof. Repeat
	// requests compare the immutable proof saved before detaching its binding;
	// they never invoke a verifier that might depend on detached producer refs.
	const bool stop_identity = bindings_current && close_process_stop_receipt.size() == 5
		&& close_process_stop_receipt.get("producer_runtime_id",Variant()) == Variant(int64_t(ids[6]))
		&& close_process_stop_receipt.get("bridge_generation",Variant()) == Variant(int64_t(bridge_generation))
		&& close_process_listener_id != 0 && ObjectDB::get_instance(ObjectID(uint64_t(close_process_listener_id))) == nullptr;
	const bool stop_verified = stop_identity && (repeated
		? (terminal_owner_unbound_stop_receipt.size() == 5 && terminal_owner_unbound_stop_receipt == close_process_stop_receipt && close_process_frames && close_process_frames->can_close())
		: (verify_original_close_process_producer_terminal_receipt(close_process_stop_receipt) && provided[6]->get("_finished") == Variant(true) && provided[6]->get("_capture_stopped") == Variant(true)));
	Guard::Facts facts;
	facts.set(Fact::MAIN_THREAD,Thread::is_main_thread());
	facts.set(Fact::STARTED_PRODUCTION,started && main_channels_prepared && !main_channels_aborted && !fixture_mode);
	facts.set(Fact::CLOSE_REQUESTED,close_requested.load(std::memory_order_acquire));
	facts.set(Fact::SOURCE_MODEL_CLOSED,source_model_close_completed.load(std::memory_order_acquire));
	facts.set(Fact::QUIESCENT,close_quiescent.load(std::memory_order_acquire) && !close_failed.load(std::memory_order_acquire));
	facts.set(Fact::JOINED,join_complete.load(std::memory_order_acquire) && !thread.is_started());
	facts.set(Fact::MAIN_JOIN_COMPLETED,lifetime_pin.is_null() && !join_reaper.joinable());
	facts.set(Fact::PHYSICS_FINISHED,physics_handoff_prepared && physics && physics->is_external_owner_mode() && physics->is_external_finished());
	facts.set(Fact::NO_RUNNING_OWNER,!running.load(std::memory_order_acquire) && owner.load(std::memory_order_acquire) == Thread::UNASSIGNED_ID);
	facts.set(Fact::NO_FAULT,no_fault);
	facts.set(Fact::NO_SOURCE_OBJECTS,model.is_null() && original_deferred_queue == nullptr && active_clock == nullptr && bootstrap.is_empty() && timer_objects.empty());
	facts.set(Fact::NO_WORKERS,close_progress->accepted_groups.load(std::memory_order_acquire) == 0);
	facts.set(Fact::ORIGINAL_MAILBOX_CLOSED,original_primitives && original_primitives->can_join() && original_primitives->quiescent() && !original_primitives->in_flight() && original_primitives->unsettled_published_count() == 0);
	facts.set(Fact::LIVE_MAILBOX_CLOSED,live_resources && live_resources->can_close() && live_resources->accepted_count() == 0 && live_feature_execution.is_empty() && live_feature_actual_reply.is_empty() && live_feature_executed_body.is_empty() && live_feature_transfers.empty() && !live_feature_execution_claimed && !live_feature_issued_prepared && !live_feature_issued_folded);
	facts.set(Fact::FEATURE_CLOSED,live_feature_closed.load(std::memory_order_acquire));
	facts.set(Fact::RESOURCE_VAULT_CLOSED,live_resource_vault_closed.load(std::memory_order_acquire) && !main_vault_close_active);
	facts.set(Fact::ADMISSION_DRAINED,source_admission_scopes && source_admission_scopes->quiescent());
	facts.set(Fact::CASTER_DRAINED,caster_event_replies && caster_event_replies->can_close());
	facts.set(Fact::MAP_DRAINED,map_drained);
	facts.set(Fact::STOP_VERIFIED,stop_verified);
	facts.set(Fact::INPUTS_DRAINED,inputs_empty);
	facts.set(Fact::BINDINGS_CURRENT,bindings_current);
	facts.set(Fact::MAIN_DEBTS_DRAINED,main_debts_drained);
	const auto decision = terminal_owner_unbind_guard.begin(facts,ids);
	if (decision == Guard::Result::ALREADY_RETIRED) return terminal_owner_unbound_receipt;
	if (decision != Guard::Result::RETIRE_NOW) { out["error"] = "actual_started_terminal_owner_unbind_rejected"; out["missing_fact_mask"] = int64_t(facts.missing()); return out; }
	terminal_owner_unbound_bindings = captured_bindings;
	terminal_owner_unbound_stop_receipt = close_process_stop_receipt.duplicate(true);
	terminal_owner_unbound_stop_receipt.make_read_only();
	Dictionary owner_ids;
	for (std::size_t i = 0; i < ids.size(); ++i) owner_ids[roles[i]] = int64_t(ids[i]);
	owner_ids.make_read_only();
	out["success"] = true; out["status"] = "UNBOUND_AFTER_CLOSE"; out["host_object_id"] = int64_t(get_instance_id()); out["bridge_generation"] = int64_t(bridge_generation); out["actual_owner_ids"] = owner_ids;
	out.make_read_only();
	// No accepted work or S object is cleared here. Retain the terminal numeric
	// mailboxes, map provenance and STOP receipt for status/close_and_join.
	main_source_admission.unref(); main_source_admission_sha = String();
	issued_main_feature.unref(); issued_main_origin.unref(); issued_feature_binding = {}; issued_origin_binding = {}; issued_helper_bindings.clear();
	live_feature_main.unref(); live_feature_bound.store(false,std::memory_order_release); live_feature_script_id = ObjectID(); live_feature_instance = 0; live_feature_source = String();
	live_resource_vault.unref(); live_resource_vault_sha = String();
	main_caster_reply_producer.unref(); main_caster_reply_sha = String(); main_caster_reply_id.store(0,std::memory_order_release);
	main_close_process_producer.unref(); main_close_process_producer_sha = String(); close_process_producer_bound.store(false,std::memory_order_release);
	main_map_loading_producer.unref(); main_map_loading_producer_sha = String(); main_map_event_executor.unref(); main_map_event_executor_sha = String();
	terminal_owner_unbound_receipt = out;
	CRASH_COND_MSG(!terminal_owner_unbind_guard.commit(),"Actual terminal owner unbind commit ordering violated.");
	main_channels_unbound_after_close.store(true,std::memory_order_release);
	return terminal_owner_unbound_receipt;
}

bool HardCoreSimulationHost::start_impl(const Ref<Script> &p_factory, const Dictionary &p_bootstrap, const Dictionary &p_config, bool p_fixture) {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || started || main_channels_aborted || close_requested.load(std::memory_order_acquire) || session_faulted.load(std::memory_order_acquire) || p_factory.is_null() || p_factory->get_instance_base_type() != SNAME("RefCounted"), false);

	// A refused Main writer cannot be erased by starting/restarting a Source.
	// This check precedes every physics preparation or factory constructor.
	if (!original_main_source_fault_receipt.is_empty()) return false;

	const char *required_native_config[] = {"bridge_generation", "source_process_frame", "source_physics_frame", "primitive_request_capacity", "primitive_result_capacity", "source_deferred_max_pages"};
	for (const char *key : required_native_config) ERR_FAIL_COND_V(!p_config.has(key) || p_config[key].get_type() != Variant::INT, false);
	const int64_t generation = p_config["bridge_generation"], process_seed = p_config["source_process_frame"], physics_seed = p_config["source_physics_frame"];
	const int64_t request_bytes = p_config["primitive_request_capacity"], result_bytes = p_config["primitive_result_capacity"];
	const int64_t deferred_pages = p_config["source_deferred_max_pages"];
	ERR_FAIL_COND_V(deferred_pages <= 0 || static_cast<uint64_t>(deferred_pages) > UINT32_MAX, false);

	ERR_FAIL_COND_V(generation <= 0 || process_seed < 0 || physics_seed < 0 || request_bytes <= 0 || result_bytes <= 0 || static_cast<uint64_t>(request_bytes) > SIZE_MAX || static_cast<uint64_t>(result_bytes) > SIZE_MAX, false);
#ifndef THREADS_ENABLED
	ERR_FAIL_V_MSG(false, "Original-position continuation requires real Godot threads.");
#endif
	const int64_t hz = p_config.get("physics_hz", 0), limit = p_config.get("max_epochs_per_turn", 0);
	const int64_t timer_limit = p_config.get("timer_capacity", 0), input_limit = p_config.get("input_capacity", 0), event_limit = p_config.get("event_capacity", 0);
	ERR_FAIL_COND_V(hz <= 0 || hz > 1000000 || limit <= 0 || limit > UINT32_MAX || timer_limit <= 0 || input_limit <= 0 || event_limit <= 0, false);
    int64_t live_capacity=0;
    if(p_config.has("live_primitive_capacity")){ERR_FAIL_COND_V(p_config["live_primitive_capacity"].get_type()!=Variant::INT,false);live_capacity=p_config["live_primitive_capacity"];ERR_FAIL_COND_V(live_capacity<=0||live_capacity>event_limit,false);}
	HardCoreContentValueGraph graph;
	Dictionary copied = graph.capture(p_bootstrap, true, false);
	ERR_FAIL_COND_V(!static_cast<bool>(copied["success"]), false);
	Variant boot = copied["value"];
	if (!prepare_main_channels_impl(p_config)) return false;
	if (p_factory->get_path() == String("res://scripts/gameplay/source/source_session_runtime.gd") && !actual_production_main_bindings_ready(p_bootstrap)) return false;
	auto prepared_timers = std::make_unique<Ledger>(static_cast<std::size_t>(timer_limit));
	auto prepared_bridge = std::make_unique<Bridge>(static_cast<std::size_t>(event_limit));
	if (!p_fixture) {
		physics = Object::cast_to<PhysicsServer2DWrapMT>(PhysicsServer2D::get_singleton());
		ERR_FAIL_COND_V(!physics || !physics->is_external_owner_mode(), false);
		ERR_FAIL_COND_V(!physics->prepare_external_handoff(), false);
		physics_handoff_prepared = true;
	}
	physics_hz = static_cast<uint32_t>(hz); max_epochs_per_turn = static_cast<uint32_t>(limit);
	source_deferred_max_pages = static_cast<uint32_t>(deferred_pages);
	timers = std::move(prepared_timers); bridge = std::move(prepared_bridge);
	factory = p_factory; bootstrap = boot; fixture_mode = p_fixture;
	source_process_frame.store(process_seed, std::memory_order_release); source_physics_frame.store(physics_seed, std::memory_order_release);
    if (p_bootstrap.has("world_identity") && p_bootstrap["world_identity"].get_type() == Variant::DICTIONARY) primitive_world = Dictionary(p_bootstrap["world_identity"]).duplicate(true);
	lifetime_pin = Ref<HardCoreSimulationHost>(this); // Main cannot destruct an accepted S continuation.
	started = true; running.store(true, std::memory_order_release);
	thread.start(&HardCoreSimulationHost::thread_entry, this);
	join_reaper = std::thread([this] {
		{ std::unique_lock<std::mutex> lock(mailbox_mutex); shutdown_wake.wait(lock, [this] { return close_quiescent.load(std::memory_order_acquire); }); }
		// Pinned core/os/thread.cpp:83-89 only joins/deallocates the native
		// Thread. ScriptServer::thread_exit runs on S at :66, before join ends.
		// This helper owns no Ref, Script, Callable, model or physics operation.
		thread.wait_to_finish();
		join_complete.store(true, std::memory_order_release);
	});
	return true;
}
bool HardCoreSimulationHost::is_owner() const { return Thread::get_caller_id() == owner.load(std::memory_order_acquire) && !Thread::is_main_thread(); }
void HardCoreSimulationHost::thread_entry(void *p_userdata) { static_cast<HardCoreSimulationHost *>(p_userdata)->thread_run(); }
uint64_t HardCoreSimulationHost::now_usec() const { return OS::get_singleton()->get_ticks_usec(); }
double HardCoreSimulationHost::sample_time_scale() const { return time_scale.load(std::memory_order_acquire); }
bool HardCoreSimulationHost::is_paused() const { return paused.load(std::memory_order_acquire); }
void HardCoreSimulationHost::set_fault(const String &p_reason) {
	session_faulted = true;
	std::lock_guard<std::mutex> lock(mailbox_mutex);
	if (fault_reason.is_empty()) fault_reason = p_reason;
}
bool HardCoreSimulationHost::call_model(const StringName &p_method, const Array &p_args) {
	if (model.is_null() || !model->has_method(p_method)) { set_fault("missing_model_method:" + String(p_method)); return false; }
	Variant value = model->callv(p_method, p_args);
	if (value.get_type() != Variant::BOOL || !static_cast<bool>(value)) { set_fault("model_boundary_failed:" + String(p_method)); return false; }
	return true;
}
void HardCoreSimulationHost::drain_inputs(const String &p_domain) {
	Array batch;
	{
		std::lock_guard<std::mutex> lock(mailbox_mutex);
		while (!inputs.empty()) {
			Variant value;
			if (!decode_plain(inputs.front(), value) || value.get_type() != Variant::DICTIONARY) { session_faulted = true; fault_reason = "invalid_internal_input_packet"; break; }
			batch.push_back(value); inputs.pop_front();
		}
	}
	if (!session_faulted && !batch.is_empty()) { Array args; args.push_back(p_domain); args.push_back(batch); call_model(SNAME("on_inputs"), args); }
}
void HardCoreSimulationHost::on_phase(Clock::Phase p_phase, const Clock::ClockFrame &p_frame) {
	if (original_site_epoch != p_frame.epoch) { CRASH_COND_MSG(!original_primitives->reset_call_sites(), "Source epoch changed with accepted primitive."); original_site_epoch = p_frame.epoch; }
	current_epoch = p_frame.epoch; current_phase = p_phase; current_phase_name = phase_name(p_phase);
	source_deferred_flush_mask = 0;
	if (p_phase == Clock::Phase::H_PREPARE) source_physics_frame.fetch_add(1, std::memory_order_release);
	Dictionary frame;
	frame["epoch"] = static_cast<int64_t>(p_frame.epoch); frame["h_ordinal"] = p_frame.h_ordinal;
	frame["source_process_frame"] = static_cast<int64_t>(source_process_frame.load(std::memory_order_acquire)); frame["source_physics_frame"] = static_cast<int64_t>(source_physics_frame.load(std::memory_order_acquire));
	frame["next_release_usec"] = static_cast<int64_t>(active_clock->release_usec(p_frame.epoch + 1));
	frame["release_usec"] = static_cast<int64_t>(p_frame.release_usec); frame["observed_usec"] = static_cast<int64_t>(p_frame.observed_usec);
	frame["lateness_usec"] = static_cast<int64_t>(p_frame.lateness_usec); frame["time_scale"] = p_frame.time_scale;
	frame["simulation_elapsed"] = p_frame.simulation_elapsed;
	frame["raw_delta"] = p_frame.delta.raw; frame["clipped_delta"] = p_frame.delta.clipped;
	frame["scaled_delta"] = p_frame.delta.scaled; frame["unscaled_timer_delta"] = p_frame.delta.unscaled_timer;
	original_source_frame = frame.duplicate(true); // Available to actual on_inputs callbacks too.
	if (p_phase == Clock::Phase::H_INPUT || p_phase == Clock::Phase::P_INPUT || p_phase == Clock::Phase::U_WAKE) drain_inputs(phase_name(p_phase));
	if (physics && p_phase == Clock::Phase::H_PREPARE) {
		// The actual Source model publishes its queued original transforms before
		// the existing native sync. This does not create another H/timer release.
		if (model.is_valid() && model->has_method(SNAME("source_prepare_before_sync"))) {
			const StringName previous_boundary = original_source_boundary;
			original_source_boundary = SNAME("H_PREPARE:before_sync");
			const bool prepared = call_model(SNAME("source_prepare_before_sync"), Array());
			original_source_boundary = previous_boundary;
			if (!prepared) return;
		}
		physics->sync(); physics->flush_queries(); physics->external_begin_logic();
	}
	if (physics && p_phase == Clock::Phase::H_STEP) { physics->end_sync(); physics->step(static_cast<real_t>(p_frame.delta.scaled)); physics->external_begin_process(); }
	if (!session_faulted) { Array args; args.push_back(String(phase_name(p_phase))); args.push_back(frame); call_model(SNAME("on_phase"), args); }
	if (p_phase == Clock::Phase::PUBLISH) source_process_frame.fetch_add(1, std::memory_order_release);
	if (physics && p_phase == Clock::Phase::PUBLISH) physics->external_end_process();
}
void HardCoreSimulationHost::thread_run() {
	Thread::set_name("HardCoreSimulation");
	owner.store(Thread::get_caller_id(), std::memory_order_release);
    CRASH_COND_MSG(!close_process_frames||!close_process_frames->bind_owner(),"Original closing P owner bind failed.");
    CRASH_COND_MSG(caster_event_replies && !caster_event_replies->bind_owner(), "Caster event reply owner bind failed.");
    CRASH_COND_MSG(map_loading_state && !map_loading_state->provenance.bind_owner(), "Map provenance owner bind failed.");
    CRASH_COND_MSG(source_admission_scopes && !source_admission_scopes->bind_owner(), "Source admission owner bind failed.");
    CRASH_COND_MSG(live_resources && !live_resources->bind_owner(), "LIVE resource owner bind failed.");
	CRASH_COND_MSG(MessageQueue::get_singleton() != MessageQueue::get_main_singleton(), "S already owns a different message queue override.");
	CallQueue source_deferred_queue(nullptr, source_deferred_max_pages, "Original S message queue out of memory.");
	original_deferred_queue = &source_deferred_queue;
	MessageQueue::set_thread_singleton_override(original_deferred_queue);
	CRASH_COND_MSG(!original_primitives->bind_owner(), "Original primitive mailbox owner binding failed.");
	bool claimed = !physics || physics->claim_external_owner();
	if (!claimed) set_fault("physics_owner_claim_failed");
	// Original bootstrap ready queries: sole claimed backend, no synthetic H,
	// sync, flush, step, tick, elapsed time or source-frame increment.
	const bool bootstrap_query = physics && claimed;
	if (bootstrap_query) { physics->external_begin_process(); original_source_boundary = SNAME("bootstrap_ready_query"); }
	if (!session_faulted) {
		Variant created = factory->call(SNAME("new"), this, bootstrap);
		model = created;
		if (model.is_null()) set_fault("model_factory_did_not_create_plain_owner");
	}
	if (bootstrap_query) physics->external_end_process();
	original_source_boundary = StringName();
	bootstrap = Dictionary(); // Release our reference; do not mutate a graph retained by the model.
	Clock clock({physics_hz, max_epochs_per_turn, now_usec()}, *this, *timers);
	active_clock = &clock;
	while (!session_faulted && !close_requested.load(std::memory_order_acquire)) {
		const auto receipt = clock.run_turn();
		serviced_epoch.store(clock.next_epoch() - 1, std::memory_order_release);
		pending_epochs.store(receipt.pending_epochs, std::memory_order_release);
		late_starts.fetch_add(receipt.late_starts, std::memory_order_relaxed);
		deadline_misses.fetch_add(receipt.deadline_misses, std::memory_order_relaxed);
		if (receipt.fault.code == Clock::FaultCode::CLOCK_OVERRUN) {
			clock_overruns.fetch_add(1, std::memory_order_relaxed);
		} else if (receipt.fault.code != Clock::FaultCode::NONE) {
			set_fault("simulation_clock_fault:" + String::num_int64(static_cast<int64_t>(receipt.fault.code))); break;
		}
		const uint64_t now = now_usec();
		const uint64_t wait_usec = receipt.next_release_usec > now ? receipt.next_release_usec - now : 0;
		if (wait_usec > 0) {
			std::unique_lock<std::mutex> lock(mailbox_mutex);
			wake.wait_for(lock, std::chrono::microseconds(wait_usec), [this] { return close_requested.load(std::memory_order_acquire) || !inputs.empty(); });
		}
	}
	closing_session = true;
    if(caster_event_replies)caster_event_replies->request_close();
	close_requested.store(true, std::memory_order_release); original_primitives->request_close();
    bool close_model_initialized=false;
	for (;;) {
		close_attempts.fetch_add(1, std::memory_order_relaxed);
		const uint64_t revision = close_revision.load(std::memory_order_acquire);
		original_primitives->consume_published_receipts(); // Actual M receipts only, still S ledger owner.
		const bool source_prefix_settled = original_primitives->unsettled_published_count() == 0;
        if(live_resources)live_resources->request_close();
		// A true model-close receipt relinquishes its business owners exactly
		// once. Main physical finalizers can still need later service turns;
		// those turns must not re-enter an already-closed Profile/Session.
		bool closed = model.is_null() || source_model_close_completed.load(std::memory_order_acquire);
		if (!closed && model.is_valid() && source_prefix_settled) {
			if (!model->has_method(SNAME("close_session"))) set_fault("missing_model_method:close_session");
			else {
				// False is a factual retained-owner close result, not a protocol
				// failure. Generic call_model would make this retry permanently fail.
				close_model_initialized=true;
				Array args; Variant value = model->callv(SNAME("close_session"), args);
				if (value.get_type() != Variant::BOOL) set_fault("invalid_model_close_receipt");
				else closed = static_cast<bool>(value);
			}
		}
		if(closed)source_model_close_completed.store(true,std::memory_order_release);
        if(close_model_initialized)service_original_close_process_frames();
		// Never destroy accepted deferred calls merely because model close returned true.
		const bool business_closed = close_progress->accepted_groups.load(std::memory_order_acquire)==0 && closed && source_prefix_settled && original_primitives->unsettled_published_count()==0 && !original_primitives->in_flight() && !original_deferred_queue->has_messages() && (!live_resources || live_resources->can_close()) && live_resource_vault_closed.load(std::memory_order_acquire) && live_feature_closed.load(std::memory_order_acquire) && (!source_admission_scopes || source_admission_scopes->quiescent()) && (!caster_event_replies || caster_event_replies->can_close()) && (!map_loading_state || map_loading_state->provenance.can_close());
        if(business_closed&&close_process_producer_bound.load(std::memory_order_acquire))close_process_frames->request_stop();
        if(business_closed&&(!close_process_producer_bound.load(std::memory_order_acquire)||close_process_frames->can_close()))break;
		// A false close is a live owner, with all model, timer, physics and
		// accepted obligations retained. No automatic retry, teardown or NULL.
		close_failed.store(true, std::memory_order_release);
		std::unique_lock<std::mutex> lock(mailbox_mutex);
        const auto progressed=[this,revision]{return close_revision.load(std::memory_order_acquire)!=revision;};
        if(close_progress->accepted_groups.load(std::memory_order_acquire)>0){
            // Only the known accepted native-group completion/reclaim blocker.
            // Completion notification can race a try-lock while pool releases
            // its mutex. One coalesced real-time recheck avoids a lost release;
            // this never generates P, timers, budgets, inputs or physics work.
            worker_close_rechecks.fetch_add(1,std::memory_order_relaxed);
            wake.wait_for(lock,std::chrono::milliseconds(1),progressed);
        }else wake.wait(lock,progressed);
	}
	close_failed.store(false, std::memory_order_release);
	for (auto &entry : timer_objects) { Ledger::Timer timer; entry.second->detach(timers->read(entry.first, timer) ? timer.time_left : 0); }
	timer_objects.clear();
	model.unref(); // Actual Script/model destruction stays inside S/TLS.
	if (physics && claimed && !physics->release_external_owner()) {
		set_fault("physics_owner_shutdown_failed");
		// Do not advertise quiescence or let Main drop a still-owned backend.
		std::unique_lock<std::mutex> lock(mailbox_mutex);
		wake.wait(lock, [] { return false; });
	}
	CRASH_COND_MSG(!original_primitives->mark_quiescent(), "Accepted primitive obligations remain at shutdown.");
	active_clock = nullptr;
	MessageQueue::set_thread_singleton_override(nullptr);
	original_deferred_queue = nullptr;
	owner.store(Thread::UNASSIGNED_ID, std::memory_order_release);
	running.store(false, std::memory_order_release);
	close_quiescent.store(true, std::memory_order_release); shutdown_wake.notify_one();
}
bool HardCoreSimulationHost::submit_input(const Dictionary &p_packet) {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || !started, false);
	std::vector<uint8_t> bytes;
	ERR_FAIL_COND_V(!encode_plain(p_packet, bytes), false);
	{
		std::lock_guard<std::mutex> lock(mailbox_mutex);
		if (close_requested.load(std::memory_order_acquire) || !running.load(std::memory_order_acquire) || inputs.size() >= input_capacity) return false;
		inputs.push_back(std::move(bytes));
	}
	wake.notify_one();
	return true;
}
Dictionary HardCoreSimulationHost::acquire_presentation(int64_t p_min_tick, int64_t p_event_capacity) {
	ERR_FAIL_COND_V(!Thread::is_main_thread() || !bridge || p_min_tick < 0 || p_event_capacity < 0, Dictionary());
	auto lease = bridge->acquire_frame(static_cast<uint64_t>(p_min_tick));
	if (!lease.valid()) return {};
	auto event_lease = bridge->drain_events(lease.snapshot->last_effect_ordinal, static_cast<std::size_t>(p_event_capacity));
	Dictionary result;
	if (event_lease.valid()) {
		Variant frame;
		if (decode_plain(lease.snapshot->bytes, frame)) {
			Array events;
			for (const auto &event : event_lease.events) {
				Variant decoded;
				if (!decode_plain(event.bytes, decoded)) { bridge->release_frame(lease); ERR_FAIL_V_MSG(Dictionary(), "Invalid internal presentation event."); }
				Dictionary envelope; envelope["ordinal"] = static_cast<int64_t>(event.ordinal); envelope["tick"] = static_cast<int64_t>(event.tick); envelope["value"] = decoded; events.push_back(envelope);
			}
			result["frame"] = frame; result["events"] = events;
			result["tick"] = static_cast<int64_t>(lease.snapshot->tick); result["through_ordinal"] = static_cast<int64_t>(lease.snapshot->last_effect_ordinal);
		}
	}
	bridge->release_frame(lease);
	return result;
}
bool HardCoreSimulationHost::ack_events(int64_t p_through_ordinal) { ERR_FAIL_COND_V(!Thread::is_main_thread() || !bridge || p_through_ordinal < 0, false); return bridge->ack_events(static_cast<uint64_t>(p_through_ordinal)); }
Dictionary HardCoreSimulationHost::status() const {
	Dictionary result;
	result["main_channels_unbound_after_close"] = main_channels_unbound_after_close.load(std::memory_order_acquire);
    {std::lock_guard<std::mutex> lock(mailbox_mutex);result["original_terminal_gameplay_random_restored"]=terminal_gameplay_random_restored;}
	result["started"] = started; result["main_channels_prepared"] = main_channels_prepared; result["main_channels_aborted"] = main_channels_aborted; result["physics_handoff_prepared"] = physics_handoff_prepared;
	result["running"] = running.load(std::memory_order_acquire); result["owner_thread"] = static_cast<int64_t>(owner.load(std::memory_order_acquire));
	result["serviced_epoch"] = static_cast<int64_t>(serviced_epoch.load(std::memory_order_acquire)); result["pending_epochs"] = static_cast<int64_t>(pending_epochs.load(std::memory_order_acquire));
	result["late_starts"] = static_cast<int64_t>(late_starts.load(std::memory_order_relaxed)); result["deadline_misses"] = static_cast<int64_t>(deadline_misses.load(std::memory_order_relaxed));
	result["clock_overruns"] = static_cast<int64_t>(clock_overruns.load(std::memory_order_relaxed));
	if(caster_event_replies)result["caster_reply_obligations_quiescent"]=caster_event_replies->can_close();
	result["close_requested"] = close_requested.load(std::memory_order_acquire); result["close_quiescent"] = close_quiescent.load(std::memory_order_acquire); result["join_complete"] = join_complete.load(std::memory_order_acquire); result["close_failed"] = close_failed.load(std::memory_order_acquire);
	result["source_model_close_completed"] = source_model_close_completed.load(std::memory_order_acquire);
	result["live_resource_vault_closed"] = live_resource_vault_closed.load(std::memory_order_acquire);
	result["live_feature_closed"] = live_feature_closed.load(std::memory_order_acquire);
	result["map_owner_closed"] = !map_loading_state || map_loading_state->provenance.can_close();
	result["source_admission_scopes_quiescent"] = !source_admission_scopes || source_admission_scopes->quiescent();
	if(live_resources)result["accepted_live_resource_obligations"]=static_cast<int64_t>(live_resources->accepted_count());
    result["accepted_worker_group_obligations"]=static_cast<int64_t>(close_progress->accepted_groups.load(std::memory_order_acquire));
    result["worker_completion_release_rechecks"]=static_cast<int64_t>(worker_close_rechecks.load(std::memory_order_relaxed));
	result["close_attempts"] = static_cast<int64_t>(close_attempts.load(std::memory_order_relaxed)); result["original_deadline_failures"] = static_cast<int64_t>(original_deadline_failures.load(std::memory_order_relaxed));
	if (original_primitives) { result["unsettled_original_published_prefixes"] = static_cast<int64_t>(original_primitives->unsettled_published_count()); result["original_operation_sequence"] = static_cast<int64_t>(original_primitives->completed_sequence()); result["original_primitive_in_flight"] = original_primitives->in_flight(); result["original_main_applied_prefix"] = static_cast<int64_t>(original_primitives->applied_prefix()); }
	std::lock_guard<std::mutex> lock(mailbox_mutex);
	result["input_queue_size"] = static_cast<int64_t>(inputs.size()); result["fault"] = fault_reason;
	result["original_main_source_fault"] = original_main_source_fault_receipt;
	return result;
}
bool HardCoreSimulationHost::bind_original_main_source_fault_owner(const Ref<RefCounted> &p_owner, const String &p_source_sha256) {
	if (!Thread::is_main_thread() || started || p_owner.is_null() || original_main_source_fault_owner_id.is_valid()) return false;
	Ref<Script> script = p_owner->get_script();
	if (script.is_null() || script->get_path() != "res://scripts/gameplay/source/main_source_failure.gd" || p_source_sha256.length() != 64 || script->get_source_code().sha256_text() != p_source_sha256 || !p_owner->has_method(SNAME("reject_original_main_profile_writer"))) return false;
	original_main_source_fault_owner_id = p_owner->get_instance_id();
	original_main_source_fault_script = script;
	original_main_source_fault_source = script->get_source_code();
	return true;
}
bool HardCoreSimulationHost::report_original_main_source_fault(const Ref<RefCounted> &p_owner, const Dictionary &p_fact) {
	if (!Thread::is_main_thread() || p_owner.is_null() || p_owner->get_instance_id() != original_main_source_fault_owner_id) return false;
	Ref<Script> script = p_owner->get_script();
	if (script != original_main_source_fault_script || script.is_null() || script->get_source_code() != original_main_source_fault_source || !p_fact.has("method") || p_fact["method"].get_type() != Variant::STRING || String(p_fact["method"]).is_empty()) return false;
	HardCoreContentValueGraph graph;
	Dictionary captured = graph.capture(p_fact, true, false);
	if (!bool(captured.get("success", false))) return false;
	Dictionary receipt;
	receipt["contract_id"] = "hardcore.main.source_fault.v1";
	receipt["owner_runtime_id"] = static_cast<int64_t>(p_owner->get_instance_id());
	receipt["accepted_usec"] = static_cast<int64_t>(now_usec());
	receipt["fact"] = captured["value"];
	receipt.make_read_only();
	{
		std::lock_guard<std::mutex> lock(mailbox_mutex);
		if (original_main_source_fault_receipt.is_empty()) original_main_source_fault_receipt = receipt;
		if (fault_reason.is_empty()) fault_reason = "original_main_source_fault:" + String(p_fact["method"]);
		session_faulted.store(true, std::memory_order_release);
	}
	// Retain model, writes, pins and accepted continuations for the genuine
	// closing protocol. This neither joins Main nor manufactures quiescence.
	request_close();
	return true;
}
void HardCoreSimulationHost::request_close() {
	CRASH_COND_MSG(!Thread::is_main_thread(), "Host close requested outside Main lifecycle.");
	close_requested.store(true, std::memory_order_release);
	close_revision.fetch_add(1, std::memory_order_release);
	if (original_primitives) original_primitives->request_close();
    if (live_resources) live_resources->request_close();
	wake.notify_all();
}
bool HardCoreSimulationHost::close_and_join() {
	ERR_FAIL_COND_V(!Thread::is_main_thread(), false);
	if (!started) return !main_channels_prepared || main_channels_aborted;
	if (!close_requested.load(std::memory_order_acquire)) request_close();
	// Main never joins S while it is parked or while model close failed. The
	// separate reaper already joined S and its ScriptServer TLS before this gate.
	if (!close_quiescent.load(std::memory_order_acquire) || !join_complete.load(std::memory_order_acquire) || (original_primitives && !original_primitives->can_join())) return false;
	Ref<HardCoreSimulationHost> keep_alive(this);
	if (join_reaper.joinable()) join_reaper.join(); // S is already fully joined.
	lifetime_pin.unref();
	std::lock_guard<std::mutex> lock(mailbox_mutex);
	return !running.load(std::memory_order_acquire) && fault_reason.is_empty();
}
Ref<HardCoreSimulationTimer> HardCoreSimulationHost::create_timer(double p_delay, bool p_process_always, bool p_process_in_physics, bool p_ignore_time_scale) {
	CRASH_COND_MSG(!is_owner() || !timers, "Simulation timer creation outside S.");
	Ledger::Flags flags{p_process_always, p_process_in_physics ? Ledger::Domain::H : Ledger::Domain::P, p_ignore_time_scale};
	auto result = timers->create(p_delay, flags, 0);
	if (result.status != Ledger::CreateStatus::ACCEPTED) { set_fault("simulation_timer_admission_failed"); return {}; }
	Ref<HardCoreSimulationTimer> timer; timer.instantiate();
	timer->host = this; timer->owner = Thread::get_caller_id(); timer->timer_id = result.id;
	timer->detached_time_left = p_delay;
	timer_objects.emplace(result.id, timer);
	return timer;
}
double HardCoreSimulationHost::read_timer(uint64_t p_id, double p_fallback) const { Ledger::Timer timer; return timers && timers->read(p_id, timer) ? timer.time_left : p_fallback; }
void HardCoreSimulationHost::write_timer(uint64_t p_id, double p_seconds) { if (!timers || !timers->set_time_left(p_id, p_seconds)) set_fault("simulation_timer_write_failed"); }
void HardCoreSimulationHost::on_timeout(const Ledger::Timer &p_timer) {
	auto found = timer_objects.find(p_timer.id);
	if (found == timer_objects.end()) { set_fault("simulation_timer_identity_missing"); return; }
	Ref<HardCoreSimulationTimer> timer = found->second;
	timer->emit_signal(SNAME("timeout")); // Synchronous, before original-list erase.
	Ledger::Timer after;
	timer->detach(timers->read(p_timer.id, after) ? after.time_left : p_timer.time_left);
	timer_objects.erase(p_timer.id); // Callback may have appended and rehashed.
}
bool HardCoreSimulationHost::publish_snapshot(const Dictionary &p_frame, const Array &p_events) {
	CRASH_COND_MSG(!is_owner() || !bridge || current_epoch == 0, "Presentation publication outside S epoch.");
	Bridge::Snapshot snapshot; snapshot.tick = current_epoch;
	if (!encode_plain(p_frame, snapshot.bytes)) { set_fault("non_plain_presentation_snapshot"); return false; }
	std::vector<Bridge::Event> events;
	for (int i = 0; i < p_events.size(); ++i) {
		Bridge::Event event{next_effect_ordinal + static_cast<uint64_t>(i), current_epoch, {}};
		if (!encode_plain(p_events[i], event.bytes)) { set_fault("non_plain_presentation_event"); return false; }
		events.push_back(std::move(event));
	}
	snapshot.last_effect_ordinal = next_effect_ordinal - 1 + events.size();
	if (!bridge->publish(snapshot, events)) return false; // Caller retains unaccepted effects.
	next_effect_ordinal += events.size();
	return true;
}
void HardCoreSimulationHost::set_simulation_paused(bool p_paused) {
	CRASH_COND_MSG(!is_owner(), "Pause mutation outside S input admission.");
	paused.store(p_paused, std::memory_order_release);
	if (physics) physics->set_active(!p_paused);
}
void HardCoreSimulationHost::set_simulation_time_scale(double p_scale) { CRASH_COND_MSG(!is_owner() || !std::isfinite(p_scale) || p_scale < 0, "Invalid S time-scale mutation."); time_scale.store(p_scale, std::memory_order_release); }
HardCoreSimulationHost::~HardCoreSimulationHost() {
	CRASH_COND_MSG(is_owner(), "Simulation host cannot destroy its own running thread.");
	// lifetime_pin prevents ordinary last-external-ref destruction before this
	// state. A raw-delete/lifetime violation is rejected instead of blocking
	// Main and freeing the still-parked original stack or physical owner.
	CRASH_COND_MSG(started && (!close_quiescent.load(std::memory_order_acquire) || !join_complete.load(std::memory_order_acquire)), "Undrained Host cannot be destructed.");
	if (join_reaper.joinable()) join_reaper.join(); // Never joins S here.
}

bool HardCoreSimulationHost::source_deferred_queue_configured() const {
	return is_owner() && original_deferred_queue && MessageQueue::get_singleton() == original_deferred_queue;
}
bool HardCoreSimulationHost::has_original_deferred_calls() const {
	CRASH_COND_MSG(!source_deferred_queue_configured(), "Source queue observed outside its original owner.");
	return original_deferred_queue->has_messages();
}
bool HardCoreSimulationHost::flush_source_deferred(const StringName &domain, const StringName &boundary) {
	if (!source_deferred_queue_configured() || original_deferred_queue->is_flushing()) return false;
	uint8_t bit = 0;
	if (domain == SNAME("H") && boundary == SNAME("H_GROUP:end_group") && current_phase == Clock::Phase::H_GROUP) bit = 1;
	if (domain == SNAME("P") && !closing_session && current_phase == Clock::Phase::P_GROUP) {
		if (boundary == SNAME("P_GROUP:after_process_frame")) bit = 1;
		if (boundary == SNAME("P_GROUP:end_group") && (source_deferred_flush_mask & 1)) bit = 2;
	}
    if(closing_session&&domain==SNAME("P")){
        if(current_phase_name==SNAME("P_CLOSE_SIGNAL")&&original_source_boundary==SNAME("PROCESS_SIGNAL")&&boundary==SNAME("P_GROUP:after_process_frame"))bit=1;
        if(current_phase_name==SNAME("P_CLOSE_SERVICE")&&original_source_boundary==SNAME("NODE_PROCESS_SERVICE")&&boundary==SNAME("P_GROUP:end_group")&&(source_deferred_flush_mask&1))bit=2;
    }
	if (!bit || (source_deferred_flush_mask & bit)) return false;
	source_deferred_flush_mask |= bit;
	// Pinned CallQueue::flush owns actual FIFO, append-during-flush, missing
	// receiver, callable binding and original reentrancy semantics.
	const Error result = original_deferred_queue->flush();
	if (result != OK) { set_fault("original_source_deferred_flush_failed"); return false; }
	return true;
}
