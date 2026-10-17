#pragma once

#include "presentation_bridge.h"
#include "simulation_clock.h"
#include "original_primitive_mailbox.h"
#include "async_live_resource_mailbox.h"
#include "source_admission_scope_ledger.h"
#include "map_loading_host_state.h"
#include "source_event_reply_mailbox.h"
#include "close_process_mailbox.h"
#include "close_progress_signal.h"
#include "terminal_owner_unbind_guard.h"
#include "core/object/ref_counted.h"
#include "core/object/script_language.h"
#include "core/os/thread.h"

#include <atomic>
#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <unordered_map>

class CallQueue;
class PhysicsServer2DWrapMT;
class HardCoreSimulationHost;

class HardCoreSimulationTimer : public RefCounted {
	GDCLASS(HardCoreSimulationTimer, RefCounted);
	friend class HardCoreSimulationHost;
	HardCoreSimulationHost *host = nullptr;
	Thread::ID owner = Thread::UNASSIGNED_ID;
	uint64_t timer_id = 0;
	double detached_time_left = 0;
	void detach(double p_time_left);
protected:
	static void _bind_methods();
public:
	double get_time_left() const;
	void set_time_left(double p_seconds);
};

// Display Main owns only the host's lifetime and transport API. The model is
// constructed, invoked and destroyed inside one Godot Thread, which installs
// ScriptServer TLS through the pinned core/os/thread.cpp wrapper.
class HardCoreSimulationHost : public RefCounted, private hardcore::simulation::SimulationClock::Hooks {
	GDCLASS(HardCoreSimulationHost, RefCounted);
	friend class HardCoreSimulationTimer;
	using Clock = hardcore::simulation::SimulationClock;
	using Ledger = hardcore::simulation::TimerLedger;
	using Bridge = hardcore::simulation::PresentationBridge;
	Thread thread;
	using OriginalMailbox = hardcore::simulation::OriginalPrimitiveMailbox;
	std::unique_ptr<OriginalMailbox> original_primitives;
    std::unique_ptr<hardcore::simulation::AsyncLiveResourceMailbox> live_resources;
    bool gameplay_random_captured=false;
    std::unique_ptr<hardcore::simulation::SourceAdmissionScopeLedger> source_admission_scopes;
    Ref<RefCounted> main_source_admission; // Main-only, never exposed to S.
    String main_source_admission_sha;
    std::size_t source_scope_capacity=0;
    uint64_t current_source_scope=0;
    std::unique_ptr<hardcore::simulation::SourceEventReplyMailbox> caster_event_replies;
    std::unique_ptr<hardcore::simulation::MapLoadingHostState> map_loading_state;
    Ref<RefCounted> main_map_loading_producer,main_map_event_executor;
    String main_map_loading_producer_sha,main_map_event_executor_sha;
    Ref<RefCounted> main_caster_reply_producer;String main_caster_reply_sha;std::atomic<int64_t> main_caster_reply_id{0};
    struct IssuedClaimBinding {uint64_t object=0,script=0;uintptr_t instance=0;Thread::ID thread=Thread::UNASSIGNED_ID;String source,sha;};
    Ref<RefCounted> issued_main_feature,issued_main_origin; // Main-only pins.
    IssuedClaimBinding issued_feature_binding,issued_origin_binding,issued_source_binding,issued_session_binding;
    uint64_t issued_source_budget=0,issued_source_session=0;
    std::unordered_map<uint64_t,IssuedClaimBinding> issued_helper_bindings; // Main-only origin Script provenance.
    std::unordered_map<uint64_t,IssuedClaimBinding> issued_warm_bindings; // S-only actual Warm commit owners.
    hardcore::simulation::TerminalOwnerUnbindGuard terminal_owner_unbind_guard;
    std::array<IssuedClaimBinding,9> terminal_owner_unbound_bindings;
    Dictionary terminal_owner_unbound_receipt;
	Dictionary terminal_owner_unbound_stop_receipt;
    std::atomic<bool> main_channels_unbound_after_close{false};
    bool issued_binding_valid(const IssuedClaimBinding&)const;
    bool issued_prepare_original_execution(const Dictionary&caller,Dictionary&execution);
    bool issued_fold_original_physical_reply(const Dictionary&execution,const Dictionary&reply,const hardcore::simulation::SourceEventReplyMailbox::TransferRead* live_record=nullptr);
    hardcore::simulation::SourceEventReplyMailbox::Status capture_issued_live_context(const Dictionary&,Dictionary&);
    hardcore::simulation::SourceEventReplyMailbox::Status prepare_issued_live_execution(const hardcore::simulation::AsyncLiveResourceMailbox::Request&,Dictionary&);
    void issued_observe_main_io_delivery();
    Dictionary issued_claim_result(const hardcore::simulation::SourceEventReplyMailbox::TransferRead&)const;
    Ref<RefCounted> live_feature_main; // Actual Main physical Feature owner, never resolved by S.
    ObjectID live_feature_script_id;uintptr_t live_feature_instance=0;String live_feature_source;
    std::atomic<bool> live_feature_bound{false},live_feature_closed{true};
    Dictionary live_feature_execution,live_feature_actual_reply,live_feature_executed_body;bool live_feature_execution_claimed=false,live_feature_issued_prepared=false,live_feature_issued_folded=false;int64_t live_feature_cpu_usec=0;uint64_t live_feature_execution_process_frame=0;
    std::unordered_map<uint64_t,hardcore::simulation::AsyncLiveResourceMailbox::Bytes> live_feature_transfers; // Main-only ACK metadata, no resource scheduling.
    bool live_feature_main_valid()const;
    bool live_feature_reply_actual(const Dictionary&)const;
    void drain_live_feature_transfer_receipts();
    std::unique_ptr<hardcore::simulation::CloseProcessMailbox> close_process_frames;
    Ref<RefCounted> main_close_process_producer;String main_close_process_producer_sha;
    int64_t close_process_generation=0,close_process_listener_id=0;
    Dictionary close_process_stop_receipt;
    std::atomic<bool> close_process_producer_bound{false};
    bool service_original_close_process_frames();
	uint64_t bridge_generation = 0;
	std::atomic<uint64_t> source_process_frame{0}, source_physics_frame{0};
	std::atomic<uint64_t> original_deadline_failures{0};
    std::shared_ptr<hardcore::simulation::CloseProgressSignal> close_progress=std::make_shared<hardcore::simulation::CloseProgressSignal>();
    std::atomic<uint64_t>&close_revision=close_progress->revision;
    std::atomic<uint64_t> close_attempts{0},worker_close_rechecks{0};
	std::atomic<bool> close_quiescent{false}, join_complete{false}, close_failed{false};
	Ref<HardCoreSimulationHost> lifetime_pin; // Released only by Main after async join.
	std::thread join_reaper; // Joins only; never calls/unrefs any Script or model.
	std::condition_variable shutdown_wake;
	Clock *active_clock = nullptr; // S-only pointer to the original stack clock.
	Clock::Phase current_phase = Clock::Phase::U_BEGIN;
	StringName current_phase_name;
	Dictionary original_source_frame, primitive_world, original_main_prefix;
	uint64_t original_site_epoch = 0;
	CallQueue *original_deferred_queue = nullptr; // S-only pointer to its actual original Godot queue.
	uint32_t source_deferred_max_pages = 0; // Captured original Main project setting.
	uint8_t source_deferred_flush_mask = 0;
	bool closing_session = false;
	StringName original_source_boundary;
	bool validate_original_site(const Dictionary &request, bool resource);
	bool validate_original_source_site(const Dictionary &site) const;
	Dictionary exchange_primitive(const Dictionary &request, bool resource);

    Ref<RefCounted> live_resource_vault; // Main-only physical owner pin; S reads only the atomic close fence.
    String live_resource_vault_sha;
    std::atomic<bool> live_resource_vault_closed{true};
	std::atomic<bool> source_model_close_completed{false};
	bool main_vault_close_active = false; // Main-only, valid only inside the real finalizer call.
	Dictionary main_vault_close_ticket;
	std::atomic<bool> running{false};
	std::atomic<bool> close_requested{false};
	std::atomic<Thread::ID> owner{Thread::UNASSIGNED_ID};
	std::atomic<uint64_t> serviced_epoch{0};
	std::atomic<uint64_t> pending_epochs{0};
	std::atomic<uint64_t> late_starts{0};
	std::atomic<uint64_t> deadline_misses{0};
	std::atomic<uint64_t> clock_overruns{0};
	mutable std::mutex mailbox_mutex;
	std::condition_variable&wake=close_progress->wake;
	std::deque<std::vector<uint8_t>> inputs;
	String fault_reason;
    Dictionary terminal_gameplay_random_handoff,terminal_gameplay_random_restore_receipt; // Plain values only, protected by mailbox_mutex.
    bool terminal_gameplay_random_event_registered=false,terminal_gameplay_random_restored=false;
    bool check_original_terminal_gameplay_random_prefix(const Dictionary &,bool);
	ObjectID original_main_source_fault_owner_id;
	Ref<Script> original_main_source_fault_script;
	String original_main_source_fault_source;
	Dictionary original_main_source_fault_receipt; // Immutable; mailbox_mutex protects publication.
	Ref<Script> factory;
	Dictionary bootstrap; // Private decoded copy consumed only by S.
	Ref<RefCounted> model; // S-only; never exposed to display Main.
	std::unique_ptr<Ledger> timers;
	std::unique_ptr<Bridge> bridge;
	std::unordered_map<uint64_t, Ref<HardCoreSimulationTimer>> timer_objects;
	PhysicsServer2DWrapMT *physics = nullptr;
	uint32_t physics_hz = 0;
	uint32_t max_epochs_per_turn = 0;
	std::size_t input_capacity = 0;
	uint64_t current_epoch = 0;
	uint64_t next_effect_ordinal = 1;
	std::atomic<double> time_scale{1};
	std::atomic<bool> paused{false};
	std::atomic<bool> session_faulted{false};
	bool started = false;
	bool main_channels_prepared = false, main_channels_aborted = false, physics_handoff_prepared = false;
	Dictionary prepared_main_channel_config;
	bool prepare_main_channels_impl(const Dictionary &config);
	bool actual_production_main_bindings_ready(const Dictionary &boot) const;
	bool fixture_mode = false;

	static void thread_entry(void *p_userdata);
	void thread_run();
	bool start_impl(const Ref<Script> &p_factory, const Dictionary &p_bootstrap, const Dictionary &p_config, bool p_fixture);
	bool call_model(const StringName &p_method, const Array &p_args);
	void set_fault(const String &p_reason);
	void drain_inputs(const String &p_domain);
	bool is_owner() const;
	uint64_t now_usec() const override;
	double sample_time_scale() const override;
	bool is_paused() const override;
	void on_timeout(const Ledger::Timer &p_timer) override;
	void on_phase(Clock::Phase p_phase, const Clock::ClockFrame &p_frame) override;
	double read_timer(uint64_t p_id, double p_fallback) const;
	void write_timer(uint64_t p_id, double p_seconds);
protected:
	static void _bind_methods();
public:

    std::shared_ptr<hardcore::simulation::CloseProgressSignal> original_worker_close_progress()const{return is_owner()?close_progress:nullptr;}
	bool source_deferred_queue_configured() const;
	bool has_original_deferred_calls() const;
	bool flush_source_deferred(const StringName &domain, const StringName &boundary);

    bool bind_original_source_admission_producer(const Ref<RefCounted> &producer,const String &actual_source_sha256);
    Dictionary publish_original_source_admission_scope(const Dictionary &scope);
    Dictionary claim_original_source_admission_scope(int64_t scope_id);
    Dictionary poll_original_source_admission_scope(int64_t scope_id);
    bool finish_original_source_admission_scope(int64_t scope_id);

    bool bind_original_map_loading_producer(const Ref<RefCounted>&producer,const String&source_sha256,const Ref<RefCounted>&executor,const String&executor_sha256);
    Dictionary publish_original_map_loading_scope(const Dictionary &scope);
    bool verify_original_map_loading_scope(const Dictionary &scope,const Dictionary &descriptor,const String &transition_id,int64_t coordinator_generation,int64_t map_id);
    Dictionary commit_original_map_arrival(const Ref<RefCounted> &core, const Dictionary &transaction);
    bool verify_committed_original_map_arrival(const Dictionary &transaction) const;
    Dictionary publish_original_map_loading_publication(const Dictionary &scope,const Dictionary &publication,const Dictionary &receipt);
    bool verify_original_map_loading_publication(const Dictionary &scope,const Dictionary &descriptor,const Dictionary &publication,const Dictionary &receipt);
    Dictionary reserve_original_map_loading_event(const Dictionary &identity,const Dictionary &event);
    Dictionary accept_original_map_loading_event(const Dictionary &identity,const Dictionary &event,const Dictionary &prefix);
    Dictionary cancel_unaccepted_original_map_loading_event(const Dictionary &identity);
    Dictionary claim_original_map_loading_event(const Dictionary &identity,const Dictionary &event);
    Dictionary submit_original_map_loading_reply(const Dictionary &identity,const Dictionary &reply);
    Dictionary poll_original_map_loading_event(const Dictionary &identity);
    Dictionary settle_original_map_loading_event_status(const Dictionary &identity,const Dictionary &settlement);
    bool retire_original_map_loading_event(const Dictionary &identity,const Dictionary &reply);
    Dictionary certify_original_map_loading_owner_closed(const Dictionary &receipt);

    bool bind_main_caster_reply_producer(const Ref<RefCounted>&producer,const String&source_sha256);
    bool bind_original_main_feature_claim_producer(const Ref<RefCounted>&producer,const String&actual_source_sha256);
    bool bind_original_main_warm_claim_origin_producer(const Ref<RefCounted>&producer,const String&actual_source_sha256);
    bool bind_original_source_feature_claim_owner(const Ref<RefCounted>&coordinator,const String&actual_source_sha256);
    Dictionary offer_claim_transfer(const Dictionary&identity,const Dictionary&evidence);
    Dictionary accept_claim_transfer(const Dictionary&identity);
    Dictionary confirm_origin_released(const Dictionary&identity);
    bool bind_live_original_feature_main_executor(const Ref<RefCounted>&producer,const String&actual_source_sha256);
    Dictionary execute_pending_live_original_feature(const Dictionary&actual_packet);
    bool validate_live_original_feature_execution(const Dictionary&actual_execution_wire);
    bool certify_live_original_feature_main_closed();
    Dictionary reserve_original_caster_event(const Dictionary&identity,const Dictionary&event);
    Dictionary accept_original_caster_event(const Dictionary&identity,const Dictionary&event,const Dictionary&prefix);
    bool cancel_unaccepted_original_caster_event(const Dictionary&identity);
    Dictionary acquire_original_caster_prefix();
    Dictionary inspect_next_original_published_prefix();
    Dictionary claim_original_caster_event(const Dictionary&identity,const Dictionary&event);
    Dictionary submit_original_caster_event_reply(const Dictionary&identity,const Dictionary&reply);
    Dictionary poll_original_caster_event_reply(const Dictionary&identity);
    Dictionary consume_original_caster_event_reply(const Dictionary&identity);
    Dictionary ack_original_caster_node_retired(const Dictionary&identity);
    Dictionary retire_original_caster_event_reply(const Dictionary&identity);
    bool bind_original_close_process_producer(const Ref<RefCounted>&producer,const String&actual_source_sha256);
    Dictionary enqueue_original_close_process_frame(const Dictionary&publication);
    Dictionary acquire_original_close_process_frame_receipt();
    bool ack_original_close_process_frame_receipt(const Dictionary&receipt);
    int64_t original_close_process_signal_highwater() const;
    bool original_close_process_producer_drained() const;
    bool request_original_close_process_producer_stop();
    Dictionary acquire_original_close_process_producer_stop_request();
    bool confirm_original_close_process_producer_stopped(const Dictionary&receipt);
    bool verify_original_close_process_producer_terminal_receipt(const Dictionary&receipt);
    bool current_host_paused() const;
    double current_host_time_scale() const;
    Dictionary capture_main_gameplay_random();
    bool is_original_operation_completed(const Dictionary &identity) const;
    Dictionary acquire_original_main_prefix(const Dictionary &prefix);
    Dictionary submit_live_original_resource(const Dictionary &request);
    Dictionary acquire_pending_live_original_resource();
    bool ack_live_original_main_prefix(const Dictionary &identity,const Dictionary &prefix);
    bool validate_live_original_resource_ticket(const Dictionary &request);
    bool submit_live_original_resource_result(const Dictionary &identity,const Dictionary &reply);
    Dictionary poll_live_original_resource(const Dictionary &identity);
    bool settle_live_original_resource(const Dictionary &settlement);
    Dictionary settle_live_original_resource_status(const Dictionary &settlement);
    bool ack_live_original_resource_retirement(const Dictionary &identity,const Array &actual_lease_obligations);
    bool bind_live_original_resource_vault(const Ref<RefCounted> &vault,const String &actual_source_sha256);
    Dictionary transfer_live_original_resource_obligations(const Dictionary &identity,const Array &actual_lease_obligations,const Dictionary &receipt);
    bool certify_live_original_resource_vault_closed(const Dictionary &actual_close_receipt);
    bool live_original_resource_transport_releasable(const Dictionary &identity) const;
    bool retire_live_original_resource(const Dictionary &identity);
    int64_t sample_main_thread_cpu_usec() const;

	int64_t owner_thread_id() const;
	Ref<HardCoreSimulationHost> resource_primitive_transport();
	Ref<HardCoreSimulationHost> world_primitive_transport();
	Dictionary capabilities() const;
	Dictionary prepare_original_main_channels(const Dictionary &config);
	Dictionary abort_prepared_original_main_channels(const Dictionary &retained_owners);
	int64_t next_original_operation_sequence() const;
	int64_t completed_original_operation_sequence() const;
	int64_t next_original_call_ordinal(const Dictionary &source_site) const;
	bool finish_original_call_site(const Dictionary &source_site);
	Dictionary current_clock_frame() const;
	bool bind_original_world_context(const Dictionary &world);
	bool stage_original_main_prefix(const Dictionary &prefix);
	bool register_published_original_main_prefix(const Dictionary &prefix);
    Dictionary try_register_published_original_main_prefix(const Dictionary&prefix);
	bool ack_published_original_main_prefix(const Dictionary &prefix, const Dictionary &ack);
	Dictionary completed_original_main_prefix_receipt();
	Dictionary ordered_main_prefix() const;
	Dictionary exchange_original_primitive(const Dictionary &request);
	Dictionary exchange_world_primitive(const Dictionary &request);
	Dictionary acquire_pending_original_primitive();
	bool ack_original_main_prefix(const Dictionary &identity, const Dictionary &ack);
	bool validate_original_primitive_ticket(const Dictionary &request, const StringName &kind);
	Dictionary finalize_original_main_resource_vault();
	bool submit_original_primitive_result(const Dictionary &identity, const Dictionary &reply);
	bool start(const Ref<Script> &p_factory, const Dictionary &p_bootstrap, const Dictionary &p_config);
#ifdef DEBUG_ENABLED
	// Exact same clock/timer/transport driver, without a physics world. This
	// cannot be used in a release package or pass a production world test.
	bool start_clock_fixture(const Ref<Script> &p_factory, const Dictionary &p_bootstrap, const Dictionary &p_config);
#endif
	bool submit_input(const Dictionary &p_packet);
	Dictionary acquire_presentation(int64_t p_min_tick, int64_t p_event_capacity);
	bool ack_events(int64_t p_through_ordinal);
	Dictionary status() const;
	bool bind_original_main_source_fault_owner(const Ref<RefCounted> &p_owner, const String &p_source_sha256);
	bool report_original_main_source_fault(const Ref<RefCounted> &p_owner, const Dictionary &p_fact);
	void request_close();
	Dictionary retire_started_original_main_channels(const Dictionary &owners);
    Dictionary capture_original_terminal_gameplay_random(Object *,const Dictionary &);
    Dictionary restore_original_terminal_gameplay_random(const Dictionary &);
	bool close_and_join(); // Nonblocking until S quiescent and async join complete.
	Ref<HardCoreSimulationTimer> create_timer(double p_delay, bool p_process_always = true, bool p_process_in_physics = false, bool p_ignore_time_scale = false);
	bool publish_snapshot(const Dictionary &p_frame, const Array &p_events);
	void set_simulation_paused(bool p_paused);
	void set_simulation_time_scale(double p_scale);
	~HardCoreSimulationHost();
};
