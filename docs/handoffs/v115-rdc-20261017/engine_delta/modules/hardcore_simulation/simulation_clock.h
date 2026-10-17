#pragma once

#include "timer_ledger.h"
#include <cstdint>
#include <vector>

namespace hardcore::simulation {

// The driver calls this only from its Godot Thread S (whose callback performs
// ScriptServer thread_enter/thread_exit). This class creates no OS thread and
// never touches Engine's shared process/physics fields or the live SceneTree.
class SimulationClock {
public:
	enum class Mode : uint8_t { FIXED_RUNTIME, TRACE_REPLAY };
	enum class Phase : uint8_t {
		U_BEGIN, H_INPUT, H_PREPARE, H_GROUP, H_AFTER_TIMERS, H_STEP,
		P_INPUT, P_GROUP, P_AFTER_TIMERS, U_END, PUBLISH, U_WAKE
	};
	struct Delta {
		double raw = 0;
		double clipped = 0;
		double scaled = 0;
		// Original Engine::_process_step, including for H ignore-scale timers.
		double unscaled_timer = 0;
	};
	struct ClockFrame {
		uint64_t epoch = 0;
		uint32_t h_ordinal = 0;
		uint64_t release_usec = 0;
		uint64_t observed_usec = 0;
		uint64_t lateness_usec = 0;
		double time_scale = 1;
		double simulation_elapsed = 0;
		Delta delta;
	};
	struct Hooks : TimerLedger::Consumer {
		virtual uint64_t now_usec() const = 0;
		virtual double sample_time_scale() const = 0;
		// Input cutoffs are obtained separately at H_INPUT and P_INPUT.
		// H_PREPARE owns prepare/sync/flush; H_STEP owns end_sync, the single
		// backend step and its original post-step boundary. Group/tail hooks
		// preserve original actor, deferred, tween, transform and delete order.
		// U hooks are non-timing transaction boundaries, never process(0).
		virtual void on_phase(Phase phase, const ClockFrame &frame) = 0;
	};
	struct Config {
		uint32_t physics_hz;
		uint32_t max_epochs_per_turn;
		uint64_t origin_usec;
		Mode mode = Mode::FIXED_RUNTIME;
	};
	enum class FaultCode : uint8_t { NONE, INVALID, REENTRANT, CLOCK_OVERRUN };
	struct FaultReceipt {
		FaultCode code = FaultCode::NONE;
		uint64_t next_epoch = 0;
		uint64_t observed_usec = 0;
		uint64_t pending_epochs = 0;
		uint64_t lateness_usec = 0;
		double threshold_seconds = 0;
	};
	struct TurnReceipt {
		uint32_t epochs_serviced = 0;
		uint64_t pending_epochs = 0;
		uint64_t next_release_usec = 0;
		uint64_t late_starts = 0;
		uint64_t deadline_misses = 0;
		bool suspended = false;
		FaultReceipt fault;
	};
	struct ReplayIteration {
		double time_scale = 1;
		std::vector<Delta> h;
		Delta p;
	};

	SimulationClock(Config config, Hooks &hooks, TimerLedger &timers);
	TurnReceipt run_turn();
	TurnReceipt replay_iteration(const ReplayIteration &trace);
	FaultReceipt service_receipts();
	// APP_SUSPEND is distinct from game pause. Rebase by the measured suspended
	// interval, preserving pre-existing debt and all timer remaining values.
	FaultReceipt suspend(uint64_t now_usec);
	FaultReceipt resume(uint64_t now_usec);
	uint64_t next_epoch() const { return next_epoch_; }
	uint64_t release_usec(uint64_t epoch) const;
	double simulation_elapsed() const { return simulation_elapsed_; }
	bool is_servicing() const { return servicing_; }

private:
	bool valid_config() const;
	bool valid_delta(const Delta &delta) const;
	bool observe(uint64_t &now);
	uint64_t pending(uint64_t now) const;
	FaultReceipt fault(FaultCode code, uint64_t now) const;
	ClockFrame frame(uint64_t epoch, uint64_t now, double scale) const;
	void h_phase(ClockFrame &frame);
	void p_phase(ClockFrame &frame);
	void control(Phase phase, const ClockFrame &frame);
	Config config_;
	Hooks &hooks_;
	TimerLedger &timers_;
	uint64_t next_epoch_ = 1;
	uint64_t last_observed_usec_ = 0;
	uint64_t suspend_usec_ = 0;
	double simulation_elapsed_ = 0;
	bool observed_ = false;
	bool servicing_ = false;
	bool suspended_ = false;
};

} // namespace hardcore::simulation
