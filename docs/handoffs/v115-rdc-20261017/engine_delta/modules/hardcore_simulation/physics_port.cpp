#include "physics_port.h"
#include <cmath>
namespace hardcore::simulation {
bool PhysicsPort::require(Phase expected, const char *message) {
	if (phase_ == expected) return true;
	error_ = message;
	return false;
}
bool PhysicsPort::start() {
	if (!require(Phase::Stopped, "start requires Stopped")) return false;
	if (!backend_.claim_owner()) { error_ = "backend owner claim failed"; return false; }
	phase_ = Phase::Idle;
	return true;
}
bool PhysicsPort::begin(uint64_t tick, double delta) {
	if (!require(Phase::Idle, "begin requires Idle")) return false;
	if (!std::isfinite(delta) || delta < 0.0) { error_ = "delta must be finite and nonnegative"; return false; }
	if (has_tick_ && tick <= tick_) { error_ = "tick must advance"; return false; }
	tick_ = tick;
	has_tick_ = true;
	delta_ = delta;
	error_ = "";
	phase_ = Phase::Prepared;
	return true;
}
bool PhysicsPort::sync() {
	if (!require(Phase::Prepared, "sync requires Prepared")) return false;
	backend_.sync(); phase_ = Phase::Synced; return true;
}
bool PhysicsPort::flush_queries() {
	if (!require(Phase::Synced, "flush requires Synced")) return false;
	backend_.flush_queries(); phase_ = Phase::QueriesFlushed; return true;
}
bool PhysicsPort::begin_logic() {
	if (!require(Phase::QueriesFlushed, "logic requires QueriesFlushed")) return false;
	backend_.begin_logic(); phase_ = Phase::Logic; return true;
}
bool PhysicsPort::end_sync() {
	if (!require(Phase::Logic, "end_sync requires Logic")) return false;
	backend_.end_sync(); phase_ = Phase::Ended; return true;
}
bool PhysicsPort::step() {
	if (!require(Phase::Ended, "step requires Ended")) return false;
	backend_.step(delta_); phase_ = Phase::Stepped; return true;
}
bool PhysicsPort::finish() {
	if (!require(Phase::Stepped, "finish tick requires Stepped")) return false;
	phase_ = Phase::Idle; return true;
}
bool PhysicsPort::shutdown() {
	if (!require(Phase::Idle, "shutdown requires Idle")) return false;
	if (!backend_.release_owner()) { error_ = "backend finish/release failed"; return false; }
	phase_ = Phase::Finished; return true;
}
} // namespace hardcore::simulation
