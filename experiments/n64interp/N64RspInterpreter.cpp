// See N64RspInterpreter.h. Each case mirrors what RSPRecomp generates for that instruction.
#include "N64RspInterpreter.h"
#include "librecomp/rsp_vu_impl.hpp"

#include <TargetConditionals.h>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <utility>

namespace {
// COP2, LWC2 and SWC2. Their element is a template argument of librecomp's vector unit, so this
// is instantiated for each of the 16 and picked from a table.
template <u8 e> bool cop2(RSP &rsp, uint32_t ins, uint32_t *r) {
    auto &v = rsp.vpu.r;
    const unsigned base = (ins >> 21) & 31, vt = (ins >> 16) & 31, vs = (ins >> 11) & 31, vd = (ins >> 6) & 31;
    // RSPRecomp's Imm7: the offset's low 7 bits, sign-extended.
    const s8 offset = (s8)(s8((ins & 0x7F) << 1) >> 1);
    switch (ins >> 26) {
    case 0x32:
        switch (vs) {
        case 0: rsp.LBV<e>(v[vt], r[base], offset); return true;
        case 1: rsp.LSV<e>(v[vt], r[base], offset); return true;
        case 2: rsp.LLV<e>(v[vt], r[base], offset); return true;
        case 3: rsp.LDV<e>(v[vt], r[base], offset); return true;
        case 4: rsp.LQV<e>(v[vt], r[base], offset); return true;
        case 5: rsp.LRV<e>(v[vt], r[base], offset); return true;
        case 6: rsp.LPV<e>(v[vt], r[base], offset); return true;
        case 7: rsp.LUV<e>(v[vt], r[base], offset); return true;
        case 8: rsp.LHV<e>(v[vt], r[base], offset); return true;
        case 9: rsp.LFV<e>(v[vt], r[base], offset); return true;
        case 11: rsp.LTV<e>(vt, r[base], offset); return true;
        }
        return false;
    case 0x3A:
        switch (vs) {
        case 0: rsp.SBV<e>(v[vt], r[base], offset); return true;
        case 1: rsp.SSV<e>(v[vt], r[base], offset); return true;
        case 2: rsp.SLV<e>(v[vt], r[base], offset); return true;
        case 3: rsp.SDV<e>(v[vt], r[base], offset); return true;
        case 4: rsp.SQV<e>(v[vt], r[base], offset); return true;
        case 5: rsp.SRV<e>(v[vt], r[base], offset); return true;
        case 6: rsp.SPV<e>(v[vt], r[base], offset); return true;
        case 7: rsp.SUV<e>(v[vt], r[base], offset); return true;
        case 8: rsp.SHV<e>(v[vt], r[base], offset); return true;
        case 9: rsp.SFV<e>(v[vt], r[base], offset); return true;
        case 10: rsp.SWV<e>(v[vt], r[base], offset); return true;
        case 11: rsp.STV<e>(vt, r[base], offset); return true;
        }
        return false;
    }
    if (!(ins & (1u << 25))) {
        switch (base) {
        case 0: rsp.MFC2<e>(r[vt], v[vs]); return true;
        case 4: rsp.MTC2<e>(r[vt], v[vs]); return true;
        }
        return false;
    }
    auto &d = v[vd];
    const auto &s = v[vs], &t = v[vt];
    switch (ins & 63) {
    case 0x00: rsp.VMULF<e>(d, s, t); return true;
    case 0x01: rsp.VMULU<e>(d, s, t); return true;
    case 0x02: rsp.VRNDP<e>(d, vs, t); return true;
    case 0x03: rsp.VMULQ<e>(d, s, t); return true;
    case 0x04: rsp.VMUDL<e>(d, s, t); return true;
    case 0x05: rsp.VMUDM<e>(d, s, t); return true;
    case 0x06: rsp.VMUDN<e>(d, s, t); return true;
    case 0x07: rsp.VMUDH<e>(d, s, t); return true;
    case 0x08: rsp.VMACF<e>(d, s, t); return true;
    case 0x09: rsp.VMACU<e>(d, s, t); return true;
    case 0x0A: rsp.VRNDN<e>(d, vs, t); return true;
    case 0x0B: rsp.VMACQ(d); return true;
    case 0x0C: rsp.VMADL<e>(d, s, t); return true;
    case 0x0D: rsp.VMADM<e>(d, s, t); return true;
    case 0x0E: rsp.VMADN<e>(d, s, t); return true;
    case 0x0F: rsp.VMADH<e>(d, s, t); return true;
    case 0x10: rsp.VADD<e>(d, s, t); return true;
    case 0x11: rsp.VSUB<e>(d, s, t); return true;
    case 0x13: rsp.VABS<e>(d, s, t); return true;
    case 0x14: rsp.VADDC<e>(d, s, t); return true;
    case 0x15: rsp.VSUBC<e>(d, s, t); return true;
    case 0x1D: rsp.VSAR<e>(d, s); return true;
    case 0x20: rsp.VLT<e>(d, s, t); return true;
    case 0x21: rsp.VEQ<e>(d, s, t); return true;
    case 0x22: rsp.VNE<e>(d, s, t); return true;
    case 0x23: rsp.VGE<e>(d, s, t); return true;
    case 0x24: rsp.VCL<e>(d, s, t); return true;
    case 0x25: rsp.VCH<e>(d, s, t); return true;
    case 0x26: rsp.VCR<e>(d, s, t); return true;
    case 0x27: rsp.VMRG<e>(d, s, t); return true;
    case 0x28: rsp.VAND<e>(d, s, t); return true;
    case 0x29: rsp.VNAND<e>(d, s, t); return true;
    case 0x2A: rsp.VOR<e>(d, s, t); return true;
    case 0x2B: rsp.VNOR<e>(d, s, t); return true;
    case 0x2C: rsp.VXOR<e>(d, s, t); return true;
    case 0x2D: rsp.VNXOR<e>(d, s, t); return true;
    // RSPRecomp passes the vs field's low three bits as the destination element.
    case 0x30: rsp.VRCP<e>(d, vs & 7, t); return true;
    case 0x31: rsp.VRCPL<e>(d, vs & 7, t); return true;
    case 0x32: rsp.VRCPH<e>(d, vs & 7, t); return true;
    case 0x33: rsp.VMOV<e>(d, vs & 7, t); return true;
    case 0x34: rsp.VRSQ<e>(d, vs & 7, t); return true;
    case 0x35: rsp.VRSQL<e>(d, vs & 7, t); return true;
    case 0x36: rsp.VRSQH<e>(d, vs & 7, t); return true;
    case 0x37: rsp.VNOP(); return true;
    }
    return false;
}

using Cop2 = bool (*)(RSP &, uint32_t, uint32_t *);
template <u8... e> constexpr std::array<Cop2, 16> cop2_table(std::integer_sequence<u8, e...>) { return {{&cop2<e>...}}; }
constexpr auto cop2_ops = cop2_table(std::make_integer_sequence<u8, 16>());

#if TARGET_OS_SIMULATOR
// N64INTERP_RSP_CAPTURE=DIRECTORY saves the state 16 tasks, 120 tasks apart, start from, for
// RspSpike.cpp to compare this interpreter with a microcode RSPRecomp generated, on the Mac.
void capture(uint8_t *rdram, uint32_t ucode_addr) {
    static const char *directory = std::getenv("N64INTERP_RSP_CAPTURE");
    static unsigned task;
    if (!directory || task++ % 120 || task > 120 * 16) return;
    char path[1024];
    std::snprintf(path, sizeof path, "%s/task-%04u.bin", directory, task);
    if (FILE *file = std::fopen(path, "wb")) {
        std::fwrite(&ucode_addr, sizeof ucode_addr, 1, file);
        std::fwrite(dmem, 1, 0x1000, file);
        std::fwrite(rdram, 1, 0x800000, file);
        std::fclose(file);
    }
}
#endif

RspExitReason unsupported(uint32_t pc, uint32_t instruction) {
    std::fprintf(stderr, "[n64interp] unsupported RSP instruction %08X at %04X\n", instruction, 0x1000 + pc);
    return RspExitReason::Unsupported;
}
} // namespace

RspExitReason n64interp_rsp_run(uint8_t *rdram, uint32_t ucode_addr, const N64InterpRspPatch *patch) {
#if TARGET_OS_SIMULATOR
    capture(rdram, ucode_addr);
#endif
    // rspboot copies the microcode to IMEM 0x080 and starts it there. IMEM holds words as the
    // RSP reads them; pc below is an offset into it.
    uint32_t imem[0x400] = {};
    const gpr ucode = (gpr)(int32_t)(0x80000000u | (ucode_addr & 0x00FFFFFFu));
    for (uint32_t i = 0x20; i < 0x400; ++i) imem[i] = (uint32_t)MEM_W((int64_t)(i - 0x20) * 4, ucode);
    const uint32_t patch_pc = patch ? patch->pc & 0xFFC : 0x1000;
    if (patch && imem[patch_pc >> 2] != patch->instruction) {
        std::fprintf(stderr, "[n64interp] the RSP microcode at %08X has %08X at %04X, not the %08X its patch replaces\n",
                     ucode_addr, imem[patch_pc >> 2], patch->pc, patch->instruction);
        return RspExitReason::Unsupported;
    }

    // RSPRecomp's function locals.
    uint32_t r[32] = {};
    r[1] = 0xFC0;
    uint32_t dma_mem_address = 0, dma_dram_address = 0;
    RSP rsp{};
    uint32_t pc = 0x080, npc = 0x084;

    for (;;) {
        // RSPRecomp returns this when the code runs off the end of the microcode.
        if (pc >= 0x1000) return RspExitReason::ImemOverrun;
        uint32_t next = npc, next2 = npc + 4;
        if (pc == patch_pc) {
            patch->run(r);
        } else {
            const uint32_t ins = imem[pc >> 2];
            const unsigned rs = (ins >> 21) & 31, rt = (ins >> 16) & 31, rd = (ins >> 11) & 31, sa = (ins >> 6) & 31;
            const uint32_t imm = ins & 0xFFFF, simm = (uint32_t)(int32_t)(int16_t)imm;
            const uint32_t branch_target = (pc + 4 + (simm << 2)) & 0xFFC;
            switch (ins >> 26) {
            case 0x00: // SPECIAL
                switch (ins & 63) {
                case 0x00: r[rd] = r[rt] << sa; break;                                    // sll
                case 0x02: r[rd] = r[rt] >> sa; break;                                    // srl
                case 0x03: r[rd] = (uint32_t)((int32_t)r[rt] >> sa); break;               // sra
                case 0x04: r[rd] = r[rt] << (r[rs] & 31); break;                          // sllv
                case 0x06: r[rd] = r[rt] >> (r[rs] & 31); break;                          // srlv
                case 0x07: r[rd] = (uint32_t)((int32_t)r[rt] >> (r[rs] & 31)); break;     // srav
                case 0x08: next2 = r[rs] & 0xFFC; break;                                  // jr
                case 0x09: {                                                              // jalr
                    const uint32_t target = r[rs];
                    r[rd] = 0x1000 + pc + 8;
                    next2 = target & 0xFFC;
                    break;
                }
                case 0x0D: return RspExitReason::Broke;                                   // break
                case 0x20: case 0x21: r[rd] = r[rs] + r[rt]; break;                       // add, addu
                case 0x22: case 0x23: r[rd] = r[rs] - r[rt]; break;                       // sub, subu
                case 0x24: r[rd] = r[rs] & r[rt]; break;                                  // and
                case 0x25: r[rd] = r[rs] | r[rt]; break;                                  // or
                case 0x26: r[rd] = r[rs] ^ r[rt]; break;                                  // xor
                case 0x27: r[rd] = ~(r[rs] | r[rt]); break;                               // nor
                case 0x2A: r[rd] = (int32_t)r[rs] < (int32_t)r[rt]; break;                // slt
                case 0x2B: r[rd] = r[rs] < r[rt]; break;                                  // sltu
                default: return unsupported(pc, ins);
                }
                break;
            case 0x01: // REGIMM
                if (rt == 0) { if ((int32_t)r[rs] < 0) next2 = branch_target; }          // bltz
                else if (rt == 1) { if ((int32_t)r[rs] >= 0) next2 = branch_target; }    // bgez
                else return unsupported(pc, ins);
                break;
            case 0x02: next2 = (ins << 2) & 0xFFC; break;                                 // j
            case 0x03: r[31] = 0x1000 + pc + 8; next2 = (ins << 2) & 0xFFC; break;        // jal
            case 0x04: if (r[rs] == r[rt]) next2 = branch_target; break;                  // beq
            case 0x05: if (r[rs] != r[rt]) next2 = branch_target; break;                  // bne
            case 0x06: if ((int32_t)r[rs] <= 0) next2 = branch_target; break;             // blez
            case 0x07: if ((int32_t)r[rs] > 0) next2 = branch_target; break;              // bgtz
            case 0x08: case 0x09: r[rt] = r[rs] + simm; break;                            // addi, addiu
            case 0x0A: r[rt] = (int32_t)r[rs] < (int32_t)simm; break;                     // slti
            case 0x0B: r[rt] = r[rs] < simm; break;                                       // sltiu
            case 0x0C: r[rt] = r[rs] & imm; break;                                        // andi
            case 0x0D: r[rt] = r[rs] | imm; break;                                        // ori
            case 0x0E: r[rt] = r[rs] ^ imm; break;                                        // xori
            case 0x0F: r[rt] = imm << 16; break;                                          // lui
            case 0x10: // COP0, as RSPRecomp: DMA completes at once and nothing waits.
                if (rs == 0) {                                                            // mfc0
                    if (rd < 4 || (rd > 7 && rd != 11)) return unsupported(pc, ins);
                    r[rt] = 0;
                } else if (rs == 4) {                                                     // mtc0
                    switch (rd) {
                    case 0: dma_mem_address = r[rt]; break;
                    case 1: dma_dram_address = r[rt]; break;
                    case 2: dma_rdram_to_dmem(rdram, dma_mem_address, dma_dram_address, r[rt]); break;
                    case 3: dma_dmem_to_rdram(rdram, dma_mem_address, dma_dram_address, r[rt]); break;
                    case 4: case 7: break;
                    default: return unsupported(pc, ins);
                    }
                } else {
                    return unsupported(pc, ins);
                }
                break;
            case 0x12: // COP2
                if (!cop2_ops[(ins >> ((ins & (1u << 25)) ? 21 : 7)) & 15](rsp, ins, r)) return unsupported(pc, ins);
                break;
            case 0x20: r[rt] = RSP_MEM_B(simm, r[rs]); break;                             // lb
            case 0x21: r[rt] = RSP_MEM_H_LOAD(simm, r[rs]); break;                        // lh
            case 0x23: r[rt] = RSP_MEM_W_LOAD(simm, r[rs]); break;                        // lw
            case 0x24: r[rt] = RSP_MEM_BU(simm, r[rs]); break;                            // lbu
            case 0x25: r[rt] = RSP_MEM_HU_LOAD(simm, r[rs]); break;                       // lhu
            case 0x28: RSP_MEM_B(simm, r[rs]) = (int8_t)r[rt]; break;                     // sb
            case 0x29: RSP_MEM_H_STORE(simm, r[rs], r[rt]); break;                        // sh
            case 0x2B: RSP_MEM_W_STORE(simm, r[rs], r[rt]); break;                        // sw
            case 0x32: case 0x3A:                                                         // lwc2, swc2
                if (!cop2_ops[(ins >> 7) & 15](rsp, ins, r)) return unsupported(pc, ins);
                break;
            default: return unsupported(pc, ins);
            }
        }
        r[0] = 0;
        pc = next;
        npc = next2;
    }
}
