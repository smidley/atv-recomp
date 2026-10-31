// The host functions navjack's configurations hook into the games' code, force-included into the
// generated n64interp_game.c files. scripts/prepare-cruisn.py leaves out the hooks that only trace.
#pragma once
#include <stdint.h>
#include "recomp.h"

#ifdef __cplusplus
extern "C" {
#endif

// Cruis'n USA: interrupt delivery in the game's busy-wait loops (CruisnGame.cpp), and the Controller
// Pak primitives (navjack's controller_pak.cpp).
void cruisn_guest_poll(uint8_t *rdram, recomp_context *ctx);
void cruisn_pak_is_plug(uint8_t *rdram, recomp_context *ctx);
void cruisn_pak_get_status(uint8_t *rdram, recomp_context *ctx);
void cruisn_pak_ram_read(uint8_t *rdram, recomp_context *ctx);
void cruisn_pak_ram_write(uint8_t *rdram, recomp_context *ctx);

// Cruis'n World: the boot state its copy protection checks, and that check's result.
void cruisn_world_seed_boot_state(uint8_t *rdram, recomp_context *ctx);
void cruisn_world_report_self_test(uint8_t *rdram, recomp_context *ctx);

#ifdef __cplusplus
}
#endif
