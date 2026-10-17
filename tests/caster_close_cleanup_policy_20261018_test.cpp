#include "source_caster_cleanup_policy.h"
#include "source_event_reply_mailbox.h"
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <thread>
#include <vector>

using Box = hardcore::simulation::SourceEventReplyMailbox;
using Status = Box::Status;
using hardcore::simulation::is_original_caster_cleanup_operation;

int main() {
 int checks = 0, failures = 0;
 auto check = [&](bool value, const char *label) {
  ++checks;
  if (!value) { ++failures; std::cout << "FAIL " << label << '\n'; }
 };
 const char *cleanup[] = {"retire_cast", "discard_visual", "source_interactable::retire",
  "source_caster_warm::retire", "source_caster_warm::loading_claim_retire"};
 const char *ordinary[] = {"", "unknown", "create_visual_model", "bind_projectile", "bind_ground",
  "redraw_cast", "prepare_projectile_visual", "prepare_ground_visual", "create_fire_wall_cell",
  "activate_fire_wall_cells", "synchronize_fire_wall_cells", "refresh_cell_lifetime", "monster_audio",
  "source_interactable::spawn_npc", "source_interactable::spawn_portal", "source_interactable::face_npc",
  "source_caster_warm::collect_admit", "source_caster_warm::loading_state",
  "source_caster_warm::retire_extra", "SOURCE_CASTER_WARM::RETIRE"};
 for (const char *name : cleanup) check(is_original_caster_cleanup_operation(name), name);
 for (const char *name : ordinary) check(!is_original_caster_cleanup_operation(name), name);

 // Actual mailbox and two real owners. The CV is test synchronization only;
 // it substitutes no engine, Main receipt, Source retirement or policy result.
 Box box(115, 8, 64, 64);
 const Box::Bytes event = std::make_shared<const std::vector<uint8_t>>(std::initializer_list<uint8_t>{1, 2});
 const Box::Bytes prefix = std::make_shared<const std::vector<uint8_t>>(std::initializer_list<uint8_t>{3, 4});
 const Box::Bytes reply = std::make_shared<const std::vector<uint8_t>>(std::initializer_list<uint8_t>{5, 6});
 std::mutex mutex;
 std::condition_variable cv;
 int stage = 0;
 std::vector<Box::Identity> accepted;
 std::thread source([&] {
  check(box.bind_owner(), "actual Source thread binds once");
  Box::Identity original{115, 7, 1};
  check(box.reserve(original, event, false) == Status::READY, "ordinary pre-close reservation");
  check(box.accept(original, event, prefix) == Status::READY, "ordinary pre-close actual append acceptance");
  accepted.push_back(original);
  box.request_close();
  check(box.reserve(original, event, false) == Status::READY, "close retains same previously accepted ordinary event");
  check(box.reserve({115, 7, 2}, event, false) == Status::INVALID, "close refuses new ordinary work");
  uint64_t ordinal = 3;
  for (const char *name : cleanup) {
   const Box::Identity id{115, 7, ordinal++};
   const Status reserved = box.reserve(id, event, is_original_caster_cleanup_operation(name));
   check(reserved == Status::READY, name);
   if (reserved == Status::READY) {
    check(box.accept(id, event, prefix) == Status::READY, "actual cleanup append accepted after close");
    accepted.push_back(id);
   }
  }
  check(!box.can_close(), "accepted obligations prevent premature terminal");
  { std::lock_guard<std::mutex> lock(mutex); stage = 1; }
  cv.notify_one();
  { std::unique_lock<std::mutex> lock(mutex); cv.wait(lock, [&] { return stage == 2; }); }
  check(!box.can_close(), "real Main reply alone does not clear Source debt");
  for (const auto &id : accepted) {
   const auto result = box.poll(id);
   check(result.status == Status::READY && result.reply && *result.reply == *reply && result.retired,
    "Source observes the actual Main reply and zero-Node terminal fact");
   check(box.consume(id) == Status::READY, "Source consumes each real reply");
   check(box.retire(id) == Status::READY, "Source retires only after actual Main and Source completion");
  }
  check(box.can_close(), "all original and cleanup records are physically terminal");
 });
 { std::unique_lock<std::mutex> lock(mutex); cv.wait(lock, [&] { return stage == 1; }); }
 for (const auto &id : accepted) {
  check(box.claim(id, event) == Status::READY, "actual Main claims exact accepted event bytes");
  check(box.submit(id, reply, 0) == Status::READY, "actual Main submits immutable result and actual zero Node");
 }
 { std::lock_guard<std::mutex> lock(mutex); stage = 2; }
 cv.notify_one();
 source.join();
 std::cout << "CASTER_CLOSE_CLEANUP_POLICY_" << (failures ? "FAIL" : "PASS")
  << " checks=" << checks << " failures=" << failures << '\n';
 return failures ? 1 : 0;
}
