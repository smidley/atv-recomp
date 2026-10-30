#include "PerformanceSettings.h"
#include "AdaptiveResolution.h"
#include "../metal/FramePacing.h"
#include <cassert>
#include <limits>
#include <map>
#include <string>
#include <variant>
#include <vector>

struct Variables {
    std::map<std::string, std::variant<int32_t, float>> values;
    bool Get(const char* key) const { return values.contains(key); }
    void SetInteger(const char* key, int32_t value) { values[key] = value; }
    void SetFloat(const char* key, float value) { values[key] = value; }
    void CopyVariable(const char* from, const char* to) { values[to] = values.at(from); }
    int32_t Integer(const char* key) const { return std::get<int32_t>(values.at(key)); }
};

int main() {
    assert(RecompTV::RenderFrameTarget(60, 50, false) == 50);
    assert(RecompTV::RenderFrameTarget(30, 50, false) == 30);
    assert(RecompTV::RenderFrameTarget(144, 120, false) == 60);
    assert(RecompTV::RenderFrameTarget(60, 0, false) == 60);
    assert(RecompTV::RenderFrameTarget(30, 50, true) == 50);
    assert(RecompTV::RenderFrameTarget(-1, 60, false) == 20);
    Variables fresh;
    fresh.SetInteger("gSettings.Controllers.Port1.Mapping", 42);
    fresh.SetInteger("gEnhancements.SkipIntro", 1);
    assert(RecompTV::InitializePerformanceDefaults(fresh));
    assert(fresh.Integer("gSettings.InterpolationFPS") == 60);
    assert(fresh.Integer("gSettings.AdvancedResolution.VerticalPixelCount") == 2160);
    assert(fresh.Integer(RecompTV::kAutomaticResolution) == 1);
    assert(fresh.Integer("gSettings.Controllers.Port1.Mapping") == 42);
    assert(fresh.Integer("gEnhancements.SkipIntro") == 1);

    Variables legacy;
    legacy.SetInteger("gControllers.Port1.Mapping", 7);
    legacy.SetInteger("gMSAAValue", 4);
    legacy.SetInteger("gSettings.MSAAValue", 2);
    legacy.SetInteger("gControllersOther", 99);
    std::vector<std::string> names = {"gControllers.Port1.Mapping", "gMSAAValue", "gControllersOther"};
    assert(RecompTV::MigrateLegacySettings(legacy, names));
    assert(legacy.Integer("gSettings.Controllers.Port1.Mapping") == 7);
    assert(legacy.Integer("gSettings.MSAAValue") == 2);
    assert(legacy.Integer("gControllers.Port1.Mapping") == 7);
    assert(!legacy.Get("gSettings.ControllersOther"));
    legacy.values.erase("gSettings.Controllers.Port1.Mapping");
    assert(!RecompTV::MigrateLegacySettings(legacy, names));
    assert(!legacy.Get("gSettings.Controllers.Port1.Mapping"));

    fresh.SetInteger("gSettings.InterpolationFPS", 40);
    auto edited = fresh.values;
    assert(!RecompTV::InitializePerformanceDefaults(fresh));
    assert(fresh.values == edited); // Later launches preserve manual changes.

    for (const auto* key : RecompTV::kGraphicsKeys) {
        Variables customized;
        customized.SetInteger(key, 2);
        auto expected = customized.values;
        expected[RecompTV::kPresetVersion] = int32_t{2};
        assert(RecompTV::InitializePerformanceDefaults(customized));
        assert(customized.values == expected); // Includes legacy settings and explicit zero/off values.
    }
    Variables disabled;
    disabled.SetInteger("gSettings.VsyncEnabled", 0);
    RecompTV::InitializePerformanceDefaults(disabled);
    assert(disabled.Integer("gSettings.VsyncEnabled") == 0);
    assert(!disabled.Get("gSettings.InterpolationFPS"));

    Variables previousRelease;
    previousRelease.SetInteger(RecompTV::kPresetVersion, 1);
    previousRelease.SetInteger("gSettings.AdvancedResolution.VerticalPixelCount", 720);
    const auto previousValues = previousRelease.values;
    assert(!RecompTV::InitializePerformanceDefaults(previousRelease));
    assert(previousRelease.values == previousValues);

    RecompTV::ApplyPerformancePreset(fresh, RecompTV::PerformancePreset::Sharper);
    assert(fresh.Integer("gSettings.AdvancedResolution.VerticalPixelCount") == 1080);
    assert(fresh.Integer("gSettings.InterpolationFPS") == 60);
    assert(fresh.Integer(RecompTV::kAutomaticResolution) == 0);
    RecompTV::ApplyPerformancePreset(fresh, RecompTV::PerformancePreset::Ultra);
    assert(fresh.Integer("gSettings.AdvancedResolution.VerticalPixelCount") == 2160);
    assert(fresh.Integer("gSettings.InterpolationFPS") == 60);
    assert(fresh.Integer(RecompTV::kAutomaticResolution) == 0);
    RecompTV::ApplyPerformancePreset(fresh, RecompTV::PerformancePreset::LowLoad);
    assert(fresh.Integer("gSettings.AdvancedResolution.VerticalPixelCount") == 720);
    assert(fresh.Integer("gSettings.InterpolationFPS") == 30);
    assert(fresh.Integer("gSettings.MSAAValue") == 1);
    assert(fresh.Integer("gSettings.Controllers.Port1.Mapping") == 42);
    assert(fresh.Integer("gEnhancements.SkipIntro") == 1);

    RecompTV::AdaptiveResolution resolution;
    resolution.Reset(2160, 60);
    // Occasional long frames must not blur an otherwise fast scene.
    for (int i = 0; i < 900; ++i) resolution.Observe(i % 45 == 0 ? 250 : 4, 2160);
    assert(resolution.Height() == 2160);
    // Sustained GPU load lowers one step, then waits before changing again.
    for (int i = 0; i < 120; ++i) resolution.Observe(18, 2160);
    assert(resolution.Height() == 1800);
    for (int i = 0; i < 500; ++i) resolution.Observe(1, 2160); // Stale in-flight data.
    assert(resolution.Height() == 1800);
    for (int i = 0; i < 300; ++i) resolution.Observe(4, 1800);
    assert(resolution.Height() == 2160); // Restores quality when headroom returns.
    for (int i = 0; i < 3000; ++i) resolution.Observe(35, resolution.Height());
    assert(resolution.Height() == 720);
    for (int i = 0; i < 100; ++i) {
        resolution.Observe(0, 720);
        resolution.Observe(std::numeric_limits<double>::quiet_NaN(), 720);
        resolution.Observe(3000, 720);
    }
    assert(resolution.Height() == 720);
    resolution.Reset(1080, 60);
    for (int i = 0; i < 1000; ++i) resolution.Observe(1, resolution.Height());
    assert(resolution.Height() == 1080); // Never supersample in Automatic.
    resolution.Reset(4320, 60);
    assert(resolution.Height() == 2160);
    resolution.Reset(0, 60);
    assert(resolution.Height() == 1080);
    resolution.Reset(480, 60);
    for (int i = 0; i < 1000; ++i) resolution.Observe(40, resolution.Height());
    assert(resolution.Height() == 480);
    resolution.Reset(2160, 50);
    for (int i = 0; i < 1000; ++i) resolution.Observe(17, 2160);
    assert(resolution.Height() == 2160); // Uses the actual display-rate budget.

    // Small wake-up delays must not accumulate into a 55 FPS timer cadence.
    constexpr int64_t interval = 166666;
    int64_t anchor = 0;
    for (int frame = 0; frame < 600; ++frame) {
        const int64_t deadline = anchor + interval;
        anchor = RecompTV::PacingAnchor(deadline + 15000, deadline, interval, true);
    }
    assert(anchor == 600 * interval);
    assert(RecompTV::PacingAnchor(500000, interval, interval, true) == 500000);
    assert(RecompTV::PacingAnchor(interval + 5000, interval, interval, false) == interval + 5000);
    assert(RecompTV::PacingAnchor(interval - 1000, interval, interval, true) == interval - 1000);
}
