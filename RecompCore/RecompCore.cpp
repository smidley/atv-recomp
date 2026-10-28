#include "RecompCore.h"

#include <array>
#include <numeric>

int32_t RTVRunNativeProbe(void) {
    const std::array<int32_t, 4> values{6, 9, 12, 15};
    return std::accumulate(values.begin(), values.end(), int32_t{0});
}

RTVClearColor RTVGetClearColor(uint32_t paletteIndex) {
    constexpr std::array<RTVClearColor, 3> palette{{
        {0.04, 0.35, 0.46, 1.0},
        {0.36, 0.12, 0.48, 1.0},
        {0.50, 0.23, 0.05, 1.0},
    }};
    return palette[paletteIndex % palette.size()];
}
