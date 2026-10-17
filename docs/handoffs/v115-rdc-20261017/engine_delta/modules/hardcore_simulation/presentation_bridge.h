#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <vector>

namespace hardcore::simulation {

class PresentationBridge {
public:
	enum class SlotState : uint8_t { FREE, WRITING, PUBLISHED, READING };
	struct Snapshot { uint64_t tick = 0; uint64_t last_effect_ordinal = 0; std::vector<uint8_t> bytes; };
	struct Event { uint64_t ordinal = 0; uint64_t tick = 0; std::vector<uint8_t> bytes; };
	struct FrameLease { uint32_t slot = UINT32_MAX; uint64_t generation = 0; const Snapshot *snapshot = nullptr; bool valid() const { return snapshot != nullptr; } };
	struct EventLease { uint64_t first_ordinal = 0; uint64_t last_ordinal = 0; std::vector<Event> events; bool ready = false; bool valid() const { return ready; } };

	explicit PresentationBridge(std::size_t event_capacity = 256);
	bool publish(const Snapshot &snapshot, const std::vector<Event> &events);
	FrameLease acquire_frame(uint64_t min_tick);
	bool release_frame(const FrameLease &lease);
	EventLease drain_events(uint64_t through_ordinal, std::size_t capacity) const;
	bool ack_events(uint64_t last_ordinal);
	SlotState slot_state(uint32_t slot) const;
	uint64_t acknowledged_ordinal() const { return acknowledged_ordinal_.load(std::memory_order_acquire); }

private:
	struct Slot { std::atomic<SlotState> state{SlotState::FREE}; uint64_t generation = 0; Snapshot snapshot; };
	Slot slots_[3];
	mutable std::mutex mutex_;
	std::vector<Event> events_;
	std::size_t event_capacity_;
	std::atomic<uint64_t> next_ordinal_{1};
	uint64_t published_ordinal_ = 0;
	mutable uint64_t drained_ordinal_ = 0;
	std::atomic<uint64_t> acknowledged_ordinal_{0};
};

} // namespace hardcore::simulation
