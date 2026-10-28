#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import <TargetConditionals.h>
#include <SDL.h>
#include <SDL_main.h>
#include <SDL_system.h>
#include <imgui.h>
#include <imgui_impl_metal.h>
#include <fast/backends/gfx_metal.h>
#include <ship/Context.h>
#include <ship/resource/ResourceManager.h>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <iterator>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#if !TARGET_OS_TV || !TARGET_OS_SIMULATOR
#error This fixture is only for tvOS Simulator.
#endif

// The same registry entry point used by upstream Fast3dWindow.cpp.
namespace Fast { void GfxSetInstance(std::shared_ptr<Interpreter>); }

namespace {
constexpr int kCycles = 3;
SDL_Window* window = nullptr;
SDL_Renderer* sdlRenderer = nullptr;
std::unique_ptr<Fast::GfxRenderingAPIMetal> renderer;
std::shared_ptr<Fast::Interpreter> interpreter;
bool imguiMetalInitialized = false;
bool finished = false;
int cycle = 0;
int frame = 0;
int completedFrames = 0;
int destroyedRenderers = 0;
int width = 0;
int height = 0;
std::string deviceName;
std::vector<uint16_t> pixels;
std::vector<std::vector<uint16_t>> sampleReadbacks;

NSString* ResultPath() {
    NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [[NSFileManager defaultManager] createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:nil];
    return [documents stringByAppendingPathComponent:@"shipwright-render-result.json"];
}

void Report(const char* status, const std::string& detail) {
    const char* run = getenv("RECOMPTV_PROBE_RUN");
    NSMutableArray* samples = [NSMutableArray array];
    for (const auto& cycleSamples : sampleReadbacks) {
        NSMutableArray* values = [NSMutableArray array];
        for (uint16_t value : cycleSamples) [values addObject:@(value)];
        [samples addObject:values];
    }
    NSDictionary* report = @{
        @"schema_version": @1,
        @"run_id": run ? @(run) : @"manual",
        @"status": @(status),
        @"detail": @(detail.c_str()),
        @"backend": @"libultraship Metal",
        @"depth_clip_mode": @"clip (simulator fallback)",
        @"libultraship_revision": @"da6daf1a50a5e46d6641408d52227e31e85e46df",
        @"metal_device": @(deviceName.c_str()),
        @"completed_frames": @(completedFrames),
        @"verified_cycles": @(cycle),
        @"destroyed_renderers": @(destroyedRenderers),
        @"width": @(width), @"height": @(height),
        @"sample_colors": @[@"red", @"green", @"blue"],
        @"rgba5551_samples": samples,
        @"system_version": UIDevice.currentDevice.systemVersion
    };
    NSError* error = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
    if (!data || ![data writeToFile:ResultPath() options:NSDataWritingAtomic error:&error]) {
        fprintf(stderr, "error: Cannot write renderer report: %s\n", error.localizedDescription.UTF8String);
        abort();
    }
    fprintf(stdout, "RecompTV renderer: %s (%s)\n", status, detail.c_str());
    fflush(stdout);
}

void DestroyRenderer() {
    if (renderer) {
        renderer.reset(); // Drains its queues and releases owned Metal resources.
        ++destroyedRenderers;
    }
    if (imguiMetalInitialized) {
        ImGui_ImplMetal_Shutdown();
        imguiMetalInitialized = false;
    }
    if (ImGui::GetCurrentContext()) ImGui::DestroyContext();
}

void Finish(const char* status, const std::string& detail) {
    finished = true;
    if (window) SDL_iPhoneSetAnimationCallback(window, 1, nullptr, nullptr);
    DestroyRenderer();
    Fast::GfxSetInstance(nullptr);
    interpreter.reset();
    Ship::Context::DestroyInstance();
    Report(status, detail);
    // Keep SDL's surface visible for a simulator screenshot. The host then
    // terminates the process and starts a fresh run to test app relaunch.
}

void CreateRenderer() {
    Report("running", "Creating renderer for cycle " + std::to_string(cycle + 1));
    ImGui::CreateContext();
    ImGui::GetIO().IniFilename = nullptr;
    renderer = std::make_unique<Fast::GfxRenderingAPIMetal>();
    imguiMetalInitialized = renderer->MetalInit(sdlRenderer);
    if (!imguiMetalInitialized) throw std::runtime_error("libultraship Metal initialization failed");
    Report("running", "Initializing Metal depth shader");
    renderer->Init();
    // (0 - 0) * 0 + input1: one RGB vertex attribute, no textures or blending.
    Report("running", "Generating and compiling the triangle shader from the O2R template");
    auto* program = reinterpret_cast<Fast::ShaderProgramMetal*>(
        renderer->CreateAndLoadNewShader(uint64_t(SHADER_INPUT_1) << 12, 0));
    if (!program || program->numFloats != 7 || program->numInputs != 1 || !program->pipeline_state_variants[1]) {
        throw std::runtime_error("Generated triangle shader has an invalid layout or pipeline");
    }
    frame = 0;
}

void VerifyPixels() {
    // Interior and exterior samples check geometry and clear, not just a color
    // somewhere in the image. Changing color per cycle rejects stale readback.
    const std::array<std::pair<float, float>, 5> inside = {{{.5f, .5f}, {.5f, .2f}, {.3f, .7f}, {.7f, .7f}, {.5f, .8f}}};
    const std::array<std::pair<float, float>, 4> outside = {{{.02f, .02f}, {.98f, .02f}, {.02f, .98f}, {.98f, .98f}}};
    auto sample = [](const auto& point) {
        return pixels[size_t(int(point.second * height)) * width + int(point.first * width)];
    };
    for (const auto& point : inside) {
        uint16_t value = sample(point);
        int channels[] = {int((value >> 11) & 31), int((value >> 6) & 31), int((value >> 1) & 31)};
        for (int channel = 0; channel < 3; ++channel) {
            if ((channel == cycle && channels[channel] < 28) || (channel != cycle && channels[channel] > 2)) {
                throw std::runtime_error("Triangle pixel mismatch in cycle " + std::to_string(cycle + 1));
            }
        }
        if (!(value & 1)) throw std::runtime_error("Triangle alpha readback is not opaque");
    }
    for (const auto& point : outside) {
        if (sample(point) & 0xFFFE) throw std::runtime_error("Framebuffer clear pixel mismatch");
    }
    std::vector<uint16_t> evidence;
    for (const auto& point : inside) evidence.push_back(sample(point));
    for (const auto& point : outside) evidence.push_back(sample(point));
    sampleReadbacks.push_back(std::move(evidence));
}

void SDLCALL Tick(void*) {
    @autoreleasepool {
        if (finished || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        try {
            if (!renderer) CreateRenderer();
            int currentWidth = 0, currentHeight = 0;
            if (SDL_GetRendererOutputSize(sdlRenderer, &currentWidth, &currentHeight) != 0 ||
                currentWidth <= 0 || currentHeight <= 0 || currentWidth > 4096 || currentHeight > 4096) {
                throw std::runtime_error("Invalid simulator drawable dimensions");
            }
            if (frame && (currentWidth != width || currentHeight != height)) {
                throw std::runtime_error("Surface resized during the bounded readback fixture");
            }
            width = currentWidth;
            height = currentHeight;
            if (!frame) pixels.assign(size_t(width) * height, 0xA5A5);

            Report("running", "Starting triangle frame for cycle " + std::to_string(cycle + 1));
            renderer->StartFrame();
            renderer->NewFrame();
            renderer->StartDrawToFramebuffer(0, 1.0f);
            renderer->SetViewport(0, 0, width, height);
            renderer->SetScissor(0, 0, width, height);
            renderer->ClearFramebuffer(true, true);
            renderer->SetDepthTestAndMask(false, false);
            renderer->SetZmodeDecal(false);
            const float r = cycle == 0 ? 1.f : 0.f;
            const float g = cycle == 1 ? 1.f : 0.f;
            const float b = cycle == 2 ? 1.f : 0.f;
            float vertices[] = {
                -.8f, -.8f, .5f, 1.f, r, g, b,
                 .8f, -.8f, .5f, 1.f, r, g, b,
                  0.f, .8f, .5f, 1.f, r, g, b,
            };
            renderer->DrawTriangles(vertices, std::size(vertices), 1);
            renderer->ReadFramebufferToCPU(0, width, height, pixels.data());
            Report("running", "Submitting triangle frame and waiting for GPU completion");
            renderer->EndFrame();
            std::string gpuError;
            if (!renderer->WaitForFrame(gpuError)) throw std::runtime_error(gpuError);
            ++completedFrames;
            if (++frame < 2) return; // Screen readback arrives one frame later.
            VerifyPixels();
            ++cycle;
            DestroyRenderer();
            if (cycle == kCycles) Finish("passed", "Three renderer lifecycles passed GPU completion and pixel checks");
        } catch (const std::exception& error) {
            Finish("failed", error.what());
        }
    }
}

int RunProbe(int, char**) {
    @autoreleasepool {
        Report("running", "Checking simulator Metal device");
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            Finish("unavailable", "This tvOS Simulator host exposes no Metal device");
            return 0;
        }
        deviceName = device.name.UTF8String;
        try {
            SDL_SetHint(SDL_HINT_RENDER_DRIVER, "metal");
            if (SDL_Init(SDL_INIT_VIDEO) != 0) throw std::runtime_error(SDL_GetError());
            window = SDL_CreateWindow("Shipwright Metal probe", 0, 0, 960, 540,
                                      SDL_WINDOW_SHOWN | SDL_WINDOW_FULLSCREEN_DESKTOP | SDL_WINDOW_ALLOW_HIGHDPI);
            if (!window) throw std::runtime_error(SDL_GetError());
            sdlRenderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
            if (!sdlRenderer) throw std::runtime_error(SDL_GetError());
            CAMetalLayer* layer = (__bridge CAMetalLayer*)SDL_RenderGetMetalLayer(sdlRenderer);
            if (!layer || !layer.device) throw std::runtime_error("SDL did not provide a Metal layer/device");
            // This diagnostic reads the actual drawable; normal rendering should
            // leave framebufferOnly enabled when readback is unnecessary.
            layer.framebufferOnly = NO;

            NSString* archive = [NSBundle.mainBundle pathForResource:@"probe-shaders" ofType:@"o2r"];
            if (!archive) throw std::runtime_error("Pinned shader archive is missing from the app bundle");
            auto* context = Ship::Context::CreateUninitializedInstance("RecompTV Render Probe", "recomptv-probe", "probe.json");
            if (!context->InitConfiguration() || !context->InitConsoleVariables() ||
                !context->InitResourceManager({archive.UTF8String}, {}, 1, true) || !context->GetResourceManager()->IsLoaded()) {
                throw std::runtime_error("libultraship shader resource initialization failed");
            }
            interpreter = std::make_shared<Fast::Interpreter>();
            Fast::GfxSetInstance(interpreter);
            if (SDL_iPhoneSetAnimationCallback(window, 1, Tick, nullptr) != 0) throw std::runtime_error(SDL_GetError());
            Report("running", "Drawing through libultraship's generated Metal shader");
        } catch (const std::exception& error) {
            Finish("failed", error.what());
        }
        return 0; // SDL/UIKit owns the run loop and invokes Tick on the main thread.
    }
}
}

int main(int argc, char** argv) {
    return SDL_UIKitRunApp(argc, argv, RunProbe);
}
