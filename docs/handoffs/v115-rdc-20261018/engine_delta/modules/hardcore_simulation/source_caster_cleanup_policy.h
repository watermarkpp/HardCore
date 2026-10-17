#pragma once
#include <string_view>
namespace hardcore::simulation {
inline constexpr bool is_original_caster_cleanup_operation(std::string_view operation) {
 return operation == "retire_cast" || operation == "discard_visual" || operation == "source_interactable::retire"
  || operation == "source_caster_warm::retire" || operation == "source_caster_warm::loading_claim_retire";
}
}
