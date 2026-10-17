#include "simulation_clock.h"
#include <cmath>
#include <limits>

namespace hardcore::simulation {

namespace {
constexpr uint64_t USEC_PER_SECOND = 1000000;
constexpr uint64_t OVERFLOW_TIME = std::numeric_limits<uint64_t>::max();
struct ServiceScope {
	bool &servicing;
	explicit ServiceScope(bool &value) : servicing(value) { servicing = true; }
	~ServiceScope() { servicing = false; }
};
}

SimulationClock::SimulationClock(Config config, Hooks &hooks, TimerLedger &timers) :
		config_(config), hooks_(hooks), timers_(timers) {}

bool SimulationClock::valid_config() const {
	return config_.physics_hz > 0 && config_.physics_hz <= USEC_PER_SECOND &&
			config_.max_epochs_per_turn > 0 &&
			(config_.mode == Mode::FIXED_RUNTIME || config_.mode == Mode::TRACE_REPLAY) &&
			release_usec(next_epoch_) != OVERFLOW_TIME;
}

bool SimulationClock::valid_delta(const Delta &d) const {
	return std::isfinite(d.raw) && std::isfinite(d.clipped) && std::isfinite(d.scaled) &&
			std::isfinite(d.unscaled_timer) && d.raw >= 0 && d.clipped >= 0 &&
			d.scaled >= 0 && d.unscaled_timer >= 0;
}

uint64_t SimulationClock::release_usec(uint64_t epoch) const {
	if (config_.physics_hz == 0 || config_.physics_hz > USEC_PER_SECOND) return OVERFLOW_TIME;
	// R_n = origin + n/F, rounded upwards only for this absolute wake-up.
	// The division remainder is kept; repeated floor(1e6/F) additions drift.
	const uint64_t whole_seconds = epoch / config_.physics_hz;
	const uint64_t remainder = epoch % config_.physics_hz;
	if (whole_seconds > OVERFLOW_TIME / USEC_PER_SECOND) return OVERFLOW_TIME;
	const uint64_t whole_usec = whole_seconds * USEC_PER_SECOND;
	const uint64_t fraction = (remainder * USEC_PER_SECOND + config_.physics_hz - 1) / config_.physics_hz;
	if (whole_usec > OVERFLOW_TIME - fraction) return OVERFLOW_TIME;
	const uint64_t offset = whole_usec + fraction;
	if (config_.origin_usec > OVERFLOW_TIME - offset) return OVERFLOW_TIME;
	return config_.origin_usec + offset;
}

bool SimulationClock::observe(uint64_t &now) {
	now = hooks_.now_usec();
	if (observed_ && now < last_observed_usec_) return false;
	observed_ = true;
	last_observed_usec_ = now;
	return true;
}

uint64_t SimulationClock::pending(uint64_t now) const {
	if (now < config_.origin_usec || config_.physics_hz == 0) return 0;
	const uint64_t elapsed = now - config_.origin_usec;
	const uint64_t seconds = elapsed / USEC_PER_SECOND;
	if (seconds > OVERFLOW_TIME / config_.physics_hz) return OVERFLOW_TIME;
	const uint64_t whole = seconds * config_.physics_hz;
	const uint64_t fraction = ((elapsed % USEC_PER_SECOND) * config_.physics_hz) / USEC_PER_SECOND;
	if (whole > OVERFLOW_TIME - fraction) return OVERFLOW_TIME;
	const uint64_t released = whole + fraction;
	return released >= next_epoch_ ? released - next_epoch_ + 1 : 0;
}

SimulationClock::FaultReceipt SimulationClock::fault(FaultCode code, uint64_t now) const {
	FaultReceipt result;
	result.code = code;
	result.next_epoch = next_epoch_;
	result.observed_usec = now;
	result.pending_epochs = pending(suspended_ ? suspend_usec_ : now);
	const uint64_t release = release_usec(next_epoch_);
	result.lateness_usec = now > release ? now - release : 0;
	result.threshold_seconds = config_.physics_hz == 0 ? 0 :
			static_cast<double>(config_.max_epochs_per_turn) / config_.physics_hz;
	return result;
}

SimulationClock::ClockFrame SimulationClock::frame(uint64_t epoch, uint64_t now, double scale) const {
	ClockFrame f;
	f.epoch = epoch;
	f.release_usec = config_.mode == Mode::TRACE_REPLAY ? now : release_usec(epoch);
	f.observed_usec = now;
	f.lateness_usec = now > f.release_usec ? now - f.release_usec : 0;
	f.time_scale = scale;
	f.simulation_elapsed = simulation_elapsed_;
	return f;
}

void SimulationClock::control(Phase phase, const ClockFrame &f) {
	hooks_.on_phase(phase, f);
}

void SimulationClock::h_phase(ClockFrame &f) {
	hooks_.on_phase(Phase::H_INPUT, f);
	hooks_.on_phase(Phase::H_PREPARE, f);
	hooks_.on_phase(Phase::H_GROUP, f);
	timers_.sweep(TimerLedger::Domain::H, f.delta.scaled, f.delta.unscaled_timer, hooks_);
	hooks_.on_phase(Phase::H_AFTER_TIMERS, f);
	hooks_.on_phase(Phase::H_STEP, f);
	// This is the single simulation-time consumer. P and U never add time.
	// Pause eligibility is read here, rather than frozen at epoch entrance.
	if (!hooks_.is_paused()) simulation_elapsed_ += f.delta.scaled;
	f.simulation_elapsed = simulation_elapsed_;
}

void SimulationClock::p_phase(ClockFrame &f) {
	hooks_.on_phase(Phase::P_INPUT, f);
	hooks_.on_phase(Phase::P_GROUP, f);
	timers_.sweep(TimerLedger::Domain::P, f.delta.scaled, f.delta.unscaled_timer, hooks_);
	hooks_.on_phase(Phase::P_AFTER_TIMERS, f);
}

SimulationClock::TurnReceipt SimulationClock::run_turn() {
	TurnReceipt result;
	if (servicing_ || timers_.is_sweeping()) {
		result.fault = fault(FaultCode::REENTRANT, last_observed_usec_); return result;
	}
	if (!valid_config() || config_.mode != Mode::FIXED_RUNTIME) {
		result.fault = fault(FaultCode::INVALID, last_observed_usec_); return result;
	}
	ServiceScope scope(servicing_);
	uint64_t now;
	if (!observe(now)) { result.fault = fault(FaultCode::INVALID, now); return result; }
	result.suspended = suspended_;
	if (suspended_) {
		control(Phase::U_WAKE, frame(next_epoch_, now, 0));
		result.pending_epochs = pending(suspend_usec_);
		result.next_release_usec = release_usec(next_epoch_);
		return result;
	}

	while (result.epochs_serviced < config_.max_epochs_per_turn) {
		const uint64_t debt = pending(now);
		if (debt == 0) {
			if (result.epochs_serviced == 0) control(Phase::U_WAKE, frame(next_epoch_, now, 0));
			break;
		}
		if (debt > config_.max_epochs_per_turn && result.fault.code == FaultCode::NONE) {
			// Report a missed service envelope, but keep bounded forward
			// progress. Freezing here would make this debt permanent even after
			// the workload becomes cheap. No epoch, timer or origin is dropped.
			result.fault = fault(FaultCode::CLOCK_OVERRUN, now);
		}
		const double scale = hooks_.sample_time_scale();
		const double h = 1.0 / config_.physics_hz;
		if (!std::isfinite(scale) || scale < 0 || !std::isfinite(h * scale)) {
			result.fault = fault(FaultCode::INVALID, now); break;
		}
		ClockFrame f = frame(next_epoch_, now, scale);
		if (f.lateness_usec > 0) ++result.late_starts;
		control(Phase::U_BEGIN, f); // One epoch budget admission, shared by H/P.
		f.delta = {h, h, h * scale, h};
		h_phase(f);
		p_phase(f); // P_n depends on H_n, never on R_(n+1).
		f.delta = {};
		control(Phase::U_END, f);
		control(Phase::PUBLISH, f);
		++next_epoch_;
		++result.epochs_serviced;
		if (!observe(now)) { result.fault = fault(FaultCode::INVALID, now); break; }
		if (now > release_usec(next_epoch_)) ++result.deadline_misses;
		if (pending(now) > config_.max_epochs_per_turn && result.fault.code == FaultCode::NONE) {
			// Each turn still admits at most M complete H/P pairs. The next turn
			// may service remaining debt; this receipt is never a fluency PASS.
			result.fault = fault(FaultCode::CLOCK_OVERRUN, now);
		}
	}
	result.pending_epochs = pending(now);
	result.next_release_usec = release_usec(next_epoch_);
	return result;
}

SimulationClock::TurnReceipt SimulationClock::replay_iteration(const ReplayIteration &trace) {
	TurnReceipt result;
	if (servicing_ || timers_.is_sweeping()) {
		result.fault = fault(FaultCode::REENTRANT, last_observed_usec_); return result;
	}
	bool valid = valid_config() && config_.mode == Mode::TRACE_REPLAY && !suspended_ &&
			std::isfinite(trace.time_scale) && trace.time_scale >= 0 && valid_delta(trace.p) &&
			trace.h.size() <= std::numeric_limits<uint32_t>::max();
	for (const Delta &d : trace.h) valid = valid && valid_delta(d);
	if (!valid) { result.fault = fault(FaultCode::INVALID, last_observed_usec_); return result; }
	ServiceScope scope(servicing_);
	uint64_t now;
	if (!observe(now)) { result.fault = fault(FaultCode::INVALID, now); return result; }
	ClockFrame f = frame(next_epoch_, now, trace.time_scale);
	control(Phase::U_BEGIN, f);
	for (const Delta &d : trace.h) {
		f.delta = d;
		h_phase(f);
		++f.h_ordinal;
	}
	f.delta = trace.p;
	p_phase(f);
	f.delta = {};
	control(Phase::U_END, f);
	control(Phase::PUBLISH, f);
	++next_epoch_;
	result.epochs_serviced = 1;
	return result;
}

SimulationClock::FaultReceipt SimulationClock::service_receipts() {
	if (servicing_ || timers_.is_sweeping()) return fault(FaultCode::REENTRANT, last_observed_usec_);
	ServiceScope scope(servicing_);
	uint64_t now;
	if (!observe(now)) return fault(FaultCode::INVALID, now);
	control(Phase::U_WAKE, frame(next_epoch_, now, 0));
	return {};
}

SimulationClock::FaultReceipt SimulationClock::suspend(uint64_t now) {
	if (servicing_ || timers_.is_sweeping()) return fault(FaultCode::REENTRANT, now);
	if (!valid_config() || suspended_ || (observed_ && now < last_observed_usec_)) return fault(FaultCode::INVALID, now);
	suspended_ = true;
	suspend_usec_ = now;
	last_observed_usec_ = now;
	observed_ = true;
	return {};
}

SimulationClock::FaultReceipt SimulationClock::resume(uint64_t now) {
	if (servicing_ || timers_.is_sweeping()) return fault(FaultCode::REENTRANT, now);
	if (!suspended_ || now < suspend_usec_ || (observed_ && now < last_observed_usec_)) return fault(FaultCode::INVALID, now);
	const uint64_t suspended_usec = now - suspend_usec_;
	if (config_.origin_usec > OVERFLOW_TIME - suspended_usec) return fault(FaultCode::INVALID, now);
	config_.origin_usec += suspended_usec;
	suspended_ = false;
	last_observed_usec_ = now;
	observed_ = true;
	return {};
}

} // namespace hardcore::simulation
