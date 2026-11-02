#pragma once
#include <stdbool.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// Verifies the imported Super Smash Bros. (USA) ROM, extracts BattleShip.o2r from it with Torch
// (cached per ROM, release and Torch revision) and installs the game for the next Play.
__attribute__((visibility("default"))) bool NativecadePrepareSuperSmashBros(const char *romPath, const char *expectedSHA1,
    char *error, size_t errorCapacity);
#ifdef __cplusplus
}
#endif
