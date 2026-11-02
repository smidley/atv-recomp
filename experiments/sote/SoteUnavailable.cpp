// The framework built without Shadows of the Empire: where the pinned SotE-Recomp wasn't prepared
// (scripts/prepare-sote.py).
#include <cstdio>
#include "SoteRuntime.h"

bool NativecadePrepareShadowsOfTheEmpire(const char *, const char *, char *error, size_t capacity) {
    if (error && capacity)
        snprintf(error, capacity, "This build of Nativecade doesn't include Shadows of the Empire. "
            "SotE-Recomp wasn't prepared on the Mac that built it.");
    return false;
}
