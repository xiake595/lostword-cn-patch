# -*- coding: utf-8 -*-
"""Find code xrefs (ADRP+ADD / ADRP+LDR) to a file-offset target inside a .so,
then disassemble a window around each xref with capstone (ARM64).

Usage: python find_xrefs.py <so> <target_file_offset> [window]
"""
import struct
import sys

from capstone import CS_ARCH_ARM64, CS_MODE_ARM, Cs
from elftools.elf.elffile import ELFFile


def main():
    path = sys.argv[1]
    target_off = int(sys.argv[2], 0)
    window = int(sys.argv[3]) if len(sys.argv) > 3 else 96
    f = open(path, 'rb')
    elf = ELFFile(f)
    # file offset -> VA
    target_va = None
    for sec in elf.iter_sections():
        off = sec['sh_offset']
        size = sec['sh_size']
        if off <= target_off < off + size and sec['sh_flags'] & 0x2:  # ALLOC
            target_va = sec['sh_addr'] + (target_off - off)
            break
    if target_va is None:
        print('target not in an allocated section')
        return
    print('target file_off=0x%X va=0x%X' % (target_off, target_va))
    # find .text
    text = None
    for sec in elf.iter_sections():
        if sec.name == '.text':
            text = sec
            break
    data = text.data()
    text_va = text['sh_addr']
    hits = []
    n = len(data) // 4
    insns = struct.unpack('<%dI' % n, data[:n * 4])
    for i in range(n - 4):
        w = insns[i]
        # ADRP: bits 31=1, 28..24=10000 -> 0x90000000 mask 0x9F000000 == 0x90000000
        if (w & 0x9F000000) != 0x90000000:
            continue
        rd = w & 0x1F
        immlo = (w >> 29) & 0x3
        immhi = (w >> 5) & 0x7FFFF
        imm = (immhi << 2) | immlo
        if imm & (1 << 20):
            imm -= 1 << 21
        page = ((text_va + i * 4) & ~0xFFF) + (imm << 12)
        # look ahead up to 6 instructions for ADD/LDR imm using same rd
        for j in range(1, 7):
            w2 = insns[i + j]
            # ADD (immediate) 64-bit: sf=1 op=0 S=0 100010 -> mask
            if (w2 & 0xFF800000) == 0x91000000:
                rn = (w2 >> 5) & 0x1F
                rd2 = w2 & 0x1F
                imm12 = (w2 >> 10) & 0xFFF
                shift = (w2 >> 22) & 0x3
                if rn == rd and rd2 == rd:
                    addr = page + (imm12 << (12 if shift == 1 else 0))
                    if addr == target_va:
                        hits.append((text_va + i * 4, 'add', j))
            # LDR (unsigned offset) 64-bit: 1111100101
            elif (w2 & 0xFFC00000) == 0xF9400000:
                rn = (w2 >> 5) & 0x1F
                imm12 = (w2 >> 10) & 0xFFF
                if rn == rd:
                    addr = page + imm12 * 8
                    if addr == target_va:
                        hits.append((text_va + i * 4, 'ldr', j))
    print('xref count:', len(hits))
    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    for va, kind, j in hits[:20]:
        start = va - window
        off = text['sh_offset'] + (start - text_va)
        print('=' * 80)
        print('xref at 0x%X (%s +%d)' % (va, kind, j))
        code = open(path, 'rb').read()[off:off + window * 2]
        for ins in md.disasm(code, start):
            mark = '  <== target' if ins.address == va else ''
            print('  %08x: %s %s%s' % (ins.address, ins.mnemonic, ins.op_str, mark))


if __name__ == '__main__':
    main()
