#include "PerformanceSettings.h"
#include <cassert>
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
    assert(fresh.Integer("gSettings.AdvancedResolution.VerticalPixelCount") == 720);
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
        expected[RecompTV::kPresetVersion] = int32_t{1};
        assert(RecompTV::InitializePerformanceDefaults(customized));
        assert(customized.values == expected); // Includes legacy settings and explicit zero/off values.
    }
    Variables disabled;
    disabled.SetInteger("gSettings.VsyncEnabled", 0);
    RecompTV::InitializePerformanceDefaults(disabled);
    assert(disabled.Integer("gSettings.VsyncEnabled") == 0);
    assert(!disabled.Get("gSettings.InterpolationFPS"));

    RecompTV::ApplyPerformancePreset(fresh, RecompTV::PerformancePreset::Sharper);
    assert(fresh.Integer("gSettings.AdvancedResolution.VerticalPixelCount") == 1080);
    assert(fresh.Integer("gSettings.InterpolationFPS") == 60);
    RecompTV::ApplyPerformancePreset(fresh, RecompTV::PerformancePreset::LowLoad);
    assert(fresh.Integer("gSettings.AdvancedResolution.VerticalPixelCount") == 720);
    assert(fresh.Integer("gSettings.InterpolationFPS") == 30);
    assert(fresh.Integer("gSettings.MSAAValue") == 1);
    assert(fresh.Integer("gSettings.Controllers.Port1.Mapping") == 42);
    assert(fresh.Integer("gEnhancements.SkipIntro") == 1);
}
