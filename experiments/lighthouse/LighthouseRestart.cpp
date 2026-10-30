int NativecadeLighthouseMain(int argc, char **argv); // Lighthouse's main, renamed in CMakeLists.txt
// Added to Lighthouse's Game.cpp and OS layer by scripts/prepare-lighthouse.py.
extern "C" void NativecadeLighthouseResetGame(void);
extern "C" void NativecadeLighthouseResetThreads(void);
extern "C" void NativecadeLighthouseResetRcp(void);
extern "C" void NativecadeLighthouseResetTimers(void);

// Runs Banjo-Kazooie for one start. Lighthouse expects a new process for each start; C++ state
// that its own startup does not rebuild is reset here when a game ends (docs/GAME_SWITCHING.md).
int NativecadeRunBanjoKazooie(int argc, char **argv) {
    const int result = NativecadeLighthouseMain(argc, argv);
    NativecadeLighthouseResetGame();
    NativecadeLighthouseResetThreads();
    NativecadeLighthouseResetRcp();
    NativecadeLighthouseResetTimers();
    return result;
}
