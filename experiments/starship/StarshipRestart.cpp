extern "C" int NativecadeStarshipMain(int argc, char **argv);
extern "C" void NativecadeStarshipReset(); // Added to Engine.cpp by scripts/prepare-starship.py

// Runs Star Fox for one start. Starship expects a new process for each start; C++ state that
// its own startup does not rebuild is reset here when a game ends (docs/GAME_SWITCHING.md).
int NativecadeRunStarFox(int argc, char **argv) {
    const int result = NativecadeStarshipMain(argc, argv);
    NativecadeStarshipReset();
    return result;
}
