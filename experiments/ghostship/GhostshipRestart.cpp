int NativecadeGhostshipMain(int argc, char **argv); // Ghostship's main, renamed in CMakeLists.txt

// Runs Super Mario 64 for one start. Ghostship expects a new process for each start; C++ state
// that its own startup does not rebuild must be reset here when a game ends (docs/GAME_SWITCHING.md).
int NativecadeRunSuperMario(int argc, char **argv) {
    return NativecadeGhostshipMain(argc, argv);
}
