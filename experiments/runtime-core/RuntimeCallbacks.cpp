#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include "ultramodern/ultramodern.hpp"

// Synthetic host services exercise the real upstream input/audio implementation.
// No game thread, renderer, audio device, controller hardware, or ROM is used.
namespace {
int polls = 0;
int si_messages = 0;
bool connected = true;
uint16_t button_state = 0x8000;
uint32_t frequency = 0;
size_t queued_samples = 0;
size_t remaining_frames = 0;
int16_t* queued_pointer = nullptr;

void require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "Runtime callback check failed: %s\n", message);
        std::exit(EXIT_FAILURE);
    }
}

void poll_input() { ++polls; }

bool get_input(int port, uint16_t* buttons, float* x, float* y) {
    if (port != 0 || !connected) {
        return false;
    }
    *buttons = button_state;
    *x = 0.5f;
    *y = -1.0f;
    return true;
}

void set_frequency(uint32_t value) { frequency = value; }
size_t get_frames_remaining() { return remaining_frames; }
void queue_samples(int16_t* samples, size_t count) {
    queued_pointer = samples;
    queued_samples += count;
}
} // namespace

// Deliberate event-service test double: input.cpp signals SI here. Linking the
// actual event loop would also require game lifecycle and renderer services.
void ultramodern::send_si_message(uint8_t*) { ++si_messages; }

int main() {
    std::array<int16_t, 32> memory{};
    auto* rdram = reinterpret_cast<uint8_t*>(memory.data());
    std::array<OSContPad, 4> pads{};

    ultramodern::input::set_callbacks({
        .poll_input = poll_input,
        .get_input = get_input,
        .set_rumble = nullptr,
        .get_connected_device_info = nullptr,
    });
    require(osContSetCh(rdram, 4) == 0, "configure controller ports");
    require(osContStartReadData(rdram, 0) == 0, "start input poll");
    require(polls == 1 && si_messages == 1, "poll callback and SI notification");
    osContGetReadData(pads.data());
    require(pads[0].err_no == 0 && pads[0].button == 0x8000, "button press");
    require(pads[0].stick_x == 63 && pads[0].stick_y == -127, "analog conversion");
    for (size_t i = 1; i < pads.size(); ++i) {
        require(pads[i].err_no == 8, "absent ports report no response");
    }
    button_state = 0;
    osContGetReadData(pads.data());
    require(pads[0].button == 0, "button release");
    connected = false;
    osContGetReadData(pads.data());
    require(pads[0].err_no == 8, "controller disconnect");
    connected = true;
    osContGetReadData(pads.data());
    require(pads[0].err_no == 0, "controller reconnect");
    ultramodern::input::set_callbacks({});
    osContGetReadData(pads.data());
    require(pads[0].err_no == 8, "missing host callback reports no response");

    ultramodern::set_audio_callbacks({
        .queue_samples = queue_samples,
        .get_frames_remaining = get_frames_remaining,
        .set_frequency = set_frequency,
    });
    ultramodern::init_audio();
    require(frequency == 48000, "initial sample rate");
    ultramodern::set_audio_frequency(32000);
    require(frequency == 32000, "game-selected sample rate");

    // Native-endian synthetic sample storage at emulated address 0x80000010.
    memory[8] = 123;
    memory[9] = -123;
    constexpr int32_t audio_address = -2147483632;
    ultramodern::queue_audio_buffer(rdram, audio_address, 8);
    require(queued_pointer == memory.data() + 8 && queued_samples == 4,
            "RDRAM address and byte-to-sample conversion");
    require(queued_pointer[0] == 123 && queued_pointer[1] == -123, "sample data");
    ultramodern::queue_audio_buffer(rdram, audio_address, 0);
    require(queued_samples == 4, "empty audio buffer is not queued");

    remaining_frames = 1000;
    require(ultramodern::get_remaining_audio_bytes() == 3467,
            "stereo frame accounting with upstream latency offset");
    remaining_frames = 0;
    require(ultramodern::get_remaining_audio_bytes() == 0, "empty queue saturates at zero");
    ultramodern::set_audio_callbacks({});
    ultramodern::queue_audio_buffer(rdram, audio_address, 8);
    require(queued_samples == 4, "removed audio callback is not invoked");

    std::puts("Upstream input and audio callback checks passed (synthetic host services).");
    return EXIT_SUCCESS;
}
