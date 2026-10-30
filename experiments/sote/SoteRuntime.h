#pragma once
#include <stdbool.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// False with a message when this app build has no Shadows of the Empire code: the code is
// generated from the player's ROM on the Mac that builds Nativecade (scripts/generate-sote-code.sh).
__attribute__((visibility("default"))) bool NativecadePrepareShadowsOfTheEmpire(const char *romPath,
    const char *expectedSHA1, char *error, size_t errorCapacity);
#ifdef __cplusplus
}
#endif
