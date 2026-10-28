#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <TargetConditionals.h>

#if !TARGET_OS_TV || !TARGET_OS_SIMULATOR
#error The API contract must target tvOS Simulator.
#endif

// Also check native declarations: metal-cpp's selectors do not diagnose availability.
void CheckShipwrightTVMetalContract(id<MTLDevice> device, CAMetalLayer* layer,
                                   id<MTLCommandBuffer> commands, id<CAMetalDrawable> drawable) {
    (void)MTLCreateSystemDefaultDevice();
    (void)[device supportsFamily:MTLGPUFamilyApple4];
    (void)layer.device;
    (void)layer.drawableSize;
    [commands presentDrawable:drawable];
}
