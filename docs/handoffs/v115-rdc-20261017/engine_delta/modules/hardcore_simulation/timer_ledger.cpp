#include "timer_ledger.h"
#include <cmath>
#include <iterator>

namespace hardcore::simulation {

TimerLedger::TimerLedger(size_t capacity) : capacity_(capacity) {}

TimerLedger::CreateResult TimerLedger::create(double seconds, Flags flags, uint64_t token) {
	if (!std::isfinite(seconds) || (flags.domain != Domain::H && flags.domain != Domain::P) || next_id_ == 0) {
		return {CreateStatus::INVALID, 0};
	}
	if (timers_.size() >= capacity_) {
		return {CreateStatus::CAPACITY, 0};
	}
	const TimerId id = next_id_++;
	timers_.push_back({id, seconds, flags, token});
	return {CreateStatus::ACCEPTED, id};
}

bool TimerLedger::set_time_left(TimerId id, double seconds) {
	if (!std::isfinite(seconds)) return false;
	for (Timer &timer : timers_) {
		if (timer.id == id) { timer.time_left = seconds; return true; }
	}
	return false;
}

bool TimerLedger::set_flags(TimerId id, Flags flags) {
	if (flags.domain != Domain::H && flags.domain != Domain::P) return false;
	for (Timer &timer : timers_) {
		if (timer.id == id) { timer.flags = flags; return true; }
	}
	return false;
}

bool TimerLedger::read(TimerId id, Timer &out) const {
	for (const Timer &timer : timers_) {
		if (timer.id == id) { out = timer; return true; }
	}
	return false;
}

TimerLedger::SweepResult TimerLedger::sweep(Domain domain, double scaled_delta,
		double unscaled_process_step, Consumer &consumer) {
	if (sweeping_) return {SweepStatus::REENTRANT};
	if ((domain != Domain::H && domain != Domain::P) || !std::isfinite(scaled_delta) ||
			!std::isfinite(unscaled_process_step) || scaled_delta < 0 || unscaled_process_step < 0) {
		return {SweepStatus::INVALID};
	}
	SweepResult result{SweepStatus::PASS};
	if (timers_.empty()) return result;
	struct Scope { bool &busy; ~Scope() { busy = false; } } scope{sweeping_};
	sweeping_ = true;

	// Mechanical adaptation of SceneTree::process_timers: one shared H/P list,
	// capture original last, capture next before the synchronous timeout, and
	// erase only after it returns. Newly appended entries cannot extend a scan.
	const auto last = std::prev(timers_.end());
	for (auto current = timers_.begin(); current != timers_.end();) {
		const auto next = std::next(current);
		const bool at_last = current == last;
		++result.visited;
		Timer &timer = *current;
		if ((consumer.is_paused() && !timer.flags.process_always) || timer.flags.domain != domain) {
			if (at_last) break;
			current = next;
			continue;
		}
		double time_left = timer.time_left;
		time_left -= timer.flags.ignore_time_scale ? unscaled_process_step : scaled_delta;
		timer.time_left = time_left;
		if (time_left <= 0) {
			consumer.on_timeout(timer);
			timers_.erase(current);
			++result.fired;
		}
		if (at_last) break;
		current = next;
	}
	return result;
}

} // namespace hardcore::simulation
