package tlw.fps;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;

/**
 * Glue: boots the resolver, keeps the value pinned, and hands the overlay to
 * whichever Activity comes to the front.
 */
public final class TlwCore {

    static final String TAG = "TlwFps";
    static final String PREFS = "tlw_fps";

    static final String K_FPS = "desired_fps";     // -1 = 游戏默认（写回原厂 -1）
    static final String K_X = "ball_x";
    static final String K_Y = "ball_y";
    static final String K_HIDDEN = "hidden";

    private static volatile boolean installed = false;
    private static volatile UnityFps unity = null;
    private static volatile FpsOverlay overlay = null;
    static SharedPreferences prefs;
    private static volatile Context appCtx;

    static void install(Context ctx) {
        if (installed) return;
        installed = true;

        final Context app = ctx.getApplicationContext();
        appCtx = app;
        prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);

        // first launch: start at the panel's own refresh rate. The stock value the
        // game leaves behind (-1) means "no explicit cap", which lands on the
        // engine's own mobile default -- measured ~30fps here, far below the
        // display, so "do nothing" looks broken to anyone who installs this.
        if (!prefs.getBoolean("seeded", false)) {
            int hz = refreshHz(app);
            prefs.edit().putInt(K_FPS, hz).putBoolean("seeded", true).apply();
            Log.i(TAG, "first run, default target = " + hz + " fps");
        }

        // a fresh launch always shows the badge; only the long-press close is
        // meant to hide it, and that one is per-process
        prefs.edit().putInt(K_HIDDEN, 0).apply();

        if (app instanceof Application) {
            ((Application) app).registerActivityLifecycleCallbacks(new Life());
        }

        // ask for "display over other apps" once; without it we fall back to the
        // (slower) decorView host
        if (!Host.canOverlay(app)) {
            new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
                @Override public void run() { requestOverlayPermission(app); }
            }, 1500L);
        }

        Thread t = new Thread(new Runnable() {
            @Override public void run() {
                UnityFps u = new UnityFps(app);
                if (!u.attach(120000L)) {
                    Log.w(TAG, "libunity.so never appeared");
                    return;
                }
                unity = u;
                u.applyDesired();
                guard(u);
            }
        }, "tlw-fps");
        t.setDaemon(true);
        t.start();

        Log.i(TAG, "installed");
    }

    /** the game rewrites targetFrameRate on scene loads, so keep it pinned */
    private static void guard(UnityFps u) {
        while (true) {
            UnityFps.sleep(1000L);
            try {
                int want = desired();
                int live = u.readTfr();
                if (live != Integer.MIN_VALUE) cachedTfr = live;   // feed the badge
                if (want > 0 && live != want) {
                    u.writeTfr(want);
                } else if (want <= 0 && live > 0) {
                    // user asked for the game's own default again
                    u.writeTfr(-1);
                }
            } catch (Throwable ignored) {
            }
        }
    }

    static int desired() {
        return prefs == null ? -1 : prefs.getInt(K_FPS, -1);
    }

    static void setDesired(int fps) {
        if (prefs == null) return;
        prefs.edit().putInt(K_FPS, fps).apply();
        UnityFps u = unity;
        if (u != null) u.applyDesired();
    }

    static UnityFps unity() { return unity; }

    /**
     * Open the system page that grants "display over other apps".
     *
     * This is the one thing a system overlay cannot avoid: without it the window
     * manager refuses the addView call. If the user declines we still run with the
     * decor-hosted overlay, just without the GPU-composited surface.
     */
    private static void requestOverlayPermission(Context app) {
        if (Host.canOverlay(app)) return;
        try {
            Intent i = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + app.getPackageName()));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            app.startActivity(i);
            Log.i(TAG, "asked for SYSTEM_ALERT_WINDOW");
        } catch (Throwable t) {
            // some ROMs have no such screen; try the generic app-details page
            try {
                Intent i = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:" + app.getPackageName()));
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                app.startActivity(i);
            } catch (Throwable ignored) {
            }
        }
    }

    /**
     * Last known targetFrameRate, refreshed by the guard thread once a second.
     *
     * The badge's onDraw() must never read process memory directly: an Unsafe
     * read is cheap but the surrounding bookkeeping is not, and onDraw runs at
     * the display's refresh rate. One integer read per second is enough for a
     * label that only changes when the user taps a button.
     */
    private static volatile int cachedTfr = Integer.MIN_VALUE;

    static int currentTfr() {
        UnityFps u = unity;
        if (u == null) return Integer.MIN_VALUE;
        int v = u.readTfr();
        if (v != Integer.MIN_VALUE) cachedTfr = v;
        return cachedTfr;
    }

    /** cheap: no memory access at all, for the per-frame paint path */
    static int cachedTfr() { return cachedTfr; }

    /**
     * What a requested target really turns into.
     *
     * Unity feeds targetFrameRate to the compositor against the panel's vsync, so
     * the rate that actually reaches the screen is refreshRate / N for some
     * integer N (165Hz: 165, 82.5, 55, 41.25 ...). Anything else gets rounded to
     * the nearest reachable step.
     */
    static int effective(int want) {
        if (want <= 0) return -1;
        Context c = appCtx;
        if (c == null) return want;
        int hz = refreshHz(c);
        if (hz <= 0) return want;
        int best = want;
        double bestErr = Double.MAX_VALUE;
        for (int n = 1; n <= 8; n++) {
            int v = (int) Math.round(hz / (double) n);
            if (v < 1) continue;
            double err = Math.abs(v - want);
            if (err < bestErr) {
                bestErr = err;
                best = v;
            }
        }
        // within a frame or two of the request? then it is effectively exact
        return (bestErr <= Math.max(1.0, want * 0.03)) ? want : best;
    }

    /** display refresh rate in Hz, rounded, clamped to a sane range */
    static int refreshHz(Context c) {
        try {
            android.view.Display d = c.getDisplay();
            if (d != null) {
                float hz = d.getRefreshRate();
                if (hz > 20 && hz < 500) return Math.round(hz);
            }
        } catch (Throwable ignored) {
        }
        try {
            android.view.WindowManager wm =
                    (android.view.WindowManager) c.getSystemService(Context.WINDOW_SERVICE);
            if (wm != null && wm.getDefaultDisplay() != null) {
                float hz = wm.getDefaultDisplay().getRefreshRate();
                if (hz > 20 && hz < 500) return Math.round(hz);
            }
        } catch (Throwable ignored) {
        }
        return 60;
    }

    // ------------------------------------------------------------- lifecycle

    private static final class Life implements Application.ActivityLifecycleCallbacks {
        private final Handler ui = new Handler(Looper.getMainLooper());

        @Override public void onActivityResumed(final Activity a) {
            ui.post(new Runnable() {
                @Override public void run() {
                    try {
                        if (overlay == null) overlay = new FpsOverlay(a);
                        overlay.attach(a);
                    } catch (Throwable t) {
                        Log.e(TAG, "overlay attach failed", t);
                    }
                }
            });
        }

        @Override public void onActivityPaused(Activity a) {
            // A system overlay lives outside the activity, so it must NOT be torn
            // down when the game loses focus (notification shade, recents, IME).
            // Only the decor-hosted fallback follows the activity lifecycle.
            ui.post(new Runnable() {
                @Override public void run() {
                    if (overlay != null && overlay.isDecorHosted()) overlay.detach();
                }
            });
        }

        @Override public void onActivityCreated(Activity a, Bundle b) {}
        @Override public void onActivityStarted(Activity a) {}
        @Override public void onActivityStopped(Activity a) {}
        @Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}
        @Override public void onActivityDestroyed(Activity a) {
            ui.post(new Runnable() {
                @Override public void run() {
                    // the activity backing the decor host is going away
                    if (overlay != null && overlay.isDecorHosted()) overlay.detach();
                }
            });
        }
    }

    private TlwCore() {}
}
