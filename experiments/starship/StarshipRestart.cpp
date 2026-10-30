extern "C" int NativecadeStarshipMain(int argc, char **argv);

// Runs Star Fox for one start. Starship expects a new process for each start; C++ state that
// its own startup does not rebuild is reset here when a game ends (docs/GAME_SWITCHING.md).
int NativecadeRunStarFox(int argc, char **argv) {
    return NativecadeStarshipMain(argc, argv);
}
