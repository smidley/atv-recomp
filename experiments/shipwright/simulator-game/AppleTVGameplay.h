#pragma once
#include <filesystem>
#include <string>
#include <cstddef>
#include <cstdint>

void RecompTVInitializeSaveStorage(const char* root);
void RecompTVSaveWritten(const std::filesystem::path& path, const std::string& contents);
bool RecompTVDeleteSave(const std::filesystem::path& path);
void RecompTVBackupNow();
void RecompTVInitializeGameplayDefaults();
void RecompTVInitializeGameplay();
void RecompTVClearGameHooks();
void RecompTVGameplayFrame();
void RecompTVSetGameplayActive(bool active);
bool RecompTVControllerCanRumble(size_t port);
uint8_t RecompTVRumbleCommand(uint8_t requested);
void RecompTVTestRumble();
void RecompTVStopRumble();
void RecompTVShowBackupSetup();
void RecompTVShowBackupStatus();
void RecompTVShowRestoreBackups();
void RecompTVShowUndoRestore();
void RecompTVDisconnectBackups();
void RecompTVInstallLifecycleObservers();
