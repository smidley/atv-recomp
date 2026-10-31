// The framework built without Cruis'n: where navjack's setups weren't prepared (scripts/prepare-cruisn.py).
#include <cstdio>
#include "CruisnRuntime.h"

static bool Unavailable(const char *title, char *error, size_t capacity) {
    if (error && capacity)
        snprintf(error, capacity, "This build of Nativecade doesn't include %s. "
            "Cruis'n wasn't prepared on the Mac that built it.", title);
    return false;
}

bool NativecadePrepareCruisnUSA(const char *, const char *, char *error, size_t capacity) {
    return Unavailable("Cruis'n USA", error, capacity);
}

bool NativecadePrepareCruisnWorld(const char *, const char *, char *error, size_t capacity) {
    return Unavailable("Cruis'n World", error, capacity);
}
