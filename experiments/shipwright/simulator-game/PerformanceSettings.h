#pragma once

#include <array>
#include <algorithm>
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>

namespace RecompTV {
enum class PerformancePreset : int32_t { Performance = 1, Sharper = 2, LowLoad = 3, Automatic = 4, Ultra = 5 };

inline int RenderFrameTarget(int requested, int refreshRate, bool matchRefresh) {
    const int limit = refreshRate > 0 ? std::clamp(refreshRate, 20, 60) : 60;
    return matchRefresh ? limit : std::clamp(requested, 20, limit);
}

// These are the pinned game's persisted keys, independent of CMake's cache.
inline constexpr const char* kPresetVersion = "gRecompTV.PerformancePresetVersion";
inline constexpr const char* kPreset = "gRecompTV.PerformancePreset";
inline constexpr const char* kNamespaceVersion = "gRecompTV.CVarNamespaceVersion";
inline constexpr const char* kAutomaticResolution = "gRecompTV.AutomaticResolution";
inline constexpr std::pair<std::string_view, std::string_view> kLegacyAliases[] = {
    {"gControllers", "gSettings.Controllers"}, {"gAdvancedResolution", "gSettings.AdvancedResolution"},
    {"gVsyncEnabled", "gSettings.VsyncEnabled"}, {"gZFightingMode", "gSettings.ZFightingMode"},
    {"gInternalResolution", "gSettings.InternalResolution"}, {"gMSAAValue", "gSettings.MSAAValue"},
    {"gSdlWindowedFullscreen", "gSettings.SdlWindowedFullscreen"}, {"gTextureFilter", "gSettings.TextureFilter"},
    {"gControlNav", "gSettings.ControlNav"}, {"gConsoleEnabled", "gOpenWindows.Console"},
    {"gControllerDisconnectedWindowEnabled", "gOpenWindows.ControllerDisconnected"},
    {"gControllerReorderingWindowEnabled", "gOpenWindows.ControllerReordering"},
    {"gGfxDebuggerEnabled", "gOpenWindows.GfxDebugger"}, {"gStatsEnabled", "gOpenWindows.Stats"},
    {"gEnableMultiViewports", "gSettings.EnableMultiViewports"}, {"gLowResMode", "gSettings.LowResMode"},
    {"gSimulatedInputLag", "gSettings.SimulatedInputLag"}, {"gOverlayFont", "gSettings.OverlayFont"},
    {"gOpenMenuBar", "gSettings.OpenMenuBar"}, {"gInterpolationFPS", "gSettings.InterpolationFPS"},
    {"gMatchRefreshRate", "gSettings.MatchRefreshRate"}
};

// Copy legacy values once, retaining the old keys and preferring an existing
// namespaced value. This also preserves custom controls from the earlier build.
template<class Variables, class Names>
bool MigrateLegacySettings(Variables& vars, const Names& names) {
    if (vars.Get(kNamespaceVersion)) return false;
    for (const auto& name : names) {
        const std::string_view source(name);
        for (const auto& [from, to] : kLegacyAliases) {
            if (source != from && !(source.starts_with(from) && source.size() > from.size() && source[from.size()] == '.')) continue;
            const std::string destination = std::string(to) + std::string(source.substr(from.size()));
            if (vars.Get(name.c_str()) && !vars.Get(destination.c_str())) vars.CopyVariable(name.c_str(), destination.c_str());
        }
    }
    vars.SetInteger(kNamespaceVersion, 1);
    return true;
}
inline constexpr std::array kGraphicsKeys = {
    kAutomaticResolution,
    "gSettings.InterpolationFPS", "gSettings.MatchRefreshRate", "gSettings.MSAAValue",
    "gSettings.InternalResolution", "gSettings.TextureFilter", "gSettings.VsyncEnabled",
    "gSettings.LowResMode", "gSettings.AdvancedResolution.Enabled",
    "gSettings.AdvancedResolution.VerticalResolutionToggle", "gSettings.AdvancedResolution.VerticalPixelCount",
    "gSettings.AdvancedResolution.AspectRatioX", "gSettings.AdvancedResolution.AspectRatioY",
    "gSettings.AdvancedResolution.PixelPerfectMode",
    "gInterpolationFPS", "gMatchRefreshRate", "gMSAAValue", "gInternalResolution",
    "gTextureFilter", "gVsyncEnabled", "gLowResMode", "gAdvancedResolution.Enabled",
    "gAdvancedResolution.VerticalResolutionToggle", "gAdvancedResolution.VerticalPixelCount",
    "gAdvancedResolution.AspectRatioX", "gAdvancedResolution.AspectRatioY", "gAdvancedResolution.PixelPerfectMode"
};

template<class Variables>
void ApplyPerformancePreset(Variables& vars, PerformancePreset preset) {
    vars.SetInteger("gSettings.InterpolationFPS", preset == PerformancePreset::LowLoad ? 30 : 60);
    vars.SetInteger("gSettings.MatchRefreshRate", 0);
    vars.SetInteger("gSettings.VsyncEnabled", 1);
    vars.SetInteger("gSettings.MSAAValue", 1); // One sample means anti-aliasing is off.
    vars.SetFloat("gSettings.InternalResolution", 1.0f);
    vars.SetInteger("gSettings.TextureFilter", 1); // Hardware bilinear filtering.
    vars.SetInteger("gSettings.LowResMode", 0);
    vars.SetInteger("gSettings.AdvancedResolution.Enabled", 1);
    vars.SetInteger("gSettings.AdvancedResolution.VerticalResolutionToggle", 1);
    vars.SetInteger("gSettings.AdvancedResolution.VerticalPixelCount",
                    preset == PerformancePreset::Automatic || preset == PerformancePreset::Ultra ? 2160 :
                    preset == PerformancePreset::Sharper ? 1080 : 720);
    vars.SetInteger("gSettings.AdvancedResolution.PixelPerfectMode", 0);
    vars.SetInteger(kPreset, static_cast<int32_t>(preset));
    vars.SetInteger(kAutomaticResolution, preset == PerformancePreset::Automatic ? 1 : 0);
    vars.SetInteger(kPresetVersion, 2);
}

// Never overwrite an existing custom graphics setup, including legacy settings.
// Explicit preset buttons may change graphics, but never saves or controller bindings.
template<class Variables>
bool InitializePerformanceDefaults(Variables& vars) {
    if (vars.Get(kPresetVersion)) return false;
    for (const auto* key : kGraphicsKeys) {
        if (vars.Get(key)) {
            vars.SetInteger(kPresetVersion, 2);
            return true;
        }
    }
    ApplyPerformancePreset(vars, PerformancePreset::Automatic);
    return true;
}
} // namespace RecompTV
