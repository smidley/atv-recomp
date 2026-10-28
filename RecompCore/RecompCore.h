#ifndef RECOMP_CORE_H
#define RECOMP_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// A C ABI keeps Swift independent of C++ implementation details.
typedef struct RTVClearColor {
    double red;
    double green;
    double blue;
    double alpha;
} RTVClearColor;

int32_t RTVRunNativeProbe(void);
RTVClearColor RTVGetClearColor(uint32_t paletteIndex);

#ifdef __cplusplus
}
#endif

#endif
