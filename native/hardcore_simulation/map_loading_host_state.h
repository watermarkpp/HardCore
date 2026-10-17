#pragma once
#include "map_loading_provenance.h"
#include "source_event_reply_mailbox.h"
#include <mutex>
namespace hardcore::simulation {
// At most one map continuation is admitted by the Source Map port. This is
// validation/accounting metadata only. The sole shared mailbox owns its packet.
struct MapLoadingHostState {
 using Replies=SourceEventReplyMailbox;using Bytes=Replies::Bytes;
 MapLoadingProvenance provenance;
 std::mutex facts_mutex;
 bool used=false,accepted=false;Replies::Identity identity;Bytes event,settlement;
 uint64_t submitted_usec=0,admission_epoch=0;
 std::atomic<uint64_t> claimed_usec{0},late_results{0};
 std::atomic<bool> late_recorded{false};
 Bytes last_settlement;Replies::Identity last_settlement_identity;
 // Exact retired finish, never a guessed map/build completion or Main phase.
 Bytes last_finish_event,last_finish_reply,last_finish_settlement;Replies::Identity last_finish_identity;
 struct Arrival {Bytes transaction,before,after,scope;uint64_t scope_id=0;};
 std::shared_ptr<const Arrival> arrival;
 struct Publication {Bytes scope,value,receipt;};
 std::shared_ptr<const Publication> publication;
 MapLoadingHostState(uint64_t generation,size_t capacity):provenance(generation,capacity){}
};
}
