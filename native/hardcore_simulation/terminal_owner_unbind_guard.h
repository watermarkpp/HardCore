#pragma once
#include <array>
#include <cstdint>
#include <thread>

namespace hardcore::simulation {
// Main-only one-shot binding retirement. Facts are produced by Host, never by
// the caller's Dictionary. This class owns no Object, cache, mailbox or cleanup.
class TerminalOwnerUnbindGuard {
public:
    enum class Fact : std::size_t {
        MAIN_THREAD, STARTED_PRODUCTION, CLOSE_REQUESTED, SOURCE_MODEL_CLOSED,
        QUIESCENT, JOINED, MAIN_JOIN_COMPLETED, PHYSICS_FINISHED, NO_RUNNING_OWNER,
        NO_FAULT, NO_SOURCE_OBJECTS, NO_WORKERS, ORIGINAL_MAILBOX_CLOSED,
        LIVE_MAILBOX_CLOSED, FEATURE_CLOSED, RESOURCE_VAULT_CLOSED,
        ADMISSION_DRAINED, CASTER_DRAINED, MAP_DRAINED, STOP_VERIFIED,
        INPUTS_DRAINED, BINDINGS_CURRENT, MAIN_DEBTS_DRAINED, COUNT
    };
    static constexpr std::size_t FACT_COUNT = static_cast<std::size_t>(Fact::COUNT);
    using OwnerIds = std::array<uint64_t, 9>;
    struct Facts {
        std::array<bool, FACT_COUNT> values{};
        void set(Fact f, bool value) { values[static_cast<std::size_t>(f)] = value; }
        uint64_t missing() const {
            uint64_t bits = 0;
            for (std::size_t i = 0; i < FACT_COUNT; ++i) if (!values[i]) bits |= uint64_t(1) << i;
            return bits;
        }
    };
    enum class Phase { BOUND, RETIRING, RETIRED };
    enum class Result { REJECTED, RETIRE_NOW, ALREADY_RETIRED, REENTRANT };
    TerminalOwnerUnbindGuard() : main_(std::this_thread::get_id()) {}
    TerminalOwnerUnbindGuard(const TerminalOwnerUnbindGuard &) = delete;
    TerminalOwnerUnbindGuard &operator=(const TerminalOwnerUnbindGuard &) = delete;
    Phase phase() const { return phase_; } // Main only.
    Result begin(const Facts &facts, const OwnerIds &ids) {
        if (std::this_thread::get_id() != main_) return Result::REJECTED;
        if (phase_ == Phase::RETIRING) return Result::REENTRANT;
        if (facts.missing() != 0 || !valid_ids(ids)) return Result::REJECTED;
        if (phase_ == Phase::RETIRED) return ids == ids_ ? Result::ALREADY_RETIRED : Result::REJECTED;
        ids_ = ids;
        phase_ = Phase::RETIRING;
        return Result::RETIRE_NOW;
    }
    bool commit() {
        if (std::this_thread::get_id() != main_ || phase_ != Phase::RETIRING) return false;
        phase_ = Phase::RETIRED;
        return true;
    }
private:
    static bool valid_ids(const OwnerIds &ids) {
        for (uint64_t id : ids) if (id == 0) return false;
        return ids[1] == ids[3]; // claim_feature / live_feature are one object.
    }
    const std::thread::id main_;
    Phase phase_ = Phase::BOUND;
    OwnerIds ids_{}; // Numeric evidence only; no strong owner references.
};
} // namespace hardcore::simulation
