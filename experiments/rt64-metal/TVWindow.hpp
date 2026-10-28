#pragma once

#include <cstdint>
#include <mutex>

namespace RecompTV {
struct WindowSnapshot {
    int width = 0;
    int height = 0;
    int refreshRate = 0;
};

// The app supplies drawable pixels and the observed display refresh rate.
// Zero dimensions represent an unavailable surface; zero refresh means unknown.
class WindowState {
public:
    bool update(uint32_t width, uint32_t height, uint32_t refreshRate);
    WindowSnapshot snapshot() const;

private:
    mutable std::mutex mutex;
    WindowSnapshot value;
};
} // namespace RecompTV

// Adapter for RT64's existing swap-chain calls. RenderWindow.window must point
// to a WindowState that outlives the swap chain; RenderWindow.view is CAMetalLayer.
struct TVWindowAttributes {
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;
};

class TVWindow {
public:
    explicit TVWindow(void* state);
    void getWindowAttributes(TVWindowAttributes* attributes) const;
    int getRefreshRate() const;
    void toggleFullscreen();

private:
    RecompTV::WindowState& state;
};
