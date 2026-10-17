#include "batch_executor.h"

#include <algorithm>

namespace hardcore::simulation {

BatchExecutor::BatchExecutor(Pool &pool, std::size_t capacity, Kernel kernel, void *kernel_context)
	: pool_(pool), capacity_(capacity), kernel_(kernel), kernel_context_(kernel_context) {}

BatchExecutor::~BatchExecutor() {
	for (const auto &task : active_) if (!task->group_joined) pool_.wait_for_group_task_completion(task->group);
}

BatchExecutor::Task *BatchExecutor::find(const BatchTicket &ticket) {
	for (auto &task : active_) if (task->ticket.tick == ticket.tick && task->ticket.generation == ticket.generation) return task.get();
	return nullptr;
}
const BatchExecutor::Task *BatchExecutor::find(const BatchTicket &ticket) const {
	for (const auto &task : active_) if (task->ticket.tick == ticket.tick && task->ticket.generation == ticket.generation) return task.get();
	return nullptr;
}
BatchBlock *BatchExecutor::find_block(Task &task, uint32_t id) {
	if (id >= task.blocks.size()) return nullptr;
	return task.blocks[id].get();
}

BatchExecutor::DispatchResult BatchExecutor::dispatch_ready(const BatchTicket &ticket, const std::vector<std::shared_ptr<const FrozenInput>> &inputs, int tasks_needed, bool high_priority, DispatchWindow window) {
	if (inputs.empty() || !kernel_ || tasks_needed <= 0 || inputs.size() > static_cast<std::size_t>(INT32_MAX)) return DispatchResult::INVALID_INPUT;
	// Lookahead refers to a later independent stage inside this tick. A future
	// tick has not observed this tick's accepted mutations and is never legal.
	if (ticket.tick != window.current_tick) return DispatchResult::INVALID_TICKET;
	if (find(ticket)) return DispatchResult::INVALID_TICKET;
	if (active_.size() >= capacity_) return DispatchResult::CAPACITY_FULL;
	auto task = std::make_unique<Task>();
	task->executor = this;
	task->ticket = ticket;
	task->window = window;
	for (uint32_t i = 0; i < inputs.size(); ++i) {
		if (!inputs[i]) return DispatchResult::INVALID_INPUT;
		auto block = std::make_unique<BatchBlock>();
		block->ticket = ticket; block->id = i; block->input = inputs[i];
		task->blocks.push_back(std::move(block));
	}
	Task *raw = task.get();
	active_.push_back(std::move(task));
	raw->group = pool_.add_group_task(&BatchExecutor::worker_entry, raw, static_cast<int>(inputs.size()), tasks_needed, high_priority, "hardcore_fixed_stage_batch");
	if (raw->group == UINT64_MAX) {
		// An invalid pool submission started no callbacks. No accepted work or
		// output lease exists, and its sentinel must never enter wait/poll.
		active_.pop_back();
		return DispatchResult::DISPATCH_FAILED;
	}
	return DispatchResult::ACCEPTED;
}

void BatchExecutor::worker_entry(void *userdata, uint32_t index) {
	Task *task = static_cast<Task *>(userdata);
	if (!task || index >= task->blocks.size()) return;
	BatchExecutor *executor = task->executor;
	BatchBlock &block = *task->blocks[index];
	BatchState expected = BatchState::UNCLAIMED;
	if (!block.state.compare_exchange_strong(expected, BatchState::RUNNING, std::memory_order_acq_rel)) return;
	block.owner.store(0xFFFFFFFFu, std::memory_order_release);
	bool completion_expected = false;
	if (!block.completion_claimed.compare_exchange_strong(completion_expected, true, std::memory_order_acq_rel)) return;
	// The input shared_ptr is held by the block for the entire task lifetime.
	// The kernel can only write this block's private output vector.
	if (executor->kernel_) executor->kernel_(*block.input, block.output, executor->kernel_context_);
	block.state.store(BatchState::READY, std::memory_order_release);
}

BatchExecutor::ReadyMask BatchExecutor::poll_published(const BatchTicket &ticket) {
	ReadyMask ready;
	Task *task = find(ticket);
	if (!task) return ready;
	if (!task->group_complete && pool_.is_group_task_completed(task->group)) task->group_complete = true;
	for (auto &block : task->blocks) if (block->state.load(std::memory_order_acquire) == BatchState::READY) ready.block_ids.push_back(block->id);
	return ready;
}

bool BatchExecutor::wait_for_published(const BatchTicket &ticket) {
	Task *task = find(ticket);
	if (!task) return false;
	if (!task->group_joined) {
		pool_.wait_for_group_task_completion(task->group);
		task->group_joined = true;
		task->group_complete = true;
	}
	return true;
}

BatchExecutor::ClaimResult BatchExecutor::claim_block(const BatchTicket &ticket, uint32_t block_id, BatchOwner owner) {
	Task *task = find(ticket); if (!task) return ClaimResult::WRONG_TICKET;
	BatchBlock *block = find_block(*task, block_id); if (!block) return ClaimResult::INVALID_BLOCK;
	BatchState expected = BatchState::UNCLAIMED;
	if (!block->state.compare_exchange_strong(expected, BatchState::RUNNING, std::memory_order_acq_rel)) return ClaimResult::ALREADY_CLAIMED;
	block->owner.store(owner.id, std::memory_order_release);
	return ClaimResult::CLAIMED;
}

BatchExecutor::OutputLease BatchExecutor::acquire_output(const BatchTicket &ticket, uint32_t block_id) const {
	const Task *task = find(ticket); if (!task || block_id >= task->blocks.size()) return {};
	const BatchBlock &block = *task->blocks[block_id];
	BatchState current = block.state.load(std::memory_order_acquire);
	if (current != BatchState::READY && current != BatchState::CONSUMED) return {};
	return OutputLease{&block.output, ticket, block_id};
}

bool BatchExecutor::complete_claimed(const BatchTicket &ticket, uint32_t block_id, BatchOwner owner) {
	Task *task = find(ticket); if (!task) return false;
	BatchBlock *block = find_block(*task, block_id); if (!block || block->owner.load(std::memory_order_acquire) != owner.id) return false;
	bool completion_expected = false;
	if (!block->completion_claimed.compare_exchange_strong(completion_expected, true, std::memory_order_acq_rel)) return false;
	if (kernel_) kernel_(*block->input, block->output, kernel_context_);
	BatchState expected = BatchState::RUNNING;
	if (!block->state.compare_exchange_strong(expected, BatchState::READY, std::memory_order_acq_rel)) return false;
	return true;
}

bool BatchExecutor::consume_block(const BatchTicket &ticket, uint32_t block_id, BatchOwner) {
	Task *task = find(ticket); if (!task) return false;
	BatchBlock *block = find_block(*task, block_id); if (!block) return false;
	BatchState expected = BatchState::READY;
	return block->state.compare_exchange_strong(expected, BatchState::CONSUMED, std::memory_order_acq_rel);
}

bool BatchExecutor::cancel_unclaimed(const BatchTicket &ticket, uint32_t block_id) {
	Task *task = find(ticket); if (!task) return false;
	BatchBlock *block = find_block(*task, block_id); if (!block) return false;
	BatchState expected = BatchState::UNCLAIMED;
	return block->state.compare_exchange_strong(expected, BatchState::CANCELLED, std::memory_order_acq_rel);
}

bool BatchExecutor::retire_completed(const BatchTicket &ticket) {
	Task *task = find(ticket); if (!task || !task->group_complete) return false;
	if (!task->group_joined) {
		pool_.wait_for_group_task_completion(task->group);
		task->group_joined = true;
	}
	for (auto &block : task->blocks) {
		BatchState state = block->state.load(std::memory_order_acquire);
		if (state == BatchState::READY || state == BatchState::RUNNING || state == BatchState::UNCLAIMED) return false;
		if (state == BatchState::CONSUMED || state == BatchState::CANCELLED) block->state.store(BatchState::RETIRED, std::memory_order_release);
	}
	active_.erase(std::remove_if(active_.begin(), active_.end(), [&](const std::unique_ptr<Task> &candidate) { return candidate.get() == task; }), active_.end());
	return true;
}

BatchState BatchExecutor::state(const BatchTicket &ticket, uint32_t block_id) const {
	const Task *task = find(ticket); if (!task || block_id >= task->blocks.size()) return BatchState::RETIRED;
	return task->blocks[block_id]->state.load(std::memory_order_acquire);
}

} // namespace hardcore::simulation
