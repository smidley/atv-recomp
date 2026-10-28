#include "TVWindow.hpp"

#include <climits>
#include <stdexcept>

bool RecompTV::WindowState::update(uint32_t width, uint32_t height, uint32_t refreshRate) {
    if (width > INT_MAX || height > INT_MAX || refreshRate > INT_MAX) {
        return false;
    }
    std::lock_guard lock(mutex);
    value = {static_cast<int>(width), static_cast<int>(height), static_cast<int>(refreshRate)};
    return true;
}

RecompTV::WindowSnapshot RecompTV::WindowState::snapshot() const {
    std::lock_guard lock(mutex);
    return value;
}

namespace {
RecompTV::WindowState& requireState(void* pointer) {
    if (pointer == nullptr) {
        throw std::invalid_argument("RT64 requires an app-owned WindowState");
    }
    return *static_cast<RecompTV::WindowState*>(pointer);
}
}

TVWindow::TVWindow(void* pointer) : state(requireState(pointer)) {}

void TVWindow::getWindowAttributes(TVWindowAttributes* attributes) const {
    if (attributes == nullptr) {
        throw std::invalid_argument("Missing window attributes output");
    }
    const auto current = state.snapshot();
    *attributes = {0, 0, current.width, current.height};
}

int TVWindow::getRefreshRate() const {
    return state.snapshot().refreshRate;
}

void TVWindow::toggleFullscreen() {
    // tvOS window ownership stays with UIKit. No desktop fullscreen transition.
}
