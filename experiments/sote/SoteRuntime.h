#pragma once
#include <stdbool.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// False with a message when this app build has no Shadows of the Empire: SotE-Recomp wasn't
// prepared on the Mac that built it (scripts/prepare-sote.py).
__attribute__((visibility("default"))) bool NativecadePrepareShadowsOfTheEmpire(const char *romPath,
    const char *expectedSHA1, char *error, size_t errorCapacity);
#ifdef __cplusplus
}
#endif
