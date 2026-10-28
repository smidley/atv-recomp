#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <TargetConditionals.h>

#if !TARGET_OS_TV
#error This API contract must compile against the tvOS SDK.
#endif

// metal-cpp sends Objective-C messages without SDK availability diagnostics.
// Also compile the native declarations used by the adapter with availability
// warnings promoted to errors, so C++ wrappers cannot hide an unavailable API.
void CheckTVMetalAPIContract(id<MTLDevice> device, CAMetalLayer* layer) {
    (void)MTLCreateSystemDefaultDevice();
    (void)device.argumentBuffersSupport;
    (void)[device supportsFamily:MTLGPUFamilyApple6];
    (void)[device supportsFamily:MTLGPUFamilyMac2];
    (void)layer.drawableSize;
}
