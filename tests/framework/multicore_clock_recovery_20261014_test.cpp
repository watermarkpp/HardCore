#include "../../native/hardcore_simulation/simulation_clock.h"
#include <iostream>
#include <stdexcept>

using Clock = hardcore::simulation::SimulationClock;
using Ledger = hardcore::simulation::TimerLedger;
#define CHECK(v) do { if (!(v)) throw std::runtime_error(#v); } while (false)
struct Hooks final : Clock::Hooks {
    uint64_t now = 90000;
    int h = 0, p = 0, timeouts = 0;
    uint64_t now_usec() const override { return now; }
    double sample_time_scale() const override { return 1; }
    bool is_paused() const override { return false; }
    void on_timeout(const Ledger::Timer &) override { ++timeouts; }
    void on_phase(Clock::Phase phase, const Clock::ClockFrame &) override {
        if (phase == Clock::Phase::H_GROUP) ++h;
        if (phase == Clock::Phase::P_GROUP) { ++p; CHECK(h == p); }
    }
};
int main() {
    try {
        Hooks hooks;
        Ledger timers(4);
        CHECK(timers.create(.06, {}, 1).status == Ledger::CreateStatus::ACCEPTED);
        Clock clock({100, 4, 0}, hooks, timers);
        const auto first = clock.run_turn();
        CHECK(first.fault.code == Clock::FaultCode::CLOCK_OVERRUN);
        CHECK(first.epochs_serviced == 4 && first.pending_epochs == 5);
        CHECK(clock.next_epoch() == 5 && hooks.h == 4 && hooks.p == 4);
        CHECK(hooks.timeouts == 0); // No timeout was fast-forwarded to wall time.
        const auto second = clock.run_turn();
        CHECK(second.epochs_serviced == 4 && second.pending_epochs == 1);
        CHECK(clock.next_epoch() == 9 && hooks.h == 8 && hooks.p == 8);
        CHECK(hooks.timeouts == 1);
        const auto third = clock.run_turn();
        CHECK(third.epochs_serviced == 1 && third.pending_epochs == 0);
        CHECK(clock.next_epoch() == 10 && hooks.h == 9 && hooks.p == 9);
        CHECK(clock.release_usec(10) == 100000); // No origin rebase or dropped debt.
        CHECK(clock.run_turn().epochs_serviced == 0);
        std::cout << "PASS bounded_clock_recovery keeps nine pairs, timer timing and absolute origin\n";
        return 0;
    } catch (const std::exception &e) {
        std::cout << "FAIL bounded_clock_recovery " << e.what() << '\n';
        return 1;
    }
}
