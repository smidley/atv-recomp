#include "BridgeProbe.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static void require(int condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(EXIT_FAILURE);
    }
}

int main(void) {
    // This translation unit is compiled as C, then linked to the C++ object.
    // This catches accidental C++ name mangling or a non-C-compatible header.
    require(RTVBridgeAdd(19, 23) == 42, "known bridge result");
    require(RTVBridgeAdd(0, 0) == 0, "zero inputs");
    require(RTVBridgeAdd(UINT32_MAX, 1) == 0, "documented unsigned wrap");
    require(RTVTestColorCount() == 3, "three test colors");

    for (uint32_t index = 0; index < 3; ++index) {
        RTVColor color = RTVTestColor(index);
        require(color.red == (index == 2 ? 1.0 : 0.0), "red component crosses C ABI");
        require(color.green == (index == 1 ? 1.0 : 0.0), "green component crosses C ABI");
        require(color.blue == (index == 0 ? 1.0 : 0.0), "blue component crosses C ABI");
        require(color.alpha == 1.0, "opaque alpha crosses C ABI");
    }
    RTVColor wrapped = RTVTestColor(3);
    require(wrapped.blue == 1.0 && wrapped.red == 0.0, "index wraps to blue");
    RTVColor maximum = RTVTestColor(UINT32_MAX);
    require(maximum.blue == 1.0, "large index is bounded");
    puts("PASS: C consumer linked to C++ probe; arithmetic and RGBA ABI checks passed.");
    return EXIT_SUCCESS;
}
