// Starts Shadows of the Empire from Nativecade's library (docs/GAME_SWITCHING.md).
#include <cstdio>
int NativecadeSoteMain(int argc, char **argv); // SotE's main.cpp, renamed by CMakeLists.txt

int NativecadeRunShadowsOfTheEmpire(int, char **) {
    // SotE prints why it stops to stdout just before exiting; keep those lines when it's a file.
    setvbuf(stdout, nullptr, _IOLBF, 0);
    // SotE reads any argument as a ROM path; it finds the prepared ROM in the game folder instead.
    char name[] = "sote";
    char *arguments[] = {name, nullptr};
    return NativecadeSoteMain(1, arguments);
}
