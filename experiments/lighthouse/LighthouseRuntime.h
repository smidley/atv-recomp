#pragma once
#include <stdbool.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
__attribute__((visibility("default"))) bool NativecadePrepareBanjoKazooie(const char *romPath, const char *expectedSHA1,
    char *error, size_t errorCapacity);
#ifdef __cplusplus
}
#endif
