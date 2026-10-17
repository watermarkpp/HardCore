#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <vector>

namespace hardcore::simulation {

enum class BatchState : uint8_t { UNCLAIMED, RUNNING, READY, CONSUMED, RETIRED, CANCELLED };

struct FrozenInput {
	std::vector<uint8_t> bytes;
	uint64_t input_version = 0;
};

struct BatchTicket {
	uint64_t tick = 0;
	uint64_t generation = 0;
	};

struct BatchOwner {
	uint32_t id = 0;
	bool operator==(const BatchOwner &other) const { return id == other.id; }
};

struct BatchBlock {
	BatchTicket ticket;
	uint32_t id = 0;
	std::shared_ptr<const FrozenInput> input;
	std::vector<uint8_t> output;
	std::atomic<BatchState> state{BatchState::UNCLAIMED};
	std::atomic<uint32_t> owner{0};
	std::atomic<bool> completion_claimed{false};

	BatchBlock() = default;
	BatchBlock(const BatchBlock &) = delete;
	BatchBlock &operator=(const BatchBlock &) = delete;
};

} // namespace hardcore::simulation
