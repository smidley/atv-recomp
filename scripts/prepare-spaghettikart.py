"""Prepare the pinned port without changing its checkout or reading any game ROM."""
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
pin = json.loads((root / "upstream/spaghettikart-baseline.json").read_text())
source = root / "build/upstream/SpaghettiKart"
actual = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
if actual != pin["sources"]["spaghettikart"]["revision"]:
    raise SystemExit("The SpaghettiKart checkout does not match the pinned release.")
if subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"], text=True).strip():
    raise SystemExit("Preserve the upstream checkout's local edits before preparing a generated copy.")
destination = root / "build/spaghettikart/source"
shutil.copytree(source, destination, dirs_exist_ok=True,
    ignore=shutil.ignore_patterns(".git", "src", "libultraship", "torch", "doxygen-awesome-css"))
# The shared runtime's CVar names are a configuration ABI.
mapping = {
    "gVsyncEnabled": "gSettings.VsyncEnabled",
    "gInternalResolution": "gSettings.InternalResolution",
    "gMSAAValue": "gSettings.MSAAValue",
    "gControlNav": "gSettings.ControlNav",
    "gTextureFilter": "gSettings.TextureFilter",
    "gSdlWindowedFullscreen": "gSettings.SdlWindowedFullscreen",
    "gEnableMultiViewports": "gSettings.EnableMultiViewports",
    "gInterpolationFPS": "gSettings.InterpolationFPS",
    "gMatchRefreshRate": "gSettings.MatchRefreshRate",
    "gLowResMode": "gSettings.LowResMode",
}


def adapt(relative, text):
    # Current libultraship owns Context and separates Fast3D GUI/backend types.
    text = text.replace('Context::GetInstance()', 'Context::GetRawInstance()')
    text = text.replace('std::shared_ptr<Ship::Context> context;', 'Ship::Context* context = nullptr;')
    text = text.replace('this->context->InitGfxDebugger();', '// Fast3dWindow initializes its own graphics debugger.')
    text = text.replace('"port/mobile/MobileImpl.h"', '"ship/port/mobile/MobileImpl.h"')
    text = text.replace('Ship::WindowBackend::', 'Fast::WindowBackend::')
    text = text.replace('Ship::WindowBackend', 'int32_t')
    for old, new in mapping.items():
        text = text.replace('"' + old + '"', '"' + new + '"')
    text = text.replace('"gAdvancedResolution.', '"gSettings.AdvancedResolution.')
    if relative == 'port/SpaghettiGui.h':
        text = text.replace('#include "ship/window/gui/Gui.h"', '#include "fast/Fast3dGui.h"')
        text = text.replace('class SpaghettiGui : public Gui', 'class SpaghettiGui : public Fast::Fast3dGui')
        text = text.replace(': Gui(', ': Fast::Fast3dGui(')
    if relative == 'port/ui/MenuTypes.h':
        text = '#include "fast/Fast3dWindow.h"\n' + text
    if relative == 'port/ui/ImguiUI.cpp':
        text = '#include "fast/Fast3dGui.h"\n' + text
        text = text.replace('Ship::Context::GetRawInstance()->GetWindow()->GetGui()->GetTextureByName',
            'std::static_pointer_cast<Fast::Fast3dGui>(Ship::Context::GetRawInstance()->GetWindow()->GetGui())->GetTextureByName')
    # HMAS mixes PCM for SDL; it must not initialize a second audio device.
    if relative == 'port/audio/HMAS.cpp':
        text = '#define MA_NO_DEVICE_IO\n' + text
    if relative == 'port/Engine.cpp':
        text = text.replace('#include "Engine.h"', '#include "Engine.h"\n#include "AppleTVPerformance.h"\n'
            '#include "libultraship/window/gui/InputEditorWindow.h"\n'
            'void NativecadeKartInputProbeInit();\nvoid NativecadeKartInputProbeTick();')
        text = text.replace('auto controlDeck = std::make_shared<LUS::ControlDeck>',
            'NativecadeKartInputProbeInit();\n    auto controlDeck = std::make_shared<LUS::ControlDeck>')
        text = text.replace('wnd->HandleEvents();', 'NativecadeKartInputProbeTick();\n    wnd->HandleEvents();')
        text = text.replace('std::make_shared<Ship::SpaghettiGui>(std::vector<std::shared_ptr<Ship::GuiWindow>>({}))',
            'std::make_shared<Ship::SpaghettiGui>(std::vector<std::shared_ptr<Ship::GuiWindow>>({'
            'std::make_shared<LUS::InputEditorWindow>("gInputEditorWindow", "Input Editor")}))')
        text = text.replace('this->context->InitConsoleVariables();',
            'this->context->InitConsoleVariables();\n    RecompTVInitializePerformanceDefaults();')
        start = text.index('uint32_t GameEngine::GetInterpolationFPS() {')
        end = text.index('\nuint32_t GameEngine::GetInterpolationFrameCount()', start)
        text = text[:start] + ('uint32_t GameEngine::GetInterpolationFPS() {\n'
            '    return RecompTVGetFrameTarget(CVarGetInteger("gSettings.InterpolationFPS", 60),\n'
            '        CVarGetInteger("gSettings.MatchRefreshRate", 0));\n}\n') + text[end:]
        text = text.replace('wnd->DrawAndRunGraphicsCommands(pool, mtxStack);',
            'RecompTVPrepareFrame(wnd->GetTargetFps());\n'
            '        if (wnd->DrawAndRunGraphicsCommands(pool, mtxStack)) RecompTVRecordFrame(wnd->GetTargetFps());')
    if relative == 'engine/tracks/Track.cpp':
        # KartRestart.cpp clears this set when Nativecade restarts the game in one process.
        text = text.replace('static std::unordered_set<std::string> gModifiedGfxSet;',
            'std::unordered_set<std::string> gModifiedGfxSet;')
    return text


for original in (source / "src").rglob("*"):
    if not original.is_file():
        continue
    relative = original.relative_to(source / "src").as_posix()
    target = destination / "src" / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if original.suffix not in {".c", ".cpp", ".h"}:
        shutil.copy2(original, target)
        continue
    text = adapt(relative, original.read_text())
    # Preserve timestamps when an adapter hasn't changed, keeping rebuilds small.
    if not target.exists() or target.read_text() != text:
        target.write_text(text)
# Shared Torch supports newer MK64 ports that use indexed display-list buffers
# and runtime texture segments. SpaghettiKart 1.0.0 resolves both by asset hash.
# Adapt only these two exports; the Ocarina path and upstream checkout stay intact.
torch = root / "build/upstream/Torch"
baseline = json.loads((root / "upstream/shipwright-baseline.json").read_text())
if subprocess.check_output(["git", "-C", str(torch), "rev-parse", "HEAD"], text=True).strip() != baseline["sources"]["torch"]["revision"]:
    raise SystemExit("Use the pinned shared Torch checkout.")
if subprocess.check_output(["git", "-C", str(torch), "status", "--porcelain"], text=True).strip():
    raise SystemExit("Preserve the Torch checkout's local edits before preparing a generated adapter.")
factory = (torch / "src/factories/DisplayListFactory.cpp").read_text()
start = factory.index('            // Export displaylist segment addresses as an index into a buffer of gfx')
end = factory.index('\n\n            writer.Write(w0);', start)
factory = factory[:start] + '''            // Nativecade: SpaghettiKart 1.0.0 uses hash-addressed assets.
            value = gsSPDisplayListOTRHash(ptr);
            w0 = value.words.w0;
            w1 = value.words.w1;''' + factory[end:]
start = factory.index('            } else if ((Companion::Instance->GetGBIMinorVersion() == GBIMinorVersion::Mk64)')
end = factory.index('            } else if ((Companion::Instance->GetGBIMinorVersion() == GBIMinorVersion::BK64)', start)
factory = factory[:start] + factory[end:]
target = destination.parent / "torch-compat/DisplayListFactory.cpp"
target.parent.mkdir(exist_ok=True)
if not target.exists() or target.read_text() != factory:
    target.write_text(factory)
# A separately compressed asset starts at byte zero in its decoded buffer.
# Subtracting its ROM offset truncates large TKMK00 textures such as the title
# background (320x240 RGBA16), even though their dimensions remain unchanged.
decoder = (torch / "src/utils/Decompressor.cpp").read_text()
assert decoder.count('size_t decodedSize = decoded->size - offset;') == 2
decoder = decoder.replace('size_t decodedSize = decoded->size - offset;',
                          'size_t decodedSize = decoded->size;')
target = destination.parent / "torch-compat/Decompressor.cpp"
if not target.exists() or target.read_text() != decoder:
    target.write_text(decoder)
print(f"Prepared SpaghettiKart {pin['release']} in {destination}")
