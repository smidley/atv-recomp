#pragma once
#include <stdbool.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// False with a message when this app build has no Cruis'n: navjack's setups weren't prepared on the
// Mac that built it (scripts/prepare-cruisn.py).
__attribute__((visibility("default"))) bool NativecadePrepareCruisnUSA(const char *romPath,
    const char *expectedSHA1, char *error, size_t errorCapacity);
__attribute__((visibility("default"))) bool NativecadePrepareCruisnWorld(const char *romPath,
    const char *expectedSHA1, char *error, size_t errorCapacity);
#ifdef __cplusplus
}
#endif
