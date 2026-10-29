#pragma once
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// UI callbacks run on the main thread. Preparation is synchronous and must run
// away from the main actor; it never reads network credentials or touches saves.
int NativecadeRunApplication(int argc, char **argv, void (*showLibrary)(void), void (*hideLibrary)(void));
bool NativecadePrepareGame(const char *romPath, const char *expectedSHA1, char *error, size_t errorCapacity);
double NativecadePreparationProgress(void);
bool NativecadeLaunchPreparedGame(void);

#ifdef __cplusplus
}
#endif
