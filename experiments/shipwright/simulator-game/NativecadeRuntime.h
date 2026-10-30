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
// A bundled game shares SDL's one UIKit event loop and installs its own entry
// point only after successful preparation. Directory is private app storage.
bool NativecadeSetPreparedGameRunner(int (*runner)(int, char **), const char *dataDirectory);
// Removes a game's earlier preparations from PREPARED (Library/Caches/Nativecade/Prepared): the
// folders whose name starts like CURRENT up to its first hyphen, other than CURRENT. Ocarina's
// folders are named by release alone, so for it these are the other names without a hyphen.
void NativecadeRemoveOutdatedPreparations(const char *prepared, const char *current);

#ifdef __cplusplus
}
#endif
