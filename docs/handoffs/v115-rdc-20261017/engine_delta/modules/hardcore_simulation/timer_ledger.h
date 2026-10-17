#pragma once

#include <cstddef>
#include <cstdint>
#include <list>

namespace hardcore::simulation {

// S-confined counterpart of SceneTree's one insertion-ordered timer list.
// No Node, Resource, Callable, wall deadline, or gameplay identity is stored here.
class TimerLedger {
public:
	enum class Domain : uint8_t { H, P };
	using TimerId = uint64_t; // Private list handle, never an ActorRef/release_id.
	struct Flags {
		bool process_always = true;
		Domain domain = Domain::P;
		bool ignore_time_scale = false;
	};
	struct Timer {
		TimerId id = 0;
		double time_left = 0;
		Flags flags;
		uint64_t continuation_token = 0; // Resolves only in the S-owned consumer.
	};
	struct Consumer {
		virtual ~Consumer() = default;
		virtual bool is_paused() const = 0;
		// S checks the original world/life/combat conditions and synchronously
		// consumes this individual continuation. A later action is not a cancel.
		virtual void on_timeout(const Timer &timer) = 0;
	};
	enum class CreateStatus : uint8_t { ACCEPTED, CAPACITY, INVALID };
	struct CreateResult { CreateStatus status; TimerId id; };
	enum class SweepStatus : uint8_t { PASS, INVALID, REENTRANT };
	struct SweepResult { SweepStatus status; size_t visited = 0; size_t fired = 0; };

	explicit TimerLedger(size_t capacity);
	CreateResult create(double seconds, Flags flags, uint64_t continuation_token);
	bool set_time_left(TimerId id, double seconds);
	bool set_flags(TimerId id, Flags flags);
	bool read(TimerId id, Timer &out) const;
	SweepResult sweep(Domain domain, double scaled_delta, double unscaled_process_step, Consumer &consumer);
	size_t size() const { return timers_.size(); }
	bool is_sweeping() const { return sweeping_; }

private:
	size_t capacity_;
	TimerId next_id_ = 1;
	bool sweeping_ = false;
	std::list<Timer> timers_;
};

} // namespace hardcore::simulation
