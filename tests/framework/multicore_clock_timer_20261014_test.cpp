#include "../../native/hardcore_simulation/simulation_clock.h"

#include <cmath>
#include <functional>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

using namespace hardcore::simulation;
using Clock = SimulationClock;
using Phase = Clock::Phase;
using Domain = TimerLedger::Domain;

#define CHECK(test) do { if (!(test)) throw std::runtime_error(#test); } while (false)
static bool near(double a, double b) { return std::abs(a - b) < 1e-12; }

struct Consumer final : Clock::Hooks {
	uint64_t now = 0;
	double scale = 1;
	bool paused = false;
	std::vector<uint64_t> fired;
	std::vector<Phase> phases;
	std::vector<Clock::ClockFrame> h_frames, p_frames;
	std::function<void(const TimerLedger::Timer &)> timeout;
	std::function<void(Phase, const Clock::ClockFrame &)> phase;
	uint64_t now_usec() const override { return now; }
	double sample_time_scale() const override { return scale; }
	bool is_paused() const override { return paused; }
	void on_timeout(const TimerLedger::Timer &timer) override {
		fired.push_back(timer.continuation_token);
		if (timeout) timeout(timer);
	}
	void on_phase(Phase p, const Clock::ClockFrame &f) override {
		phases.push_back(p);
		if (p == Phase::H_GROUP) h_frames.push_back(f);
		if (p == Phase::P_GROUP) p_frames.push_back(f);
		if (phase) phase(p, f);
	}
};

static TimerLedger::TimerId add(TimerLedger &timers, double seconds, uint64_t token,
		Domain domain = Domain::P, bool always = true, bool ignore_scale = false) {
	const auto result = timers.create(seconds, {always, domain, ignore_scale}, token);
	CHECK(result.status == TimerLedger::CreateStatus::ACCEPTED);
	return result.id;
}

// Catches an EDF heap, create-time zero emission, epsilon expiry and loss of
// the synchronous continuation's ability to mutate a later list element.
static void insertion_zero_and_exact_subtraction() {
	TimerLedger timers(16); Consumer c;
	const auto first = add(timers, .5, 11);
	const auto later = add(timers, .125, 12);
	CHECK(c.fired.empty());
	c.timeout = [&](const auto &t) {
		if (t.id == first) CHECK(timers.set_time_left(later, .5));
	};
	CHECK(timers.sweep(Domain::P, .5, .5, c).fired == 2);
	CHECK((c.fired == std::vector<uint64_t>{11, 12}));
	add(timers, 0, 13);
	CHECK(c.fired.size() == 2);
	CHECK(timers.sweep(Domain::H, 0, 0, c).fired == 0);
	CHECK(timers.sweep(Domain::P, 0, 0, c).fired == 1);
	add(timers, std::nextafter(.125, 1.0), 14);
	CHECK(timers.sweep(Domain::P, .125, .125, c).fired == 0);
	CHECK(timers.sweep(Domain::P, .125, .125, c).fired == 1);
}

// Catches scanning newly appended timeout children and the incorrect rule
// that every timer-created timer has to wait an entire epoch.
static void original_tail_and_cross_domain_creation() {
	TimerLedger timers(16); Consumer c;
	add(timers, 0, 1, Domain::H);
	add(timers, 0, 2, Domain::P);
	c.timeout = [&](const auto &t) {
		if (t.continuation_token == 1) add(timers, 0, 3, Domain::P);
		if (t.continuation_token == 2) {
			add(timers, 0, 4, Domain::P);
			add(timers, 0, 5, Domain::H);
		}
	};
	CHECK(timers.sweep(Domain::H, .01, .01, c).fired == 1);
	CHECK(timers.sweep(Domain::P, .01, .01, c).fired == 2);
	CHECK((c.fired == std::vector<uint64_t>{1, 2, 3}));
	CHECK(timers.size() == 2);
	timers.sweep(Domain::H, .01, .01, c);
	timers.sweep(Domain::P, .01, .01, c);
	CHECK((c.fired == std::vector<uint64_t>{1, 2, 3, 5, 4}));
}

// Catches sampling pause/flags once for the whole scan instead of per timer.
static void pause_and_later_flags_observe_synchronous_callbacks() {
	TimerLedger timers(16); Consumer c;
	add(timers, 0, 1);
	const auto paused_timer = add(timers, .02, 2, Domain::P, false);
	add(timers, 0, 3);
	const auto edited = add(timers, .02, 4, Domain::P, false);
	c.timeout = [&](const auto &t) {
		if (t.continuation_token == 1) c.paused = true;
		if (t.continuation_token == 3) {
			c.paused = false;
			CHECK(timers.set_flags(edited, {false, Domain::P, true}));
		}
	};
	timers.sweep(Domain::P, .01, .02, c);
	CHECK((c.fired == std::vector<uint64_t>{1, 3, 4}));
	TimerLedger::Timer remaining;
	CHECK(timers.read(paused_timer, remaining) && remaining.time_left == .02);
	timers.sweep(Domain::P, .02, .02, c);
	CHECK(c.fired.back() == 2);
}

static void pause_scale_zero_and_ignore_scale_are_distinct() {
	TimerLedger timers(16); Consumer c; c.paused = true;
	const auto windup = add(timers, .025, 1, Domain::P, false);
	const auto death = add(timers, .8, 2);
	add(timers, .1, 3, Domain::P, true, true);
	add(timers, 0, 4, Domain::P, false);
	add(timers, 0, 5);
	timers.sweep(Domain::P, 0, .1, c);
	CHECK((c.fired == std::vector<uint64_t>{3, 5}));
	c.paused = false;
	timers.sweep(Domain::P, 0, .1, c);
	CHECK(c.fired.back() == 4);
	TimerLedger::Timer value;
	CHECK(timers.read(windup, value) && value.time_left == .025);
	CHECK(timers.read(death, value) && value.time_left == .8);
	c.paused = true;
	timers.sweep(Domain::P, .8, .8, c);
	CHECK(c.fired.back() == 2);
	CHECK(timers.read(windup, value) && value.time_left == .025);
}

static void fixed_epochs_keep_h_p_pairs_and_input_cutoffs() {
	TimerLedger timers(32); Consumer c; c.now = 30000;
	Clock clock({100, 4, 0}, c, timers);
	std::vector<int> samples;
	int input = 1;
	c.phase = [&](Phase p, const auto &f) {
		if (p == Phase::H_INPUT) samples.push_back(input);
		if (p == Phase::H_STEP) ++input;
		if (p == Phase::P_INPUT) samples.push_back(input);
		if (p == Phase::P_GROUP) add(timers, .01, 100 + f.epoch);
	};
	const auto result = clock.run_turn();
	CHECK(result.fault.code == Clock::FaultCode::NONE && result.epochs_serviced == 3);
	CHECK((samples == std::vector<int>{1, 2, 2, 3, 3, 4}));
	CHECK((c.fired == std::vector<uint64_t>{101, 102, 103}));
	const std::vector<Phase> expected{Phase::U_BEGIN, Phase::H_INPUT, Phase::H_PREPARE,
		Phase::H_GROUP, Phase::H_AFTER_TIMERS, Phase::H_STEP, Phase::P_INPUT,
		Phase::P_GROUP, Phase::P_AFTER_TIMERS, Phase::U_END, Phase::PUBLISH};
	CHECK(c.phases.size() == 33);
	for (size_t i = 0; i < c.phases.size(); ++i) CHECK(c.phases[i] == expected[i % 11]);
	CHECK(near(clock.simulation_elapsed(), .03));
	CHECK(result.late_starts == 2 && result.deadline_misses == 1);
	CHECK(result.next_release_usec == 40000 && result.pending_epochs == 0);
}

static void epoch_scale_is_fixed_but_pause_is_live() {
	TimerLedger timers(16); Consumer c; c.now = 10000;
	Clock clock({100, 4, 0}, c, timers);
	c.phase = [&](Phase p, const auto &) {
		if (p == Phase::H_GROUP) { c.scale = 0; c.paused = true; }
		if (p == Phase::P_GROUP) add(timers, 0, 1, Domain::P, false);
	};
	clock.run_turn();
	CHECK(c.h_frames.size() == 1 && c.p_frames.size() == 1);
	CHECK(c.h_frames[0].delta.scaled == .01 && c.p_frames[0].delta.scaled == .01);
	CHECK(c.fired.empty() && clock.simulation_elapsed() == 0);
	c.phase = nullptr; c.paused = false; c.now = 20000;
	clock.run_turn();
	CHECK(c.h_frames[1].delta.scaled == 0 && c.p_frames[1].delta.scaled == 0);
	CHECK((c.fired == std::vector<uint64_t>{1}));
	CHECK(clock.simulation_elapsed() == 0);
}

// Consumer resolves individual continuations to original IDs and checks old
// life/world/combat conditions. The clock/ledger cannot cancel older actions.
static void accepted_releases_survive_retarget_but_obey_original_lifecycle() {
	struct Release { std::string id; int world; int life; int combat; };
	const std::vector<Release> releases{{"original/A", 2, 5, 7}, {"original/B", 2, 5, 7},
		{"old/world", 1, 5, 7}, {"old/life", 2, 4, 7}, {"old/combat", 2, 5, 6}};
	TimerLedger timers(16); Consumer c; c.now = 10000;
	Clock clock({100, 4, 0}, c, timers);
	std::vector<std::string> emitted;
	uint64_t current_action = 0;
	c.timeout = [&](const auto &t) {
		const auto &r = releases.at(static_cast<size_t>(t.continuation_token));
		if (r.world == 2 && r.life == 5 && r.combat == 7) emitted.push_back(r.id);
	};
	c.phase = [&](Phase p, const auto &f) {
		if (p == Phase::P_GROUP && f.epoch == 1) {
			for (uint64_t i = 0; i < releases.size(); ++i) add(timers, .025, i, Domain::P, false);
			current_action = 999; // Replacement does not edit previous obligations.
		}
	};
	clock.run_turn(); CHECK(emitted.empty());
	c.now = 20000; clock.run_turn(); CHECK(emitted.empty());
	c.now = 30000; clock.run_turn();
	CHECK(current_action == 999);
	CHECK((emitted == std::vector<std::string>{"original/A", "original/B"}));
	CHECK(timers.size() == 0);
}

static void replay_zero_one_multi_h_preserves_raw_clipped_fields() {
	TimerLedger timers(16); Consumer c;
	Clock clock({100, 4, 0, Clock::Mode::TRACE_REPLAY}, c, timers);
	const Clock::Delta h{.01, .01, .02, .09};
	const Clock::Delta p{.09, .03, .06, .09};
	add(timers, .08, 1, Domain::H, true, true);
	add(timers, .08, 2, Domain::P, true, true);
	CHECK(clock.replay_iteration({2, {}, p}).epochs_serviced == 1);
	CHECK(c.h_frames.empty() && c.p_frames.size() == 1);
	CHECK((c.fired == std::vector<uint64_t>{2}));
	CHECK(clock.simulation_elapsed() == 0);
	clock.replay_iteration({2, {h}, p});
	CHECK(c.fired.back() == 1 && c.h_frames.size() == 1);
	clock.replay_iteration({2, {h, h}, p});
	CHECK(c.h_frames.size() == 3 && c.p_frames.size() == 3);
	CHECK(near(clock.simulation_elapsed(), .06));
	CHECK(c.p_frames[2].delta.raw == .09 && c.p_frames[2].delta.clipped == .03);
	CHECK(c.p_frames[2].delta.scaled == .06 && c.p_frames[2].delta.unscaled_timer == .09);
	CHECK(c.h_frames[2].h_ordinal == 1);
}

static void ongoing_heals_keep_individual_callbacks_at_p_ordinal() {
	TimerLedger timers(16); Consumer c;
	Clock clock({100, 4, 0, Clock::Mode::TRACE_REPLAY}, c, timers);
	double elapsed = .09;
	int hp = 0;
	std::vector<std::string> effects;
	c.phase = [&](Phase p, const auto &f) {
		if (p != Phase::P_GROUP) return;
		effects.push_back("skill_input");
		elapsed += f.delta.scaled;
		while (elapsed >= .1) {
			elapsed -= .1;
			++hp;
			effects.push_back("heal_" + std::to_string(hp));
			if (hp == 1) effects.push_back("first_heal_callback");
		}
	};
	clock.replay_iteration({1, {}, {.25, .25, .25, .25}});
	CHECK((effects == std::vector<std::string>{"skill_input", "heal_1", "first_heal_callback", "heal_2", "heal_3"}));
	CHECK(near(elapsed, .04));
}

static void receipt_wake_never_sweeps_zero_timers_or_reenters_commit() {
	TimerLedger timers(16); Consumer c; c.paused = true;
	Clock clock({100, 4, 0}, c, timers);
	add(timers, 0, 77);
	int commits = 0;
	c.phase = [&](Phase p, const auto &) {
		if (p != Phase::U_WAKE) return;
		++commits;
		CHECK(clock.service_receipts().code == Clock::FaultCode::REENTRANT);
		CHECK(clock.run_turn().fault.code == Clock::FaultCode::REENTRANT);
	};
	CHECK(clock.service_receipts().code == Clock::FaultCode::NONE);
	CHECK(commits == 1 && c.fired.empty() && timers.size() == 1);
	CHECK(c.h_frames.empty() && c.p_frames.empty() && clock.next_epoch() == 1);
	c.phase = nullptr; c.now = 10000;
	c.timeout = [&](const auto &) { CHECK(clock.service_receipts().code == Clock::FaultCode::REENTRANT); };
	clock.run_turn(); CHECK(c.fired.back() == 77);
}

static void bounded_turn_retains_debt_and_overrun_keeps_timers_and_u() {
	TimerLedger timers(16); Consumer c; c.now = 40000;
	Clock clock({100, 4, 0}, c, timers);
	add(timers, 1, 1, Domain::P, false);
	c.phase = [&](Phase p, const auto &) { if (p == Phase::H_STEP) c.now += 10000; };
	const auto short_backlog = clock.run_turn();
	CHECK(short_backlog.epochs_serviced == 4 && short_backlog.pending_epochs == 4);
	CHECK(short_backlog.fault.code == Clock::FaultCode::NONE && clock.next_epoch() == 5);
	CHECK(c.h_frames.size() == 4 && c.p_frames.size() == 4);
	TimerLedger::Timer remaining;
	CHECK(timers.read(1, remaining) && near(remaining.time_left, .96));
	c.phase = nullptr; c.now = 90000;
	const auto fault = clock.run_turn();
	CHECK(fault.fault.code == Clock::FaultCode::CLOCK_OVERRUN);
	CHECK(fault.epochs_serviced == 4 && fault.pending_epochs == 1 && clock.next_epoch() == 9);
	CHECK(near(fault.fault.threshold_seconds, .04));
	CHECK(c.phases.back() == Phase::PUBLISH);
	CHECK(c.h_frames.size() == 8 && c.p_frames.size() == 8);
	CHECK(timers.read(1, remaining) && near(remaining.time_left, .92));
	CHECK(clock.service_receipts().code == Clock::FaultCode::NONE);
	CHECK(timers.size() == 1);
}

static void overrun_detected_after_complete_atomic_epoch() {
	TimerLedger timers(16); Consumer c; c.now = 10000;
	Clock clock({100, 4, 0}, c, timers);
	add(timers, .03, 1);
	c.phase = [&](Phase p, const auto &) { if (p == Phase::H_GROUP) c.now = 60000; };
	const auto result = clock.run_turn();
	CHECK(result.fault.code == Clock::FaultCode::CLOCK_OVERRUN);
	CHECK(result.epochs_serviced == 4 && result.pending_epochs == 2);
	CHECK(c.h_frames.size() == 4 && c.p_frames.size() == 4 && clock.next_epoch() == 5);
	CHECK(result.deadline_misses == 4);
	CHECK((c.fired == std::vector<uint64_t>{1}) && timers.size() == 0);
}

static void absolute_release_no_rounding_drift_and_suspend_no_catchup() {
	TimerLedger timers(16); Consumer c;
	Clock fractional({60, 8, 7}, c, timers);
	CHECK(fractional.release_usec(1) == 16674);
	CHECK(fractional.release_usec(2) == 33341);
	CHECK(fractional.release_usec(60) == 1000007);
	CHECK(fractional.release_usec(6000) == 100000007);
	CHECK(fractional.release_usec(60000000) == 1000000000007ULL);
	Clock clock({100, 4, 0}, c, timers);
	add(timers, .02, 1);
	c.now = 10000; clock.run_turn();
	CHECK(clock.suspend(10000).code == Clock::FaultCode::NONE);
	c.now = 1000000;
	CHECK(clock.run_turn().suspended && c.p_frames.size() == 1);
	CHECK(clock.resume(1000000).code == Clock::FaultCode::NONE);
	CHECK(clock.run_turn().epochs_serviced == 0);
	c.now = 1010000;
	CHECK(clock.run_turn().epochs_serviced == 1 && c.fired.back() == 1);
	CHECK(near(clock.simulation_elapsed(), .02));
}

static void suspension_preserves_preexisting_debt() {
	TimerLedger timers(16); Consumer c;
	Clock clock({100, 4, 0}, c, timers);
	CHECK(clock.suspend(20000).code == Clock::FaultCode::NONE);
	CHECK(clock.resume(1020000).code == Clock::FaultCode::NONE);
	c.now = 1020000;
	const auto result = clock.run_turn();
	CHECK(result.epochs_serviced == 2 && result.pending_epochs == 0);
	CHECK(clock.next_epoch() == 3 && result.next_release_usec == 1030000);
}

static void invalid_reentrant_and_capacity_fail_explicitly_without_loss() {
	TimerLedger timers(2); Consumer c;
	add(timers, 0, 1); add(timers, 0, 2);
	CHECK(timers.create(1, {}, 3).status == TimerLedger::CreateStatus::CAPACITY);
	CHECK(timers.create(std::numeric_limits<double>::quiet_NaN(), {}, 4).status == TimerLedger::CreateStatus::INVALID);
	c.timeout = [&](const auto &) {
		CHECK(timers.sweep(Domain::P, 0, 0, c).status == TimerLedger::SweepStatus::REENTRANT);
	};
	CHECK(timers.sweep(Domain::P, -.01, .01, c).status == TimerLedger::SweepStatus::INVALID);
	CHECK(timers.size() == 2);
	timers.sweep(Domain::P, 0, 0, c);
	CHECK((c.fired == std::vector<uint64_t>{1, 2}));
	Clock invalid({0, 4, 0}, c, timers);
	CHECK(invalid.run_turn().fault.code == Clock::FaultCode::INVALID);
	Clock clock({100, 4, 0}, c, timers);
	CHECK(clock.replay_iteration({}).fault.code == Clock::FaultCode::INVALID);
	c.now = 10000; clock.run_turn(); c.now = 9000;
	CHECK(clock.run_turn().fault.code == Clock::FaultCode::INVALID);
	CHECK(clock.next_epoch() == 2);
}

static void same_epoch_h_p_tail_and_u_end_creation_boundaries() {
	TimerLedger timers(32); Consumer c; c.now = 10000;
	Clock clock({100, 4, 0}, c, timers);
	c.timeout = [&](const auto &t) {
		if (t.continuation_token == 1) {
			add(timers, .01, 3, Domain::H);
			add(timers, .01, 4, Domain::P);
		}
		if (t.continuation_token == 2) add(timers, .01, 6, Domain::P);
	};
	c.phase = [&](Phase p, const auto &f) {
		if (f.epoch != 1) return;
		if (p == Phase::H_GROUP) {
			add(timers, .01, 1, Domain::H);
			add(timers, .01, 2, Domain::P);
		}
		if (p == Phase::H_STEP) CHECK((c.fired == std::vector<uint64_t>{1}));
		if (p == Phase::P_GROUP) add(timers, .01, 5, Domain::P);
		if (p == Phase::U_END) add(timers, .01, 7, Domain::P);
	};
	clock.run_turn();
	CHECK((c.fired == std::vector<uint64_t>{1, 2, 4, 5}));
	CHECK(timers.size() == 3);
	c.now = 20000; clock.run_turn();
	CHECK((c.fired == std::vector<uint64_t>{1, 2, 4, 5, 3, 6, 7}));
}

static void fractional_wakeup_and_one_budget_per_epoch() {
	TimerLedger timers(16); Consumer c;
	Clock clock({60, 4, 0}, c, timers);
	int budget_resets = 0;
	c.phase = [&](Phase p, const auto &) { if (p == Phase::U_BEGIN) ++budget_resets; };
	c.now = 16666;
	CHECK(clock.run_turn().epochs_serviced == 0 && budget_resets == 0);
	clock.service_receipts(); CHECK(budget_resets == 0);
	c.now = 16667;
	CHECK(clock.run_turn().epochs_serviced == 1 && budget_resets == 1);
	CHECK(c.h_frames[0].delta.raw == 1.0 / 60 && c.p_frames[0].delta.scaled == 1.0 / 60);
	c.now = 66667;
	CHECK(clock.run_turn().epochs_serviced == 3 && budget_resets == 4);
	CHECK(c.h_frames.size() == 4 && c.p_frames.size() == 4);
	CHECK(near(clock.simulation_elapsed(), 4.0 / 60));
}

static void invalid_trace_validates_all_fields_before_callbacks() {
	TimerLedger timers(16); Consumer c;
	Clock clock({100, 4, 0, Clock::Mode::TRACE_REPLAY}, c, timers);
	add(timers, .02, 1);
	const Clock::Delta h{.01, .01, .01, .01};
	const Clock::Delta invalid{.01, .01, .01, std::numeric_limits<double>::infinity()};
	CHECK(clock.replay_iteration({1, {h, invalid}, h}).fault.code == Clock::FaultCode::INVALID);
	CHECK(c.phases.empty() && clock.next_epoch() == 1 && timers.size() == 1);
	CHECK(clock.replay_iteration({1, {h}, h}).epochs_serviced == 1);
	TimerLedger::Timer remaining;
	CHECK(timers.read(1, remaining) && remaining.time_left == .01);
}

int main() {
	const std::pair<const char *, void (*)()> tests[] = {
		{"insertion_zero_and_exact_subtraction", insertion_zero_and_exact_subtraction},
		{"original_tail_and_cross_domain_creation", original_tail_and_cross_domain_creation},
		{"pause_and_later_flags_observe_synchronous_callbacks", pause_and_later_flags_observe_synchronous_callbacks},
		{"pause_scale_zero_and_ignore_scale_are_distinct", pause_scale_zero_and_ignore_scale_are_distinct},
		{"fixed_epochs_keep_h_p_pairs_and_input_cutoffs", fixed_epochs_keep_h_p_pairs_and_input_cutoffs},
		{"epoch_scale_is_fixed_but_pause_is_live", epoch_scale_is_fixed_but_pause_is_live},
		{"accepted_releases_survive_retarget_but_obey_original_lifecycle", accepted_releases_survive_retarget_but_obey_original_lifecycle},
		{"replay_zero_one_multi_h_preserves_raw_clipped_fields", replay_zero_one_multi_h_preserves_raw_clipped_fields},
		{"ongoing_heals_keep_individual_callbacks_at_p_ordinal", ongoing_heals_keep_individual_callbacks_at_p_ordinal},
		{"receipt_wake_never_sweeps_zero_timers_or_reenters_commit", receipt_wake_never_sweeps_zero_timers_or_reenters_commit},
		{"bounded_turn_retains_debt_and_overrun_keeps_timers_and_u", bounded_turn_retains_debt_and_overrun_keeps_timers_and_u},
		{"overrun_detected_after_complete_atomic_epoch", overrun_detected_after_complete_atomic_epoch},
		{"absolute_release_no_rounding_drift_and_suspend_no_catchup", absolute_release_no_rounding_drift_and_suspend_no_catchup},
		{"suspension_preserves_preexisting_debt", suspension_preserves_preexisting_debt},
		{"invalid_reentrant_and_capacity_fail_explicitly_without_loss", invalid_reentrant_and_capacity_fail_explicitly_without_loss},
		{"same_epoch_h_p_tail_and_u_end_creation_boundaries", same_epoch_h_p_tail_and_u_end_creation_boundaries},
		{"fractional_wakeup_and_one_budget_per_epoch", fractional_wakeup_and_one_budget_per_epoch},
		{"invalid_trace_validates_all_fields_before_callbacks", invalid_trace_validates_all_fields_before_callbacks},
	};
	int failed = 0;
	for (const auto &test : tests) {
		try { test.second(); std::cout << "PASS " << test.first << '\n'; }
		catch (const std::exception &e) { ++failed; std::cout << "FAIL " << test.first << ": " << e.what() << '\n'; }
	}
	std::cout << "RESULT " << (failed ? "FAIL" : "PASS") << " cases=" << std::size(tests) << " failed=" << failed << '\n';
	return failed ? 1 : 0;
}
