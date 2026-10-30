// Shadows of the Empire's audio microcode (M_AUDTASK), run by experiments/n64interp from the copy
// the game loads into RDRAM, in place of the generated/aspMain.cpp RSPRecomp converts from the ROM.
#include "N64RspInterpreter.h"

#include <TargetConditionals.h>
#include <cstdio>
#include <cstdlib>

namespace {
// SotE-Recomp's tools/patch_rsp_audio.py makes the audio command dispatcher use the microcode's
// 16 handler addresses as the task loaded them, because long audio lists overwrite their copy in
// DMEM before later commands dispatch. The same here: they're read as each task starts, and the
// dispatcher's lh $2, 0x10($2) takes them from there.
uint16_t handlers[16];
void dispatch(uint32_t *r) { r[2] = handlers[(r[1] >> 1) & 15]; }
constexpr N64InterpRspPatch dispatch_patch{0x1108, 0x84420010u, dispatch};

#if TARGET_OS_SIMULATOR
// SOTE_RSP_CAPTURE=DIRECTORY saves the state 16 audio tasks five seconds apart start from, for
// experiments/n64interp/RspSpike.cpp to compare this with the recompiled microcode on the Mac.
void capture(uint8_t *rdram, uint32_t ucode_addr) {
    static const char *directory = std::getenv("SOTE_RSP_CAPTURE");
    static unsigned task;
    if (!directory || task++ % 300 || task > 300 * 16) return;
    char path[1024];
    std::snprintf(path, sizeof path, "%s/task-%04u.bin", directory, task);
    if (FILE *file = std::fopen(path, "wb")) {
        std::fwrite(&ucode_addr, sizeof ucode_addr, 1, file);
        std::fwrite(dmem, 1, 0x1000, file);
        std::fwrite(rdram, 1, 0x800000, file);
        std::fclose(file);
    }
}
#endif
} // namespace

RspExitReason aspMain(uint8_t *rdram, uint32_t ucode_addr) {
    for (uint32_t i = 0; i < 16; ++i) handlers[i] = RSP_MEM_HU_LOAD(0x10 + 2 * i, 0);
#if TARGET_OS_SIMULATOR
    capture(rdram, ucode_addr);
#endif
    return n64interp_rsp_run(rdram, ucode_addr, &dispatch_patch);
}
