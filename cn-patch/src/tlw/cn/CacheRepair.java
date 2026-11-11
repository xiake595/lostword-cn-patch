package tlw.cn;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.io.File;

/**
 * 「缓存修复」入口（悬浮窗面板上的按钮会调用）。
 *
 * <p>用途：游戏有时会自己清掉/重新下载 UnityCache 里的资源包（例如登录后首次下载资源、
 * 游戏更新、或用户手动清缓存），这会把内置的汉化资源包冲掉，表现为<b>角色名/UI 文本
 * 回退英文</b>（主数据表还在，所以技能名等仍是中文）。点这个按钮会：</p>
 *
 * <ol>
 *   <li>删掉安装器 marker（以及可能存在的 skip_extract 等调试钩子），
 *       让 {@link CnSetupActivity} 下次启动时重新解包；</li>
 *   <li>1.5 秒后用 AlarmManager 的 PendingIntent 重新拉起启动 Activity；</li>
 *   <li>随后主动结束当前进程，保证 Unity 在全新进程里重启，不会复用已经加载过的英文资源包。</li>
 * </ol>
 *
 * <p>重启后 {@link CnSetupActivity} 会显示进度界面，把 APK 内置的 lwlocal.zip 重新解包
 * （445 MB，含 Unity 缓存需要的 __info），完成后自动进入游戏。全程不需要 root/adb。</p>
 */
public final class CacheRepair {

    private static final String TAG = "TlwCn";

    /** PendingIntent 请求码，固定即可（FLAG_UPDATE_CURRENT 会覆盖旧的）。 */
    private static final int REQUEST_CODE = 0x7C00;
    /** 延迟多久重新拉起 App：留一点时间让下拉动画/进程退出完成。 */
    private static final long RELAUNCH_DELAY_MS = 1500L;
    /** 调度成功后多久杀掉自己（必须晚于 PendingIntent 已登记）。 */
    private static final long SELF_KILL_DELAY_MS = 600L;

    private CacheRepair() {
    }

    /**
     * 执行一次「删 marker + 重启 App + 重新解包」。调用后当前进程会在几百毫秒内结束，
     * 由 AlarmManager 拉起一个全新的进程。
     */
    public static void perform(Context context) {
        final Context app = context.getApplicationContext();
        try {
            clearMarkerAndHooks(app);
            scheduleRelaunch(app);
            Log.i(TAG, "cache repair: marker deleted, relaunch scheduled, killing process");
        } catch (Throwable t) {
            Log.e(TAG, "cache repair: cannot schedule relaunch, falling back to direct start", t);
            try {
                Intent direct = launchIntent(app);
                app.startActivity(direct);
            } catch (Throwable t2) {
                Log.e(TAG, "cache repair: direct relaunch failed too", t2);
                return;     // 两套方案都失败：不杀进程，避免用户直接卡死
            }
        }
        killSelfSoon();
    }

    // ------------------------------------------------------------------ steps

    private static void clearMarkerAndHooks(Context app) {
        File cnDir = new File(app.getFilesDir(), "tlw_cn");
        delete(new File(cnDir, "installed.txt"));
        delete(new File(cnDir, "installed.txt.tmp"));
        // 「还原官方」模式标记必须一起清掉，否则重启后 CnSetupActivity 会继续跳过解包
        delete(new File(cnDir, "restore_mode"));
        // 调试钩子必须一起清掉，否则重启后 CnSetupActivity 会跳过解包
        delete(new File(cnDir, "skip_extract"));
        delete(new File(cnDir, "no_autolaunch"));
        File ext = app.getExternalFilesDir(null);
        if (ext != null) {
            File ecn = new File(ext, "tlw_cn");
            delete(new File(ecn, "skip_extract"));
            delete(new File(ecn, "no_autolaunch"));
        }
    }

    private static void scheduleRelaunch(Context app) {
        Intent intent = launchIntent(app);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (android.os.Build.VERSION.SDK_INT >= 23) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        PendingIntent pending = PendingIntent.getActivity(app, REQUEST_CODE, intent, flags);
        AlarmManager am = (AlarmManager) app.getSystemService(Context.ALARM_SERVICE);
        if (am == null) {
            throw new IllegalStateException("AlarmManager unavailable");
        }
        // 普通 set() 不需要 SCHEDULE_EXACT_ALARM，误差几秒无所谓
        am.set(AlarmManager.RTC, System.currentTimeMillis() + RELAUNCH_DELAY_MS, pending);
    }

    private static Intent launchIntent(Context app) {
        Intent intent = app.getPackageManager().getLaunchIntentForPackage(app.getPackageName());
        if (intent == null) {
            // 兜底：直接点名启动 Activity（它被 manifest 声明为 MAIN/LAUNCHER）
            intent = new Intent();
            intent.setClassName(app.getPackageName(), "tlw.cn.CnSetupActivity");
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        return intent;
    }

    private static void killSelfSoon() {
        Thread t = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    Thread.sleep(SELF_KILL_DELAY_MS);
                } catch (InterruptedException ignored) {
                    Thread.currentThread().interrupt();
                }
                android.os.Process.killProcess(android.os.Process.myPid());
                System.exit(0);
            }
        }, "tlw-cache-repair-exit");
        t.setDaemon(true);
        t.start();
    }

    private static void delete(File f) {
        try {
            if (f != null && f.exists() && !f.delete()) {
                Log.w(TAG, "cache repair: cannot delete " + f);
            }
        } catch (Throwable t) {
            Log.w(TAG, "cache repair: delete failed " + f, t);
        }
    }
}
