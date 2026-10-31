// One game's tables from scripts/generate-n64interp.py --prefix, compiled once per game with that
// game's interpreter folder and CRUISN_GAME, its prefix (CMakeLists.txt).
#include "librecomp/game.hpp"
#include "librecomp/overlays.hpp"
#include "librecomp/sections.h"
#include "recomp_overlays.inl"
#include "lookup.cpp"

#define CRUISN_JOIN2(a, b) a##b
#define CRUISN_JOIN(a, b) CRUISN_JOIN2(a, b)

extern "C" void CRUISN_JOIN(CRUISN_GAME, n64interp_register_game)(void);

// The game's code: the libultra functions the runtime replaces and the hooks for the interpreter,
// its sections for librecomp, and its entry point.
void CRUISN_JOIN(CRUISN_GAME, register_code)(recomp::GameEntry &entry) {
    CRUISN_JOIN(CRUISN_GAME, n64interp_register_game)();
    recomp::overlays::register_overlays(
        {.code_sections = section_table, .num_code_sections = ARRLEN(section_table), .total_num_sections = num_sections},
        {.table = overlay_sections_by_index, .len = ARRLEN(overlay_sections_by_index)});
    entry.entrypoint_address = CRUISN_JOIN(CRUISN_GAME, get_entrypoint_address)();
    entry.entrypoint = CRUISN_JOIN(CRUISN_GAME, recomp_entrypoint);
}
