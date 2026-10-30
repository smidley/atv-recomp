// Shadows of the Empire's audio microcode (M_AUDTASK), run by experiments/n64interp from the copy
// the game loads into RDRAM, in place of the generated/aspMain.cpp RSPRecomp converts from the ROM.
#include "N64RspInterpreter.h"

namespace {
// SotE-Recomp's tools/patch_rsp_audio.py makes the audio command dispatcher use the microcode's
// 16 handler addresses as the task loaded them, because long audio lists overwrite their copy in
// DMEM before later commands dispatch. The same here: they're read as each task starts, and the
// dispatcher's lh $2, 0x10($2) takes them from there.
uint16_t handlers[16];
void dispatch(uint32_t *r) { r[2] = handlers[(r[1] >> 1) & 15]; }
constexpr N64InterpRspPatch dispatch_patch{0x1108, 0x84420010u, dispatch};
} // namespace

RspExitReason aspMain(uint8_t *rdram, uint32_t ucode_addr) {
    for (uint32_t i = 0; i < 16; ++i) handlers[i] = RSP_MEM_HU_LOAD(0x10 + 2 * i, 0);
    return n64interp_rsp_run(rdram, ucode_addr, &dispatch_patch);
}
