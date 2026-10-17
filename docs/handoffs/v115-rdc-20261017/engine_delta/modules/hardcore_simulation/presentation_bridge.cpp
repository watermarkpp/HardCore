#include "presentation_bridge.h"

#include <algorithm>

namespace hardcore::simulation {

PresentationBridge::PresentationBridge(std::size_t event_capacity) : event_capacity_(event_capacity) { events_.reserve(event_capacity); }

bool PresentationBridge::publish(const Snapshot &snapshot, const std::vector<Event> &events) {
	std::lock_guard<std::mutex> lock(mutex_);
	if (events.size() > event_capacity_ || events_.size() + events.size() > event_capacity_) return false;
	uint64_t previous = published_ordinal_;
	for (const Event &event : events) {
		if (event.ordinal != previous + 1) return false;
		previous = event.ordinal;
	}
	if (snapshot.last_effect_ordinal > previous) return false;
	if (!events.empty() && snapshot.last_effect_ordinal != events.back().ordinal) return false;
	uint32_t selected = UINT32_MAX;
	for (uint32_t i = 0; i < 3; ++i) {
		SlotState expected = SlotState::FREE;
		if (slots_[i].state.compare_exchange_strong(expected, SlotState::WRITING, std::memory_order_acq_rel)) {
			selected = i;
			break;
		}
	}
	if (selected == UINT32_MAX) {
		// Presentation is a latest-state channel. Display Main being late must
		// not stall simulation after three frames. Only unacquired PUBLISHED
		// slots may be replaced; reliable events remain in their separate log.
		uint64_t oldest = UINT64_MAX;
		for (uint32_t i = 0; i < 3; ++i) {
			if (slots_[i].state.load(std::memory_order_acquire) == SlotState::PUBLISHED && slots_[i].snapshot.tick < oldest) {
				selected = i;
				oldest = slots_[i].snapshot.tick;
			}
		}
		if (selected == UINT32_MAX) return false;
		SlotState expected = SlotState::PUBLISHED;
		if (!slots_[selected].state.compare_exchange_strong(expected, SlotState::WRITING, std::memory_order_acq_rel)) return false;
	}
	slots_[selected].generation++;
	slots_[selected].snapshot = snapshot;
	events_.insert(events_.end(), events.begin(), events.end());
	published_ordinal_ = previous;
	slots_[selected].state.store(SlotState::PUBLISHED, std::memory_order_release);
	return true;
}

PresentationBridge::FrameLease PresentationBridge::acquire_frame(uint64_t min_tick) {
	std::lock_guard<std::mutex> lock(mutex_);
	uint32_t selected = UINT32_MAX; uint64_t best_tick = 0;
	for (uint32_t i = 0; i < 3; ++i) {
		if (slots_[i].state.load(std::memory_order_acquire) != SlotState::PUBLISHED) continue;
		if (slots_[i].snapshot.tick >= min_tick && (selected == UINT32_MAX || slots_[i].snapshot.tick > best_tick)) { selected = i; best_tick = slots_[i].snapshot.tick; }
	}
	if (selected == UINT32_MAX) return {};
	SlotState expected = SlotState::PUBLISHED;
	if (!slots_[selected].state.compare_exchange_strong(expected, SlotState::READING, std::memory_order_acq_rel)) return {};
	for (uint32_t i = 0; i < 3; ++i) if (i != selected) {
		SlotState old = SlotState::PUBLISHED;
		slots_[i].state.compare_exchange_strong(old, SlotState::FREE, std::memory_order_acq_rel);
	}
	return FrameLease{selected, slots_[selected].generation, &slots_[selected].snapshot};
}

bool PresentationBridge::release_frame(const FrameLease &lease) {
	if (!lease.valid() || lease.slot >= 3) return false;
	std::lock_guard<std::mutex> lock(mutex_);
	if (slots_[lease.slot].generation != lease.generation) return false;
	SlotState expected = SlotState::READING;
	return slots_[lease.slot].state.compare_exchange_strong(expected, SlotState::FREE, std::memory_order_acq_rel);
}

PresentationBridge::EventLease PresentationBridge::drain_events(uint64_t through_ordinal, std::size_t capacity) const {
	std::lock_guard<std::mutex> lock(mutex_);
	EventLease lease;
	const uint64_t ack = acknowledged_ordinal_.load(std::memory_order_acquire);
	if (through_ordinal > published_ordinal_) return lease;
	std::size_t pending = 0;
	for (const Event &event : events_) if (event.ordinal > ack && event.ordinal <= through_ordinal) ++pending;
	if (pending > capacity) return lease;
	for (const Event &event : events_) {
		if (event.ordinal <= ack || event.ordinal > through_ordinal) continue;
		if (lease.events.size() >= capacity) break;
		if (lease.first_ordinal == 0) lease.first_ordinal = event.ordinal;
		lease.last_ordinal = event.ordinal;
		lease.events.push_back(event);
	}
	lease.ready = true;
	drained_ordinal_ = std::max(drained_ordinal_, through_ordinal);
	return lease;
}

bool PresentationBridge::ack_events(uint64_t last_ordinal) {
	std::lock_guard<std::mutex> lock(mutex_);
	uint64_t current = acknowledged_ordinal_.load(std::memory_order_acquire);
	if (last_ordinal < current || last_ordinal > published_ordinal_ || last_ordinal > drained_ordinal_) return false;
	acknowledged_ordinal_.store(last_ordinal, std::memory_order_release);
	events_.erase(std::remove_if(events_.begin(), events_.end(), [&](const Event &event) { return event.ordinal <= last_ordinal; }), events_.end());
	return true;
}

PresentationBridge::SlotState PresentationBridge::slot_state(uint32_t slot) const {
	if (slot >= 3) return SlotState::FREE;
	return slots_[slot].state.load(std::memory_order_acquire);
}

} // namespace hardcore::simulation
