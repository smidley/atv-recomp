#pragma once
#include <algorithm>
#include <array>
#include <cmath>

namespace RecompTV {
// GPU work only: CPU sleep, shader compilation and loading delays must not
// lower image quality. The caller supplies each completed frame once.
class AdaptiveResolution {
public:
    void Reset(int outputHeight, int targetFps) {
        ceiling = std::clamp(outputHeight > 0 ? outputHeight : 1080, 240, 2160);
        fps = std::clamp(targetFps, 20, 60);
        height = ceiling;
        count = highWindows = lowWindows = 0;
        cooldown = 60;
    }

    int Height() const { return height; }
    int Ceiling() const { return ceiling; }
    int TargetFps() const { return fps; }

    int Observe(double gpuMs, int renderedHeight) {
        if (renderedHeight != height) return height; // In-flight frames from the old size.
        if (!std::isfinite(gpuMs) || gpuMs <= 0 || gpuMs > 1000) {
            count = highWindows = lowWindows = 0;
            return height; // Missing timestamps, suspension or device errors.
        }
        if (cooldown > 0) {
            --cooldown;
            return height;
        }
        samples[count++] = gpuMs;
        if (count != samples.size()) return height;
        count = 0;
        const double budget = 1000.0 / fps;
        const int overBudget = std::count_if(samples.begin(), samples.end(),
                                            [budget](double ms) { return ms > budget * 0.9; });
        const int next = NextHigher();
        auto sorted = samples;
        std::sort(sorted.begin(), sorted.end());
        const double nextCost = sorted[53] * double(next) * next / (double(height) * height);
        highWindows = overBudget >= 45 ? highWindows + 1 : 0;
        lowWindows = next > height && nextCost < budget * 0.7 ? lowWindows + 1 : 0;
        int candidate = height;
        if (highWindows >= 2) candidate = NextLower();
        else if (lowWindows >= 4) candidate = next;
        if (candidate != height) {
            height = candidate;
            highWindows = lowWindows = 0;
            cooldown = 60; // Avoid oscillation and ignore allocation warm-up.
        }
        return height;
    }

private:
    static constexpr std::array levels{720, 1080, 1440, 1800, 2160};
    int NextLower() const {
        for (auto it = levels.rbegin(); it != levels.rend(); ++it) {
            if (*it < height) return *it;
        }
        return height;
    }
    int NextHigher() const {
        for (int level : levels) {
            if (level > height) return std::min(level, ceiling);
        }
        return ceiling;
    }
    int height = 1080, ceiling = 1080, fps = 60;
    int highWindows = 0, lowWindows = 0, cooldown = 0;
    size_t count = 0;
    std::array<double, 60> samples{};
};
} // namespace RecompTV
