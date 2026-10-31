// A renderer that draws nothing, for simulator smoke runs of the games that use Racer's frontend
// (Racer, Cruis'n): RT64 can't draw in the tvOS simulator. With <prefix>HEADLESS_SMOKE=1 the
// frontend uses it instead (rt64_tvos.FRONTEND), so the game code and audio can be checked there.
#include <TargetConditionals.h>
#include <cstdio>
#include <memory>
#include "ultramodern/renderer_context.hpp"

#if TARGET_OS_SIMULATOR
namespace {
class HeadlessRenderer final : public ultramodern::renderer::RendererContext {
public:
    HeadlessRenderer() {
        setup_result = ultramodern::renderer::SetupResult::Success;
        chosen_api = ultramodern::renderer::GraphicsApi::Auto;
    }
    bool valid() override { return true; }
    bool update_config(const ultramodern::renderer::GraphicsConfig &, const ultramodern::renderer::GraphicsConfig &) override {
        return true;
    }
    void enable_instant_present() override {}
    void send_dl(const OSTask *) override {
        if (++display_lists % 300 == 0) std::printf("[headless] %d display lists\n", display_lists);
    }
    void send_dummy_workload(uint32_t) override {}
    void update_screen() override {}
    void shutdown() override {}
    uint32_t get_display_framerate() const override { return 60; }
    float get_resolution_scale() const override { return 1.0f; }

private:
    int display_lists = 0;
};
} // namespace

std::unique_ptr<ultramodern::renderer::RendererContext> nativecade_headless_renderer(uint8_t *,
    ultramodern::renderer::WindowHandle, bool) {
    return std::make_unique<HeadlessRenderer>();
}
#endif
