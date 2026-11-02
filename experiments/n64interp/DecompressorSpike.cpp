// Spike: interprets Shadows of the Empire's boot decompressor from the player's ROM and compares
// the result with the image SotE-Recomp's extractor wrote at offset 0xC00000 of
// generated/recomp.z64. Runs on the Mac; neither file leaves it.
//   clang++ -std=c++20 -O2 -I <N64Recomp/include> N64Interpreter.cpp DecompressorSpike.cpp
//   ./a.out ROM.z64 build/sote/source/generated/recomp.z64
#include "N64Interpreter.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <vector>

extern "C" {
void cop0_status_write(recomp_context *, gpr) {}
gpr cop0_status_read(recomp_context *) { return 0; }
void switch_error(const char *, uint32_t, uint32_t) { std::abort(); }
void do_break(uint32_t vram) { std::fprintf(stderr, "break at %08X\n", vram); std::abort(); }
recomp_func_t *get_function(int32_t) { return nullptr; }
void recomp_syscall_handler(uint8_t *, recomp_context *, int32_t) { std::abort(); }
void pause_self(uint8_t *) { std::abort(); }
}

static std::vector<uint8_t> read(const char *path) {
    std::ifstream file(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(file), {}};
}

static uint32_t be32(const std::vector<uint8_t> &data, size_t offset) {
    return uint32_t(data[offset]) << 24 | uint32_t(data[offset + 1]) << 16 | uint32_t(data[offset + 2]) << 8 | data[offset + 3];
}

int main(int argc, char **argv) {
    if (argc != 3) { std::fprintf(stderr, "usage: spike ROM.z64 recomp.z64\n"); return 2; }
    const auto rom = read(argv[1]), expected = read(argv[2]);
    // The values extract_boot_image.py uses: an Ogre header names the compressed executable.
    const uint32_t start = be32(rom, 0x1F38), end = be32(rom, 0x1F3C);
    const uint32_t size = be32(rom, start);
    std::vector<uint8_t> memory(0x00800000);
    uint8_t *rdram = memory.data();
    auto store = [&](uint32_t vram, const uint8_t *bytes, size_t length) {
        for (size_t i = 0; i < length; ++i) MEM_B((int64_t)i, (gpr)(int32_t)vram) = (int8_t)bytes[i];
    };
    store(0x80000400, rom.data() + 0x1000, start - 0x1000);
    store(0x80300000, rom.data() + start, end - start);

    recomp_context ctx{};
    ctx.f_odd = &ctx.f0.u32h;
    ctx.r4 = (gpr)(int32_t)0x80300000;
    ctx.r5 = (gpr)(int32_t)0x80001EC0;
    ctx.r29 = (gpr)(int32_t)0x807FF000;
    const auto began = std::chrono::steady_clock::now();
    n64interp_call(rdram, &ctx, 0x80000E64);
    const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - began).count();

    size_t mismatches = 0;
    for (uint32_t i = 0; i < size; ++i)
        if ((uint8_t)MEM_BU((int64_t)i, (gpr)(int32_t)0x80001EC0) != expected.at(0xC00000 + i)) ++mismatches;
    const uint64_t instructions = n64interp_instruction_count();
    std::printf("decompressed 0x%X bytes, returned %08X (expected %08X), %zu bytes differ\n", size,
                (uint32_t)ctx.r2, 0x80001EC0 + size, mismatches);
    std::printf("%llu instructions in %.3f s: %.1f million per second\n", (unsigned long long)instructions,
                seconds, instructions / seconds / 1e6);
    return mismatches == 0 && (uint32_t)ctx.r2 == 0x80001EC0 + size ? 0 : 1;
}
