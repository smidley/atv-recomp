// Runs N64 game code from RDRAM instead of code converted from the ROM ahead of time, so a build
// holds nothing from the ROM. It follows N64Recomp's generated C operation for operation
// (recomp.h), so the same N64ModernRuntime, replaced libultra functions and hooks work with it.
#pragma once
#include <stdint.h>
#include "recomp.h"

#ifdef __cplusplus
extern "C" {
#endif

// Runs the function at VRAM until it returns, like calling its recompiled C function.
void n64interp_call(uint8_t *rdram, recomp_context *ctx, uint32_t vram);

// A native replacement for the function at VRAM, such as the runtime's osRecvMesg_recomp. Jumps
// and calls to VRAM run it instead and then return to $ra, as calls to *_recomp functions do.
void n64interp_set_replacement(uint32_t vram, recomp_func_t *function);

// Code to run just before the instruction at VRAM, like a hook in an N64Recomp configuration.
// Its result says how to continue: 0 runs the instruction, N64INTERP_RETURN returns from the
// current function, and any other value is the address to jump to (a hook's goto).
#define N64INTERP_RETURN 1u
typedef uint32_t (n64interp_hook_t)(uint8_t *rdram, recomp_context *ctx);
void n64interp_set_hook(uint32_t vram, n64interp_hook_t *hook);

// Stops with a message: the game called NAME at VRAM, a function the runtime replaces in
// recompilations but that nothing implements here. A recompiled build couldn't run it either.
void n64interp_missing(uint32_t vram, const char *name);

// Instructions run since start-up, for measuring speed.
uint64_t n64interp_instruction_count(void);

#ifdef __cplusplus
}
#endif
