package tlw.fps;

import java.io.RandomAccessFile;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

/**
 * In-process memory access.
 *
 * This code runs INSIDE the game process, so the address space is ours:
 * no root, no ptrace, no adb, no injected native module.
 *
 * Reads and writes go through sun.misc.Unsafe, which is always present in
 * Android's libcore. Unsafe does not bounds-check, so every access is first
 * validated against /proc/self/maps -- touching an unmapped page would take the
 * whole game down with SIGSEGV, and that is exactly what we must never do.
 *
 * IMPORTANT: /proc/self/maps is 3000+ lines / ~300KB in this game and parsing it
 * costs ~11ms. Reading it per call (the first version did) meant every badge
 * repaint parsed the whole file -- 120x per second while dragging, which burned
 * a full core. The snapshot is therefore cached and refreshed on a timer, and
 * reads that fall inside a known range skip the re-parse entirely.
 */
final class Mem {

    static volatile String mode = "-";

    /** how long a maps snapshot is trusted before it is re-read */
    private static final long MAPS_TTL_MS = 3000L;

    private static volatile List<Range> cachedMaps = null;
    private static volatile long cachedAt = 0L;

    // ------------------------------------------------------------------ maps

    /** one row of /proc/self/maps */
    static final class Range {
        long start, end;
        String perms;
        long offset;
        String path;

        boolean has(long a) { return a >= start && a < end; }
        boolean readable() { return perms.length() > 0 && perms.charAt(0) == 'r'; }
        boolean writable() { return perms.length() > 1 && perms.charAt(1) == 'w'; }
    }

    /** cached view of /proc/self/maps; re-read at most once per MAPS_TTL_MS */
    static List<Range> maps() {
        long now = System.currentTimeMillis();
        List<Range> c = cachedMaps;
        if (c != null && now - cachedAt < MAPS_TTL_MS) return c;
        return reloadMaps();
    }

    static List<Range> reloadMaps() {
        List<Range> out = new ArrayList<>();
        RandomAccessFile raf = null;
        try {
            raf = new RandomAccessFile("/proc/self/maps", "r");
            String line;
            while ((line = raf.readLine()) != null) {
                try {
                    Range r = new Range();
                    int sp1 = line.indexOf(' ');
                    if (sp1 < 0) continue;
                    String addr = line.substring(0, sp1);
                    int dash = addr.indexOf('-');
                    r.start = Long.parseLong(addr.substring(0, dash), 16);
                    r.end = Long.parseLong(addr.substring(dash + 1), 16);

                    String rest = line.substring(sp1 + 1).trim();
                    // perms offset dev inode [path]
                    String[] f = rest.split("\\s+");
                    if (f.length < 4) continue;
                    r.perms = f[0];
                    r.offset = Long.parseLong(f[1], 16);
                    r.path = f.length > 4 ? f[4] : "";
                    out.add(r);
                } catch (Throwable ignored) {
                }
            }
        } catch (Throwable ignored) {
        } finally {
            close(raf);
        }
        cachedMaps = out;
        cachedAt = System.currentTimeMillis();
        return out;
    }

    static boolean mapped(List<Range> ms, long addr, boolean needWrite) {
        if (addr <= 0L) return false;
        for (Range r : ms) {
            if (!r.has(addr)) continue;
            if (!r.readable()) return false;
            return !needWrite || r.writable();
        }
        return false;
    }

    static boolean canWrite(long addr) {
        return mapped(maps(), addr, true);
    }

    static boolean canRead(long addr) {
        return mapped(maps(), addr, false);
    }

    /** every mapping of libName whose file offset is 0 -- each one is a load base */
    static List<Long> basesOf(String libName) {
        List<Long> out = new ArrayList<>();
        for (Range r : reloadMaps()) {
            if (r.offset != 0L) continue;
            if (r.path == null || !r.path.endsWith(libName)) continue;
            if (r.start == 0L) continue;
            if (!out.contains(r.start)) out.add(r.start);
        }
        return out;
    }

    static String pathOf(String libName) {
        for (Range r : maps()) {
            if (r.path != null && r.path.endsWith(libName) && r.path.startsWith("/")) return r.path;
        }
        return null;
    }

    // ---------------------------------------------------------------- unsafe

    private static Object unsafe;
    private static Method mPutInt, mGetInt;

    static {
        try {
            Class<?> c = Class.forName("sun.misc.Unsafe");
            Field f = c.getDeclaredField("theUnsafe");
            f.setAccessible(true);
            unsafe = f.get(null);
            mPutInt = c.getMethod("putInt", long.class, int.class);
            mGetInt = c.getMethod("getInt", long.class);
        } catch (Throwable t) {
            unsafe = null;
        }
    }

    static boolean hasUnsafe() { return unsafe != null; }

    /**
     * @return the int at addr, or null when the address is not safely readable
     *
     * Hot path: called from the badge's onDraw(). Everything here must stay O(1)
     * after the first call -- the address was validated once by the caller.
     */
    static Integer tryReadInt(long addr) {
        if (unsafe == null || addr <= 0L) return null;
        try {
            int v = (Integer) mGetInt.invoke(unsafe, addr);
            mode = "U";
            return v;
        } catch (Throwable t) {
            return null;
        }
    }

    /** same as tryReadInt but validates against maps first (cold path / setup) */
    static Integer tryReadIntChecked(long addr) {
        if (!canRead(addr)) return null;
        return tryReadInt(addr);
    }

    static int readInt(long addr) {
        Integer v = tryReadInt(addr);
        return v == null ? Integer.MIN_VALUE : v;
    }

    static boolean writeInt(long addr, int val) {
        if (unsafe == null || addr <= 0L) return false;
        if (!canWrite(addr)) return false;
        try {
            mPutInt.invoke(unsafe, addr, val);
            mode = "U";
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    private static void close(RandomAccessFile r) {
        try { if (r != null) r.close(); } catch (Throwable ignored) {}
    }

    private Mem() {}
}
