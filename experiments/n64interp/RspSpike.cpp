// Spike: runs audio tasks a game saved in the simulator (N64INTERP_RSP_CAPTURE, N64RspInterpreter.cpp)
// through the interpreter, as the game's aspMain runs it, and through the microcode RSPRecomp
// generated from the ROM, then compares DMEM and RDRAM. Runs on the Mac; neither the captures nor
// the generated code leave it. For Shadows of the Empire:
//   clang++ -std=c++20 -O2 -DaspMain=recompiled_aspMain -c build/sote/source/generated/aspMain.cpp ...
//   clang++ -std=c++20 -O2 RspSpike.cpp N64RspInterpreter.cpp ../sote/SoteAudioMicrocode.cpp librecomp/src/rsp.cpp aspMain.o
//   ./a.out CAPTURE...
#include "N64RspInterpreter.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

RspExitReason aspMain(uint8_t *rdram, uint32_t ucode_addr);
RspExitReason recompiled_aspMain(uint8_t *rdram, uint32_t ucode_addr);

int main(int argc, char **argv) {
    recomp::rsp::constants_init();
    int failures = 0;
    for (int i = 1; i < argc; ++i) {
        std::ifstream file(argv[i], std::ios::binary);
        const std::vector<uint8_t> saved{std::istreambuf_iterator<char>(file), {}};
        if (saved.size() != 4 + 0x1000 + 0x800000) { std::fprintf(stderr, "%s: not a capture\n", argv[i]); return 2; }
        uint32_t ucode_addr;
        std::memcpy(&ucode_addr, saved.data(), 4);

        struct Run { std::vector<uint8_t> rdram, dmem; RspExitReason result; double seconds; };
        auto run = [&](RspExitReason (*microcode)(uint8_t *, uint32_t)) {
            Run out{std::vector<uint8_t>(0x1000000), {}, {}, 0};
            std::memcpy(out.rdram.data(), saved.data() + 4 + 0x1000, 0x800000);
            std::memcpy(dmem, saved.data() + 4, 0x1000);
            const auto began = std::chrono::steady_clock::now();
            out.result = microcode(out.rdram.data(), ucode_addr);
            out.seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - began).count();
            out.dmem.assign(dmem, dmem + 0x1000);
            return out;
        };
        const Run expected = run(recompiled_aspMain), interpreted = run(aspMain);
        size_t rdram_diff = 0, dmem_diff = 0, first = SIZE_MAX, changed = 0;
        for (size_t a = 0; a < 0x1000000; ++a) {
            if (expected.rdram[a] != interpreted.rdram[a]) { ++rdram_diff; if (first == SIZE_MAX) first = a; }
            if (a < 0x800000 && expected.rdram[a] != saved[4 + 0x1000 + a]) ++changed;
        }
        for (size_t a = 0; a < 0x1000; ++a) dmem_diff += expected.dmem[a] != interpreted.dmem[a];
        const bool same = rdram_diff == 0 && dmem_diff == 0 && expected.result == interpreted.result;
        failures += !same;
        std::printf("%s: %s; results %d/%d, %zu RDRAM bytes written, %zu RDRAM and %zu DMEM bytes differ",
                    argv[i], same ? "same" : "DIFFERENT", (int)expected.result, (int)interpreted.result, changed,
                    rdram_diff, dmem_diff);
        if (first != SIZE_MAX) std::printf(" (first at %06zX)", first);
        std::printf("; %.0f us recompiled, %.0f us interpreted\n", expected.seconds * 1e6, interpreted.seconds * 1e6);
    }
    return failures ? 1 : 0;
}
