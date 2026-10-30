#include "../metal/RumblePolicy.h"
#include <SDL.h>
#include <cstdio>

struct MotorProbe { uint16_t low = 0, high = 0; int calls = 0; };
static int MotorCommand(void* userdata, Uint16 low, Uint16 high) {
    auto& motor = *static_cast<MotorProbe*>(userdata);
    motor.low = low; motor.high = high; ++motor.calls;
    return 0;
}
bool RecompTVRunControllerProbe() {
    if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) != 0) return false;
    MotorProbe motor;
    SDL_VirtualJoystickDesc description{};
    description.version = SDL_VIRTUAL_JOYSTICK_DESC_VERSION;
    description.type = SDL_JOYSTICK_TYPE_GAMECONTROLLER;
    description.naxes = SDL_CONTROLLER_AXIS_MAX;
    description.nbuttons = SDL_CONTROLLER_BUTTON_MAX;
    description.name = "RecompTV test controller";
    description.userdata = &motor;
    description.Rumble = MotorCommand;
    const int index = SDL_JoystickAttachVirtualEx(&description);
    SDL_GameController* pad = index >= 0 ? SDL_GameControllerOpen(index) : nullptr;
    bool passed = pad && SDL_GameControllerHasRumble(pad);
    const uint16_t half = RecompTV::RumbleStrength(UINT16_MAX, 50, true);
    if (passed) {
        passed = half == 32767 && RecompTV::RumbleStrength(UINT16_MAX, 200, true) == UINT16_MAX &&
                 RecompTV::RumbleStrength(UINT16_MAX, -1, true) == 0 &&
                 RecompTV::RumbleStrength(UINT16_MAX, 100, false) == 0;
        passed &= SDL_GameControllerRumble(pad, half, half, RecompTV::kRumblePulseMs) == 0;
        passed &= motor.low == half && motor.high == half;
        SDL_Delay(RecompTV::kRumblePulseMs / 2);
        SDL_GameControllerRumble(pad, half, half, RecompTV::kRumblePulseMs);
        SDL_Delay(RecompTV::kRumblePulseMs / 2 + 20);
        SDL_JoystickUpdate();
        passed &= motor.low == half; // A repeated game command renews the pulse.
        SDL_Delay(RecompTV::kRumblePulseMs / 2 + 20);
        SDL_JoystickUpdate();
        passed &= motor.low == 0 && motor.high == 0;
        SDL_GameControllerRumble(pad, UINT16_MAX, UINT16_MAX, RecompTV::kRumblePulseMs);
        SDL_GameControllerRumble(pad, 0, 0, 0);
        passed &= motor.low == 0 && motor.high == 0; // An interruption stops immediately.
    }
    if (pad) SDL_GameControllerClose(pad);
    if (index >= 0) SDL_JoystickDetachVirtual(index);
    SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
    fprintf(stderr, "[RecompTVControllerTest] %s: strength, pulse renewal, expiration, immediate stop (virtual controller).\n", passed ? "PASS" : "FAIL");
    return passed;
}
