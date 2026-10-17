/**************************************************************************/
/*  physics_server_2d_wrap_mt.cpp                                         */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "physics_server_2d_wrap_mt.h"

#include "core/object/callable_mp.h"

void PhysicsServer2DWrapMT::_assign_mt_ids(WorkerThreadPool::TaskID p_pump_task_id) {
	server_thread = Thread::get_caller_id();
	server_task_id = p_pump_task_id;
}

void PhysicsServer2DWrapMT::_thread_exit() {
	exit = true;
}

void PhysicsServer2DWrapMT::_thread_loop() {
	while (!exit) {
		WorkerThreadPool::get_singleton()->yield();

		if (!doing_sync.is_set()) {
			command_queue.flush_all();
		}
	}
}

void PhysicsServer2DWrapMT::_thread_sync() {
	doing_sync.set();
}

/* EVENT QUEUING */

void PhysicsServer2DWrapMT::step(real_t p_step) {
	if (external_owner_mode) {
		require_external_phase(ExternalPhase::ENDED);
		external_phase.store(ExternalPhase::STEPPING, std::memory_order_release);
		physics_server_2d->step(p_step);
		for (int i = 0; i < 3; ++i) {
			published_process_info[i].store(physics_server_2d->get_process_info(static_cast<ProcessInfo>(i)), std::memory_order_release);
		}
		external_phase.store(ExternalPhase::IDLE, std::memory_order_release);
		return;
	}
	if (create_thread) {
		command_queue.push(physics_server_2d, &PhysicsServer2D::step, p_step);
	} else {
		physics_server_2d->step(p_step);
	}
}

void PhysicsServer2DWrapMT::sync() {
	if (external_owner_mode) {
		require_external_phase(ExternalPhase::IDLE);
		physics_server_2d->sync();
		external_phase.store(ExternalPhase::SYNCED, std::memory_order_release);
		return;
	}
	if (create_thread) {
		command_queue.push_and_sync(this, &PhysicsServer2DWrapMT::_thread_sync);
	} else {
		command_queue.flush_all(); // Flush all pending from other threads.
	}
	physics_server_2d->sync();
}

void PhysicsServer2DWrapMT::flush_queries() {
	if (external_owner_mode) {
		require_external_phase(ExternalPhase::SYNCED);
		external_phase.store(ExternalPhase::FLUSHING, std::memory_order_release);
		physics_server_2d->flush_queries();
		external_phase.store(ExternalPhase::QUERIES_FLUSHED, std::memory_order_release);
		return;
	}
	physics_server_2d->flush_queries();
}

void PhysicsServer2DWrapMT::end_sync() {
	if (external_owner_mode) {
		require_external_phase(ExternalPhase::LOGIC);
		physics_server_2d->end_sync();
		external_phase.store(ExternalPhase::ENDED, std::memory_order_release);
		return;
	}
	physics_server_2d->end_sync();

	if (create_thread) {
		doing_sync.clear();
	}
}

void PhysicsServer2DWrapMT::init() {
	if (external_owner_mode) {
		CRASH_COND_MSG(!Thread::is_main_thread() || external_lifecycle.load() != ExternalLifecycle::CONSTRUCTED, "External Physics2D init must happen once on Main.");
		physics_server_2d->init();
		external_lifecycle.store(ExternalLifecycle::BOOTSTRAP_MAIN, std::memory_order_release);
		return;
	}
	if (create_thread) {
		WorkerThreadPool::TaskID tid = WorkerThreadPool::get_singleton()->add_task(callable_mp(this, &PhysicsServer2DWrapMT::_thread_loop), true, "Physics server 2D pump task", true);
		command_queue.set_pump_task_id(tid);
		command_queue.push(this, &PhysicsServer2DWrapMT::_assign_mt_ids, tid);
		command_queue.push_and_sync(physics_server_2d, &PhysicsServer2D::init);
		DEV_ASSERT(server_task_id == tid);
	} else {
		server_thread = Thread::MAIN_ID;
		physics_server_2d->init();
	}
}

void PhysicsServer2DWrapMT::finish() {
	if (external_owner_mode) {
		CRASH_COND_MSG(!release_external_owner(), "External Physics2D finish must happen once on S at idle.");
		return;
	}
	if (create_thread) {
		command_queue.push(physics_server_2d, &PhysicsServer2D::finish);
		command_queue.push(this, &PhysicsServer2DWrapMT::_thread_exit);
		if (server_task_id != WorkerThreadPool::INVALID_TASK_ID) {
			WorkerThreadPool::get_singleton()->wait_for_task_completion(server_task_id);
			server_task_id = WorkerThreadPool::INVALID_TASK_ID;
		}
		server_thread = Thread::MAIN_ID;
	} else {
		physics_server_2d->finish();
	}
}

bool PhysicsServer2DWrapMT::is_external_query_phase() const {
	ExternalPhase phase = external_phase.load(std::memory_order_acquire);
	return is_external_owner_thread() && (phase == ExternalPhase::SYNCED || phase == ExternalPhase::FLUSHING || phase == ExternalPhase::QUERIES_FLUSHED || phase == ExternalPhase::LOGIC || phase == ExternalPhase::PROCESS);
}

void PhysicsServer2DWrapMT::assert_external_access(bool p_query) const {
	if (!external_owner_mode) {
		return;
	}
	ExternalLifecycle state = external_lifecycle.load(std::memory_order_acquire);
	if (state == ExternalLifecycle::BOOTSTRAP_MAIN && Thread::is_main_thread() && !p_query) {
		return;
	}
	CRASH_COND_MSG(state != ExternalLifecycle::OWNED_BY_S || !is_external_owner_thread(), "External Physics2D owner violation: Main/worker access is forbidden after handoff; no command was queued.");
	ExternalPhase phase = external_phase.load(std::memory_order_acquire);
	CRASH_COND_MSG(phase == ExternalPhase::STEPPING || phase == ExternalPhase::ENDED, "External Physics2D access outside the service window.");
	CRASH_COND_MSG(p_query && !is_external_query_phase(), "External Physics2D query outside sync/flush/logic; cannot return an ordinary no-hit result.");
}

void PhysicsServer2DWrapMT::require_external_phase(ExternalPhase p_phase) const {
	CRASH_COND_MSG(external_lifecycle.load(std::memory_order_acquire) != ExternalLifecycle::OWNED_BY_S || !is_external_owner_thread(), "External Physics2D phase driver must be its claimed S thread.");
	CRASH_COND_MSG(external_phase.load(std::memory_order_acquire) != p_phase, "External Physics2D phase order violation.");
}

bool PhysicsServer2DWrapMT::prepare_external_handoff() {
	ERR_FAIL_COND_V(!external_owner_mode || !Thread::is_main_thread(), false);
	ERR_FAIL_COND_V(external_lifecycle.load() != ExternalLifecycle::BOOTSTRAP_MAIN, false);
	// Bootstrap operations were direct; drain any pre-init command before publication.
	command_queue.flush_all();
	external_lifecycle.store(ExternalLifecycle::HANDOFF_QUIESCENT, std::memory_order_release);
	return true;
}

bool PhysicsServer2DWrapMT::claim_external_owner() {
	ERR_FAIL_COND_V(!external_owner_mode || Thread::is_main_thread(), false);
	ExternalLifecycle expected = ExternalLifecycle::HANDOFF_QUIESCENT;
	if (!external_lifecycle.compare_exchange_strong(expected, ExternalLifecycle::OWNED_BY_S, std::memory_order_acq_rel)) {
		return false;
	}
	external_owner_thread.store(Thread::get_caller_id(), std::memory_order_release);
	return true;
}

void PhysicsServer2DWrapMT::external_begin_logic() {
	require_external_phase(ExternalPhase::QUERIES_FLUSHED);
	external_phase.store(ExternalPhase::LOGIC, std::memory_order_release);
}

void PhysicsServer2DWrapMT::external_begin_process() {
	// Original process callbacks and their timers query the state produced by
	// the preceding physics step. This phase performs no second sync or step.
	require_external_phase(ExternalPhase::IDLE);
	external_phase.store(ExternalPhase::PROCESS, std::memory_order_release);
}

void PhysicsServer2DWrapMT::external_end_process() {
	require_external_phase(ExternalPhase::PROCESS);
	external_phase.store(ExternalPhase::IDLE, std::memory_order_release);
}

bool PhysicsServer2DWrapMT::finish_external_unclaimed_bootstrap() {
	if (!external_owner_mode || !Thread::is_main_thread() || external_lifecycle.load(std::memory_order_acquire) != ExternalLifecycle::BOOTSTRAP_MAIN || external_owner_thread.load(std::memory_order_acquire) != Thread::UNASSIGNED_ID || external_phase.load(std::memory_order_acquire) != ExternalPhase::IDLE) {
		return false;
	}
	// No S was prepared or claimed. Original bootstrap operations belonged to
	// Main directly; no transition from HANDOFF_QUIESCENT/OWNED_BY_S is allowed.
	command_queue.flush_all();
	physics_server_2d->finish();
	external_lifecycle.store(ExternalLifecycle::FINISHED, std::memory_order_release);
	return true;
}

bool PhysicsServer2DWrapMT::release_external_owner() {
	ERR_FAIL_COND_V(!external_owner_mode || !is_external_owner_thread(), false);
	ERR_FAIL_COND_V(external_lifecycle.load() != ExternalLifecycle::OWNED_BY_S || external_phase.load() != ExternalPhase::IDLE, false);
	physics_server_2d->finish();
	external_owner_thread.store(Thread::UNASSIGNED_ID, std::memory_order_release);
	external_lifecycle.store(ExternalLifecycle::FINISHED, std::memory_order_release);
	return true;
}

bool PhysicsServer2DWrapMT::is_external_owner_server(const PhysicsServer2D *p_server) {
	const PhysicsServer2DWrapMT *wrap = Object::cast_to<PhysicsServer2DWrapMT>(p_server);
	return wrap && wrap->is_external_owner_mode();
}

PhysicsServer2DWrapMT::PhysicsServer2DWrapMT(PhysicsServer2D *p_contained, bool p_create_thread, bool p_external_owner_mode) {
	external_owner_mode = p_external_owner_mode;
	CRASH_COND_MSG(external_owner_mode && p_create_thread, "External Physics2D cannot start the WrapMT pump.");
	physics_server_2d = p_contained;
	create_thread = p_create_thread;
}

PhysicsServer2DWrapMT::~PhysicsServer2DWrapMT() {
	CRASH_COND_MSG(external_owner_mode && !is_external_finished(), "External Physics2D must be finished by S and joined before destruction.");
	memdelete(physics_server_2d);
}
