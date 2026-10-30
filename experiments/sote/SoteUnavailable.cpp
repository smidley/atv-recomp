// The framework built without Shadows of the Empire's code: in CI, or on a Mac that hasn't
// generated it from the player's ROM (scripts/generate-sote-code.sh).
#include <cstdio>
#include "SoteRuntime.h"

bool NativecadePrepareShadowsOfTheEmpire(const char *, const char *, char *error, size_t capacity) {
    if (error && capacity)
        snprintf(error, capacity, "This build of Nativecade doesn't include Shadows of the Empire. "
            "Its code is generated from your ROM on the Mac that builds the app.");
    return false;
}
