// Runs RSP microcode from the copy the game loads into RDRAM, instead of code RSPRecomp converted
// from the ROM ahead of time. It follows RSPRecomp's generated C++ instruction for instruction
// (N64Recomp/RSPRecomp/src/rsp_recomp.cpp) with librecomp's vector unit, DMEM and DMA, so a task
// runs as it does through a recompiled microcode function.
#pragma once
#include "librecomp/rsp.hpp"

// Replaces one instruction of a microcode, as a game's patches to RSPRecomp's output do.
struct N64InterpRspPatch {
    uint32_t pc;                       // its IMEM address, such as 0x1108
    uint32_t instruction;              // the instruction it replaces, checked before each task
    void (*run)(uint32_t *registers);  // runs instead, with the scalar registers r0-r31
};

// The body of a RspUcodeFunc: loads the microcode at UCODE_ADDR into IMEM at 0x1080, as rspboot
// does, and runs it with the task already in DMEM until it breaks.
RspExitReason n64interp_rsp_run(uint8_t *rdram, uint32_t ucode_addr, const N64InterpRspPatch *patch = nullptr);
