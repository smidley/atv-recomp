// The framework built without Racer: where the pinned Racer wasn't prepared (scripts/prepare-racer.py).
#include <cstdio>
#include "RacerRuntime.h"

bool NativecadePrepareEpisodeOneRacer(const char *, const char *, char *error, size_t capacity) {
    if (error && capacity)
        snprintf(error, capacity, "This build of Nativecade doesn't include Star Wars Episode I: Racer. "
            "Racer wasn't prepared on the Mac that built it.");
    return false;
}
