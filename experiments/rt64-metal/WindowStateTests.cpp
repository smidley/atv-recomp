#include "TVWindow.hpp"

#include <atomic>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <thread>

static void require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "Window adapter check failed: %s\n", message);
        std::exit(EXIT_FAILURE);
    }
}

int main() {
    RecompTV::WindowState state;
    TVWindow window(&state);
    TVWindowAttributes attributes;
    window.getWindowAttributes(&attributes);
    require(attributes.width == 0 && attributes.height == 0 && window.getRefreshRate() == 0,
            "unavailable surface has no invented size or refresh rate");
    require(state.update(1920, 1080, 60), "accept initial drawable metrics");
    window.getWindowAttributes(&attributes);
    require(attributes.width == 1920 && attributes.height == 1080 && window.getRefreshRate() == 60,
            "forward app-provided pixels and refresh rate");
    require(state.update(1280, 720, 50), "accept resize and refresh change");
    window.toggleFullscreen();
    window.getWindowAttributes(&attributes);
    require(attributes.width == 1280 && attributes.height == 720 && window.getRefreshRate() == 50,
            "fullscreen request does not alter host-owned metrics");
    require(!state.update(UINT32_MAX, 720, 50), "reject width overflow");
    require(!state.update(1280, UINT32_MAX, 50), "reject height overflow");
    require(!state.update(1280, 720, UINT32_MAX), "reject refresh overflow");
    require(state.snapshot().width == 1280, "invalid update preserves state");
    require(state.update(0, 0, 0), "accept suspended surface");

    // Renderer reads must not observe dimensions from two different UI updates.
    std::atomic<bool> coherent{true};
    std::thread writer([&] {
        for (uint32_t i = 1; i <= 20000; ++i) {
            state.update(i, i * 2, i * 3);
        }
    });
    std::thread reader([&] {
        for (int i = 0; i < 20000; ++i) {
            const auto sample = state.snapshot();
            if (sample.height != sample.width * 2 || sample.refreshRate != sample.width * 3) {
                coherent = false;
            }
        }
    });
    writer.join();
    reader.join();
    require(coherent, "coherent snapshots across app/render threads");

    bool rejected = false;
    try { TVWindow invalid(nullptr); }
    catch (const std::invalid_argument&) { rejected = true; }
    require(rejected, "reject a missing host state");
    std::puts("RT64 window adapter checks passed.");
}
