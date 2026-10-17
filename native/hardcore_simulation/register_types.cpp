#include "register_types.h"

#include "core/object/class_db.h"
#include "simulation_host.h"
#include "gameplay_global_random_binding.h"
#include "main_source_deferred.h"
#include "content_value_graph.h"
#include "simulation_world_2d.h"
#include "resource_observation.h"
#include "crowd_geometry_owner.h"
#include "pursuit_planning_owner.h"
#ifdef DEBUG_ENABLED
#include "transport_probe.h"
#endif

void initialize_hardcore_simulation_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    ClassDB::register_class<HardCoreSimulationTimer>();
    ClassDB::register_class<HardCoreSimulationHost>();
    ClassDB::register_class<HardCoreGameplayGlobalRandom>();
    ClassDB::register_class<HardCoreMainSourceDeferred>();
    ClassDB::register_class<HardCoreContentValueGraph>();
    ClassDB::register_class<HardCoreSimulationActorMotion2D>();
    ClassDB::register_class<HardCoreSimulationWorld2D>();
    ClassDB::register_class<HardCoreResourceObservation>();
    ClassDB::register_class<HardCoreCrowdGeometry>();
    ClassDB::register_class<HardCorePursuitPlanning>();
#ifdef DEBUG_ENABLED
    ClassDB::register_class<HardCoreMulticoreProbe>();
#endif
}

void uninitialize_hardcore_simulation_module(ModuleInitializationLevel p_level) {
    // The module owns no singleton or background thread at initialization.
    // Runtime hosts must close their own session before engine teardown.
}
