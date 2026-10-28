#include "fast/backends/gfx_metal.h"
#include <TargetConditionals.h>
#include <cstring>

#if !TARGET_OS_TV || !TARGET_OS_SIMULATOR
#error The fixture must target tvOS Simulator.
#endif

// Cross-linked only. This is not an app entry point or a rendered-frame test.
int main() {
    Fast::GfxRenderingAPIMetal renderer;
    return std::strcmp(renderer.GetName(), "Metal");
}
