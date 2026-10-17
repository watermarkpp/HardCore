#pragma once
#include <cstdint>

namespace hardcore::simulation {
// S owns the backend for the entire session. Tick completion never releases it.
class PhysicsPort {
public:
	enum class Phase : uint8_t { Stopped, Idle, Prepared, Synced, QueriesFlushed, Logic, Ended, Stepped, Finished };
	struct Backend {
		virtual ~Backend() = default;
		virtual bool claim_owner() = 0;
		virtual bool release_owner() = 0;
		virtual void sync() = 0;
		virtual void flush_queries() = 0;
		virtual void begin_logic() = 0;
		virtual void end_sync() = 0;
		virtual void step(double delta) = 0;
	};
	explicit PhysicsPort(Backend &backend) : backend_(backend) {}
	bool start();
	bool begin(uint64_t tick, double delta);
	bool sync();
	bool flush_queries();
	bool begin_logic();
	bool end_sync();
	bool step();
	bool finish();
	bool shutdown();
	Phase phase() const { return phase_; }
	uint64_t tick() const { return tick_; }
	double delta() const { return delta_; }
	const char *last_error() const { return error_; }
private:
	bool require(Phase expected, const char *message);
	Backend &backend_;
	Phase phase_ = Phase::Stopped;
	uint64_t tick_ = 0;
	bool has_tick_ = false;
	double delta_ = 0;
	const char *error_ = "";
};
} // namespace hardcore::simulation
