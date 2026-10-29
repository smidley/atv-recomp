#include <TargetConditionals.h>
#if TARGET_OS_SIMULATOR
#include <SDL.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <libultraship.h>
extern "C" {
#include "main.h"
#include "menus.h"
}

static SDL_Joystick* testPad;
static Uint64 started;
static bool passed;

void NativecadeKartInputProbeInit() {
    const char* flag = std::getenv("NATIVECADE_KART_INPUT_PROBE");
    if (!flag || std::strcmp(flag, "1") != 0) return;
    if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) != 0 || SDL_NumJoysticks() != 0) return;
    SDL_VirtualJoystickDesc desc{};
    desc.version = SDL_VIRTUAL_JOYSTICK_DESC_VERSION;
    desc.type = SDL_JOYSTICK_TYPE_GAMECONTROLLER;
    desc.naxes = SDL_CONTROLLER_AXIS_MAX;
    desc.nbuttons = SDL_CONTROLLER_BUTTON_MAX;
    desc.axis_mask = (1u << SDL_CONTROLLER_AXIS_MAX) - 1;
    desc.button_mask = (1u << SDL_CONTROLLER_BUTTON_MAX) - 1;
    desc.name = "Nativecade Mario Kart integration test";
    int index = SDL_JoystickAttachVirtualEx(&desc);
    if (index >= 0) testPad = SDL_JoystickOpen(index);
    started = SDL_GetTicks64();
    std::fprintf(stderr, "[MarioKartInputProbe] virtual controller %s\n", testPad ? "attached" : "failed");
}

void NativecadeKartInputProbeTick() {
    if (!testPad) return;
    const auto elapsed = SDL_GetTicks64() - started;
    const bool racing = gGamestate == RACING && gDemoMode == 0;
    // Navigate the real game menus through its normal SDL controller path.
    // No game-state variables or ROM data are modified by this test.
    const bool pulse = elapsed > 12000 && elapsed < 55000 && elapsed % 1500 < 200;
    SDL_JoystickSetVirtualButton(testPad, SDL_CONTROLLER_BUTTON_A, elapsed < 65000 && (racing || pulse));
    SDL_JoystickSetVirtualButton(testPad, SDL_CONTROLLER_BUTTON_START, !racing && pulse);
    static int lastMenu = -999, lastState = -999;
    if (lastMenu != gMenuSelection || lastState != gGamestate) {
        std::fprintf(stderr, "[MarioKartInputProbe] state=%d menu=%d demo=%u\n", gGamestate, gMenuSelection, gDemoMode);
        lastMenu = gMenuSelection; lastState = gGamestate;
    }
    if (!passed && racing && gPlayerOne && gPlayerOne->speed > 1.0f) {
        passed = true;
        std::fprintf(stderr, "[MarioKartInputProbe] PASS: controller selected a race and accelerated (speed=%.2f).\n", gPlayerOne->speed);
    }
}
#else
void NativecadeKartInputProbeInit() {}
void NativecadeKartInputProbeTick() {}
#endif
