"""Write the files that let experiments/n64interp run a game set up for N64Recomp.

They stand in for N64Recomp's output, with the same names, so the game's host code, librecomp and
the configuration's hooks work unchanged. Everything comes from public project files: the game's
N64Recomp configuration and symbol file, and N64Recomp's lists of libultra functions the runtime
replaces. No ROM is read, and nothing here contains the game's code.

  python3 scripts/generate-n64interp.py CONFIG.toml N64RECOMP_SOURCE OUTPUT_DIR [NAME=TARGET | NAME@ADDRESS ...]

Writes funcs.h, recomp_overlays.inl and lookup.cpp, as N64Recomp does, and n64interp_game.c:
a function for each game function that interprets it, the replacements, and the hooks. The game's
host code calls n64interp_register_game() once before starting the game.

NAME=TARGET runs the host function TARGET wherever the game calls NAME, as a project's patches to
the generated C can (Racer's tools/post_recomp_patches.py). NAME@ADDRESS adds a function the symbol
file doesn't list, such as one N64Recomp split off at a call into another (static_0_ADDRESS), for a
project whose own section table names it.
"""
from pathlib import Path
import re
import sys
import tomllib


def symbol_lists(n64recomp):
    """N64Recomp's built-in reimplemented, ignored and renamed function names."""
    text = (n64recomp / "src/symbol_lists.cpp").read_text()
    lists = {}
    for name in ("reimplemented_funcs", "ignored_funcs", "renamed_funcs"):
        block = re.search(rf"N64Recomp::{name}\s*\{{(.*?)\n\}};", text, re.S)
        if not block:
            raise SystemExit(f"generate-n64interp.py: {name} is no longer in N64Recomp's symbol_lists.cpp")
        lists[name] = set(re.findall(r'"([^"]+)"', block.group(1)))
    return lists


def load(config_path, n64recomp, extras):
    config = tomllib.loads(config_path.read_text())
    symbols = tomllib.loads((config_path.parent / config["input"]["symbols_file_path"]).read_text())
    patches = config.get("patches", {})
    unsupported = set(patches) - {"stubs", "ignored", "renamed", "hook"}
    if unsupported:
        raise SystemExit(f"generate-n64interp.py: patches.{', patches.'.join(sorted(unsupported))} aren't supported yet")
    lists = symbol_lists(n64recomp)
    entrypoint = config["input"].get("entrypoint")
    sections, functions = [], []
    for index, section in enumerate(symbols["section"]):
        if section.get("relocatable") or section.get("relocs"):
            raise SystemExit("generate-n64interp.py: relocatable sections (overlays) aren't supported yet")
        sections.append({"index": index, "name": section["name"].lstrip(".") or f"s{index}",
                         "rom": section["rom"], "vram": section["vram"], "size": section["size"], "functions": []})
        for symbol in section.get("functions", []):
            name, ignored, reimplemented = symbol["name"], False, False
            # The order N64Recomp's main.cpp applies its lists in.
            if name in lists["reimplemented_funcs"]:
                name, ignored, reimplemented = name + "_recomp", True, True
            elif name in lists["ignored_funcs"]:
                name, ignored = name + "_recomp", True
            elif name in lists["renamed_funcs"]:
                name += "_recomp"
            if symbol["vram"] == entrypoint and section["rom"] + symbol["vram"] - section["vram"] == 0x1000:
                name = "recomp_entrypoint"
            function = {"name": name, "vram": symbol["vram"], "size": symbol["size"], "ignored": ignored,
                        "reimplemented": reimplemented, "stubbed": False}
            functions.append(function)
            sections[-1]["functions"].append(function)
    by_name = {function["name"]: function for function in functions}
    for name, vram in extras.items():
        if name in by_name:
            continue
        section = next((s for s in sections if s["vram"] <= vram < s["vram"] + s["size"]), None)
        if section is None:
            raise SystemExit(f"generate-n64interp.py: {name}@{vram:08X} is outside every section")
        function = {"name": name, "vram": vram, "size": 0, "ignored": False, "reimplemented": False, "stubbed": False}
        functions.append(function)
        section["functions"].append(function)
        by_name[name] = function

    def named(name, list_name):
        if name not in by_name:
            raise SystemExit(f"generate-n64interp.py: {list_name} names {name}, which the symbol file doesn't have")
        return by_name[name]

    for name in patches.get("stubs", []):
        named(name, "patches.stubs")["stubbed"] = True
    for name in patches.get("ignored", []):
        named(name, "patches.ignored")["ignored"] = True
    for name in patches.get("renamed", []):
        function = named(name, "patches.renamed")
        del by_name[name]
        function["name"] += "_recomp"
        by_name[function["name"]] = function
    return config, sections, functions, patches.get("hook", [])


C_TYPES = r"(?:u?int(?:8|16|32|64)_t|int|unsigned|float|double|gpr)"


def share_hook_locals(hooks):
    """Hooks in one recompiled function share its local variables. Each hook is a function of its
    own here, so a variable one hook declares and another uses becomes per-thread storage, which
    the declaring hook sets as before. Returns the declarations for the file."""
    declarations, by_function = [], {}
    for hook in hooks:
        by_function.setdefault(hook["func"], []).append(hook)
    for function, group in by_function.items():
        for hook in group:
            for kind, name in re.findall(rf"\b({C_TYPES})\s+(\w+)\s*=", hook["text"]):
                if not any(other is not hook and re.search(rf"\b{name}\b", other["text"]) for other in group):
                    continue
                shared = f"n64interp_{function}_{name}"
                declarations.append(f"static _Thread_local {kind} {shared};")
                hook["text"] = re.sub(rf"\b{kind}\s+{name}\s*=", f"{shared} =", hook["text"])
                for other in group:
                    other["text"] = re.sub(rf"\b{name}\b", shared, other["text"])
    return declarations


def hook_functions(hooks):
    """C for the configuration's hooks: return becomes N64INTERP_RETURN and goto the label's address."""
    labels = {}
    for hook in hooks:
        for label in re.findall(r"(\w+)\s*:\s*;", hook["text"]):
            if hook["text"].strip() != f"{label}:;":
                raise SystemExit(f"generate-n64interp.py: label {label} must be a hook of its own")
            labels[label] = hook["before_vram"]
    by_vram = {}
    for hook in hooks:
        text = hook["text"]
        text = re.sub(r"\breturn\s*;", "return N64INTERP_RETURN;", text)
        # N64Recomp names the labels inside a function L_<address>; the others are hooks' own.
        text = re.sub(r"\bgoto\s+L_([0-9A-F]{8})\s*;", lambda match: f"return 0x{match.group(1)}u;", text)
        text = re.sub(r"\bgoto\s+(\w+)\s*;", lambda match: f"return 0x{labels[match.group(1)]:08X}u;", text)
        text = re.sub(r"(\w+)\s*:\s*;", "", text)
        by_vram.setdefault(hook["before_vram"], []).append(text)
    return by_vram


def write(config, sections, functions, hooks, shared_locals, redirects, output):
    output.mkdir(parents=True, exist_ok=True)
    generated = [f for f in functions if not f["ignored"]]
    # As N64Recomp does: replaced functions are declared and listed, with no size; functions that
    # are only ignored are neither, and the game's host code supplies any it calls.
    listed = [f for f in functions if f["reimplemented"] or not f["ignored"]]
    (output / "funcs.h").write_text(
        '#include "recomp.h"\n\n#ifdef __cplusplus\nextern "C" {\n#endif\n\n'
        + "".join(f"void {f['name']}(uint8_t* rdram, recomp_context* ctx);\n" for f in listed)
        + '\n#ifdef __cplusplus\n}\n#endif\n')

    overlays = ['#include "recomp.h"', '#include "funcs.h"', '#include "librecomp/sections.h"', ""]
    for section in sections:
        overlays.append(f"static FuncEntry section_{section['index']}_{section['name']}_funcs[] = {{")
        for f in section["functions"]:
            if f in listed:
                overlays.append(f"    {{ .func = {f['name']}, .offset = 0x{f['vram'] - section['vram']:08X}, "
                                f".rom_size = 0x{0 if f['reimplemented'] else f['size']:08X} }},")
        overlays.append("};")
    overlays.append("static SectionTableEntry section_table[] = {")
    for section in sections:
        overlays.append(f"    {{ .rom_addr = 0x{section['rom']:08X}, .ram_addr = 0x{section['vram']:08X}, "
                        f".size = 0x{section['size']:08X}, .funcs = section_{section['index']}_{section['name']}_funcs, "
                        f".num_funcs = ARRLEN(section_{section['index']}_{section['name']}_funcs), "
                        f".relocs = nullptr, .num_relocs = 0, .index = {section['index']} }},")
    overlays += ["};", f"const size_t num_sections = {len(sections)};",
                 "static int overlay_sections_by_index[] = {", "    -1,", "};", ""]
    (output / "recomp_overlays.inl").write_text("\n".join(overlays))

    (output / "lookup.cpp").write_text(
        '#include "recomp.h"\n\n'
        f"gpr get_entrypoint_address() {{ return (gpr)(int32_t)0x{config['input']['entrypoint']:08X}u; }}\n\n"
        'const char* get_rom_name() { return ".z64"; }\n')

    game = ['// Generated by scripts/generate-n64interp.py from the game\'s N64Recomp configuration.',
            '#include "N64Interpreter.h"', ""]
    for f in functions:
        if f["name"] in redirects:
            target = redirects[f["name"]]
            game.append(f"void {target}(uint8_t* rdram, recomp_context* ctx);")
            game.append(f"void {f['name']}(uint8_t* rdram, recomp_context* ctx) {{ {target}(rdram, ctx); }}")
        elif f["ignored"]:
            # The runtime or the game's host code defines it; a recompiled build needs it too.
            game.append(f"__attribute__((weak)) void {f['name']}(uint8_t* rdram, recomp_context* ctx) "
                        f"{{ n64interp_missing(0x{f['vram']:08X}u, \"{f['name']}\"); }}")
        elif f["stubbed"]:
            game.append(f"void {f['name']}(uint8_t* rdram, recomp_context* ctx) {{ }}")
        else:
            game.append(f"void {f['name']}(uint8_t* rdram, recomp_context* ctx) "
                        f"{{ n64interp_call(rdram, ctx, 0x{f['vram']:08X}u); }}")
    game += [""] + shared_locals
    for vram, texts in sorted(hooks.items()):
        body = "".join(f"    {{ {text} }}\n" for text in texts)
        game.append(f"static uint32_t n64interp_hook_{vram:08X}(uint8_t* rdram, recomp_context* ctx) {{\n{body}"
                    "    return 0;\n}")
    game += ["", "void n64interp_register_game(void) {", "    static int registered;",
             "    if (registered) return;", "    registered = 1;"]
    for f in functions:
        if f["ignored"] or f["stubbed"] or f["name"] in redirects:
            game.append(f"    n64interp_set_replacement(0x{f['vram']:08X}u, {f['name']});")
    for vram in sorted(hooks):
        game.append(f"    n64interp_set_hook(0x{vram:08X}u, n64interp_hook_{vram:08X});")
    game += ["}", ""]
    (output / "n64interp_game.c").write_text("\n".join(game))
    return len(generated), sum(f["ignored"] for f in functions), len(hooks)


if __name__ == "__main__":
    if len(sys.argv) < 4 or not all("=" in arg or "@" in arg for arg in sys.argv[4:]):
        raise SystemExit(__doc__)
    extras = {name: int(address, 16) for name, address in (arg.split("@", 1) for arg in sys.argv[4:] if "@" in arg)}
    config, sections, functions, hooks = load(Path(sys.argv[1]), Path(sys.argv[2]), extras)
    redirects = dict(arg.split("=", 1) for arg in sys.argv[4:] if "=" in arg)
    missing = set(redirects) - {f["name"] for f in functions}
    if missing:
        raise SystemExit(f"generate-n64interp.py: the symbol file has no {', '.join(sorted(missing))}")
    shared_locals = share_hook_locals(hooks)
    interpreted, replaced, hooked = write(config, sections, functions, hook_functions(hooks), shared_locals,
                                          redirects, Path(sys.argv[3]))
    print(f"{interpreted} interpreted functions, {replaced} replaced by the runtime, hooks at {hooked} addresses")
