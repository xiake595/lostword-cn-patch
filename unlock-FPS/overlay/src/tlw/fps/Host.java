package tlw.fps;

import android.app.Activity;
import android.content.Context;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.FrameLayout;

/**
 * Where the overlay lives.
 *
 *   SystemHost -- TYPE_APPLICATION_OVERLAY windows with their own hardware
 *                 accelerated surfaces. Smooth to drag, survives game updates.
 *   DecorHost  -- added to the game's decorView. No permission needed, but the
 *                 Unity activity declares hardwareAccelerated="false", so it is
 *                 rasterised by the CPU.
 *
 * The badge and the panel live in SEPARATE windows on the system host. That is
 * not cosmetic: a translucent overlay window only gets a correct touchableRegion
 * at the moment it is added. Resizing an existing window with
 * updateViewLayout() moves the frame but leaves the touchable region at the old
 * size -- measured on Android 12: frame went 130x130 -> 692x980 while the region
 * stayed 130x130, so the panel (and its EditText) was dead to touch everywhere
 * except the badge-sized corner. Adding a fresh window per panel open side-steps
 * the whole problem, and it lets the badge window stay one fixed size forever.
 */
abstract class Host {

    abstract String name();

    /** container for the badge, created at a fixed pixel size */
    abstract FrameLayout create(int w, int h);

    abstract void destroy();

    /** true when this host is a real system window (own GPU surface) */
    abstract boolean isSystem();

    // ------------------------------------------------------------- panel

    /** show the panel view at a screen position; w/h are its exact pixel size */
    abstract void mountPanel(View panel, int x, int y, int w, int h, boolean focusable);

    /** move an already mounted panel (never resizes it) */
    abstract void movePanel(int x, int y);

    abstract void unmountPanel();

    /**
     * Ask the panel window to accept (or give up) input focus.
     *
     * Hold this for as long as the user is actually typing and not one moment
     * longer. A focusable overlay window takes the activity's window focus away
     * and the whole game stops receiving input -- measured: after one tap on
     * 应用 the app was left "without a focused window" and Android threw an
     * "Input dispatching timed out" ANR, i.e. the game became unclickable.
     */
    abstract void setPanelFocusable(boolean focusable);

    /** true while the panel window is currently allowed to take focus */
    abstract boolean panelFocusable();

    // ------------------------------------------------------------ factory

    static Host pick(Context ctx) {
        if (canOverlay(ctx)) return new SystemHost(ctx);
        return null;                    // caller falls back to DecorHost
    }

    static boolean canOverlay(Context ctx) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true;
        try {
            return Settings.canDrawOverlays(ctx);
        } catch (Throwable t) {
            return false;
        }
    }

    // --------------------------------------------------------- system host

    static final class SystemHost extends Host {
        private final Context ctx;
        private WindowManager wm;
        private int type;

        private FrameLayout root;                   // badge window
        private WindowManager.LayoutParams lp;
        private int winX = Integer.MIN_VALUE, winY = Integer.MIN_VALUE;

        private FrameLayout panelRoot;              // panel window
        private WindowManager.LayoutParams plp;
        private int panX = Integer.MIN_VALUE, panY = Integer.MIN_VALUE;
        private int panW = 0, panH = 0;

        SystemHost(Context c) { ctx = c.getApplicationContext(); }

        @Override String name() { return "系统悬浮窗"; }
        @Override boolean isSystem() { return true; }

        @Override FrameLayout create(int w, int h) {
            wm = (WindowManager) ctx.getSystemService(Context.WINDOW_SERVICE);
            if (wm == null) return null;
            type = (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    : WindowManager.LayoutParams.TYPE_PHONE;

            root = new FrameLayout(ctx);
            root.setClipChildren(false);

            // Exact size, never WRAP_CONTENT: the size must not change after the
            // window exists, or the touchable region goes stale.
            lp = new WindowManager.LayoutParams(
                    w, h,
                    type,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                            | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                            | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT);
            lp.gravity = Gravity.TOP | Gravity.START;
            lp.x = 0;
            lp.y = 0;
            cutout(lp);

            try {
                wm.addView(root, lp);
            } catch (Throwable t) {
                Log.e(TlwCore.TAG, "overlay addView failed", t);
                root = null;
                return null;
            }
            Log.i(TlwCore.TAG, "system overlay attached " + w + "x" + h);
            return root;
        }

        /** move the badge window; the size is fixed, so only x/y ever change */
        void setBounds(int x, int y) {
            if (wm == null || root == null || lp == null) return;
            if (x == winX && y == winY) return;
            try {
                lp.x = x;
                lp.y = y;
                winX = x;
                winY = y;
                wm.updateViewLayout(root, lp);
            } catch (Throwable t) {
                Log.w(TlwCore.TAG, "overlay layout update failed", t);
            }
        }

        @Override void mountPanel(View panel, int x, int y, int w, int h, boolean focusable) {
            if (wm == null) return;
            unmountPanel();
            try {
                // The panel view outlives its window: it is detached from the old
                // root in unmountPanel(), but if that ever missed, adding it twice
                // would throw right through the touch dispatch and kill the game.
                if (panel.getParent() instanceof ViewGroup) {
                    ((ViewGroup) panel.getParent()).removeView(panel);
                }

                panelRoot = new FrameLayout(ctx);
                panelRoot.setClipChildren(false);

                int flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS;
                if (!focusable) flags |= WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;

                plp = new WindowManager.LayoutParams(w, h, type, flags,
                        PixelFormat.TRANSLUCENT);
                plp.gravity = Gravity.TOP | Gravity.START;
                plp.x = x;
                plp.y = y;
                // Let the IME float above the panel instead of resizing it: a
                // resize would invalidate the touchable region all over again.
                plp.softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
                        | WindowManager.LayoutParams.SOFT_INPUT_STATE_UNSPECIFIED;
                cutout(plp);

                panelRoot.addView(panel, new FrameLayout.LayoutParams(w, h));
                wm.addView(panelRoot, plp);
                panX = x;
                panY = y;
                panW = w;
                panH = h;
                Log.i(TlwCore.TAG, "panel window " + w + "x" + h + " at " + x + "," + y
                        + (focusable ? " (focusable)" : ""));
            } catch (Throwable t) {
                Log.e(TlwCore.TAG, "panel addView failed", t);
                panelRoot = null;
                plp = null;
            }
        }

        @Override void movePanel(int x, int y) {
            if (wm == null || panelRoot == null || plp == null) return;
            if (x == panX && y == panY) return;
            try {
                plp.x = x;
                plp.y = y;
                panX = x;
                panY = y;
                wm.updateViewLayout(panelRoot, plp);
            } catch (Throwable t) {
                Log.w(TlwCore.TAG, "panel move failed", t);
            }
        }

        /**
         * Grant or drop panel focus by REBUILDING the window.
         *
         * Toggling FLAG_NOT_FOCUSABLE on a live window with updateViewLayout()
         * does not move the focus: the window manager keeps the current focus
         * target even though the flag changed (measured -- the EditText never got
         * an input connection that way). Adding a window always does, so the
         * panel is unmounted and re-added at the same rect. It looks like nothing
         * happened: same view, same pixels, next frame.
         */
        @Override void setPanelFocusable(final boolean focusable) {
            if (wm == null || panelRoot == null || plp == null) return;
            boolean now = (plp.flags & WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE) == 0;
            if (now == focusable) return;
            final View panel = panelRoot.getChildCount() > 0
                    ? panelRoot.getChildAt(0) : null;
            if (panel == null) return;
            final int x = panX, y = panY, w = panW, h = panH;
            unmountPanel();                 // async removal of the old window
            new Handler(Looper.getMainLooper()).post(new Runnable() {
                @Override public void run() {   // re-add once the old one is gone
                    mountPanel(panel, x, y, w, h, focusable);
                }
            });
        }

        @Override boolean panelFocusable() {
            return plp != null
                    && (plp.flags & WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE) == 0;
        }

        @Override void unmountPanel() {
            FrameLayout old = panelRoot;
            panelRoot = null;
            plp = null;
            panX = Integer.MIN_VALUE;
            panY = Integer.MIN_VALUE;
            if (old == null) return;
            try {
                // Detach the panel view first, otherwise the next mount finds it
                // still parented to the dead root and addView() throws.
                old.removeAllViews();
                if (wm != null) wm.removeView(old);   // async: safe inside touch dispatch
            } catch (Throwable ignored) {
            }
        }

        private static void cutout(WindowManager.LayoutParams p) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                p.layoutInDisplayCutoutMode = WindowManager.LayoutParams
                        .LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            }
        }

        @Override void destroy() {
            unmountPanel();
            try {
                // removeView (async), not removeViewImmediate: this can run from a
                // click handler, and an immediate removal during input dispatch on
                // a focused tree is what made ViewRootImpl.doTraversal NPE before.
                if (wm != null && root != null) wm.removeView(root);
            } catch (Throwable ignored) {
            }
            root = null;
            wm = null;
            lp = null;
        }
    }

    // ---------------------------------------------------------- decor host

    static final class DecorHost extends Host {
        private final Activity act;
        private FrameLayout root;
        private View panel;

        DecorHost(Activity a) { act = a; }

        @Override String name() { return "游戏内视图"; }
        @Override boolean isSystem() { return false; }

        @Override FrameLayout create(int w, int h) {
            // Keep the decor view a fixed size while the soft keyboard is up,
            // otherwise Unity's surface gets resized and the game re-lays out.
            try {
                act.getWindow().setSoftInputMode(
                        WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING);
            } catch (Throwable ignored) {
            }

            ViewGroup decor = (ViewGroup) act.getWindow().getDecorView();
            root = new FrameLayout(act);
            root.setClipChildren(false);
            root.setLayoutParams(new ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT));
            decor.addView(root);
            Log.i(TlwCore.TAG, "decor overlay attached");
            return root;
        }

        @Override void mountPanel(View v, int x, int y, int w, int h, boolean focusable) {
            unmountPanel();
            panel = v;
            FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(w, h);
            lp.gravity = Gravity.TOP | Gravity.START;
            lp.leftMargin = x;
            lp.topMargin = y;
            root.addView(v, lp);
        }

        @Override void movePanel(int x, int y) {
            if (panel == null || panel.getLayoutParams() == null) return;
            FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) panel.getLayoutParams();
            lp.leftMargin = x;
            lp.topMargin = y;
            panel.setLayoutParams(lp);
        }

        @Override void unmountPanel() {
            try {
                if (panel != null && panel.getParent() instanceof ViewGroup) {
                    ((ViewGroup) panel.getParent()).removeView(panel);
                }
            } catch (Throwable ignored) {
            }
            panel = null;
        }

        // The panel lives inside the activity's own window here, so it already
        // has the window focus (and the IME) the game uses. Nothing to toggle.
        @Override void setPanelFocusable(boolean focusable) {}

        @Override boolean panelFocusable() { return false; }

        @Override void destroy() {
            unmountPanel();
            try {
                if (root != null && root.getParent() instanceof ViewGroup) {
                    ((ViewGroup) root.getParent()).removeView(root);
                }
            } catch (Throwable ignored) {
            }
            root = null;
        }
    }
}
