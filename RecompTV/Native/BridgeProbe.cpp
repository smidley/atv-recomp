#include "BridgeProbe.h"

#include <array>

namespace {
constexpr std::array<RTVColor, 3> colors{{
    {0.0, 0.0, 1.0, 1.0},
    {0.0, 1.0, 0.0, 1.0},
    {1.0, 0.0, 0.0, 1.0},
}};
}

uint32_t RTVBridgeAdd(uint32_t lhs, uint32_t rhs) {
    return lhs + rhs;
}

uint32_t RTVTestColorCount(void) {
    return static_cast<uint32_t>(colors.size());
}

RTVColor RTVTestColor(uint32_t index) {
    return colors[index % colors.size()];
}
