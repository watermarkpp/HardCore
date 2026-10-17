#pragma once

#include "batch_types.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

namespace hardcore::simulation {

class BatchExecutor {
public:
	using GroupID = uint64_t;
	using GroupCallback = void (*)(void *, uint32_t);
	struct Pool {
		virtual ~Pool() = default;
		virtual GroupID add_group_task(GroupCallback callback, void *userdata, int elements, int tasks, bool high_priority, const char *description) = 0;
		virtual bool is_group_task_completed(GroupID id) const = 0;
		virtual void wait_for_group_task_completion(GroupID id) = 0;
	};
	using Kernel = void (*)(const FrozenInput &, std::vector<uint8_t> &, void *);

	enum class DispatchResult : uint8_t { ACCEPTED, CAPACITY_FULL, INVALID_INPUT, INVALID_TICKET, DISPATCH_FAILED };
	enum class ClaimResult : uint8_t { CLAIMED, ALREADY_CLAIMED, INVALID_BLOCK, WRONG_TICKET };

	struct ReadyMask { std::vector<uint32_t> block_ids; };
	struct DispatchWindow { uint64_t current_tick = 0; bool allow_same_tick_lookahead = false; };
	struct OutputLease {
		const std::vector<uint8_t> *bytes = nullptr;
		BatchTicket ticket;
		uint32_t block_id = 0;
		bool valid() const { return bytes != nullptr; }
	};

	BatchExecutor(Pool &pool, std::size_t capacity, Kernel kernel, void *kernel_context = nullptr);
	~BatchExecutor();

	DispatchResult dispatch_ready(const BatchTicket &ticket, const std::vector<std::shared_ptr<const FrozenInput>> &inputs, int tasks_needed, bool high_priority, DispatchWindow window);
	ReadyMask poll_published(const BatchTicket &ticket);
	// Necessary current-stage work may park its sole consumer; display Main
	// never enters this executor. This joins the real group exactly once.
	bool wait_for_published(const BatchTicket &ticket);
	ClaimResult claim_block(const BatchTicket &ticket, uint32_t block_id, BatchOwner owner);
	OutputLease acquire_output(const BatchTicket &ticket, uint32_t block_id) const;
	bool complete_claimed(const BatchTicket &ticket, uint32_t block_id, BatchOwner owner);
	bool consume_block(const BatchTicket &ticket, uint32_t block_id, BatchOwner owner);
	bool cancel_unclaimed(const BatchTicket &ticket, uint32_t block_id);
	bool retire_completed(const BatchTicket &ticket);
	BatchState state(const BatchTicket &ticket, uint32_t block_id) const;
	std::size_t in_flight() const { return active_.size(); }

private:
	struct Task {
		BatchExecutor *executor = nullptr;
		BatchTicket ticket;
		DispatchWindow window;
		GroupID group = 0;
		std::vector<std::unique_ptr<BatchBlock>> blocks;
		bool group_complete = false;
		bool group_joined = false;
	};
	Pool &pool_;
	std::size_t capacity_;
	Kernel kernel_;
	void *kernel_context_;
	std::vector<std::unique_ptr<Task>> active_;

	Task *find(const BatchTicket &ticket);
	const Task *find(const BatchTicket &ticket) const;
	BatchBlock *find_block(Task &, uint32_t id);
	static void worker_entry(void *userdata, uint32_t index);
};

} // namespace hardcore::simulation
