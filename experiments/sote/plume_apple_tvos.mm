//
// tvOS replacement for plume's plume_apple.mm, which reads its window through AppKit and IOKit.
// prepare-sote.py copies it over that file. On tvOS, RenderWindow.window and RenderWindow.view
// are both the CAMetalLayer of the view that SDL_Metal_CreateView made.
//
// RT64 creates its swap chain on the graphics thread while N64ModernRuntime's main thread waits
// for it, so nothing here may wait for the main thread: the size comes from the layer itself,
// which Core Animation lets any thread read. The refresh rate is only read on the main thread;
// elsewhere it stays at the Apple TV's usual 60 Hz.
//

#include "plume_apple.h"

#include <cmath>

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

namespace plume {
    RenderDeviceVendor getRenderDeviceVendor(uint64_t) {
        return RenderDeviceVendor::APPLE;
    }

    static CocoaWindowAttributes readAttributes(void *windowHandle) {
        CALayer *layer = (__bridge CALayer *)windowHandle;
        const CGSize size = layer.bounds.size;
        const CGFloat scale = layer.contentsScale;
        return {0, 0, (int)std::round(size.width * scale), (int)std::round(size.height * scale)};
    }

    CocoaWindow::CocoaWindow(void *window)
        : windowHandle(window), cachedRefreshRate(60) {
        cachedAttributes = readAttributes(windowHandle);
        if ([NSThread isMainThread]) {
            cachedRefreshRate.store((int)UIScreen.mainScreen.maximumFramesPerSecond);
        }
    }

    CocoaWindow::~CocoaWindow() {}

    void CocoaWindow::updateWindowAttributesInternal(bool) {
        const CocoaWindowAttributes attributes = readAttributes(windowHandle);
        std::lock_guard<std::mutex> lock(attributesMutex);
        cachedAttributes = attributes;
    }

    void CocoaWindow::updateRefreshRateInternal(bool) {}

    void CocoaWindow::getWindowAttributes(CocoaWindowAttributes *attributes) const {
        const_cast<CocoaWindow *>(this)->updateWindowAttributesInternal(false);
        std::lock_guard<std::mutex> lock(attributesMutex);
        *attributes = cachedAttributes;
    }

    int CocoaWindow::getRefreshRate() const {
        return cachedRefreshRate.load();
    }

    // The app owns the whole screen on Apple TV.
    void CocoaWindow::toggleFullscreen() {}
}
