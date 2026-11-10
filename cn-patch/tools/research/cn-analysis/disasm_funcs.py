# -*- coding: utf-8 -*-
"""Disassemble selected IL2CPP methods from libil2cpp.so with symbol annotation.

Uses Il2CppDumper script.json (Address->Name) and capstone (ARM64).
Prints each instruction; bl/b calls are annotated with target method name.
Also resolves ADRP+ADD / ADRP+LDR literal references against stringliteral.json
when possible (best effort).
"""
import json
import struct
import sys

from capstone import CS_ARCH_ARM64, CS_MODE_ARM, Cs
from capstone.arm64 import ARM64_OP_IMM, ARM64_OP_MEM, ARM64_OP_REG

LIB = r'D:\Codex_Project\Lostword\work\cn-analysis\apk\split_arm64.apk__lib_arm64-v8a_libil2cpp.so'
SCRIPT = r'D:\Codex_Project\Lostword\work\cn-analysis\il2cpp-out\script.json'
STRINGS = r'D:\Codex_Project\Lostword\work\cn-analysis\il2cpp-out\stringliteral.json'


def load_elf(path):
    with open(path, 'rb') as f:
        data = f.read()
    assert data[:4] == b'\x7fELF'
    is64 = data[4] == 2
    assert is64
    e_phoff = struct.unpack_from('<Q', data, 0x20)[0]
    e_phentsize = struct.unpack_from('<H', data, 0x36)[0]
    e_phnum = struct.unpack_from('<H', data, 0x38)[0]
    segs = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from('<I', data, off)[0]
        if p_type != 1:  # PT_LOAD
            continue
        p_offset = struct.unpack_from('<Q', data, off + 0x08)[0]
        p_vaddr = struct.unpack_from('<Q', data, off + 0x10)[0]
        p_filesz = struct.unpack_from('<Q', data, off + 0x20)[0]
        segs.append((p_vaddr, p_vaddr + p_filesz, p_offset))
    return data, segs


def va_to_off(segs, va):
    for vstart, vend, off in segs:
        if vstart <= va < vend:
            return off + (va - vstart)
    return None


def main():
    lib, segs = load_elf(LIB)
    script = json.load(open(SCRIPT, encoding='utf-8'))
    addr2name = {}
    for m in script.get('ScriptMethod', []):
        a = int(m['Address'])
        if a and a not in addr2name:
            addr2name[a] = m['Name']
    # also ScriptString
    addr2str = {}
    try:
        for s in json.load(open(STRINGS, encoding='utf-8')):
            a = s.get('address')
            if a is not None:
                addr2str[int(a)] = s.get('value')
    except Exception as e:
        print('stringliteral load failed', e, file=sys.stderr)

    targets = [int(x, 0) for x in sys.argv[1:]]
    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    md.detail = True

    for tva in targets:
        off = va_to_off(segs, tva)
        print('=' * 100)
        print('METHOD VA 0x%X  name=%s  file_off=0x%X' % (tva, addr2name.get(tva, '?'), off or 0))
        if off is None:
            print('  <not in a PT_LOAD segment>')
            continue
        code = lib[off:off + 4096]
        insns = list(md.disasm(code, tva))
        # adrp tracking for string refs: reg -> page
        page_reg = {}
        for ins in insns[:200]:
            text = '%08x: %-8s %s %s' % (ins.address, ins.bytes.hex(), ins.mnemonic, ins.op_str)
            ann = ''
            if ins.mnemonic in ('bl', 'b') and ins.operands and ins.operands[0].type == ARM64_OP_IMM:
                tgt = ins.operands[0].imm
                nm = addr2name.get(tgt)
                if nm:
                    ann = '  ; -> ' + nm
                elif tgt in addr2str:
                    ann = '  ; -> string %r' % addr2str[tgt]
            if ins.mnemonic == 'adrp' and len(ins.operands) >= 2 and ins.operands[0].type == ARM64_OP_REG \
                    and ins.operands[1].type == ARM64_OP_IMM:
                page_reg[ins.reg_name(ins.operands[0].reg)] = ins.operands[1].imm
            if ins.mnemonic in ('add', 'ldr') and len(ins.operands) >= 3:
                base = ins.operands[1]
                if base.type == ARM64_OP_REG:
                    bname = ins.reg_name(base.reg)
                    if bname in page_reg:
                        if ins.mnemonic == 'add' and ins.operands[2].type == ARM64_OP_IMM:
                            full = page_reg[bname] + ins.operands[2].imm
                            if full in addr2str:
                                ann += '  ; str %r' % addr2str[full]
                            elif full in addr2name:
                                ann += '  ; addr ' + addr2name[full]
                        elif ins.mnemonic == 'ldr' and ins.operands[2].type == ARM64_OP_MEM:
                            full = page_reg[bname] + ins.operands[2].mem.disp
                            if full in addr2str:
                                ann += '  ; str %r' % addr2str[full]
            print(text + ann)
            if ins.mnemonic == 'ret' and ins.address != tva:
                break
            if ins.mnemonic in ('b',) and ins.address != tva:
                break


if __name__ == '__main__':
    main()
