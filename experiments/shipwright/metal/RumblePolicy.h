#pragma once
#include <algorithm>
#include <atomic>
#include <cstdint>

namespace RecompTV {
inline std::atomic_bool rumbleActive{true};
inline constexpr uint32_t kRumblePulseMs = 250;
inline uint16_t RumbleStrength(uint16_t motor, int percent, bool enabled) {
    return enabled ? uint16_t(uint32_t(motor) * std::clamp(percent, 0, 100) / 100) : 0;
}
}
