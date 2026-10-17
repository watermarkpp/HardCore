#pragma once
#include "core/math/math_funcs.h"
// C++-only bridge. Host terminal proof must precede the single Main restore.
namespace Math {bool restore_default_random_handoff(const GlobalRandomHandoff &);}
