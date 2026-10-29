#pragma once
#include <cstdint>

namespace RecompTV {
// Preserve the absolute cadence across small timer wake-up delays. A long
// stall resets the cadence instead of generating a burst of catch-up frames.
inline int64_t PacingAnchor(int64_t now, int64_t deadline, int64_t interval, bool slept) {
    return slept && now >= deadline && now - deadline < interval / 2 ? deadline : now;
}
} // namespace RecompTV
