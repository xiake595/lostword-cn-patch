package tlw.cn;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;

/**
 * 「还原官方」入口（悬浮窗面板上的按钮会调用）。
 *
 * <p>用途：装完汉化后如果<b>主界面黑屏、点登录无反应、进不去游戏</b>（典型原因是旧数据包/
 * 旧版安装器残留的主表结构与新游戏版本不匹配，游戏代码读旧表时空引用），点这个按钮会：</p>
 *
 * <ol>
 *   <li>删掉本安装器写过的主表（按 {@code installed.list} + 内置 legacy 清单）和
 *       汉化资源包（按 {@code installed.bundles}）；<b>游戏自己下载的文件不在清单里，一律不碰</b>；</li>
 *   <li>删掉安装器 marker 和清单（下次「缓存修复」会从头重装）；</li>
 *   <li>写下 {@code restore_mode} 标记：{@link CnSetupActivity} 下次启动会跳过解包、
 *       直接拉起游戏，让游戏按官方逻辑重新下载主表/资源包；</li>
 *   <li>1.5 秒后自动重启 App（AlarmManager + PendingIntent），并结束当前进程。</li>
 * </ol>
 *
 * <p>这是「保证能进游戏」的兜底；想重新装回汉化，点悬浮窗「缓存修复」即可
 * （{@link CacheRepair} 会清掉 restore_mode 并重新解包）。</p>
 */
public final class CacheRestore {

    private static final String TAG = "TlwCn";

    /** 与 CnSetupActivity 中保持一致；只用于兜底，避免两处各写一个字符串。 */
    private static final String RESTORE_NAME = "restore_mode";
    private static final String MARKER_NAME = "installed.txt";
    private static final String LIST_MASTER = "installed.list";
    private static final String LIST_BUNDLE = "installed.bundles";
    private static final String ASSET_LEGACY = "tlw_cn_legacy.txt";

    private static final int REQUEST_CODE = 0x7C01;
    private static final long RELAUNCH_DELAY_MS = 1500L;
    private static final long SELF_KILL_DELAY_MS = 600L;

    private CacheRestore() {
    }

    /** 删汉化数据 + 写 restore_mode + 自动重启 App。 */
    public static void perform(Context context) {
        final Context app = context.getApplicationContext();
        try {
            File filesDir = app.getFilesDir();
            File cnDir = new File(filesDir, "tlw_cn");
            File cacheDir = new File(filesDir, "cache");
            File ext = app.getExternalFilesDir(null);
            File bundleRoot = (ext == null) ? null : new File(new File(ext, "UnityCache"), "Shared");

            int removed = 0;
            // 1) 按清单删主表（当前安装器写的）
            List<String> masters = readList(new File(cnDir, LIST_MASTER));
            for (String name : masters) {
                if (isSafeName(name) && delete(new File(cacheDir, name))) {
                    removed++;
                }
            }
            // 2) 按内置 legacy 清单删旧版安装器写的主表（v1.3/ci1 没有 installed.list）
            List<String> legacy = readAssetLines(app, ASSET_LEGACY);
            for (String name : legacy) {
                if (isSafeName(name) && delete(new File(cacheDir, name))) {
                    removed++;
                }
            }
            // 3) 按清单删汉化资源包目录（__data/__info；目录空了才删）
            if (bundleRoot != null) {
                for (String ab : readList(new File(cnDir, LIST_BUNDLE))) {
                    if (ab == null || ab.indexOf('/') <= 0) {
                        continue;
                    }
                    File dir = new File(new File(bundleRoot, ab.substring(0, ab.indexOf('/'))),
                            ab.substring(ab.indexOf('/') + 1));
                    boolean any = delete(new File(dir, "__data"));
                    any |= delete(new File(dir, "__info"));
                    if (any) {
                        removed++;
                    }
                    try {
                        String[] left = dir.list();
                        if (left != null && left.length == 0) {
                            dir.delete();
                        }
                    } catch (Throwable ignored) {
                    }
                }
            }
            // 4) 清 marker / 清单（清单内容已经用过，留着会让下次安装按旧清单删东西）
            delete(new File(cnDir, MARKER_NAME));
            delete(new File(cnDir, MARKER_NAME + ".tmp"));
            delete(new File(cnDir, LIST_MASTER));
            delete(new File(cnDir, LIST_BUNDLE));
            // 5) 写 restore_mode（restore 模式跳过解包，让游戏重下官方数据）
            writeRestoreMarker(cnDir);
            Log.i(TAG, "restore: removed=" + removed + " entries, restore_mode written, relaunching");
            scheduleRelaunch(app);
        } catch (Throwable t) {
            Log.e(TAG, "restore: failed, falling back to direct start", t);
            try {
                app.startActivity(launchIntent(app));
            } catch (Throwable t2) {
                Log.e(TAG, "restore: direct relaunch failed too", t2);
                return;     // 两套方案都失败：不杀进程，避免用户直接卡死
            }
        }
        killSelfSoon();
    }

    // ------------------------------------------------------------------ steps

    private static void writeRestoreMarker(File cnDir) throws Exception {
        if (!cnDir.isDirectory() && !cnDir.mkdirs() && !cnDir.isDirectory()) {
            throw new IllegalStateException("cannot create " + cnDir);
        }
        File marker = new File(cnDir, RESTORE_NAME);
        FileOutputStreamLite.write(marker);
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
        am.set(AlarmManager.RTC, System.currentTimeMillis() + RELAUNCH_DELAY_MS, pending);
    }

    private static Intent launchIntent(Context app) {
        Intent intent = app.getPackageManager().getLaunchIntentForPackage(app.getPackageName());
        if (intent == null) {
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
        }, "tlw-cache-restore-exit");
        t.setDaemon(true);
        t.start();
    }

    // ------------------------------------------------------------------ io

    private static List<String> readList(File f) {
        List<String> out = new ArrayList<String>();
        if (f == null || !f.isFile()) {
            return out;
        }
        BufferedReader r = null;
        try {
            r = new BufferedReader(new InputStreamReader(new FileInputStream(f), "UTF-8"));
            String line;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (line.length() > 0) {
                    out.add(line);
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "restore: read " + f + " failed: " + t);
        } finally {
            closeQuietly(r);
        }
        return out;
    }

    private static List<String> readAssetLines(Context app, String assetName) {
        List<String> out = new ArrayList<String>();
        InputStream in = null;
        BufferedReader r = null;
        try {
            in = app.getAssets().open(assetName);
            r = new BufferedReader(new InputStreamReader(in, "UTF-8"));
            String line;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (line.length() > 0) {
                    out.add(line);
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "restore: read assets/" + assetName + " failed: " + t);
        } finally {
            closeQuietly(r);
            closeQuietly(in);
        }
        return out;
    }

    private static boolean isSafeName(String name) {
        if (name == null || name.length() == 0 || name.length() > 128) {
            return false;
        }
        return name.indexOf('/') < 0 && name.indexOf('\\') < 0
                && !name.equals(".") && !name.equals("..");
    }

    private static boolean delete(File f) {
        try {
            if (f != null && f.exists() && f.delete()) {
                return true;
            }
        } catch (Throwable t) {
            Log.w(TAG, "restore: delete failed " + f, t);
        }
        return false;
    }

    private static void closeQuietly(java.io.Closeable c) {
        if (c != null) {
            try {
                c.close();
            } catch (Throwable ignored) {
            }
        }
    }

    /** 极简的 FileOutputStream 封装：restore_mode 只有一个固定内容。 */
    private static final class FileOutputStreamLite {
        static void write(File f) throws Exception {
            java.io.FileOutputStream fos = new java.io.FileOutputStream(f, false);
            try {
                fos.write("1\n".getBytes("UTF-8"));
                fos.flush();
                try {
                    fos.getFD().sync();
                } catch (Throwable ignored) {
                }
            } finally {
                try {
                    fos.close();
                } catch (Throwable ignored) {
                }
            }
        }
    }
}
