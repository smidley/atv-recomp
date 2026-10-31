// Starts Cruis'n USA or Cruis'n World from Nativecade's library (docs/CRUISN.md). The games' code and
// audio microcode run through experiments/n64interp from the ROM in memory, on Racer's frontend in
// place of navjack's RecompFrontend host (cruisn-recomp/native/main.cpp), whose settings it follows.
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <string>
#include "CruisnHooks.h"
#include "N64RspInterpreter.h"
#include "controller_pak.hpp"
#include "frontend/frontend.hpp"
#include "librecomp/addresses.hpp"
#include "librecomp/game.hpp"
#include "librecomp/rsp.hpp"
#include "ultramodern/ultramodern.hpp"

void cruisn_usa_register_code(recomp::GameEntry &entry);   // CruisnTables.cpp, once per game
void cruisn_world_register_code(recomp::GameEntry &entry);

namespace {

// libultra's audio microcode, the same in both games. RT64 draws the graphics tasks.
RspExitReason aspMain(uint8_t *rdram, uint32_t ucode_addr) { return n64interp_rsp_run(rdram, ucode_addr); }
RspExitReason no_microcode(uint8_t *, uint32_t) { return RspExitReason::Broke; }

RspUcodeFunc *get_rsp_microcode(const OSTask *task) {
    return task->t.type == M_AUDTASK ? aspMain : no_microcode;
}

std::string thread_name(const OSThread *thread) {
    return "[Cruis'n] " + std::to_string(thread != nullptr ? thread->id : -1);
}

int run(recomp::GameEntry entry, fe::GameInfo game) {
    // The frontend prints why a game stops just before returning; keep those lines in a log file.
    setvbuf(stdout, nullptr, _IOLBF, 0);
    entry.is_enabled = true;
    if (!recomp::register_game(entry)) {
        std::fprintf(stderr, "[%s] the runtime refused the game\n", game.short_name.c_str());
        return 1;
    }
    // Only used when CRUISN_CONTROLLER_PAK is set, as in navjack's build; the games save to EEPROM.
    cruisn_controller_pak_configure(std::filesystem::current_path() / "saves" / (game.short_name + ".mpk"));
    recomp::Configuration cfg{};
    cfg.project_version = {1, 0, 0};
    cfg.rsp_callbacks.get_rsp_microcode = get_rsp_microcode;
    cfg.threads_callbacks.get_game_thread_name = thread_name;
    game.players = 1;   // navjack reports one controller, so the games never start a session nobody joined
    game.env_prefix = "CRUISN_";
    // --play skips the frontend's launcher; it finds the ROM in the game folder.
    char name[] = "cruisn", play[] = "--play";
    char *arguments[] = {name, play, nullptr};
    const int result = fe::run(game, cfg, 2, arguments);
    cruisn_controller_pak_flush();
    return result;
}

} // namespace

// Interrupt delivery in USA's busy-wait loops (navjack's main.cpp): guest threads switch only at OS
// calls in this runtime, so the configuration hooks this into the loops.
extern "C" void cruisn_guest_poll(uint8_t *rdram, recomp_context *ctx) {
    ultramodern::check_for_thread_shutdown();
    if ((ctx->status_reg & 7u) == 1u) {
        ultramodern::poll_external_messages(rdram);
        ultramodern::yield_running_thread(rdram);
    }
}

#ifndef RECOMPTV_CRUISN_WORLD_BOOT_WORDS
// Without navjack's cruisn_world_boot.cpp (CMakeLists.txt): the cartridge's boot code, which the copy
// protection reads, comes from the player's ROM, and the boot values it compares are left out.
extern "C" void cruisn_world_seed_boot_state(uint8_t *rdram, recomp_context *) {
    recomp::do_rom_read(rdram, (gpr)(int32_t)0x90000000u, recomp::rom_base, 0x1000);
    std::fprintf(stderr, "[cruisn_world] the boot values the copy protection checks are left out (docs/CRUISN.md)\n");
}

extern "C" void cruisn_world_report_self_test(uint8_t *rdram, recomp_context *) {
    std::fprintf(stderr, "[cruisn_world] copy-protection mask=%08X\n", (uint32_t)MEM_W(0, (gpr)(int32_t)0x803BDE2Cu));
}
#endif

int NativecadeRunCruisnUSA(int, char **) {
    recomp::GameEntry entry{};
    entry.rom_hash = 0xef2918d8cdc30441ULL;   // navjack's cruisn-usa-recomp/CMakeLists.txt
    entry.internal_name = "Cruis'n USA";
    entry.display_name = "Cruis'n USA";
    entry.game_id = u8"cruisn_usa";
    entry.mod_game_id = "cruisn_usa";
    entry.save_type = recomp::SaveType::Eep4k;
    cruisn_usa_register_code(entry);
    fe::GameInfo game;
    game.title = "Cruis'n USA";
    game.game_id = u8"cruisn_usa";
    game.short_name = "cruisn_usa";
    game.rom_names = {"cruisnusa.z64"};
    // USA reads the N64's Z trigger as the accelerator: navjack puts it on the right trigger.
    game.controller_bindings = fe::default_controller_bindings();
    game.controller_bindings["A"] = {"a"};
    game.controller_bindings["Z"] = {"+righttrigger"};
    return run(entry, game);
}

int NativecadeRunCruisnWorld(int, char **) {
    recomp::GameEntry entry{};
    entry.rom_hash = 0x25719e5d267c09d0ULL;   // navjack's cruisn-world-recomp/CMakeLists.txt
    entry.internal_name = "CRUIS'N WORLD";
    entry.display_name = "Cruis'n World";
    entry.game_id = u8"cruisn_world";
    entry.mod_game_id = "cruisn_world";
    entry.save_type = recomp::SaveType::Eep16k;
    cruisn_world_register_code(entry);
    fe::GameInfo game;
    game.title = "Cruis'n World";
    game.game_id = u8"cruisn_world";
    game.short_name = "cruisn_world";
    game.rom_names = {"cruisnworld.z64"};
    return run(entry, game);
}
