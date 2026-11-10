package tlw.fps;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.util.Log;

import java.io.File;
import java.io.RandomAccessFile;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Finds Application.targetFrameRate inside libunity.so and writes it from
 * inside the game process.
 *
 * Unity's arm64 accessors are extremely regular:
 *
 *   get_targetFrameRate:        set_targetFrameRate:
 *       adrp  x8, page              adrp  x8, page
 *       ldr   w0, [x8, #off]        str   w0, [x8, #off]
 *       ret                         b     ...
 *
 * Both land on the same static int32 in .data/.bss, so intersecting the two
 * candidate sets leaves only a handful of addresses; the one holding -1 (or 0)
 * is targetFrameRate.
 */
final class UnityFps {

    static final String LIB = "libunity.so";

    /** offset tables verified against real builds */
    private static final String[] KNOWN_VER = {"1.57.0", "1.58.0", "1.71.1"};
    private static final long OFF_TFR_KNOWN = 0x199cc54L;

    private final Context ctx;
    private final SharedPreferences sp;

    long base;
    long offTfr;
    String how = "none";

    UnityFps(Context c) {
        ctx = c.getApplicationContext();
        sp = ctx.getSharedPreferences(TlwCore.PREFS, Context.MODE_PRIVATE);
    }

    private String version() {
        try {
            PackageInfo pi = ctx.getPackageManager().getPackageInfo(ctx.getPackageName(), 0);
            return pi.versionName == null ? "?" : pi.versionName;
        } catch (Throwable t) {
            return "?";
        }
    }

    /** wait for libunity.so, then pick the view the arm64 code actually writes to */
    boolean attach(long timeoutMs) {
        String ver = version();
        long cached = sp.getLong("off_" + ver, -1L);
        long want = (cached > 0L) ? cached : OFF_TFR_KNOWN;

        long deadline = System.currentTimeMillis() + timeoutMs;
        long picked = 0L;
        int seen = 0;

        // Under an arm-on-x86 translator (MuMu / LDPlayer) libunity.so is mapped
        // more than once: a read-only host view used by the translator plus the
        // guest view the arm64 code actually runs against. Only the guest view has
        // a WRITABLE page at base+offset, so that is the one we take.
        while (System.currentTimeMillis() < deadline) {
            List<Long> cands = Mem.basesOf(LIB);
            seen = cands.size();
            for (long c : cands) {
                if (!Mem.canWrite(c + want)) continue;
                Integer v = Mem.tryReadIntChecked(c + want);
                if (v == null) continue;
                picked = c;
                if (v == -1 || v == 0 || (v >= 15 && v <= 480)) break;
            }
            if (picked != 0L) break;
            // nothing writable yet: fall back to any readable view so we at least
            // report something instead of hanging forever
            if (System.currentTimeMillis() > deadline - 2000L && !cands.isEmpty()) {
                for (long c : cands) {
                    if (Mem.tryReadIntChecked(c + want) != null) { picked = c; break; }
                }
            }
            sleep(120);
        }
        if (picked == 0L) {
            List<Long> cands = Mem.basesOf(LIB);
            if (!cands.isEmpty()) picked = cands.get(0);
        }
        if (picked == 0L) {
            how = "等不到 libunity";
            return false;
        }
        base = picked;

        if (cached > 0L && plausible(base, cached)) {
            offTfr = cached;
            how = "缓存 " + ver;
        } else if (isKnown(ver) && plausible(base, OFF_TFR_KNOWN)) {
            offTfr = OFF_TFR_KNOWN;
            how = "内置 " + ver;
            sp.edit().putLong("off_" + ver, offTfr).apply();
        } else {
            long r = scan();
            if (r > 0L && Mem.tryReadIntChecked(base + r) != null) {
                offTfr = r;
                how = "扫描 " + ver;
                sp.edit().putLong("off_" + ver, offTfr).apply();
            } else {
                offTfr = OFF_TFR_KNOWN;
                how = "回退 " + ver;
            }
        }

        Log.i(TlwCore.TAG, "attach base=0x" + Long.toHexString(base)
                + " views=" + seen
                + " tfr=0x" + Long.toHexString(offTfr)
                + " writable=" + Mem.canWrite(base + offTfr)
                + " via " + how);
        return true;
    }

    private static boolean isKnown(String v) {
        for (String k : KNOWN_VER) if (k.equals(v)) return true;
        return false;
    }

    /** a targetFrameRate cell only ever holds -1, 0 or a sane frame rate */
    private static boolean plausible(long b, long off) {
        Integer v = Mem.tryReadIntChecked(b + off);
        return v != null && (v == -1 || v == 0 || (v >= 15 && v <= 480));
    }

    /**
     * Hot path -- called from the badge's onDraw() once per frame.
     *
     * Deliberately does NOT touch /proc/self/maps: that file is 3000+ lines in
     * this game and parsing it costs ~11ms, which at 120fps meant burning a full
     * core just to paint a number. The address was validated once during attach.
     */
    int readTfr() {
        return offTfr > 0L && base != 0L ? Mem.readInt(base + offTfr) : Integer.MIN_VALUE;
    }

    boolean writeTfr(int fps) {
        if (offTfr <= 0L || base == 0L) return false;
        return Mem.writeInt(base + offTfr, fps);
    }

    /** push the saved target into the game; <=0 means "the game's own default" */
    void applyDesired() {
        int want = TlwCore.desired();
        writeTfr(want > 0 ? want : -1);
    }

    // ---------------------------------------------------------------- base

    private static boolean isElf64(long base) {
        if (base <= 0L) return false;
        Integer m0 = Mem.tryReadInt(base);
        if (m0 == null || (m0 & 0xFFFFFFFFL) != 0x464C457FL) return false;   // \x7fELF
        Integer cls = Mem.tryReadInt(base + 4);
        if (cls == null) return false;
        return (cls & 0xFF) == 2 && ((cls >>> 8) & 0xFF) == 1;               // ELF64, LE
    }

    // ------------------------------------------------------------- scanning

    private long scan() {
        try {
            String path = Mem.pathOf(LIB);
            if (path == null) return -1L;
            File f = new File(path);
            if (!f.canRead() || f.length() < 4096) return -1L;

            RandomAccessFile raf = new RandomAccessFile(f, "r");
            try {
                byte[] head = new byte[64];
                raf.readFully(head);
                if (head[0] != 0x7F || head[1] != 'E' || head[2] != 'L' || head[3] != 'F') return -1L;
                if (head[4] != 2) return -1L;

                long phoff = rq(head, 0x20);
                int phentsz = (int) ru(head, 0x36);
                int phnum = (int) ru(head, 0x38);
                if (phentsz <= 0 || phnum <= 0 || phnum > 64) return -1L;

                byte[] ph = new byte[phentsz * phnum];
                raf.seek(phoff);
                raf.readFully(ph);

                List<long[]> segs = new ArrayList<>();
                for (int i = 0; i < phnum; i++) {
                    int o = i * phentsz;
                    if (ru(ph, o) != 1) continue;
                    segs.add(new long[]{ru(ph, o + 4), rq(ph, o + 8), rq(ph, o + 16),
                            rq(ph, o + 32), rq(ph, o + 40)});
                }
                if (segs.isEmpty()) return -1L;

                List<long[]> dataRanges = new ArrayList<>();
                for (long[] s : segs) {
                    if ((s[0] & 2) != 0 && (s[0] & 1) == 0) {
                        dataRanges.add(new long[]{s[2], s[2] + s[4]});
                    }
                }

                Set<Long> getters = new HashSet<>();
                Set<Long> setters = new HashSet<>();

                for (long[] s : segs) {
                    if ((s[0] & 1) == 0) continue;
                    long start = s[1];
                    long size = Math.min(s[3], 96L * 1024 * 1024);
                    if (size < 16) continue;
                    byte[] code = new byte[(int) size];
                    raf.seek(start);
                    raf.readFully(code);

                    long[] page = new long[32];
                    boolean[] has = new boolean[32];
                    int n = (int) (size / 4);

                    for (int i = 0; i < n; i++) {
                        int o = i * 4;
                        long insn = ru(code, o);
                        long va = s[2] + (long) i * 4;

                        if ((insn & 0x9F000000L) == 0x90000000L) {           // ADRP
                            int rd = (int) (insn & 0x1F);
                            long imm = (((insn >>> 5) & 0x7FFFF) << 2) | ((insn >>> 29) & 3);
                            if ((imm & 0x100000L) != 0) imm -= 0x200000L;
                            page[rd] = (va & ~0xFFFL) + (imm << 12);
                            has[rd] = true;
                            continue;
                        }
                        if ((insn & 0xFFC00000L) == 0xB9400000L) {           // LDR Wt,[Xn,#imm12]
                            int rt = (int) (insn & 0x1F);
                            int rn = (int) ((insn >>> 5) & 0x1F);
                            if (rt == 0 && rn == 8 && has[8] && i + 1 < n
                                    && ru(code, o + 4) == 0xD65F03C0L) {     // RET
                                long t = page[8] + ((insn >>> 10) & 0xFFF) * 4;
                                if (inRange(dataRanges, t)) getters.add(t);
                            }
                            continue;
                        }
                        if ((insn & 0xFFC00000L) == 0xB9000000L) {           // STR Wt,[Xn,#imm12]
                            int rt = (int) (insn & 0x1F);
                            int rn = (int) ((insn >>> 5) & 0x1F);
                            if (rt == 0 && rn == 8 && has[8] && i + 1 < n
                                    && (ru(code, o + 4) & 0xFC000000L) == 0x14000000L) {   // B
                                long t = page[8] + ((insn >>> 10) & 0xFFF) * 4;
                                if (inRange(dataRanges, t)) setters.add(t);
                            }
                        }
                    }
                }

                Set<Long> inter = new HashSet<>(getters);
                inter.retainAll(setters);

                long best = -1L;
                for (long a : inter) {
                    Integer v = Mem.tryReadInt(base + a);
                    if (v != null && (v == -1 || v == 0)) { best = a; break; }
                }
                if (best < 0 && inter.size() == 1) best = inter.iterator().next();

                Log.i(TlwCore.TAG, "scan getters=" + getters.size() + " setters=" + setters.size()
                        + " inter=" + inter.size() + " -> 0x" + Long.toHexString(best));
                return best;
            } finally {
                raf.close();
            }
        } catch (Throwable t) {
            Log.e(TlwCore.TAG, "scan failed", t);
            return -1L;
        }
    }

    private static boolean inRange(List<long[]> ranges, long va) {
        for (long[] r : ranges) if (va >= r[0] && va < r[1]) return true;
        return false;
    }

    private static long ru(byte[] b, int o) {
        return (b[o] & 0xFFL) | ((b[o + 1] & 0xFFL) << 8)
                | ((b[o + 2] & 0xFFL) << 16) | ((b[o + 3] & 0xFFL) << 24);
    }

    private static long rq(byte[] b, int o) {
        return ru(b, o) | (ru(b, o + 4) << 32);
    }

    static void sleep(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException ignored) {}
    }
}
