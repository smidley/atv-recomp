// See N64Interpreter.h. Each case mirrors what N64Recomp generates for that instruction
// (N64Recomp/src/operations.cpp, cgenerator.cpp and recompilation.cpp), using recomp.h's own
// macros and helpers, so results match the recompiled code on the same CPU.
#include "N64Interpreter.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <unordered_map>
#include <vector>

namespace {
// Native callers' return address: a KSEG3 address that game code never runs.
constexpr uint32_t kSentinel = 0xFFFFFFF0u;
// Replacements and hooks are looked up through bitmaps over the first 8 MB of KSEG0.
constexpr uint32_t kSpanWords = 0x00800000u / 4;

// Built on first use, so games can register before other static objects exist.
struct Tables {
    std::vector<uint64_t> replacement_bits = std::vector<uint64_t>(kSpanWords / 64);
    std::vector<uint64_t> hook_bits = std::vector<uint64_t>(kSpanWords / 64);
    std::unordered_map<uint32_t, recomp_func_t *> replacements;
    std::unordered_map<uint32_t, n64interp_hook_t *> hooks;
};
Tables &tables() {
    static Tables instance;
    return instance;
}
std::atomic<uint64_t> executed{0};

inline bool marked(const std::vector<uint64_t> &bits, uint32_t vram) {
    const uint32_t index = (vram - 0x80000000u) >> 2;
    return index < kSpanWords && ((bits[index >> 6] >> (index & 63)) & 1);
}

void mark(std::vector<uint64_t> &bits, uint32_t vram) {
    const uint32_t index = (vram - 0x80000000u) >> 2;
    if (index >= kSpanWords) {
        std::fprintf(stderr, "[n64interp] address %08X is outside the first 8 MB of KSEG0\n", vram);
        std::abort();
    }
    bits[index >> 6] |= uint64_t(1) << (index & 63);
}

[[noreturn]] void unsupported(uint32_t pc, uint32_t instruction) {
    std::fprintf(stderr, "[n64interp] unsupported instruction %08X at %08X\n", instruction, pc);
    std::abort();
}

void warn_once(const char *what, uint32_t pc) {
    static std::atomic<int> warnings{0};
    if (warnings.fetch_add(1) < 20) std::fprintf(stderr, "[n64interp] %s at %08X ignored\n", what, pc);
}

// N64Recomp reads odd single-precision registers through f_odd, which follows the FR mode.
inline uint32_t &u32l(recomp_context *ctx, fpr *f, unsigned n) {
    return (n & 1) ? ctx->f_odd[(n - 1) * 2] : f[n].u32l;
}
} // namespace

void n64interp_set_replacement(uint32_t vram, recomp_func_t *function) {
    tables().replacements[vram] = function;
    mark(tables().replacement_bits, vram);
}

void n64interp_set_hook(uint32_t vram, n64interp_hook_t *hook) {
    tables().hooks[vram] = hook;
    mark(tables().hook_bits, vram);
}

void n64interp_missing(uint32_t vram, const char *name) {
    std::fprintf(stderr, "[n64interp] the game called %s at %08X, which nothing implements\n", name, vram);
    std::abort();
}

static const n64interp_rom_patch_t *rom_patches;
static uint32_t rom_patch_count;

void n64interp_set_rom_patches(const n64interp_rom_patch_t *patches, uint32_t count) {
    rom_patches = patches;
    rom_patch_count = count;
}

bool n64interp_begin_game(void (*game)(void)) {
    static void (*current)(void);
    if (current == game) return false;
    current = game;
    Tables &t = tables();
    std::fill(t.replacement_bits.begin(), t.replacement_bits.end(), 0);
    std::fill(t.hook_bits.begin(), t.hook_bits.end(), 0);
    t.replacements.clear();
    t.hooks.clear();
    rom_patches = nullptr;
    rom_patch_count = 0;
    return true;
}

void n64interp_rom_loaded(uint8_t *rdram, uint32_t rom, uint32_t vram, uint32_t size) {
    for (uint32_t i = 0; i < rom_patch_count; ++i) {
        const uint32_t offset = rom_patches[i].rom - rom;
        if (rom_patches[i].rom >= rom && offset + 4 <= size)
            MEM_W(0, (gpr)(int32_t)(vram + offset)) = (int32_t)rom_patches[i].value;
    }
}

uint64_t n64interp_instruction_count(void) {
    return executed.load(std::memory_order_relaxed);
}

void n64interp_call(uint8_t *rdram, recomp_context *ctx, uint32_t vram) {
    const Tables &table = tables();
    const auto &replacement_bits = table.replacement_bits, &hook_bits = table.hook_bits;
    const auto &replacements = table.replacements;
    const auto &hooks = table.hooks;
    gpr *const r = &ctx->r0;
    fpr *const f = &ctx->f0;
    // Locals in every generated function, never carried between them.
    uint64_t hi = 0, lo = 0, result = 0;
    int c1cs = 0;
    uint64_t count = 0;
    ctx->r31 = (gpr)(int32_t)kSentinel;
    uint32_t pc = vram, npc = vram + 4;

    for (;;) {
        if (pc == kSentinel) break;
        // A function the runtime replaces runs natively however it is reached: called, jumped to,
        // or entered from the function before it, which Racer's tools/fix_fallthroughs.py makes its
        // recompiled code call. Like the C call it stands for, it returns to $ra, even if it ran
        // game code on this context, which moves $ra. A taken jump's delay slot is never an entry.
        if (npc == pc + 4 && marked(replacement_bits, pc)) {
            const uint32_t return_to = (uint32_t)r[31];
            replacements.find(pc)->second(rdram, ctx);
            pc = return_to;
            npc = pc + 4;
            continue;
        }
        if (marked(hook_bits, pc)) {
            const uint32_t return_to = (uint32_t)r[31];
            const uint32_t action = hooks.find(pc)->second(rdram, ctx);
            if (action == N64INTERP_RETURN) {
                pc = return_to;
                npc = pc + 4;
                continue;
            }
            if (action != 0) {
                pc = action;
                npc = pc + 4;
                continue;
            }
        }

        const uint32_t ins = (uint32_t)MEM_W(0, (gpr)(int32_t)pc);
        const unsigned op = ins >> 26, rs = (ins >> 21) & 31, rt = (ins >> 16) & 31, rd = (ins >> 11) & 31;
        const unsigned sa = (ins >> 6) & 31, fn = ins & 63;
        const uint16_t imm = ins & 0xFFFF;
        const int16_t simm = (int16_t)imm;
        const uint32_t branch_target = pc + 4 + ((int32_t)simm << 2);
        uint32_t next = npc, next2 = npc + 4;
        auto branch = [&](bool taken) { if (taken) next2 = branch_target; };
        auto branch_likely = [&](bool taken) {
            if (taken) next2 = branch_target;
            else { next = npc + 4; next2 = npc + 8; }
        };
        auto jump = [&](uint32_t target) { next2 = target; };
        // IDO probes memory with loads into $zero. N64Recomp with navjack's zero-register patch
        // (Cruis'n) drops them, stock N64Recomp can't compile them, and a probed register would fault.
        const bool probe = rt == 0 && (op == 0x1A || op == 0x1B || (op >= 0x20 && op <= 0x27) || op == 0x30 || op == 0x37);

        if (!probe) switch (op) {
        case 0x00: // SPECIAL
            switch (fn) {
            case 0x00: r[rd] = S32(r[rt] << sa); break;                      // sll
            case 0x02: r[rd] = S32(U32(r[rt]) >> sa); break;                 // srl
            case 0x03: r[rd] = S32(SIGNED(r[rt]) >> sa); break;              // sra
            case 0x04: r[rd] = S32(r[rt] << (r[rs] & 31)); break;            // sllv
            case 0x06: r[rd] = S32(U32(r[rt]) >> (r[rs] & 31)); break;       // srlv
            case 0x07: r[rd] = S32(SIGNED(r[rt]) >> (r[rs] & 31)); break;    // srav
            case 0x08: jump((uint32_t)r[rs]); break;                         // jr
            case 0x09:                                                       // jalr
                if (rd != 31) unsupported(pc, ins);
                {
                    const uint32_t target = (uint32_t)r[rs];
                    r[31] = (gpr)(int32_t)(pc + 8);
                    jump(target);
                }
                break;
            case 0x0C: unsupported(pc, ins);                                 // syscall: N64 games don't use it
            case 0x0D: do_break(pc); break;                                  // break
            case 0x0F: break;                                                // sync
            case 0x10: r[rd] = hi; break;                                    // mfhi
            case 0x11: hi = r[rs]; break;                                    // mthi
            case 0x12: r[rd] = lo; break;                                    // mflo
            case 0x13: lo = r[rs]; break;                                    // mtlo
            case 0x14: r[rd] = r[rt] << (r[rs] & 63); break;                 // dsllv
            case 0x16: r[rd] = r[rt] >> (r[rs] & 63); break;                 // dsrlv
            case 0x17: r[rd] = SIGNED(r[rt]) >> (r[rs] & 63); break;         // dsrav
            case 0x18:                                                       // mult
                result = S64(S32(r[rs])) * S64(S32(r[rt])); lo = S32(result >> 0); hi = S32(result >> 32);
                break;
            case 0x19:                                                       // multu
                result = U64(U32(r[rs])) * U64(U32(r[rt])); lo = S32(result >> 0); hi = S32(result >> 32);
                break;
            case 0x1A:                                                       // div
                // ARM64's sdiv gives 0 for a zero divisor, which the recompiled code relies on.
                if (S32(r[rt]) == 0) { lo = 0; hi = S32(r[rs]); }
                else { lo = S32(S64(S32(r[rs])) / S64(S32(r[rt]))); hi = S32(S64(S32(r[rs])) % S64(S32(r[rt]))); }
                break;
            case 0x1B:                                                       // divu
                if (U32(r[rt]) == 0) { lo = 0; hi = S32(r[rs]); }
                else { lo = S32(U32(r[rs]) / U32(r[rt])); hi = S32(U32(r[rs]) % U32(r[rt])); }
                break;
            case 0x1C: DMULT(S64(r[rs]), S64(r[rt]), (int64_t *)&lo, (int64_t *)&hi); break;   // dmult
            case 0x1D: DMULTU(U64(r[rs]), U64(r[rt]), &lo, &hi); break;                      // dmultu
            case 0x1E:                                                                         // ddiv
                if (S64(r[rt]) == 0) { lo = 0; hi = r[rs]; }
                else DDIV(S64(r[rs]), S64(r[rt]), (int64_t *)&lo, (int64_t *)&hi);
                break;
            case 0x1F:                                                                         // ddivu
                if (U64(r[rt]) == 0) { lo = 0; hi = r[rs]; }
                else DDIVU(U64(r[rs]), U64(r[rt]), &lo, &hi);
                break;
            case 0x20: case 0x21: r[rd] = ADD32(r[rs], r[rt]); break;        // add, addu
            case 0x22: case 0x23: r[rd] = SUB32(r[rs], r[rt]); break;        // sub, subu
            case 0x24: r[rd] = r[rs] & r[rt]; break;                         // and
            case 0x25: r[rd] = r[rs] | r[rt]; break;                         // or
            case 0x26: r[rd] = r[rs] ^ r[rt]; break;                         // xor
            case 0x27: r[rd] = ~(r[rs] | r[rt]); break;                      // nor
            case 0x2A: r[rd] = SIGNED(r[rs]) < SIGNED(r[rt]) ? 1 : 0; break; // slt
            case 0x2B: r[rd] = r[rs] < r[rt] ? 1 : 0; break;                 // sltu
            case 0x2C: case 0x2D: r[rd] = r[rs] + r[rt]; break;              // dadd, daddu
            case 0x2E: case 0x2F: r[rd] = r[rs] - r[rt]; break;              // dsub, dsubu
            case 0x30: case 0x31: case 0x32: case 0x33: case 0x34: case 0x36:
                warn_once("trap", pc); break;                                // tge..tne
            case 0x38: r[rd] = r[rt] << sa; break;                           // dsll
            case 0x3A: r[rd] = r[rt] >> sa; break;                           // dsrl
            case 0x3B: r[rd] = SIGNED(r[rt]) >> sa; break;                   // dsra
            case 0x3C: r[rd] = r[rt] << (sa + 32); break;                    // dsll32
            case 0x3E: r[rd] = r[rt] >> (sa + 32); break;                    // dsrl32
            case 0x3F: r[rd] = SIGNED(r[rt]) >> (sa + 32); break;            // dsra32
            default: unsupported(pc, ins);
            }
            break;
        case 0x01: // REGIMM
            switch (rt) {
            case 0x00: branch(SIGNED(r[rs]) < 0); break;                     // bltz
            case 0x01: branch(SIGNED(r[rs]) >= 0); break;                    // bgez
            case 0x02: branch_likely(SIGNED(r[rs]) < 0); break;              // bltzl
            case 0x03: branch_likely(SIGNED(r[rs]) >= 0); break;             // bgezl
            case 0x10: case 0x11: case 0x12: case 0x13: {                    // bltzal, bgezal(l)
                const bool taken = (rt & 1) ? SIGNED(r[rs]) >= 0 : SIGNED(r[rs]) < 0;
                r[31] = (gpr)(int32_t)(pc + 8);
                if (rt & 2) branch_likely(taken); else branch(taken);
                break;
            }
            case 0x08: case 0x09: case 0x0A: case 0x0B: case 0x0C: case 0x0E:
                warn_once("trap", pc); break;
            default: unsupported(pc, ins);
            }
            break;
        case 0x02: case 0x03: {                                              // j, jal
            const uint32_t target = ((pc + 4) & 0xF0000000u) | ((ins & 0x03FFFFFFu) << 2);
            if (op == 0x02 && target == pc) { pause_self(rdram); break; }
            if (op == 0x03) r[31] = (gpr)(int32_t)(pc + 8);
            jump(target);
            break;
        }
        case 0x04:                                                           // beq (b when rs = rt = 0)
            if (rs == 0 && rt == 0) {
                if (branch_target == pc) { pause_self(rdram); break; }
                jump(branch_target);
            } else {
                branch(r[rs] == r[rt]);
            }
            break;
        case 0x05: branch(r[rs] != r[rt]); break;                            // bne
        case 0x06: branch(SIGNED(r[rs]) <= 0); break;                        // blez
        case 0x07: branch(SIGNED(r[rs]) > 0); break;                         // bgtz
        case 0x08: case 0x09: r[rt] = ADD32(r[rs], (int64_t)simm); break;    // addi, addiu
        case 0x0A: r[rt] = SIGNED(r[rs]) < (int64_t)simm ? 1 : 0; break;     // slti
        case 0x0B: r[rt] = r[rs] < (gpr)(int64_t)simm ? 1 : 0; break;        // sltiu
        case 0x0C: r[rt] = r[rs] & imm; break;                               // andi
        case 0x0D: r[rt] = r[rs] | imm; break;                               // ori
        case 0x0E: r[rt] = r[rs] ^ imm; break;                               // xori
        case 0x0F: r[rt] = S32((uint32_t)imm << 16); break;                  // lui
        case 0x10: // COP0: N64Recomp handles only the status register; with navjack's
                   // N64Recomp-cop0-registers.patch (Cruis'n) the context keeps the others.
            if (rs == 0x00) {                                                // mfc0
#ifdef N64INTERP_COP0_REGISTERS
                if (rt != 0) r[rt] = cop0_read(ctx, rd);
#else
                if (rd == 12) r[rt] = cop0_status_read(ctx);
                else { warn_once("mfc0", pc); r[rt] = 0; }
#endif
            } else if (rs == 0x04) {                                         // mtc0
#ifdef N64INTERP_COP0_REGISTERS
                cop0_write(ctx, rd, r[rt]);
#else
                if (rd == 12) cop0_status_write(ctx, r[rt]);
                else warn_once("mtc0", pc);
#endif
            } else {
                warn_once("cop0 operation", pc);
            }
            break;
        case 0x11: // COP1
            switch (rs) {
            case 0x00: r[rt] = (int32_t)u32l(ctx, f, rd); break;             // mfc1
            case 0x01: r[rt] = f[rd].u64; break;                             // dmfc1
            case 0x02:                                                       // cfc1
                if (rd != 31) unsupported(pc, ins);
                r[rt] = get_cop1_cs();
                break;
            case 0x04: u32l(ctx, f, rd) = (uint32_t)r[rt]; break;            // mtc1
            case 0x05: f[rd].u64 = r[rt]; break;                             // dmtc1
            case 0x06:                                                       // ctc1
                if (rd != 31) unsupported(pc, ins);
                set_cop1_cs((uint32_t)r[rt]);
                break;
            case 0x08:                                                       // bc1f, bc1t, bc1fl, bc1tl
                if (rt & 2) branch_likely((c1cs != 0) == ((rt & 1) != 0));
                else branch((c1cs != 0) == ((rt & 1) != 0));
                break;
            case 0x10: { // single precision; fd = sa, fs = rd, ft = rt
                const unsigned fd = sa, fs = rd, ft = rt;
                switch (fn) {
                case 0x00: f[fd].fl = f[fs].fl + f[ft].fl; break;
                case 0x01: f[fd].fl = f[fs].fl - f[ft].fl; break;
                case 0x02: f[fd].fl = MUL_S(f[fs].fl, f[ft].fl); break;
                case 0x03: f[fd].fl = DIV_S(f[fs].fl, f[ft].fl); break;
                case 0x04: f[fd].fl = sqrtf(f[fs].fl); break;
                case 0x05: f[fd].fl = fabsf(f[fs].fl); break;
                case 0x06: f[fd].fl = f[fs].fl; break;
                case 0x07: f[fd].fl = -f[fs].fl; break;
                case 0x08: f[fd].u64 = (uint64_t)llroundf(f[fs].fl); break;              // round.l.s
                case 0x09: f[fd].u64 = (uint64_t)TRUNC_L_S(f[fs].fl); break;             // trunc.l.s
                case 0x0A: f[fd].u64 = (uint64_t)S64(ceilf(f[fs].fl)); break;            // ceil.l.s
                case 0x0B: f[fd].u64 = (uint64_t)S64(floorf(f[fs].fl)); break;           // floor.l.s
                case 0x0C: u32l(ctx, f, fd) = (uint32_t)lroundf(f[fs].fl); break;        // round.w.s
                case 0x0D: u32l(ctx, f, fd) = (uint32_t)TRUNC_W_S(f[fs].fl); break;      // trunc.w.s
                case 0x0E: u32l(ctx, f, fd) = (uint32_t)S32(ceilf(f[fs].fl)); break;     // ceil.w.s
                case 0x0F: u32l(ctx, f, fd) = (uint32_t)S32(floorf(f[fs].fl)); break;    // floor.w.s
                case 0x21: f[fd].d = CVT_D_S(f[fs].fl); break;                           // cvt.d.s
                case 0x24: u32l(ctx, f, fd) = (uint32_t)CVT_W_S(f[fs].fl); break;        // cvt.w.s
                case 0x25: f[fd].u64 = (uint64_t)do_cvt_l_s(f[fs].fl); break;            // cvt.l.s
                default:
                    if (fn < 0x30) unsupported(pc, ins);
                    // c.cond.s: false, false, ==, ==, <, <, <=, <= (N64Recomp ignores ordering)
                    switch ((fn >> 1) & 3) {
                    case 0: c1cs = 0; break;
                    case 1: c1cs = f[fs].fl == f[ft].fl; break;
                    case 2: c1cs = f[fs].fl < f[ft].fl; break;
                    case 3: c1cs = f[fs].fl <= f[ft].fl; break;
                    }
                }
                break;
            }
            case 0x11: { // double precision
                const unsigned fd = sa, fs = rd, ft = rt;
                switch (fn) {
                case 0x00: f[fd].d = f[fs].d + f[ft].d; break;
                case 0x01: f[fd].d = f[fs].d - f[ft].d; break;
                case 0x02: f[fd].d = MUL_D(f[fs].d, f[ft].d); break;
                case 0x03: f[fd].d = DIV_D(f[fs].d, f[ft].d); break;
                case 0x04: f[fd].d = sqrt(f[fs].d); break;
                case 0x05: f[fd].d = fabs(f[fs].d); break;
                case 0x06: f[fd].d = f[fs].d; break;
                case 0x07: f[fd].d = -f[fs].d; break;
                case 0x08: f[fd].u64 = (uint64_t)llround(f[fs].d); break;
                case 0x09: f[fd].u64 = (uint64_t)TRUNC_L_D(f[fs].d); break;
                case 0x0A: f[fd].u64 = (uint64_t)S64(ceil(f[fs].d)); break;
                case 0x0B: f[fd].u64 = (uint64_t)S64(floor(f[fs].d)); break;
                case 0x0C: u32l(ctx, f, fd) = (uint32_t)lround(f[fs].d); break;
                case 0x0D: u32l(ctx, f, fd) = (uint32_t)TRUNC_W_D(f[fs].d); break;
                case 0x0E: u32l(ctx, f, fd) = (uint32_t)S32(ceil(f[fs].d)); break;
                case 0x0F: u32l(ctx, f, fd) = (uint32_t)S32(floor(f[fs].d)); break;
                case 0x20: f[fd].fl = CVT_S_D(f[fs].d); break;                           // cvt.s.d
                case 0x24: u32l(ctx, f, fd) = (uint32_t)CVT_W_D(f[fs].d); break;         // cvt.w.d
                case 0x25: f[fd].u64 = (uint64_t)CVT_L_D(f[fs].d); break;                // cvt.l.d
                default:
                    if (fn < 0x30) unsupported(pc, ins);
                    switch ((fn >> 1) & 3) {
                    case 0: c1cs = 0; break;
                    case 1: c1cs = f[fs].d == f[ft].d; break;
                    case 2: c1cs = f[fs].d < f[ft].d; break;
                    case 3: c1cs = f[fs].d <= f[ft].d; break;
                    }
                }
                break;
            }
            case 0x14: { // word
                const unsigned fd = sa, fs = rd;
                if (fn == 0x20) f[fd].fl = CVT_S_W(u32l(ctx, f, fs));            // cvt.s.w
                else if (fn == 0x21) f[fd].d = CVT_D_W(u32l(ctx, f, fs));        // cvt.d.w
                else unsupported(pc, ins);
                break;
            }
            case 0x15: { // long
                const unsigned fd = sa, fs = rd;
                if (fn == 0x20) f[fd].fl = CVT_S_L(f[fs].u64);                    // cvt.s.l
                else if (fn == 0x21) f[fd].d = CVT_D_L(f[fs].u64);                // cvt.d.l
                else unsupported(pc, ins);
                break;
            }
            default: unsupported(pc, ins);
            }
            break;
        case 0x14: branch_likely(r[rs] == r[rt]); break;                     // beql
        case 0x15: branch_likely(r[rs] != r[rt]); break;                     // bnel
        case 0x16: branch_likely(SIGNED(r[rs]) <= 0); break;                 // blezl
        case 0x17: branch_likely(SIGNED(r[rs]) > 0); break;                  // bgtzl
        case 0x18: case 0x19: r[rt] = r[rs] + (gpr)(int64_t)simm; break;     // daddi, daddiu
        case 0x1A: r[rt] = do_ldl(rdram, r[rt], (int64_t)simm, r[rs]); break;   // ldl
        case 0x1B: r[rt] = do_ldr(rdram, r[rt], (int64_t)simm, r[rs]); break;   // ldr
        case 0x20: r[rt] = MEM_B((int64_t)simm, r[rs]); break;               // lb
        case 0x21: r[rt] = MEM_H((int64_t)simm, r[rs]); break;               // lh
        case 0x22: r[rt] = do_lwl(rdram, r[rt], (int64_t)simm, r[rs]); break;   // lwl
        case 0x23: case 0x30: r[rt] = MEM_W((int64_t)simm, r[rs]); break;    // lw, ll
        case 0x24: r[rt] = MEM_BU((int64_t)simm, r[rs]); break;              // lbu
        case 0x25: r[rt] = MEM_HU((int64_t)simm, r[rs]); break;              // lhu
        case 0x26: r[rt] = do_lwr(rdram, r[rt], (int64_t)simm, r[rs]); break;   // lwr
        case 0x27: r[rt] = (uint32_t)MEM_W((int64_t)simm, r[rs]); break;     // lwu
        case 0x28: MEM_B((int64_t)simm, r[rs]) = (int8_t)r[rt]; break;       // sb
        case 0x29: MEM_H((int64_t)simm, r[rs]) = (int16_t)r[rt]; break;      // sh
        case 0x2A: do_swl(rdram, (int64_t)simm, r[rs], r[rt]); break;        // swl
        case 0x2B: MEM_W((int64_t)simm, r[rs]) = (int32_t)r[rt]; break;      // sw
        case 0x2C: do_sdl(rdram, (int64_t)simm, r[rs], r[rt]); break;        // sdl
        case 0x2D: do_sdr(rdram, (int64_t)simm, r[rs], r[rt]); break;        // sdr
        case 0x2E: do_swr(rdram, (int64_t)simm, r[rs], r[rt]); break;        // swr
        case 0x2F: break;                                                    // cache
        case 0x31: u32l(ctx, f, rt) = (uint32_t)MEM_W((int64_t)simm, r[rs]); break;   // lwc1
        case 0x35: f[rt].u64 = LD((int64_t)simm, r[rs]); break;              // ldc1
        case 0x37: r[rt] = LD((int64_t)simm, r[rs]); break;                  // ld
        case 0x38: MEM_W((int64_t)simm, r[rs]) = (int32_t)r[rt]; r[rt] = 1; break;    // sc
        case 0x39: MEM_W((int64_t)simm, r[rs]) = (int32_t)u32l(ctx, f, rt); break;    // swc1
        case 0x3D: SD(f[rt].u64, (int64_t)simm, r[rs]); break;               // sdc1
        case 0x3F: SD(r[rt], (int64_t)simm, r[rs]); break;                   // sd
        default: unsupported(pc, ins);
        }

        r[0] = 0;
        ++count;
        pc = next;
        npc = next2;
    }
    executed.fetch_add(count, std::memory_order_relaxed);
}
