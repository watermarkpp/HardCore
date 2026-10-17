#pragma once

#include "physics_port.h"
#include "servers/physics_2d/physics_server_2d_wrap_mt.h"

namespace hardcore::simulation {

// Engine-module implementation. This is compiled with the pinned Godot
// source; it is deliberately unavailable to ordinary GDExtension builds.
class GodotPhysicsBackend final : public PhysicsPort::Backend {
public:
	explicit GodotPhysicsBackend(PhysicsServer2DWrapMT &server) : server_(server) {}
	bool claim_owner() override { return server_.claim_external_owner(); }
	bool release_owner() override { return server_.release_external_owner(); }
	void sync() override { server_.sync(); }
	void flush_queries() override { server_.flush_queries(); }
	void begin_logic() override { server_.external_begin_logic(); }
	void end_sync() override { server_.end_sync(); }
	void step(double delta) override { server_.step((real_t)delta); }

private:
	PhysicsServer2DWrapMT &server_;
};

} // namespace hardcore::simulation
