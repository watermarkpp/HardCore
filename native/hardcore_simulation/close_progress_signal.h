#pragma once
#include <atomic>
#include <condition_variable>
#include <cstdint>
namespace hardcore::simulation {
// Shared native wake/debt lifetime. W touches no Godot Object or Script.
struct CloseProgressSignal {
 std::atomic<uint64_t> revision{0},accepted_groups{0};
 std::condition_variable wake;
 void notify(){revision.fetch_add(1,std::memory_order_release);wake.notify_all();}
 static void formal_group_completed(void*data){static_cast<CloseProgressSignal*>(data)->notify();}
};
}
