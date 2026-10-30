// What SotE-Recomp links but Apple TV leaves out.
#include <cstdint>
#include "nfd.h"
#include "recompiler/live_recompiler.h"

// Code mods: N64ModernRuntime compiles a mod's code to native code while the game runs, which
// tvOS doesn't allow. prepare-sote.py makes every code mod fail to load, so these never run.
void N64Recomp::live_recompiler_init() {}
N64Recomp::LiveGeneratorOutput::~LiveGeneratorOutput() {}
size_t N64Recomp::LiveGeneratorOutput::num_reference_symbol_jumps() const { return 0; }
void N64Recomp::LiveGeneratorOutput::set_reference_symbol_jump(size_t, recomp_func_t *) {}
N64Recomp::ReferenceJumpDetails N64Recomp::LiveGeneratorOutput::get_reference_symbol_jump_details(size_t) { return {}; }
void N64Recomp::LiveGeneratorOutput::populate_import_symbol_jumps(size_t, recomp_func_t *) {}
N64Recomp::ShimFunction::ShimFunction(recomp_func_ext_t *, uintptr_t) : code(nullptr), func(nullptr) {}
N64Recomp::ShimFunction::~ShimFunction() {}

// File dialogs: only RT64's developer inspector opens them, and Apple TV has no file picker.
nfdresult_t NFD_Init(void) { return NFD_ERROR; }
void NFD_Quit(void) {}
void NFD_FreePathN(nfdnchar_t *) {}
nfdresult_t NFD_OpenDialogN(nfdnchar_t **, const nfdnfilteritem_t *, nfdfiltersize_t, const nfdnchar_t *) { return NFD_CANCEL; }
nfdresult_t NFD_SaveDialogN(nfdnchar_t **, const nfdnfilteritem_t *, nfdfiltersize_t, const nfdnchar_t *,
    const nfdnchar_t *) { return NFD_CANCEL; }
nfdresult_t NFD_PickFolderN(nfdnchar_t **, const nfdnchar_t *) { return NFD_CANCEL; }

// PC cutscenes: they play SAN movies from the PC version's files through LGPL-2.1 sandec. Apple TV
// has no such files, so every movie is reported unavailable and the N64 cutscenes play instead.
extern "C" {
struct sanio;
int sandec_init(void **) { return -1; }
int sandec_open(void *, struct sanio *) { return -1; }
int sandec_decode_next_frame(void *) { return -1; }
void sandec_exit(void **context) { if (context) *context = nullptr; }
int sandec_get_framecount(void *) { return 0; }
}
