// Standalone test of the actual production provenance register. No Host,
// Root, resource, physics or whole-game map acceptance is claimed here.
#include "../../native/hardcore_simulation/map_loading_provenance.h"
#include <future>
#include <iostream>
#include <thread>
#include <vector>

using Provenance=hardcore::simulation::MapLoadingProvenance;
static Provenance::Bytes bytes(uint8_t value){return std::make_shared<const std::vector<uint8_t>>(1,value);}
int main(){
 Provenance provenance(11516,4096);
 std::vector<bool> checks;
 checks.push_back(!provenance.bind_owner());
 checks.push_back(provenance.bind_main_owner(55));
 Provenance::Snapshot first{11516,1,55,1,913203,"actual-first-component",Provenance::State::LOADING,bytes(1),bytes(2),bytes(3)};
 checks.push_back(provenance.publish(first));
 checks.push_back(!provenance.read_owner());
 std::promise<void> arrived,main_retained,retained_observed,next_published,next_arrived,closed;
 auto arrived_ready=arrived.get_future();auto retained_ready=main_retained.get_future();
 auto retained_seen=retained_observed.get_future();auto next_ready=next_published.get_future();auto next_arrived_ready=next_arrived.get_future();auto closed_ready=closed.get_future();
 std::vector<bool> source_checks;
 auto retained=first;retained.state=Provenance::State::RETAINED;retained.scope_wire=bytes(4);
 auto next=first;next.scope=2;next.coordinator=2;next.map=910001;next.transition="actual-next-component";next.scope_wire=bytes(5);next.descriptor=bytes(6);next.world=bytes(7);
 std::thread source([&]{
  source_checks.push_back(provenance.bind_owner());
  source_checks.push_back(provenance.permits(first));
  auto changed=first;changed.map=910001;
  source_checks.push_back(!provenance.commit_arrival(changed));
  source_checks.push_back(provenance.permits(first));
  source_checks.push_back(provenance.commit_arrival(first));
  source_checks.push_back(!provenance.permits(first));
  source_checks.push_back(provenance.permits(first,true));
  source_checks.push_back(!provenance.commit_arrival(first));
  source_checks.push_back(first.world==provenance.read_owner()->world);
  arrived.set_value();retained_ready.wait();
  source_checks.push_back(!provenance.permits(first,true));
  source_checks.push_back(!provenance.permits(retained));
  source_checks.push_back(provenance.permits(retained,true));
  retained_observed.set_value();
  next_ready.wait();
  source_checks.push_back(!provenance.permits(retained,true));
  source_checks.push_back(provenance.permits(next));
  source_checks.push_back(!provenance.commit_arrival(first));
  source_checks.push_back(provenance.commit_arrival(next));
  source_checks.push_back(!provenance.permits(next));
  source_checks.push_back(provenance.permits(next,true));
  next_arrived.set_value();closed_ready.wait();
  source_checks.push_back(!provenance.permits(next,true));
 });
 arrived_ready.wait();
 checks.push_back(!provenance.commit_arrival(first));
 checks.push_back(provenance.publish(first)); // Exact Main replay does not reopen S build permission.
 checks.push_back(!provenance.certify_owner_closed(bytes(8)));
 checks.push_back(provenance.publish(retained));main_retained.set_value();retained_seen.wait();
 checks.push_back(provenance.publish(next));next_published.set_value();next_arrived_ready.wait();
 auto retained_next=next;retained_next.state=Provenance::State::RETAINED;retained_next.scope_wire=bytes(9);
 checks.push_back(provenance.publish(retained_next));
 checks.push_back(provenance.certify_owner_closed(bytes(10)));
 checks.push_back(provenance.can_close());closed.set_value();source.join();
 checks.insert(checks.end(),source_checks.begin(),source_checks.end());
 int failed=0;for(bool check:checks)if(!check)++failed;
 std::cout<<"{\"scope\":\"actual_production_MapLoadingProvenance_only\",\"checks\":"<<checks.size()<<",\"failed\":"<<failed<<",\"status\":\""<<(failed?"FAIL":"PASS")<<"\"}\n";
 return failed?1:0;
}
