#include "AppleTVPerformance.h"
#include <ship/Context.h>
#include <ship/config/ConsoleVariable.h>
#include <ship/config/Config.h>
#include <fast/Fast3dWindow.h>
#include <spdlog/spdlog.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <vector>

static void CollectVariableNames(const nlohmann::json& value, const std::string& prefix,
                                 std::vector<std::string>& names) {
    if (!prefix.empty()) names.push_back(prefix);
    if (!value.is_object()) return;
    for (const auto& [key, child] : value.items()) {
        CollectVariableNames(child, prefix.empty() ? key : prefix + "." + key, names);
    }
}

void RecompTVInitializePerformanceDefaults() {
    auto context = Ship::Context::GetRawInstance();
    auto vars = context->GetConsoleVariables();
    std::vector<std::string> names;
    const auto config = context->GetConfig()->GetNestedJson();
    if (config.contains("CVars")) CollectVariableNames(config.at("CVars"), "", names);
    const bool migrated = RecompTV::MigrateLegacySettings(*vars, names);
    const bool initialized = RecompTV::InitializePerformanceDefaults(*vars);
    if (migrated || initialized) vars->Save();
    std::fprintf(stderr, "[RecompTV] performance preset=%d fps=%d height=%d msaa=%d\n",
                 vars->GetInteger(RecompTV::kPreset, 0), vars->GetInteger("gSettings.InterpolationFPS", 20),
                 vars->GetInteger("gSettings.AdvancedResolution.VerticalPixelCount", 0),
                 vars->GetInteger("gSettings.MSAAValue", 1));
}

void RecompTVApplyPerformancePreset(RecompTV::PerformancePreset preset) {
    auto context = Ship::Context::GetRawInstance();
    auto vars = context->GetConsoleVariables();
    RecompTV::ApplyPerformancePreset(*vars, preset);
    if (auto window = std::dynamic_pointer_cast<Fast::Fast3dWindow>(context->GetWindow())) {
        window->SetResolutionMultiplier(1.0f);
        window->SetMsaaLevel(1);
        window->SetTextureFilter(Fast::FILTER_LINEAR);
        if (auto interpreter = window->GetInterpreterWeak().lock()) interpreter->ShaderCacheClear();
    }
    vars->Save();
}

int RecompTVGetFrameTarget(int requested, bool matchRefresh) {
    // SDL queries the display through the platform. Do not repeat that query
    // during every interpolation/menu update; still pick up display changes.
    using Clock = std::chrono::steady_clock;
    static auto nextRefresh = Clock::time_point::min();
    static int refreshRate = 60;
    const auto now = Clock::now();
    if (now >= nextRefresh) {
        refreshRate = Ship::Context::GetRawInstance()->GetWindow()->GetCurrentRefreshRate();
        nextRefresh = now + std::chrono::seconds(1);
    }
    return RecompTV::RenderFrameTarget(requested, refreshRate, matchRefresh);
}

void RecompTVRecordFrame(int targetFps) {
    static const bool enabled = [] {
        const char* value = std::getenv("RECOMPTV_PERF_LOG");
        return value && std::strcmp(value, "1") == 0;
    }();
    if (!enabled) return;

    using Clock = std::chrono::steady_clock;
    static auto previous = Clock::now();
    static std::array<double, 300> intervals{};
    static size_t count = 0;
    static int previousTarget = targetFps;
    const auto now = Clock::now();
    const double interval = std::chrono::duration<double, std::milli>(now - previous).count();
    previous = now;
    if (interval > 2000.0) {
        SPDLOG_INFO("[RecompTVPerf] gap_ms={:.2f} (long stall or app suspension)", interval);
    }
    if (previousTarget != targetFps || interval > 2000.0) {
        count = 0; // A target change or app suspension starts a new sample window.
        previousTarget = targetFps;
        return;
    }
    if (interval <= 0.01) return;
    intervals[count++] = interval;
    if (count < intervals.size()) return;

    double total = 0;
    int stalls = 0;
    for (double sample : intervals) {
        total += sample;
        if (sample > 100.0) ++stalls;
    }
    auto sorted = intervals;
    std::sort(sorted.begin(), sorted.end());
    uint32_t width = 0, height = 0;
    if (auto window = std::dynamic_pointer_cast<Fast::Fast3dWindow>(Ship::Context::GetRawInstance()->GetWindow())) {
        if (auto interpreter = window->GetInterpreterWeak().lock()) interpreter->GetCurDimensions(&width, &height);
    }
    SPDLOG_INFO("[RecompTVPerf] frames={} target={} render={}x{} avg_ms={:.2f} p95_ms={:.2f} max_ms={:.2f} over100ms={}",
                count, targetFps, width, height, total / count, sorted[284], sorted.back(), stalls);
    count = 0;
}
