"""Prepare the pinned Star Wars Episode I: Racer recompilation for tvOS without reading any game ROM.

upstream/racer-baseline.json pins Racer and the runtime, renderer and recompiler forks it builds
with. This copies them to build/racer/source, applies the tvOS changes Racer shares with Shadows of
the Empire (rt64_tvos.py) and its own, and writes the tables experiments/n64interp runs the game's
code with. Racer's own build turns that code into C from the ROM; Nativecade interprets it from
the ROM in memory instead, so nothing here comes from a ROM.
"""
import json
from pathlib import Path
import re
import shutil
import subprocess

import rt64_tvos

root = Path(__file__).resolve().parent.parent
pin = json.loads((root / "upstream/racer-baseline.json").read_text())
checkouts = {name: root / "build/upstream" / source.get("checkout", source["repository"].split("/")[1])
             for name, source in pin["sources"].items()}


def git(path, *args):
    return subprocess.check_output(["git", *args], cwd=path, text=True).strip()


for name, path in checkouts.items():
    if git(path, "rev-parse", "HEAD") != pin["sources"][name]["revision"]:
        raise SystemExit(f"{path} doesn't match its pin; run scripts/upstream.py fetch.")
    if git(path, "status", "--porcelain"):
        raise SystemExit(f"Preserve {path}'s local edits before preparing a generated copy.")

# Only what the tvOS build compiles. The N64Recomp checkout is read for its lists of the libultra
# functions the runtime replaces; librecomp builds the runtime's own N64Recomp submodule.
for base, table in ((checkouts["rt64"], rt64_tvos.RT64_SUBMODULES),
                    (checkouts["N64ModernRuntime"], rt64_tvos.RUNTIME_SUBMODULES),
                    (checkouts["N64ModernRuntime"] / "N64Recomp", rt64_tvos.N64RECOMP_SUBMODULES)):
    for parent, paths in table.items():
        subprocess.check_call(["git", "submodule", "--quiet", "update", "--init", "--depth", "1", *paths],
                              cwd=base / parent)

destination = root / "build/racer/source"
if destination.exists():
    shutil.rmtree(destination)
(destination / "racer").mkdir(parents=True)
# Clones share the checkouts' blocks until a file changes, and keeping modification times means a
# build only recompiles what the changes below touch.
racer = checkouts["racer"]
for name in ("src", "frontend", "recomp.toml", "symbols.toml", "LICENSE"):
    subprocess.check_call(["cp", "-cRp", str(racer / name), str(destination / "racer" / name)])
for name in ("N64ModernRuntime", "rt64"):
    subprocess.check_call(["cp", "-cRp", str(checkouts[name]), str(destination / name)])
# Git metadata in the copy would point back at the checkouts' submodules.
for marker in destination.rglob(".git"):
    shutil.rmtree(marker) if marker.is_dir() else marker.unlink()

rt64_tvos.adapt(destination / "rt64", destination / "N64ModernRuntime", "RECOMPTV_RACER", "prepare-racer.py")
rt64_tvos.apply(destination / "racer/frontend", rt64_tvos.FRONTEND, "prepare-racer.py")

# Nativecade starts Racer again in the same process (docs/GAME_SWITCHING.md); N64ModernRuntime
# expects a new one. Quit left its quit flag set, so the next start shut down at once, and left the
# game's threads and the timer thread waiting on the running queue and message queue, which the
# whole process shares: they woke into the next start and took its threads off the running queue.
# Now each start clears the flag, and Quit ends those threads and empties the queues.
RESTART = {
    "librecomp/src/recomp.cpp": [
        ("void recomp::start(const recomp::Configuration& cfg) {\n    project_version = cfg.project_version;\n",
         "void recomp::start(const recomp::Configuration& cfg) {\n    exited.store(false);\n"
         "    game_status.store(GameStatus::None);\n    project_version = cfg.project_version;\n"),
        ("    game_thread.join();\n    ultramodern::join_event_threads();\n    ultramodern::join_thread_cleaner_thread();\n"
         "    ultramodern::join_saving_thread();\n",
         "    ultramodern::shutdown_game_threads(rdram);\n    game_thread.join();\n    ultramodern::join_event_threads();\n"
         "    ultramodern::join_timer_thread();\n    ultramodern::join_thread_cleaner_thread();\n"
         "    ultramodern::join_saving_thread();\n    ultramodern::clear_external_messages();\n"),
    ],
    "ultramodern/include/ultramodern/ultramodern.hpp": [
        ("void join_thread_cleaner_thread();\n",
         "void join_thread_cleaner_thread();\nvoid shutdown_game_threads(RDRAM_ARG1);\nvoid join_timer_thread();\n"
         "void clear_external_messages();\n"),
    ],
    # Each game thread ends at its next wait once the quit flag is set; Quit wakes them all.
    "ultramodern/src/threads.cpp": [
        ("#include <string>\n", "#include <string>\n#include <condition_variable>\n#include <mutex>\n#include <set>\n"),
        ("void wait_for_resumed(RDRAM_ARG UltraThreadContext* thread_context) {\n    thread_context->running.wait();\n",
         "extern std::atomic_bool exited;\nstatic std::mutex live_threads_mutex;\n"
         "static std::condition_variable live_threads_ended;\nstatic std::set<UltraThreadContext*> live_threads;\n\n"
         "void wait_for_resumed(RDRAM_ARG UltraThreadContext* thread_context) {\n    thread_context->running.wait();\n"
         "    if (exited) throw ultramodern::thread_terminated{};\n"),
        # Ending threads hand over to no one: the one they would wake may have ended already.
        ('void resume_thread(OSThread* t) {\n    debug_printf("[Thread] Resuming execution of thread %d\\n", t->id);\n',
         'void resume_thread(OSThread* t) {\n    if (exited) return;\n'
         '    debug_printf("[Thread] Resuming execution of thread %d\\n", t->id);\n'),
        ("void run_next_thread(RDRAM_ARG1) {\n", "void run_next_thread(RDRAM_ARG1) {\n    if (exited) return;\n"),
        ("    // Make sure the thread wasn't replaced or destroyed before it was started.\n    if (self->context == thread_context) {\n",
         "    // Make sure the thread wasn't replaced or destroyed before it was started.\n"
         "    if (!exited && self->context == thread_context) {\n"),
        ("    // Dispose of this thread now that it's completed or terminated.\n    ultramodern::cleanup_thread(thread_context);\n}\n",
         "    // Dispose of this thread now that it's completed or terminated.\n    ultramodern::cleanup_thread(thread_context);\n"
         "    std::lock_guard lock{live_threads_mutex};\n    live_threads.erase(thread_context);\n"
         "    live_threads_ended.notify_all();\n}\n"),
        ("    UltraThreadContext* context = new UltraThreadContext{};\n    t->context = context;\n",
         "    UltraThreadContext* context = new UltraThreadContext{};\n    t->context = context;\n"
         "    {\n        std::lock_guard lock{live_threads_mutex};\n        live_threads.insert(context);\n    }\n"),
        # The cleaner runs until it is joined, so it also joins the threads Quit ended.
        ("    using namespace std::chrono_literals;\n    while (!exited) {\n        UltraThreadContext* to_delete;\n"
         "        if (deleted_threads.wait_dequeue_timed(to_delete, 10ms)) {\n"
         '            debug_printf("[Cleanup] Deleting thread context %p\\n", to_delete);\n\n'
         "            to_delete->host_thread.join();\n            delete to_delete;\n        }\n    }\n",
         "    while (true) {\n        UltraThreadContext* to_delete;\n        deleted_threads.wait_dequeue(to_delete);\n"
         "        if (to_delete == nullptr) return;\n"
         '        debug_printf("[Cleanup] Deleting thread context %p\\n", to_delete);\n\n'
         "        to_delete->host_thread.join();\n        delete to_delete;\n    }\n"),
        ("void ultramodern::join_thread_cleaner_thread() {\n    thread_cleaner_thread.join();\n}",
         "void ultramodern::join_thread_cleaner_thread() {\n    deleted_threads.enqueue(nullptr);\n"
         "    thread_cleaner_thread.join();\n}\n\n"
         "void ultramodern::shutdown_game_threads(RDRAM_ARG1) {\n    std::unique_lock lock{live_threads_mutex};\n"
         "    for (UltraThreadContext* context : live_threads) context->running.signal();\n"
         "    // ponytail: a thread looping in game code without calling the OS never ends, so Quit leaves it;\n"
         "    // give the call its loop polls an end point, as osViGetCurrentFramebuffer has.\n"
         "    if (!live_threads_ended.wait_for(lock, std::chrono::seconds{1}, [] { return live_threads.empty(); })) {\n"
         '        fprintf(stderr, "[Thread] %zu game threads didn\'t end at Quit\\n", live_threads.size());\n    }\n'
         "    while (!thread_queue_empty(PASS_RDRAM running_queue)) thread_queue_pop(PASS_RDRAM running_queue);\n}"),
    ],
    # Message calls and idle waits are where a thread that isn't waiting to be resumed ends.
    "ultramodern/src/mesgqueue.cpp": [
        ("bool do_send(RDRAM_ARG PTR(OSMesgQueue) mq_, OSMesg msg, bool jam, bool block);\n",
         "void ultramodern::clear_external_messages() {\n    QueuedMessage stale;\n"
         "    while (external_messages.try_dequeue(stale)) {}\n}\n\n"
         "bool do_send(RDRAM_ARG PTR(OSMesgQueue) mq_, OSMesg msg, bool jam, bool block);\n"),
        ("void dequeue_external_messages(RDRAM_ARG1) {\n",
         "extern std::atomic_bool exited;\n\nvoid dequeue_external_messages(RDRAM_ARG1) {\n"
         "    if (exited) throw ultramodern::thread_terminated{};\n"),
        ("    QueuedMessage to_send;\n    external_messages.wait_dequeue(to_send);\n",
         "    QueuedMessage to_send;\n    do {\n        if (exited) throw ultramodern::thread_terminated{};\n"
         "    } while (!external_messages.wait_dequeue_timed(to_send, std::chrono::milliseconds{10}));\n"),
        ("    QueuedMessage to_send;\n    if (external_messages.wait_dequeue_timed(to_send, std::chrono::milliseconds{millis})) {\n",
         "    if (exited) throw ultramodern::thread_terminated{};\n    QueuedMessage to_send;\n"
         "    if (external_messages.wait_dequeue_timed(to_send, std::chrono::milliseconds{millis})) {\n"),
    ],
    # Racer waits for a new frame by calling this until a retrace swaps framebuffers. Retraces stop
    # at Quit, so a thread waiting there ends there.
    "ultramodern/src/events.cpp": [
        ('extern "C" PTR(void) osViGetCurrentFramebuffer() {\n',
         'extern "C" PTR(void) osViGetCurrentFramebuffer() {\n    if (exited) throw ultramodern::thread_terminated{};\n'),
    ],
    # As navjack's Cruis'n patch: the timer thread is joined at Quit instead of detached.
    "ultramodern/src/timer.cpp": [
        ("using Action = std::variant<AddTimerAction, RemoveTimerAction>;\n",
         "struct ShutdownTimerAction {};\n\n"
         "using Action = std::variant<AddTimerAction, RemoveTimerAction, ShutdownTimerAction>;\n"),
        ("    auto process_timer_action = [&](const Action& action) {\n",
         "    bool shutdown = false;\n    auto process_timer_action = [&](const Action& action) {\n"),
        ("            active_timers.erase(remove_action->timer);\n        }\n    };\n\n    while (true) {\n",
         "            active_timers.erase(remove_action->timer);\n        } else {\n            shutdown = true;\n"
         "        }\n    };\n\n    while (!shutdown) {\n"),
        ("        while (active_timers.empty()) {\n            timer_context.action_queue.wait_dequeue(cur_action);\n"
         "            process_timer_action(cur_action);\n        }\n",
         "        while (active_timers.empty() && !shutdown) {\n"
         "            timer_context.action_queue.wait_dequeue(cur_action);\n            process_timer_action(cur_action);\n"
         "        }\n        if (shutdown) break;\n"),
        ("    timer_context.thread = std::thread{ timer_thread, PASS_RDRAM1 };\n    timer_context.thread.detach();\n}\n",
         "    timer_context.thread = std::thread{ timer_thread, PASS_RDRAM1 };\n}\n\n"
         "void ultramodern::join_timer_thread() {\n    timer_context.action_queue.enqueue(ShutdownTimerAction{});\n"
         "    timer_context.thread.join();\n}\n"),
    ],
}
rt64_tvos.apply(destination / "N64ModernRuntime", RESTART, "prepare-racer.py")

# Tables for experiments/n64interp, from Racer's configuration and symbol file. Its section table
# (src/section_table.cpp, which its main.cpp registers) also names the functions N64Recomp split off
# at calls into other functions, and tools/post_recomp_patches.py sends two functions to host code.
table = (racer / "src/section_table.cpp").read_text()
base = int(re.search(r"(0x[0-9A-Fa-f]+),\s*// ram_addr", table).group(1), 16)
extras = [f"{name}@{base + int(offset, 16):X}"
          for name, offset in re.findall(r"\{ (\w+), (0x[0-9A-Fa-f]+), 0x[0-9A-Fa-f]+ \}", table)]
patches = (racer / "tools/post_recomp_patches.py").read_text()
redirects = re.findall(r'"(\w+)":\s*"(\w+)"', re.search(r"REDIRECTS = \{(.*?)\n\}", patches, re.S).group(1))
subprocess.check_call(["python3", str(root / "scripts/generate-n64interp.py"), str(destination / "racer/recomp.toml"),
                       str(checkouts["N64Recomp"]), str(destination / "interpreter"),
                       *[f"{name}={target}" for name, target in redirects], *extras])
print(f"Prepared Star Wars Episode I: Racer {pin['release']} in {destination.relative_to(root)}")
