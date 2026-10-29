#include "AppleTVGameplay.h"
#include "../metal/RumblePolicy.h"
#include <SDL.h>
#include <ship/Context.h>
#include <ship/config/ConsoleVariable.h>
#include <ship/controller/controldeck/ControlDeck.h>
#include "soh/SaveManager.h"
#include "soh/Notification/Notification.h"
#include "soh/Enhancements/game-interactor/GameInteractor.h"
#include <chrono>

using Clock = std::chrono::steady_clock;
static Clock::time_point testUntil{};

void RecompTVInitializeGameplayDefaults() {
    auto vars = Ship::Context::GetRawInstance()->GetConsoleVariables();
    bool changed = false;
    for (auto [name, value] : {std::pair{"gEnhancements.Autosave", 1},
                              {"gSettings.ControlNav", 1},
                              {"gSettings.AppleTV.RumbleEnabled", 1},
                              {"gSettings.AppleTV.RumbleStrength", 100}}) {
        if (!vars->Get(name)) { vars->SetInteger(name, value); changed = true; }
    }
    if (changed) vars->Save();
}

void RecompTVStopRumble() {
    testUntil = {};
    auto context = Ship::Context::GetRawInstance();
    if (!context || !context->GetControlDeck()) return;
    for (int port = 0; port < 4; ++port) {
        // Stop even if a user has just removed all mappings.
        for (auto [id, pad] : context->GetControlDeck()->GetConnectedPhysicalDeviceManager()->GetConnectedSDLGamepadsForPort(port))
            if (SDL_GameControllerHasRumble(pad)) SDL_GameControllerRumble(pad, 0, 0, 0);
    }
}

void RecompTVSetGameplayActive(bool active) {
    RecompTV::rumbleActive.store(active);
    if (!active) {
        RecompTVStopRumble();
        // Finish snapshots already queued by the game's save code before suspension.
        // Creating a new snapshot at an arbitrary UIKit interruption is unsafe.
        if (SaveManager::Instance) SaveManager::Instance->ThreadPoolWait();
    } else RecompTVBackupNow();
}

bool RecompTVControllerCanRumble(size_t port) {
    if (port >= 4 || !RecompTV::rumbleActive.load()) return false;
    auto deck = Ship::Context::GetRawInstance()->GetControlDeck();
    auto vars = Ship::Context::GetRawInstance()->GetConsoleVariables();
    if (!vars->GetInteger("gSettings.AppleTV.RumbleEnabled", 1) ||
        vars->GetInteger("gSettings.AppleTV.RumbleStrength", 100) <= 0 ||
        deck->GetControllerByPort(port)->GetRumble()->GetAllRumbleMappings().empty()) return false;
    for (auto [id, pad] : deck->GetConnectedPhysicalDeviceManager()->GetConnectedSDLGamepadsForPort(port))
        if (SDL_GameControllerHasRumble(pad)) return true;
    return false;
}

uint8_t RecompTVRumbleCommand(uint8_t requested) {
    if (!RecompTVControllerCanRumble(0)) return 0;
    return requested || Clock::now() < testUntil;
}

void RecompTVTestRumble() {
    if (!RecompTVControllerCanRumble(0)) {
        Notification::Emit({.message = "No controller with rumble is ready. Check its connection and rumble settings."});
        return;
    }
    testUntil = Clock::now() + std::chrono::milliseconds(500);
    Ship::Context::GetRawInstance()->GetControlDeck()->GetControllerByPort(0)->GetRumble()->StartRumble();
}

void RecompTVGameplayFrame() {
    static auto nextBackup = Clock::time_point::min();
    const auto now = Clock::now();
    if (now >= nextBackup) {
        RecompTVBackupNow();
        nextBackup = now + std::chrono::seconds(60);
    }
    if (testUntil != Clock::time_point{}) {
        if (now < testUntil && RecompTVControllerCanRumble(0))
            Ship::Context::GetRawInstance()->GetControlDeck()->GetControllerByPort(0)->GetRumble()->StartRumble();
        else RecompTVStopRumble();
    }
}

void RecompTVInitializeGameplay() {
    RecompTVInstallLifecycleObservers();
    GameInteractor::Instance->RegisterGameHook<GameInteractor::OnExitGame>([](int32_t) {
        RecompTVStopRumble();
        SaveManager::Instance->ThreadPoolWait();
        RecompTVBackupNow();
    });
}
