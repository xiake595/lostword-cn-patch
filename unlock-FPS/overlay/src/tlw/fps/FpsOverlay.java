package tlw.fps;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.Region;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.text.InputFilter;
import android.text.InputType;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * In-game overlay, built entirely in code (no XML resources).
 *
 *   collapsed : draggable round badge showing the live target frame rate
 *   tap       : opens the panel
 *   panel     : 当前值 + 输入框(自定义帧率) + 应用 + 还原默认 + 隐藏悬浮窗
 *   hidden    : a faint dot stays where the badge was
 *               tap        -> badge comes back
 *               long press -> overlay shuts down until the next launch
 */
final class FpsOverlay {

    private static final int MIN_FPS = 10;
    private static final int MAX_FPS = 480;

    private final Context ctx;
    private final SharedPreferences sp;
    private final Handler ui = new Handler(Looper.getMainLooper());

    private FrameLayout root;
    private Host host;
    private BallView ball;
    private LinearLayout panel;
    private TextView status;
    private EditText input;
    private View hotspot;

    private int ballSize, panelWidth, gap, pad;
    private int ballX, ballY;           // badge top-left, SCREEN coordinates
    private int panelScreenX, panelScreenY;   // panel top-left, SCREEN coordinates
    private int screenWidth, screenHeight;
    private boolean panelOpen = false;
    private boolean hidden = false;
    private boolean closed = false;
    private boolean posInit = false;
    private long msgUntil = 0L;

    private final Runnable ticker = new Runnable() {
        @Override public void run() {
            refreshStatus();
            // Repaint the badge only when its number/state actually changed.
            // Invalidating unconditionally every 700ms forced a full redraw of the
            // decor view on top of Unity's surface, which showed up as flicker.
            if (ball != null) {
                int now = labelValue();
                if (now != lastBallLabel) {
                    lastBallLabel = now;
                    ball.invalidate();
                }
            }
            // Watchdog: the panel window may only hold input focus while the text
            // field really is focused. If focus drifted anywhere else (apply,
            // back key, IME dismissed by the system) release it immediately --
            // a lingering focusable overlay stops the GAME from getting window
            // focus, which ends in "Application does not have a focused window"
            // and an unclickable screen. The grace window keeps this from racing
            // with a focus request that is still in flight.
            if (host != null && host.panelFocusable()
                    && SystemClock.uptimeMillis() > focusGraceUntil
                    && (input == null || !input.hasFocus())) {
                dropFocus();
            }
            // Keep ticking even with the panel closed: cachedTfr() only changes
            // when the guard thread refreshes it, and the badge has to notice.
            ui.postDelayed(this, 700);
        }
    };

    private int lastBallLabel = Integer.MIN_VALUE;

    /** what the badge would draw right now; used to skip redundant invalidates */
    private int labelValue() {
        return TlwCore.cachedTfr();
    }

    private final View.OnLayoutChangeListener relayout = new View.OnLayoutChangeListener() {
        @Override public void onLayoutChange(View v, int l, int t, int r, int b,
                                             int ol, int ot, int or, int ob) {
            if (r - l == or - ol && b - t == ob - ot) return;   // only react to size changes
            rescuePosition();          // window shrank: pull the badge back on screen
            placeBall();
            if (hidden) placeHotspot();
            // move, never re-mount: recreating the panel window here would drop
            // its focus and the soft keyboard mid-typing
            if (panelOpen) followPanel();
        }
    };

    FpsOverlay(Context c) {
        ctx = c;
        sp = c.getSharedPreferences(TlwCore.PREFS, Context.MODE_PRIVATE);
        ballSize = dp(58);
        panelWidth = dp(232);
        gap = dp(9);
        pad = dp(12);
    }

    // ------------------------------------------------------------------ build

    void attach(android.app.Activity a) {
        if (closed) return;
        if (ball != null && host != null) return;    // already mounted
        detach();

        // Prefer a system window: the Unity activity is hardwareAccelerated="false",
        // so anything inside its decorView is rasterised by the CPU. A system
        // overlay owns a GPU surface, and it also survives game updates.
        Host h = Host.pick(ctx);
        FrameLayout container = (h != null) ? h.create(ballSize, ballSize) : null;
        if (container == null) {
            h = new Host.DecorHost(a);
            container = h.create(ballSize, ballSize);
        }
        if (container == null) {
            Log.e(TlwCore.TAG, "no host available");
            return;
        }
        host = h;
        root = container;

        // screen bounds: the system window is wrap_content, so root.getWidth()
        // is NOT the screen. Keep our own copy for clamping and panel placement.
        android.util.DisplayMetrics dm = ctx.getResources().getDisplayMetrics();
        screenWidth = dm.widthPixels;
        screenHeight = dm.heightPixels;
        try {
            android.view.WindowManager wm =
                    (android.view.WindowManager) ctx.getSystemService(Context.WINDOW_SERVICE);
            if (wm != null && wm.getDefaultDisplay() != null) {
                android.graphics.Point p = new android.graphics.Point();
                wm.getDefaultDisplay().getRealSize(p);
                if (p.x > 0 && p.y > 0) {
                    screenWidth = p.x;
                    screenHeight = p.y;
                }
            }
        } catch (Throwable ignored) {
        }
        Log.i(TlwCore.TAG, "screen " + screenWidth + "x" + screenHeight);

        int sx = sp.getInt(TlwCore.K_X, Integer.MIN_VALUE);
        int sy = sp.getInt(TlwCore.K_Y, Integer.MIN_VALUE);
        // a stored position wins; otherwise placeBall() picks the default once the
        // container finally reports a size
        posInit = sx != Integer.MIN_VALUE && sy != Integer.MIN_VALUE;
        ballX = posInit ? sx : 0;
        ballY = posInit ? sy : dp(130);
        hidden = sp.getInt(TlwCore.K_HIDDEN, 0) == 1;

        ball = new BallView(ctx);
        FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(ballSize, ballSize);
        bp.gravity = Gravity.TOP | Gravity.START;
        ball.setLayoutParams(bp);
        ball.setOnTouchListener(new Drag());
        root.addView(ball);

        // Built here but deliberately NOT added to root: on the system host the
        // panel gets its own window, created fresh every time it opens.
        panel = buildPanel();
        panel.setVisibility(View.GONE);

        hotspot = buildHotspot();
        FrameLayout.LayoutParams hp = new FrameLayout.LayoutParams(dp(34), dp(34));
        hp.gravity = Gravity.TOP | Gravity.START;
        hotspot.setLayoutParams(hp);
        hotspot.setVisibility(View.GONE);
        root.addView(hotspot);

        root.addOnLayoutChangeListener(relayout);

        // the container has no size yet; place once it does
        root.post(new Runnable() {
            @Override public void run() {
                rescuePosition();
                placeBall();
                if (hidden) placeHotspot();
            }
        });

        if (hidden) {
            ball.setVisibility(View.GONE);
            hotspot.setVisibility(View.VISIBLE);
            placeHotspot();
        }

        ui.removeCallbacks(ticker);
        ui.post(ticker);
    }

    /** true when the overlay lives inside the game's decorView (not a system window) */
    boolean isDecorHosted() {
        return host != null && !host.isSystem();
    }

    void detach() {
        ui.removeCallbacks(ticker);
        ui.removeCallbacks(restoreStatus);
        try {
            if (root != null) root.removeOnLayoutChangeListener(relayout);
            if (host != null) host.destroy();   // system window must be removed explicitly
        } catch (Throwable ignored) {
        }
        ball = null;
        panel = null;
        hotspot = null;
        status = null;
        input = null;
        root = null;
        host = null;
        panelOpen = false;
    }

    // ------------------------------------------------------------- components

    private LinearLayout buildPanel() {
        LinearLayout p = new LinearLayout(ctx);
        p.setOrientation(LinearLayout.VERTICAL);
        p.setPadding(pad, pad, pad, pad);
        p.setBackground(round(0xF01A1A22, dp(15), 0x55FFFFFF, dp(1)));

        TextView title = new TextView(ctx);
        title.setText("帧率");
        title.setTextColor(Color.WHITE);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        title.setPadding(dp(3), 0, 0, 0);
        p.addView(title);

        // Fixed two-line box on purpose. The panel gets its own window, and that
        // window must never change size (a resized overlay window keeps its old
        // touchableRegion), so the status line may not reflow the panel when it
        // switches between "当前 165 fps" and a two-line flash message.
        status = new TextView(ctx);
        status.setTextColor(0xFF8FC0FF);
        status.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10);
        status.setMaxLines(2);
        status.setEllipsize(android.text.TextUtils.TruncateAt.END);
        // Centred inside its fixed box: most of the time the status is a single
        // line, and top-aligning it left a visible hole between it and the
        // notice below.
        status.setGravity(Gravity.CENTER_VERTICAL);
        status.setPadding(dp(3), 0, 0, 0);
        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(30));
        slp.bottomMargin = dp(2);
        p.addView(status, slp);

        // 免费声明。固定行数，理由同上：不能让面板高度随文字变化。
        TextView free = new TextView(ctx);
        free.setText("本客户端完全免费\n如果你是付费获取，那你被骗了");
        free.setTextColor(0xFFFFC46B);
        free.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10);
        free.setGravity(Gravity.CENTER);
        free.setMaxLines(2);
        free.setLineSpacing(0, 1.15f);
        LinearLayout.LayoutParams flp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        flp.topMargin = dp(2);
        p.addView(free, flp);

        // ---- 自定义输入 ----
        LinearLayout row = new LinearLayout(ctx);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);

        input = new EditText(ctx);
        input.setHint("输入帧率");
        input.setHintTextColor(0x66FFFFFF);
        input.setTextColor(Color.WHITE);
        input.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        input.setGravity(Gravity.CENTER);
        input.setSingleLine(true);
        input.setInputType(InputType.TYPE_CLASS_NUMBER);
        input.setFilters(new InputFilter[]{new InputFilter.LengthFilter(3)});
        input.setImeOptions(EditorInfo.IME_ACTION_DONE);
        input.setBackground(round(0x33FFFFFF, dp(10), 0x44FFFFFF, dp(1)));
        // generous padding: a thin strip is hard to hit on a phone-sized screen,
        // and this field is the main thing people tap in the panel
        input.setPadding(dp(10), dp(13), dp(10), dp(13));
        input.setMinHeight(dp(48));
        LinearLayout.LayoutParams ilp = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        ilp.setMargins(0, 0, dp(7), 0);
        input.setLayoutParams(ilp);
        input.setClickable(true);
        input.setFocusable(true);
        input.setFocusableInTouchMode(true);
        // Tapping anywhere in the field must focus it and raise the keyboard. The
        // EditText's own touch handling only reacts to the text bounds, so drive it
        // explicitly and swallow the event.
        input.setOnTouchListener(new View.OnTouchListener() {
            @Override public boolean onTouch(View v, android.view.MotionEvent e) {
                if (e.getActionMasked() == android.view.MotionEvent.ACTION_UP) {
                    focusInput();
                }
                return true;
            }
        });
        input.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                input.selectAll();      // tap the field -> type over anything left
            }
        });
        input.setOnEditorActionListener(new TextView.OnEditorActionListener() {
            @Override public boolean onEditorAction(TextView v, int actionId, android.view.KeyEvent e) {
                if (actionId == EditorInfo.IME_ACTION_DONE
                        || (e != null && e.getKeyCode() == android.view.KeyEvent.KEYCODE_ENTER)) {
                    applyInput();
                    return true;
                }
                return false;
            }
        });
        row.addView(input);

        TextView apply = new TextView(ctx);
        apply.setText("应用");
        apply.setTextColor(Color.WHITE);
        apply.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        apply.setGravity(Gravity.CENTER);
        apply.setPadding(dp(16), dp(10), dp(16), dp(10));
        apply.setBackground(round(0xFF3B72F0, dp(10), 0x66FFFFFF, dp(1)));
        apply.setOnClickListener(click(new Runnable() {
            @Override public void run() { applyInput(); }
        }));
        row.addView(apply);

        p.addView(row);

        // ---- 还原默认 ----
        TextView reset = new TextView(ctx);
        reset.setText("还原默认帧率");
        reset.setTextColor(0xFFD6D6E0);
        reset.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        reset.setGravity(Gravity.CENTER);
        reset.setPadding(0, dp(10), 0, dp(10));
        reset.setBackground(round(0x26FFFFFF, dp(10), 0x33FFFFFF, dp(1)));
        LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        rlp.topMargin = dp(8);
        reset.setLayoutParams(rlp);
        reset.setOnClickListener(click(new Runnable() {
            @Override public void run() { doReset(); }
        }));
        p.addView(reset);

        View line = new View(ctx);
        line.setBackgroundColor(0x33FFFFFF);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(1));
        lp.topMargin = dp(10);
        lp.bottomMargin = dp(8);
        p.addView(line, lp);

        // ---- 隐藏 ----
        TextView hide = new TextView(ctx);
        hide.setText("隐藏悬浮窗");
        hide.setTextColor(0xFFFFC46B);
        hide.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        hide.setGravity(Gravity.CENTER);
        hide.setPadding(0, dp(8), 0, dp(8));
        hide.setBackground(round(0x26FFC46B, dp(10), 0, 0));
        hide.setOnClickListener(click(new Runnable() {
            @Override public void run() { doHide(); }
        }));
        p.addView(hide);

        TextView note = new TextView(ctx);
        note.setText("隐藏后点原位小点恢复\n长按小点彻底关闭（下次启动再出现）");
        note.setTextColor(0x77FFFFFF);
        note.setTextSize(TypedValue.COMPLEX_UNIT_SP, 9);
        note.setGravity(Gravity.CENTER);
        note.setPadding(0, dp(6), 0, 0);
        p.addView(note);

        // 最底下一行，比上面那行再小一号
        TextView welcome = new TextView(ctx);
        welcome.setText("欢迎来玩[704221486]");
        welcome.setTextColor(0x8CFFFFFF);
        welcome.setTextSize(TypedValue.COMPLEX_UNIT_SP, 8);
        welcome.setGravity(Gravity.CENTER);
        welcome.setPadding(0, dp(3), 0, 0);
        p.addView(welcome);

        return p;
    }

    private View buildHotspot() {
        final TextView dot = new TextView(ctx);
        GradientDrawable d = new GradientDrawable();
        d.setShape(GradientDrawable.OVAL);
        d.setColor(0x2E7FB4FF);
        d.setStroke(dp(1), 0x55FFFFFF);
        dot.setBackground(d);
        dot.setOnClickListener(click(new Runnable() {
            @Override public void run() { doShow(); }
        }));
        dot.setOnLongClickListener(new View.OnLongClickListener() {
            @Override public boolean onLongClick(View v) {
                try {
                    doClose();
                } catch (Throwable t) {
                    Log.e(TlwCore.TAG, "close failed", t);
                }
                return true;
            }
        });
        return dot;
    }

    /**
     * Wrap a listener body so an overlay bug can never take the game down: an
     * exception thrown from a click handler unwinds through ViewRootImpl's input
     * dispatch and kills the process.
     */
    private View.OnClickListener click(final Runnable body) {
        return new View.OnClickListener() {
            @Override public void onClick(View v) {
                try {
                    body.run();
                } catch (Throwable t) {
                    Log.e(TlwCore.TAG, "overlay click failed", t);
                }
            }
        };
    }

    private GradientDrawable round(int color, int radius, int strokeColor, int strokeWidth) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(radius);
        if (strokeWidth > 0) d.setStroke(strokeWidth, strokeColor);
        return d;
    }

    // ---------------------------------------------------------------- actions

    private void applyInput() {
        if (input == null) return;
        String s = input.getText().toString().trim();
        if (s.length() == 0) {
            complain("先输入一个帧率");
            return;
        }
        int fps;
        try {
            fps = Integer.parseInt(s);
        } catch (Throwable t) {
            complain("数字看不懂：" + s);
            return;
        }
        if (fps < MIN_FPS || fps > MAX_FPS) {
            complain("范围 " + MIN_FPS + " ~ " + MAX_FPS);
            return;
        }
        TlwCore.setDesired(fps);
        dropFocus();          // hand window focus back to the game right away
        refreshStatus();
        int eff = TlwCore.effective(fps);
        if (eff != fps) {
            flash("已设为 " + fps + "，本屏实际 ≈ " + eff);
        } else {
            flash("已设为 " + fps + " fps");
        }
    }

    private void doReset() {
        TlwCore.setDesired(-1);
        if (input != null) input.setText("");
        dropFocus();
        refreshStatus();
        // NOT "follow the display": writing the stock -1 hands the cap back to
        // the engine, which on this game lands on its own locked default (~30 fps
        // measured), well below the panel's refresh rate.
        flash("已还原为游戏默认帧率");
    }

    private void doHide() {
        if (panelOpen) closePanel();
        hidden = true;
        sp.edit().putInt(TlwCore.K_HIDDEN, 1).apply();
        ui.removeCallbacks(ticker);
        hideKeyboard();
        if (host != null) host.setPanelFocusable(false);
        if (ball != null) ball.setVisibility(View.GONE);
        if (hotspot != null) {
            hotspot.setVisibility(View.VISIBLE);
            placeHotspot();
        }
        syncWindow();
        ui.post(ticker);
    }

    private void doShow() {
        hidden = false;
        sp.edit().putInt(TlwCore.K_HIDDEN, 0).apply();
        if (hotspot != null) hotspot.setVisibility(View.GONE);
        if (ball != null) ball.setVisibility(View.VISIBLE);
        syncWindow();
    }

    private void doClose() {
        closed = true;
        detach();
        Log.i(TlwCore.TAG, "overlay closed by long press");
    }

    private void togglePanel() {
        if (panel == null || host == null) return;
        if (panelOpen) {
            closePanel();
        } else {
            panelOpen = true;
            refreshStatus();
            panel.setVisibility(View.VISIBLE);
            placePanel();
            ui.removeCallbacks(ticker);
            ui.post(ticker);
        }
    }

    /**
     * Close the panel.
     *
     * The panel has its own window; closing it removes that window. Order
     * matters: give the focus back (and let the IME detach) before the view loses
     * its window token, otherwise the game is left without a focused window.
     */
    private void closePanel() {
        panelOpen = false;
        dropFocus();
        if (panel != null) panel.setVisibility(View.GONE);
        if (host != null) host.unmountPanel();
        syncWindow();
    }

    private void refreshStatus() {
        if (status == null) return;
        if (SystemClock.uptimeMillis() < msgUntil) return;   // a flash/complain is showing
        UnityFps u = TlwCore.unity();
        if (u == null) {
            status.setText("等待 libunity.so …");
            return;
        }
        int live = TlwCore.cachedTfr();
        if (live == Integer.MIN_VALUE) {
            status.setText("等待 libunity.so …");
            return;
        }
        if (live <= 0) {
            // targetFrameRate back to the stock -1: the engine's own default cap,
            // NOT the display refresh (measured ~30 fps on a 120Hz panel).
            status.setText("当前 游戏默认 · " + u.how);
            return;
        }
        // Unity quantises targetFrameRate to refreshRate/N, so a value like 100
        // on a 165Hz panel really shows up as ~83. Say so instead of pretending.
        int eff = TlwCore.effective(live);
        String tail = (eff != live) ? "（实际 ≈ " + eff + "）" : "";
        String via = (host != null) ? host.name() : "?";
        status.setText("当前 " + live + " fps" + tail + " · " + via);
    }

    private void hideKeyboard() {
        try {
            InputMethodManager imm =
                    (InputMethodManager) ctx.getSystemService(Context.INPUT_METHOD_SERVICE);
            if (imm != null && input != null) {
                imm.hideSoftInputFromWindow(input.getWindowToken(), 0);
            }
        } catch (Throwable ignored) {
        }
    }

    /**
     * Give the keyboard/focus back to the game.
     *
     * Order matters: hide the IME, drop the view focus, and only then make the
     * panel window non-focusable. Leaving it focusable is what made the game
     * stop responding to touches right after 应用.
     */
    private void dropFocus() {
        focusGraceUntil = 0L;
        hideKeyboard();
        if (input != null) input.clearFocus();
        final Host h = host;
        if (h == null) return;
        // posted: rebuilding the panel window must not happen inside the touch
        // dispatch that triggered it
        ui.post(new Runnable() {
            @Override public void run() {
                if (panelOpen) h.setPanelFocusable(false);
            }
        });
    }

    /** nothing may release the panel focus before this timestamp */
    private long focusGraceUntil = 0L;

    /**
     * Take focus for the text field.
     *
     * The panel window is created NOT focusable so the game keeps window focus,
     * and it is rebuilt as a focusable window only while someone is actually
     * typing (a live flag change does not move the window manager's focus
     * target). The request is retried for a moment: the new window needs a frame
     * before it can hold a focus.
     */
    private void focusInput() {
        if (input == null || host == null) return;
        focusGraceUntil = SystemClock.uptimeMillis() + 3000L;
        ui.post(new Runnable() {
            @Override public void run() {
                if (!panelOpen || host == null) return;
                host.setPanelFocusable(true);
                if (input != null) input.postDelayed(focusReq, 120L);
            }
        });
    }

    private final Runnable focusReq = new Runnable() {
        @Override public void run() {
            if (!panelOpen || input == null) return;
            try {
                input.requestFocus();
                input.selectAll();
                showKeyboard();
                if (!input.hasFocus() && SystemClock.uptimeMillis() < focusGraceUntil) {
                    input.postDelayed(this, 150L);      // window not focusable yet
                }
            } catch (Throwable t) {
                Log.e(TlwCore.TAG, "input focus failed", t);
            }
        }
    };

    private void showKeyboard() {
        try {
            InputMethodManager imm =
                    (InputMethodManager) ctx.getSystemService(Context.INPUT_METHOD_SERVICE);
            if (imm != null && input != null) {
                imm.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT);
            }
        } catch (Throwable ignored) {
        }
    }

    /**
     * Feedback goes into the panel itself. Toast needs systemui to draw a window
     * over the game, which is unreliable here (and leaves "Toast already killed"
     * in logcat), so never depend on it.
     */
    private void flash(String msg) {
        if (status == null) return;
        status.setTextColor(0xFF7BE39A);
        status.setText(msg);
        msgUntil = SystemClock.uptimeMillis() + 2200;
        ui.removeCallbacks(restoreStatus);
        ui.postDelayed(restoreStatus, 2200);
    }

    private void complain(String msg) {
        if (status == null) return;
        status.setTextColor(0xFFFF8A8A);
        status.setText(msg);
        msgUntil = SystemClock.uptimeMillis() + 2200;
        ui.removeCallbacks(restoreStatus);
        ui.postDelayed(restoreStatus, 2200);
    }

    private final Runnable restoreStatus = new Runnable() {
        @Override public void run() {
            if (status != null) status.setTextColor(0xFF8FC0FF);
            refreshStatus();
        }
    };

    // --------------------------------------------------------------- geometry

    /**
     * Geometry model
     * ==============
     *
     * ballX / ballY  -- top-left of the badge in SCREEN coordinates. This is the
     *                   single source of truth and what gets persisted. On the
     *                   system host it is also the window's own position, because
     *                   the badge window is exactly badgeSize x badgeSize.
     * panelScreenX/Y -- top-left of the panel in SCREEN coordinates; on the system
     *                   host that is the panel window's position.
     *
     * A MATCH_PARENT overlay would swallow every touch even with
     * FLAG_NOT_TOUCH_MODAL -- that flag only passes through touches *outside* the
     * window bounds -- and the game would become unplayable. Hence one small
     * window for the badge and a second one for the panel.
     *
     * Dragging moves the window (WindowManager.updateViewLayout), which the
     * compositor handles on the render thread; no measure/layout runs in the app.
     * The decor-hosted fallback uses translationX/Y for the same reason.
     */

    private void placeBall() {
        if (ball == null || root == null) return;
        if (screenW() <= 0 || screenH() <= 0) return;    // not measured yet

        int maxX = Math.max(0, screenW() - ballSize);
        int maxY = Math.max(0, screenH() - ballSize);

        if (!posInit) {
            // no stored position yet: default to the right edge, just below the
            // in-game top bar
            ballX = maxX - dp(6);
            ballY = Math.min(dp(130), maxY);
            posInit = true;
        }

        ballX = clamp(ballX, 0, maxX);
        ballY = clamp(ballY, 0, maxY);
        applyBallPosition();
    }

    /** push ballX/ballY into the view tree (and the window, for a system host) */
    private void applyBallPosition() {
        if (ball == null) return;
        if (host instanceof Host.SystemHost) {
            if (panelOpen) followPanel();   // recompute the panel from ballX/ballY
            syncWindow();                   // then move the badge window
        } else {
            FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) ball.getLayoutParams();
            lp.leftMargin = ballX;
            lp.topMargin = ballY;
            ball.setTranslationX(0f);
            ball.setTranslationY(0f);
            ball.setLayoutParams(lp);
            if (panelOpen) followPanel();
            if (hidden) placeHotspot();
        }
    }

    /** screen-space top-left of the badge */
    private float laidX() {
        if (ball == null) return ballX;
        if (host instanceof Host.SystemHost) return ballX + ball.getTranslationX();
        FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) ball.getLayoutParams();
        return lp.leftMargin + ball.getTranslationX();
    }

    private float laidY() {
        if (ball == null) return ballY;
        if (host instanceof Host.SystemHost) return ballY + ball.getTranslationY();
        FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) ball.getLayoutParams();
        return lp.topMargin + ball.getTranslationY();
    }

    private static int clamp(int v, int lo, int hi) {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    private static float clampF(float v, float lo, float hi) {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    /**
     * If the window shrank (rotation, resolution change, keyboard) the badge is
     * simply laid out clamped. The stored position is left alone on purpose: a
     * transient resize must not overwrite where the user actually put it.
     */
    private void rescuePosition() {
        if (ball == null || root == null) return;
        if (screenW() <= 0 || screenH() <= 0) return;
        int maxX = Math.max(0, screenW() - ballSize);
        int maxY = Math.max(0, screenH() - ballSize);
        if (ballX > maxX || ballY > maxY || ballX < 0 || ballY < 0) {
            Log.i(TlwCore.TAG, "ball " + ballX + "," + ballY + " clamped into "
                    + maxX + "x" + maxY + " (stored value kept)");
        }
    }

    private void placeHotspot() {
        if (hotspot == null || root == null || ball == null) return;
        FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) hotspot.getLayoutParams();
        lp.leftMargin = (ballSize - lp.width) / 2;
        lp.topMargin = (ballSize - lp.height) / 2;
        hotspot.setLayoutParams(lp);
        syncWindow();
    }

    /**
     * Where the panel should go, in SCREEN coordinates.
     *
     * Pure function of ballX/ballY and the screen size -- it must NOT read winX or
     * the panel's own current margins. An earlier version did, and because
     * syncWindow() then recomputed winX from that result, the two fed each other
     * and the panel oscillated between two positions every frame (very visible
     * when the badge sits on the right edge and the panel has to flip left).
     */
    /**
     * Measured height of the panel, cached.
     *
     * The panel is only mounted while it is open, so this measures the detached
     * view once. Its contents are fixed-height on purpose (see buildPanel: the
     * status line always occupies two lines), which keeps this value constant --
     * a panel that changed height would force its window to be recreated in the
     * middle of an interaction.
     */
    private int panelHeight() {
        if (panel == null) return 0;
        if (cachedPanelHeight <= 0) {
            panel.measure(View.MeasureSpec.makeMeasureSpec(panelWidth, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
            int h = panel.getMeasuredHeight();
            if (h > 0) cachedPanelHeight = h;
        }
        return cachedPanelHeight;
    }

    private int cachedPanelHeight = 0;

    /** where the panel should go, in SCREEN coordinates */
    private int[] panelRect() {
        int rw = screenW(), rh = screenH();
        int pw = panelWidth;
        int ph = panelHeight();

        int bx = ballX, by = ballY;

        // prefer the right of the badge, flip to the left when it would overflow
        int x = bx + ballSize + gap;
        if (x + pw > rw) x = bx - pw - gap;
        x = clamp(x, 0, Math.max(0, rw - pw));

        // same for vertical: align with the badge, then shift up
        int y = by;
        if (y + ph > rh) y = by + ballSize - ph;
        y = clamp(y, 0, Math.max(0, rh - ph));

        return new int[]{x, y, pw, ph};
    }

    /** open the panel: a brand new window, so its touchable region is exact */
    private void placePanel() {
        if (panel == null || host == null) return;
        int[] r = panelRect();
        panelScreenX = r[0];
        panelScreenY = r[1];
        host.mountPanel(panel, r[0], r[1], r[2], r[3], false);
    }

    /** re-place the open panel while dragging (move only, never resize) */
    private void followPanel() {
        if (panel == null || host == null) return;
        int[] r = panelRect();
        panelScreenX = r[0];
        panelScreenY = r[1];
        host.movePanel(r[0], r[1]);
    }

    private int screenW() {
        if (root == null) return 0;
        return host instanceof Host.SystemHost ? screenWidth : root.getWidth();
    }

    private int screenH() {
        if (root == null) return 0;
        return host instanceof Host.SystemHost ? screenHeight : root.getHeight();
    }

    /**
     * Move the badge window to ballX/ballY.
     *
     * The window is created at exactly badgeSize x badgeSize and never resized:
     * a translucent overlay's touchableRegion is only computed when the window is
     * added, so growing it at runtime would leave the new area dead to touch.
     * Position-only updates are fine (that is how every floating widget drags).
     */
    private void syncWindow() {
        if (!(host instanceof Host.SystemHost)) return;
        if (root == null || ball == null) return;
        if (screenWidth <= 0 || screenHeight <= 0) return;

        ballX = clamp(ballX, 0, Math.max(0, screenWidth - ballSize));
        ballY = clamp(ballY, 0, Math.max(0, screenHeight - ballSize));

        // children live at 0,0 inside the badge window; touch this only when it
        // actually changed (a setLayoutParams per MOVE would relayout the tree)
        FrameLayout.LayoutParams blp = (FrameLayout.LayoutParams) ball.getLayoutParams();
        if (blp.leftMargin != 0 || blp.topMargin != 0) {
            blp.leftMargin = 0;
            blp.topMargin = 0;
            ball.setLayoutParams(blp);
        }

        ((Host.SystemHost) host).setBounds(ballX, ballY);
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                ctx.getResources().getDisplayMetrics());
    }


    // ------------------------------------------------------------------ input

    private final class Drag implements View.OnTouchListener {
        private final int slop = ViewConfiguration.get(ctx).getScaledTouchSlop();
        private float downRawX, downRawY;
        private float startX, startY;      // layout position when the drag began
        private float offX, offY;          // translation applied during the drag
        private long downAt;
        private boolean moved;

        @Override public boolean onTouch(View v, MotionEvent e) {
            // An exception thrown from here propagates through ViewRootImpl's
            // input dispatch and kills the whole game process -- so nothing the
            // overlay does may escape.
            try {
                return handle(v, e);
            } catch (Throwable t) {
                Log.e(TlwCore.TAG, "badge touch failed", t);
                v.setAlpha(1f);
                return true;
            }
        }

        private boolean handle(View v, MotionEvent e) {
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downRawX = e.getRawX();
                    downRawY = e.getRawY();
                    // start from where the badge actually is on screen, not from
                    // ballX/ballY -- those may still hold the "unset" sentinel
                    startX = laidX();
                    startY = laidY();
                    offX = 0f;
                    offY = 0f;
                    downAt = SystemClock.uptimeMillis();
                    moved = false;
                    v.setAlpha(0.7f);
                    return true;

                case MotionEvent.ACTION_MOVE: {
                    float dx = e.getRawX() - downRawX;
                    float dy = e.getRawY() - downRawY;
                    if (!moved && (Math.abs(dx) > slop || Math.abs(dy) > slop)) moved = true;
                    if (moved) {
                        float nx = clampF(startX + dx, 0f, Math.max(0, screenW() - ballSize));
                        float ny = clampF(startY + dy, 0f, Math.max(0, screenH() - ballSize));
                        offX = nx - startX;
                        offY = ny - startY;
                        if (host instanceof Host.SystemHost) {
                            // Move the WINDOW: the compositor shifts the overlay
                            // surface on the render thread, so no measure/layout
                            // runs in the app at all.
                            ballX = Math.round(nx);
                            ballY = Math.round(ny);
                            // BOTH windows have to move. The panel follows the
                            // badge, but the badge is its own window: skipping
                            // syncWindow() here left it frozen at the old spot
                            // for the whole drag and it snapped over on release.
                            if (panelOpen) followPanel();
                            syncWindow();
                        } else {
                            v.setTranslationX(offX);
                            v.setTranslationY(offY);
                            if (panelOpen) followPanel();
                        }
                    }
                    return true;
                }

                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    v.setAlpha(1f);
                    if (!moved && SystemClock.uptimeMillis() - downAt < 350) {
                        togglePanel();
                    } else {
                        int maxX = Math.max(0, screenW() - ballSize);
                        int maxY = Math.max(0, screenH() - ballSize);
                        ballX = clamp(Math.round(startX + offX), 0, maxX);
                        ballY = clamp(Math.round(startY + offY), 0, maxY);
                        applyBallPosition();
                        sp.edit().putInt(TlwCore.K_X, ballX)
                                 .putInt(TlwCore.K_Y, ballY).apply();
                    }
                    return true;
            }
            return false;
        }
    }

    // -------------------------------------------------------------------- ball

    private final class BallView extends View {
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint ring = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint iconPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint scrim = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.RectF dst = new android.graphics.RectF();
        private android.graphics.Bitmap icon;
        private boolean iconTried = false;

        BallView(Context c) {
            super(c);
            ring.setStyle(Paint.Style.STROKE);
            ring.setStrokeWidth(dp(2));
            text.setColor(Color.WHITE);
            text.setTextAlign(Paint.Align.CENTER);
            text.setTypeface(Typeface.DEFAULT_BOLD);
            iconPaint.setFilterBitmap(true);
        }

        /**
         * Custom icon support.
         *
         * Drop a PNG at assets/tlw_icon.png in the APK and it becomes the badge
         * background. assets/ is used instead of res/drawable on purpose: adding a
         * drawable would require re-encoding resources.arsc, which this build
         * deliberately never touches. Missing file simply falls back to the drawn
         * circle.
         */
        private void loadIcon() {
            if (iconTried) return;
            iconTried = true;
            java.io.InputStream in = null;
            try {
                in = ctx.getAssets().open("tlw_icon.png");
                icon = android.graphics.BitmapFactory.decodeStream(in);
                if (icon != null) {
                    Log.i(TlwCore.TAG, "custom icon loaded " + icon.getWidth()
                            + "x" + icon.getHeight());
                }
            } catch (Throwable t) {
                // no custom icon -- that is the normal case
            } finally {
                try { if (in != null) in.close(); } catch (Throwable ignored) {}
            }
        }

        @Override protected void onDraw(Canvas cv) {
            int w = getWidth(), h = getHeight();
            float cx = w / 2f, cy = h / 2f, rad = Math.min(w, h) / 2f - dp(2);
            if (rad <= 0) return;

            loadIcon();

            int want = TlwCore.desired();
            boolean on = want > 0;

            if (icon != null) {
                // circular crop of the bitmap
                dst.set(cx - rad, cy - rad, cx + rad, cy + rad);
                cv.save();
                cv.clipPath(circlePath(cx, cy, rad));
                cv.drawBitmap(icon, null, dst, iconPaint);

                // Very light bottom shading only -- just enough that a bright
                // picture does not swallow the "FPS" caption. The artwork stays
                // clearly visible, which is the whole point of a custom icon.
                scrim.setShader(new android.graphics.LinearGradient(
                        0, cy + rad * 0.35f, 0, cy + rad,
                        new int[]{0x00000000, 0x40000000},
                        new float[]{0f, 1f},
                        android.graphics.Shader.TileMode.CLAMP));
                cv.drawCircle(cx, cy, rad, scrim);
                scrim.setShader(null);
                cv.restore();

                ring.setColor(on ? 0xFF8FB4FF : 0xFF8A8A98);
                cv.drawCircle(cx, cy, rad, ring);
            } else {
                fill.setColor(on ? 0xE6243F9E : 0xE6262630);
                ring.setColor(on ? 0xFF8FB4FF : 0xFF8A8A98);
                cv.drawCircle(cx, cy, rad, fill);
                cv.drawCircle(cx, cy, rad, ring);
            }

            // Never touch process memory here: onDraw runs at the display's
            // refresh rate. cachedTfr() is a plain volatile field read.
            int live = TlwCore.cachedTfr();
            String label;
            if (live == Integer.MIN_VALUE) label = "…";
            else if (live <= 0) label = "OFF";
            else label = String.valueOf(live);

            if (icon != null) {
                // A custom picture is the point of this mode, so the numbers stay
                // faint and only get a soft dark halo -- enough to read them
                // without competing with the artwork underneath.
                text.setColor(0x59000000);
                text.setStyle(Paint.Style.STROKE);
                text.setStrokeWidth(dp(3) * 0.8f);
            } else {
                text.setStyle(Paint.Style.FILL);
            }

            text.setTextSize(dp(live >= 100 || live <= 0 ? 14 : 17));
            float ty = cy - (text.descent() + text.ascent()) / 2f - dp(3);
            if (icon != null) cv.drawText(label, cx, ty, text);

            text.setStyle(Paint.Style.FILL);
            text.setColor(icon != null ? 0x99FFFFFF : Color.WHITE);   // 60% white over art
            cv.drawText(label, cx, ty, text);

            text.setTextSize(dp(8));
            text.setColor(icon != null ? 0x70FFFFFF : 0xBBFFFFFF);
            cv.drawText("FPS", cx, cy + dp(15), text);
        }

        private android.graphics.Path circlePath(float cx, float cy, float r) {
            android.graphics.Path p = new android.graphics.Path();
            p.addCircle(cx, cy, r, android.graphics.Path.Direction.CW);
            return p;
        }
    }
}
