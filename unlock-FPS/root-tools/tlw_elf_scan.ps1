# tlw_elf_scan.ps1 - locate gTargetFrameRate offset in libunity.so
#
# No Python, no external tools. Uses PowerShell 5.1 + inline C# for speed.
#
# Unity's accessors have a very regular signature:
#
#   get_targetFrameRate:          set_targetFrameRate:
#       adrp  x8, <page>              adrp  x8, <page>
#       ldr   w0, [x8, #imm]          str   w0, [x8, #imm]
#       ret                           b     <...>
#
# Both point at the same address. Intersecting getter and setter
# results narrows the candidates down to exactly one.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tlw_elf_scan.ps1 libunity.so
#   powershell -ExecutionPolicy Bypass -File tlw_elf_scan.ps1 libunity.so -List

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Path,
    [switch]$List
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "ERROR: file not found: $Path" -ForegroundColor Red
    exit 1
}

$full = (Resolve-Path -LiteralPath $Path).Path

$src = @'
using System;
using System.Collections.Generic;
using System.IO;

public class ElfScan
{
    public class Hit
    {
        public long VA;
        public long At;
        public Hit(long va, long at) { VA = va; At = at; }
    }

    static long R32(byte[] b, int o)
    {
        return (long)((uint)(b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)));
    }
    static long R64(byte[] b, int o)
    {
        long lo = R32(b, o);
        long hi = R32(b, o + 4);
        return lo | (hi << 32);
    }
    static int R16(byte[] b, int o)
    {
        return b[o] | (b[o + 1] << 8);
    }

    public static string Run(string path, out List<Hit> getters, out List<Hit> setters, out string err)
    {
        getters = new List<Hit>();
        setters = new List<Hit>();
        err = null;

        byte[] b;
        try { b = File.ReadAllBytes(path); }
        catch (Exception e) { err = "read failed: " + e.Message; return null; }

        if (b.Length < 64 || b[0] != 0x7F || b[1] != 0x45 || b[2] != 0x4C || b[3] != 0x46)
        { err = "not an ELF file"; return null; }
        if (b[4] != 2) { err = "not ELF64"; return null; }

        int phoff = (int)R64(b, 0x20);
        int phentsz = R16(b, 0x36);
        int phnum = R16(b, 0x38);

        var loadOff = new List<long>();
        var loadVa = new List<long>();
        var loadSz = new List<long>();
        var loadFl = new List<long>();

        for (int i = 0; i < phnum; i++)
        {
            int o = phoff + i * phentsz;
            if (o + 56 > b.Length) break;
            if (R32(b, o) != 1) continue;
            loadOff.Add(R64(b, o + 8));
            loadVa.Add(R64(b, o + 16));
            loadSz.Add(R64(b, o + 32));
            loadFl.Add(R32(b, o + 4));
        }

        if (loadOff.Count == 0) { err = "no PT_LOAD"; return null; }

        // data ranges (writable, not executable)
        var dataLo = new List<long>();
        var dataHi = new List<long>();
        for (int i = 0; i < loadOff.Count; i++)
        {
            if ((loadFl[i] & 2) != 0 && (loadFl[i] & 1) == 0)
            {
                dataLo.Add(loadVa[i]);
                dataHi.Add(loadVa[i] + loadSz[i]);
            }
        }

        Func<long, bool> inData = va =>
        {
            for (int i = 0; i < dataLo.Count; i++)
                if (va >= dataLo[i] && va < dataHi[i]) return true;
            return false;
        };

        for (int s = 0; s < loadOff.Count; s++)
        {
            if ((loadFl[s] & 1) == 0) continue;

            int start = (int)loadOff[s];
            int size = (int)loadSz[s];
            long baseVa = loadVa[s];
            if (start + size > b.Length) size = b.Length - start;
            int n = size / 4;
            if (n < 3) continue;

            // adrp cache: reg -> page
            long[] page = new long[32];
            bool[] hasPage = new bool[32];

            for (int i = 0; i < n; i++)
            {
                int o = start + i * 4;
                long insn = R32(b, o);
                long va = baseVa + i * 4;

                // ADRP
                if ((insn & 0x9F000000L) == 0x90000000L)
                {
                    int rd = (int)(insn & 0x1F);
                    long immlo = (insn >> 29) & 0x3;
                    long immhi = (insn >> 5) & 0x7FFFF;
                    long imm = (immhi << 2) | immlo;
                    if ((imm & 0x100000L) != 0) imm -= 0x200000L;
                    long pg = (va & ~0xFFFL) + (imm << 12);
                    page[rd] = pg;
                    hasPage[rd] = true;
                    continue;
                }

                // LDR Wt,[Xn,#imm12] + RET
                if ((insn & 0xFFC00000L) == 0xB9400000L)
                {
                    int rt = (int)(insn & 0x1F);
                    int rn = (int)((insn >> 5) & 0x1F);
                    long imm12 = (insn >> 10) & 0xFFF;
                    if (rt == 0 && rn == 8 && hasPage[8] && i + 1 < n)
                    {
                        long nxt = R32(b, start + (i + 1) * 4);
                        if (nxt == 0xD65F03C0L)
                        {
                            long t = page[8] + imm12 * 4;
                            if (inData(t)) getters.Add(new Hit(t, va));
                        }
                    }
                    continue;
                }

                // STR Wt,[Xn,#imm12] + B
                if ((insn & 0xFFC00000L) == 0xB9000000L)
                {
                    int rt = (int)(insn & 0x1F);
                    int rn = (int)((insn >> 5) & 0x1F);
                    long imm12 = (insn >> 10) & 0xFFF;
                    if (rt == 0 && rn == 8 && hasPage[8] && i + 1 < n)
                    {
                        long nxt = R32(b, start + (i + 1) * 4);
                        if ((nxt & 0xFC000000L) == 0x14000000L)
                        {
                            long t = page[8] + imm12 * 4;
                            if (inData(t)) setters.Add(new Hit(t, va));
                        }
                    }
                    continue;
                }
            }
        }

        return "ok";
    }
}
'@

try {
    Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop
} catch {
    if ($_.Exception.Message -notmatch 'already exists') {
        Write-Host "ERROR: failed to compile helper" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}

$getters = $null
$setters = $null
$err = $null
$r = [ElfScan]::Run($full, [ref]$getters, [ref]$setters, [ref]$err)

if ($r -ne 'ok') {
    Write-Host "ERROR: $err" -ForegroundColor Red
    exit 1
}

if ($List) {
    Write-Host "getter candidates: $($getters.Count)" -ForegroundColor Cyan
    foreach ($g in $getters) { Write-Host ("  0x{0:x}  code=0x{1:x}" -f $g.VA, $g.At) -ForegroundColor DarkGray }
    Write-Host "setter candidates: $($setters.Count)" -ForegroundColor Cyan
    foreach ($s in $setters) { Write-Host ("  0x{0:x}  code=0x{1:x}" -f $s.VA, $s.At) -ForegroundColor DarkGray }
}

# intersect
$gMap = @{}
foreach ($g in $getters) { $gMap[[int64]$g.VA] = [int64]$g.At }

$both = New-Object System.Collections.ArrayList
foreach ($s in $setters) {
    if ($gMap.ContainsKey([int64]$s.VA)) { [void]$both.Add([int64]$s.VA) }
}

$best = $null
if ($both.Count -ge 1) {
    $sorted = $both | Sort-Object -Unique | Sort-Object { $gMap[$_] }
    $best = $sorted[0]
}
elseif ($getters.Count -eq 1) { $best = [int64]$getters[0].VA }
elseif ($setters.Count -eq 1) { $best = [int64]$setters[0].VA }

if ($null -eq $best) {
    Write-Host "ERROR: could not determine offset" -ForegroundColor Red
    Write-Host "       getters=$($getters.Count) setters=$($setters.Count) intersection=$($both.Count)" -ForegroundColor Red
    exit 1
}

$out = "0x" + $best.ToString('x')
Write-Host "offset: $out" -ForegroundColor Green
Write-Output $out
