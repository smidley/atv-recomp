#include <new>
#include <string>
#include <unordered_set>
#include "port/Game.h"
#include "engine/World.h"

extern "C" int NativecadeSpaghettiMain(int argc, char **argv);
extern std::unordered_set<std::string> gModifiedGfxSet; // engine/tracks/Track.cpp

// Mario Kart expects a new process for each start, so its own startup does not rebuild these
// C++ globals. Nativecade starts it again in one process: rebuild them when a game ends,
// while its context and resources still exist.
int NativecadeRunMarioKart(int argc, char **argv) {
    int status = NativecadeSpaghettiMain(argc, argv);
    World *world = GetWorld();
    world->~World();
    new (world) World();
    gEditor.~Editor();
    new (&gEditor) TrackEditor::Editor();
    gItemRegistry.Clear();
    gItemTableRegistry.Clear();
    gModifiedGfxSet.clear();
    return status;
}
