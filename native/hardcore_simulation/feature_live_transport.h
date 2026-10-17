#pragma once
#include "core/variant/array.h"
#include "core/string/string_name.h"
#include "core/variant/variant.h"
namespace hardcore::simulation {
bool feature_live_arguments(const StringName&,const Array&);
bool feature_live_result(const StringName&,const Variant&);
bool feature_live_cleanup_opcode(const StringName&,const Array&);
}
