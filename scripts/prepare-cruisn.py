"""Prepare Cruis'n USA and Cruis'n World for the tvOS build, from navjack's N64Recomp setups pinned
in upstream/cruisn-baseline.json. Never reads or copies a ROM.

Both games build into one framework (experiments/cruisn) on the runtime, renderer and frontend that
Racer builds, at the same pins. build/cruisn/source gets copies with navjack's runtime and renderer
patches, which were made for older commits of those forks, and the Apple TV changes (rt64_tvos.py).
The games' code and audio microcode run through experiments/n64interp, with tables written here
from each game's configuration; the debugging traces navjack's USA configuration hooks into the game
are left out.

  python3 scripts/prepare-cruisn.py
"""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rt64_tvos

root = Path(__file__).resolve().parent.parent
pin = json.loads((root / "upstream/cruisn-baseline.json").read_text())
checkouts = {name: root / "build/upstream" / source.get("checkout", source["repository"].split("/")[1])
             for name, source in pin["sources"].items()}


def git(path, *args):
    return subprocess.check_output(["git", *args], cwd=path, text=True).strip()


for name, path in checkouts.items():
    if git(path, "rev-parse", "HEAD") != pin["sources"][name]["revision"]:
        raise SystemExit(f"{path} doesn't match its pin; run scripts/upstream.py fetch.")
    if git(path, "status", "--porcelain"):
        raise SystemExit(f"Preserve {path}'s local edits before preparing a generated copy.")

# Only what the tvOS build compiles, as for Racer.
for base, table in ((checkouts["rt64"], rt64_tvos.RT64_SUBMODULES),
                    (checkouts["N64ModernRuntime"], rt64_tvos.RUNTIME_SUBMODULES),
                    (checkouts["N64ModernRuntime"] / "N64Recomp", rt64_tvos.N64RECOMP_SUBMODULES)):
    for parent, paths in table.items():
        subprocess.check_call(["git", "submodule", "--quiet", "update", "--init", "--depth", "1", *paths],
                              cwd=base / parent)

destination = root / "build/cruisn/source"
if destination.exists():
    shutil.rmtree(destination)
destination.mkdir(parents=True)
# Clones share the checkouts' blocks until a file changes.
for name in ("N64ModernRuntime", "rt64"):
    subprocess.check_call(["cp", "-cRp", str(checkouts[name]), str(destination / name)])
subprocess.check_call(["cp", "-cRp", str(checkouts["racer"] / "frontend"), str(destination / "frontend")])
workspace = checkouts["cruisn"]
(destination / "native").mkdir()
for name in ("controller_pak.cpp", "controller_pak.hpp"):
    shutil.copy2(workspace / "native" / name, destination / "native" / name)
shutil.copy2(workspace / "LICENSE", destination / "LICENSE")
for marker in destination.rglob(".git"):
    shutil.rmtree(marker) if marker.is_dir() else marker.unlink()


def apply_patch(patch, directory, *options):
    relative = (destination / directory).relative_to(root)
    command = ["git", "apply", "--unsafe-paths", f"--directory={relative}", *options, str(patch)]
    subprocess.check_call([*command[:2], "--check", *command[2:]], cwd=root)
    subprocess.check_call(command, cwd=root)


patches = workspace / "patches"
# navjack's runtime patch (threads, timers, events, audio clock, PI, overlays and address masking) was
# made for N64ModernRuntime cdf5abb, ten commits before Racer's pin. It goes in a hunk at a time;
# these five meet code those commits changed, so RUNTIME below makes their changes instead.
REPLACED_HUNKS = {
    "librecomp/src/recomp.cpp": "Unhandled status register bits changed",
    "librecomp/src/ultra_translation.cpp": "static void clock_read_boundary",
    "ultramodern/include/ultramodern/ultramodern.hpp": "+void send_si_message(PTR(OSMesgQueue) completion_mq);",
    "ultramodern/src/mesgqueue.cpp": "wait_dequeue_timed(to_send, std::chrono::milliseconds{10})",
    "ultramodern/src/timer.cpp": "void ultramodern::join_timer_thread()",
}
replaced = 0
text = (patches / "N64ModernRuntime-cruisn-runtime.patch").read_text()
for file_diff in re.split(r"(?m)^(?=diff --git )", text)[1:]:
    header, *chunks = re.split(r"(?m)^(?=@@ )", file_diff)
    path = re.search(r"(?m)^\+\+\+ b/(.+)$", header).group(1)
    for chunk in chunks:
        if REPLACED_HUNKS.get(path, "\0") in chunk:
            replaced += 1
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".patch") as hunk:
            hunk.write(header + chunk)
            hunk.flush()
            apply_patch(hunk.name, "N64ModernRuntime")
if replaced != len(REPLACED_HUNKS):
    raise SystemExit("prepare-cruisn.py: navjack's runtime patch changed; review REPLACED_HUNKS")
# Treats Cruis'n's graphics microcode as F3DEX2, and never copies a framebuffer to address 0.
apply_patch(patches / "rt64-cruisn.patch", "rt64")
# The other COP0 registers are kept in the context, as navjack's N64Recomp does. The runtime and
# experiments/n64interp (N64INTERP_COP0_REGISTERS) must see the same recomp_context.
apply_patch(patches / "N64Recomp-cop0-registers.patch", "N64ModernRuntime/N64Recomp", "--include=*include/recomp.h")

RUNTIME = {
    "librecomp/src/recomp.cpp": [
        # navjack: other status bits have no effect here, so a game may set them (Cruis'n sets CU1).
        ("""    // If any other bits were changed, assert false as they're not handled currently
    if (changed) {
        printf("Unhandled status register bits changed: 0x%08X\\n", changed);
        assert(false);
        exit(EXIT_FAILURE);
    }
    
    // Update the status register in the context
""", """    // Preserve other guest-visible status bits even though they have no host-side
    // effect in the native runtime. In particular, CU1 is used to enable the FPU.

    // Update the status register in the context
"""),
    ],
    "librecomp/src/ultra_translation.cpp": [
        # navjack: reading the clock is a scheduling point, as restoring interrupts is.
        ("""extern "C" void osGetCount_recomp(uint8_t * rdram, recomp_context * ctx) {
    // mfc0 sign-extends: games compare this against counts loaded with lw.
    ctx->r2 = (int32_t)osGetCount();
}
""", """// Games poll the clock in wait loops that end only when another thread (a
// retrace handler, say) updates shared state. On hardware an interrupt
// preempts the loop; here guest threads switch only at OS calls. libultra's
// own osGetTime restores interrupts internally, so treat reading the clock as
// the same scheduling boundary as __osRestoreInt_recomp -- and, like it, only
// with interrupts enabled: a clock read inside a guest critical section must
// not let another thread run.
static void clock_read_boundary(uint8_t* rdram, recomp_context* ctx) {
    if ((ctx->status_reg & 1u) && ultramodern::this_thread() != NULLPTR) {
        ultramodern::poll_external_messages(rdram);
        ultramodern::check_running_queue(rdram);
    }
}

extern "C" void osGetCount_recomp(uint8_t * rdram, recomp_context * ctx) {
    // mfc0 sign-extends: games compare this against counts loaded with lw.
    ctx->r2 = (int32_t)osGetCount();
    clock_read_boundary(rdram, ctx);
}
"""),
    ],
    "ultramodern/include/ultramodern/ultramodern.hpp": [
        ("void send_si_message();\nuint32_t get_speed_multiplier();\n",
         "void send_si_message(PTR(OSMesgQueue) completion_mq);\nuint32_t get_speed_multiplier();\n"),
    ],
    # navjack: waits wake every 10 ms to see whether the game is shutting down.
    "ultramodern/src/mesgqueue.cpp": [
        ("""    QueuedMessage to_send;
    external_messages.wait_dequeue(to_send);
    if (!do_send(""", """    QueuedMessage to_send;
    while (!external_messages.wait_dequeue_timed(to_send, std::chrono::milliseconds{10})) {
        ultramodern::check_for_thread_shutdown();
    }
    ultramodern::check_for_thread_shutdown();
    if (!do_send("""),
    ],
    # Racer's deterministic mode, which navjack's patch predates, calls the function it renamed.
    "ultramodern/src/deterministic.cpp": [
        ("void dequeue_external_messages(RDRAM_ARG1); // mesgqueue.cpp\n", ""),
        ("    dequeue_external_messages(PASS_RDRAM1);\n", "    ultramodern::poll_external_messages(PASS_RDRAM1);\n"),
    ],
    # navjack: the timer thread is joined at shutdown instead of detached.
    "ultramodern/src/timer.cpp": [
        ("""    timer_context.thread = std::thread{ timer_thread, PASS_RDRAM1 };
    timer_context.thread.detach();
}
""", """    timer_context.thread = std::thread{ timer_thread, PASS_RDRAM1 };
}

void ultramodern::join_timer_thread() {
    if (timer_context.thread.joinable()) {
        timer_context.action_queue.enqueue(ShutdownTimerAction{});
        timer_context.thread.join();
    }
}
"""),
    ],
    # Both games share this runtime, so a start forgets the previous game's sections as well as
    # its functions.
    "librecomp/src/overlays.cpp": [
        ("void recomp::overlays::init_overlays() {\n    func_map.clear();\n",
         "void recomp::overlays::init_overlays() {\n    func_map.clear();\n    loaded_sections.clear();\n"
         "    code_sections_by_rom.clear();\n"),
    ],
    "librecomp/src/pi.cpp": [
        # navjack's patch adds an osPiReadIo_recomp of its own, which serves PIF RAM.
        ("""// osPiReadIo(devAddr, *data): libultra reads osRomBase | devAddr, where osRomBase is the
// cartridge's KSEG1 base (0xB0000000).
extern "C" void osPiReadIo_recomp(RDRAM_ARG recomp_context * ctx) {
    uint32_t physical_addr = k1_to_phys(phys_to_k1(recomp::rom_base) | (uint32_t)ctx->r4);
    gpr dramAddr = ctx->r5;

    if (physical_addr >= recomp::rom_base) {
        recomp::do_rom_pio(PASS_RDRAM dramAddr, physical_addr);
    } else {
        assert(false && "osPiReadIo below cartridge ROM unimplemented");
    }

    ctx->r2 = 0;
}

""", ""),
        # The configurations' instruction patches go into code as it is copied from the cartridge
        # (experiments/n64interp), where a recompiled build has them in its generated code.
        ("""    for (size_t i = 0; i < num_bytes; i++) {
        MEM_B(i, ram_address) = *rom_addr;
        rom_addr++;
    }
}
""", """    for (size_t i = 0; i < num_bytes; i++) {
        MEM_B(i, ram_address) = *rom_addr;
        rom_addr++;
    }
    n64interp_rom_loaded(rdram, physical_addr - recomp::rom_base, (uint32_t)ram_address, (uint32_t)num_bytes);
}
"""),
        ('#include <ultramodern/ultramodern.hpp>\n',
         '#include <ultramodern/ultramodern.hpp>\n\nextern "C" void n64interp_rom_loaded(uint8_t* rdram, uint32_t rom, '
         'uint32_t vram, uint32_t size);\n'),
    ],
}
rt64_tvos.apply(destination / "N64ModernRuntime", RUNTIME, "prepare-cruisn.py")
# Nativecade starts games again in the same process (docs/GAME_SWITCHING.md); the runtime expects a
# new process for each. navjack's patch ends the game's threads at Quit. Each start also clears the
# quit flag, and Quit empties the running queue and the messages, which the whole process shares
# (as Racer's RESTART in prepare-racer.py).
RESTART = {
    "librecomp/src/recomp.cpp": [
        ("void recomp::start(const recomp::Configuration& cfg) {\n    project_version = cfg.project_version;\n",
         "void recomp::start(const recomp::Configuration& cfg) {\n    exited.store(false);\n"
         "    game_status.store(GameStatus::None);\n    project_version = cfg.project_version;\n"),
        ("    ultramodern::join_saving_thread();\n    \n    // rdram is left for the OS to free at exit",
         "    ultramodern::join_saving_thread();\n    ultramodern::clear_thread_queues(rdram);\n"
         "    \n    // rdram is left for the OS to free at exit"),
    ],
    "ultramodern/include/ultramodern/ultramodern.hpp": [
        ("void shutdown_game_threads();\n",
         "void shutdown_game_threads();\n// Empties the running queue and the external messages after Quit.\n"
         "void clear_thread_queues(RDRAM_ARG1);\n"),
    ],
    "ultramodern/src/mesgqueue.cpp": [
        ("bool do_send(RDRAM_ARG PTR(OSMesgQueue) mq_, OSMesg msg, bool jam, bool block);\n",
         "void ultramodern::clear_thread_queues(RDRAM_ARG1) {\n    QueuedMessage stale;\n"
         "    while (external_messages.try_dequeue(stale)) {}\n"
         "    while (!thread_queue_empty(PASS_RDRAM running_queue)) thread_queue_pop(PASS_RDRAM running_queue);\n}\n\n"
         "bool do_send(RDRAM_ARG PTR(OSMesgQueue) mq_, OSMesg msg, bool jam, bool block);\n"),
    ],
    # As Racer's: retraces stop at Quit, so a thread waiting for a new frame ends there.
    "ultramodern/src/events.cpp": [
        ('extern "C" PTR(void) osViGetCurrentFramebuffer() {\n',
         'extern "C" PTR(void) osViGetCurrentFramebuffer() {\n    ultramodern::check_for_thread_shutdown();\n'),
    ],
    "ultramodern/src/threads.cpp": [
        ("    host_contexts_empty.wait(lock, [] { return host_contexts.empty(); });\n",
         "    // ponytail: a thread looping in game code without calling the OS never ends, so Quit leaves it\n"
         "    // after a second; give the call its loop polls an end point, as osViGetCurrentFramebuffer has.\n"
         "    if (!host_contexts_empty.wait_for(lock, std::chrono::seconds{1}, [] { return host_contexts.empty(); })) {\n"
         "        fprintf(stderr, \"[Thread] %zu game threads didn't end at Quit\\n\", host_contexts.size());\n    }\n"),
    ],
}
rt64_tvos.apply(destination / "N64ModernRuntime", RESTART, "prepare-cruisn.py")
rt64_tvos.adapt(destination / "rt64", destination / "N64ModernRuntime", "RECOMPTV_CRUISN", "prepare-cruisn.py")
rt64_tvos.apply(destination / "frontend", rt64_tvos.FRONTEND, "prepare-cruisn.py")
rt64_tvos.apply(destination / "frontend", {
    # Both games use this frontend in one process, so the ROM search runs once per game.
    "src/app.cpp": [
        ("""    static bool searched = false; // ponytail: looks once; the launcher's drop/path box handles the rest
    if (searched) return false;
    searched = true;
""", """    static std::u8string searched; // once per game: Cruis'n USA and World share this frontend
    if (searched == g_game.game_id) return false;
    searched = g_game.game_id;
"""),
    ],
}, "prepare-cruisn.py")

# Tables for experiments/n64interp. The function lists come from navjack's N64Recomp, which is
# Racer's pin plus a patch that also has the runtime replace osPiWriteIo and cruisnPiRomRead.
lists = destination / "symbol-lists"
(lists / "src").mkdir(parents=True)
shutil.copy2(checkouts["N64Recomp"] / "src/symbol_lists.cpp", lists / "src/symbol_lists.cpp")
apply_patch(patches / "N64Recomp-reimplemented-pi-write.patch", "symbol-lists")
GAMES = (("usa", "cruisn-usa", "cruisn_usa_"), ("world", "cruisn-world", "cruisn_world_"))
for folder, source, prefix in GAMES:
    game = checkouts[source]
    (destination / folder / "config").mkdir(parents=True)
    shutil.copytree(game / "input", destination / folder / "input")
    for listing in (game / "config").glob("*.txt"):
        shutil.copy2(listing, destination / folder / "config" / listing.name)
    # World's boot-state hooks, compiled only with RECOMPTV_CRUISN_WORLD_BOOT_WORDS (docs/CRUISN.md).
    if folder == "world":
        (destination / folder / "native").mkdir()
        shutil.copy2(game / "native/cruisn_world_boot.cpp", destination / folder / "native/cruisn_world_boot.cpp")
    # navjack's diagnostics: the hooks that only print traces, and trace_mode, which makes every
    # recompiled function report its entry.
    text = (game / "config/recomp-symbols.toml").read_text()
    blocks = re.split(r"(?m)^(?=\[)", text)
    text = "".join(b for b in blocks if not (b.startswith("[[patches.hook]]") and "cruisn_trace_" in b))
    (destination / folder / "config/recomp-symbols.toml").write_text(text.replace("trace_mode = true\n", ""))
    subprocess.check_call(["python3", str(root / "scripts/generate-n64interp.py"),
                           str(destination / folder / "config/recomp-symbols.toml"), str(lists),
                           str(destination / folder / "interpreter"), f"--prefix={prefix}"])
print(f"Prepared Cruis'n USA and Cruis'n World ({pin['release']}) in {destination.relative_to(root)}")
