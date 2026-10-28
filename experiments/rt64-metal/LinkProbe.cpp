#include "rhi/rt64_render_interface.h"

namespace RT64 {
std::unique_ptr<RenderInterface> CreateMetalInterface();
}

// Cross-linked only. Calling the factory forces the real backend translation
// unit and its vtables to resolve. This executable is not a simulator app/test.
int main() {
    auto interface = RT64::CreateMetalInterface();
    return interface ? 0 : 1;
}
