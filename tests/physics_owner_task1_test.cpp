#include "../native/hardcore_simulation/physics_port.h"
#include <cassert>
#include <limits>
#include <vector>
using namespace hardcore::simulation;
struct ProtocolBackend final : PhysicsPort::Backend {
	std::vector<int> calls;
	bool claim_owner() override { calls.push_back(0); return true; }
	bool release_owner() override { calls.push_back(6); return true; }
	void sync() override { calls.push_back(1); }
	void flush_queries() override { calls.push_back(2); }
	void begin_logic() override { calls.push_back(3); }
	void end_sync() override { calls.push_back(4); }
	void step(double) override { calls.push_back(5); }
};
int main() {
	ProtocolBackend backend;
	PhysicsPort port(backend);
	assert(!port.begin(0, 1.0 / 60));
	assert(!port.sync());
	assert(!port.shutdown());
	assert(backend.calls.empty());
	assert(port.start());
	assert(!port.start());
	assert(!port.begin(0, -1));
	assert(!port.begin(0, std::numeric_limits<double>::quiet_NaN()));
	assert(!port.begin(0, std::numeric_limits<double>::infinity()));
	for (uint64_t i = 0; i < 100; ++i) {
		assert(port.begin(i, i == 50 ? 0.0 : 1.0 / 60));
		assert(!port.flush_queries());
		assert(!port.finish());
		assert(port.sync());
		assert(!port.sync());
		assert(port.flush_queries());
		assert(!port.end_sync());
		assert(port.begin_logic());
		assert(!port.step());
		assert(port.end_sync());
		assert(!port.shutdown());
		assert(port.step());
		assert(port.finish());
		assert(!port.begin(i, 1.0 / 60));
	}
	assert(port.shutdown());
	assert(!port.shutdown());
	assert(!port.start());
	assert(!port.begin(100, 1.0 / 60));
	assert(backend.calls.size() == 502);
	assert(backend.calls.front() == 0 && backend.calls.back() == 6);
	for (size_t i = 1; i + 1 < backend.calls.size(); ++i) assert(backend.calls[i] == int((i - 1) % 5 + 1));
	return 0;
}
