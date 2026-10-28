#ifndef RECOMPTV_BRIDGE_PROBE_H
#define RECOMPTV_BRIDGE_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// A deliberately small C ABI. No C++ objects or ownership cross into Swift.
// Addition follows uint32_t modulo-2^32 arithmetic.
uint32_t RTVBridgeAdd(uint32_t lhs, uint32_t rhs);

typedef struct RTVColor {
    double red;
    double green;
    double blue;
    double alpha;
} RTVColor;

uint32_t RTVTestColorCount(void);
// Indices wrap; each color is linear RGBA for an sRGB Metal render target.
RTVColor RTVTestColor(uint32_t index);

#ifdef __cplusplus
}
#endif

#endif
