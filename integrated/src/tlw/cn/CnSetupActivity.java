package tlw.cn;

import android.app.Activity;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Process;
import android.os.SystemClock;
import android.util.Log;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import java.io.BufferedInputStream;
import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * 东方归言录（国际服 1.57.0 重打包版）首启汉化资源安装器。
 *
 * <p><b>为什么需要它</b>：汉化补丁（GitHub xiake595/lostword-cn-patch，lwlocal.zip，约 418 MB /
 * 761 个条目）必须出现在游戏自己的数据目录里，游戏才不会去下载国际服原始资源。原来的做法是用
 * root 版 apply.sh 或 LSPatch 模块在首次启动前把文件 push 进去；本集成 APK 把整包以
 * assets/lwlocal.zip 内置，由本 Activity 在游戏进程内、Unity 启动之前完成解包，因此不需要
 * root，也不需要游戏先联网。</p>
 *
 * <p><b>安装映射（与 v1.0 apply.sh / LwLocal v1.3 反编译结论一致）</b>：
 * <pre>
 *   lwlocal/master/&lt;hash&gt;              -&gt; getFilesDir()/cache/&lt;hash&gt;
 *                                          （/data/data/&lt;pkg&gt;/files/cache/&lt;hash&gt;）
 *   lwlocal/bundles/&lt;A&gt;/&lt;B&gt;/__data     -&gt; getExternalFilesDir(null)/UnityCache/Shared/&lt;A&gt;/&lt;B&gt;/__data
 *                                          （/sdcard/Android/data/&lt;pkg&gt;/files/UnityCache/Shared/...）
 *   lwlocal/version.txt                 -&gt; 内容作为版本标记写进 getFilesDir()/tlw_cn/installed.txt
 *   lwlocal/master/manifest.json        -&gt; getFilesDir()/cache/manifest.json（补丁自身的构建报告；
 *                                          v1.0 apply.sh 与 LwLocal v1.3 都按「master/ 下任意不带 /
 *                                          的条目」原样写入 cache，v1.4 验收时应有 70 张表）
 * </pre>
 * 只有 __data，没有 __info；不做 CRC 之外的校验；不删除旧文件（按 hash 命名的旧缓存无害）。</p>
 *
 * <p><b>幂等 / 断点语义</b>：所有目标文件都是「覆盖写」，marker 最后写；进程中途被杀只会留下不完整
 * 的目标文件，下次启动 marker 不匹配（或不存在）会整体重装。marker 用 tmp -&gt; rename 原子落盘并
 * fsync，保证「marker 写完」一定发生在「启动游戏」之前。</p>
 *
 * <p><b>调试钩子</b>（模拟器验证用，全部是「文件存在即生效」）：
 * <pre>
 *   getExternalFilesDir(null)/tlw_cn/skip_extract  视为已安装，直接启动游戏（跳过解包）
 *   getExternalFilesDir(null)/tlw_cn/no_autolaunch 解包完成后停在「安装完成」界面，不启动游戏
 *   为了兼容旧脚本，getFilesDir()/tlw_cn/ 下的同名文件也认（外部目录优先，adb shell 无需 root）。
 * </pre>
 * 用例：{@code adb shell mkdir -p /sdcard/Android/data/&lt;pkg&gt;/files/tlw_cn} 后
 * {@code touch .../skip_extract}。注意：不创建任何一个钩子时，安装完会直接拉起游戏。</p>
 *
 * <p><b>入口关系</b>：APK 的 MAIN/LAUNCHER 指向本 Activity（由 build-cn.ps1 改二进制 manifest），
 * 游戏真正的启动 Activity 仍是 {@code com.google.firebase.MessagingUnityPlayerActivity}，本类用
 * 显式 setClassName 拉起它。本类只依赖 framework API，不引用任何 res/AndroidX。</p>
 *
 * <p>日志 tag：{@code TlwCn}；另外把关键日志追加到 files/tlw_cn/install.log 方便取证。</p>
 */
public class CnSetupActivity extends Activity {

    private static final String TAG = "TlwCn";

    /** 游戏真正的启动 Activity（Unity + Firebase）。 */
    private static final String GAME_ACTIVITY = "com.google.firebase.MessagingUnityPlayerActivity";

    /** build-cn.ps1 内置的汉化数据包（STORED，约 361 MB）。 */
    private static final String ASSET_ZIP = "lwlocal.zip";

    private static final String ENTRY_VERSION = "lwlocal/version.txt";
    /** 构建时写入的发布版本标记（= 汉化 Release 的 version.txt）。zip 内的
     *  lwlocal/version.txt 可能是作者遗留的旧值，所以优先用这个。 */
    private static final String ASSET_VERSION = "tlw_cn.version";
    private static final String PREFIX_MASTER = "lwlocal/master/";
    private static final String PREFIX_BUNDLES = "lwlocal/bundles/";
    private static final String MANIFEST_NAME = "manifest.json";

    /**
     * zip 条目总数 / 解压后总字节数（来自数据包统计，仅用于进度百分比与文案兜底）。
     *
     * <p>v1.4 数据包：761 个条目 = 345 个 {@code __data} + 345 个 {@code __info}
     * + 70 张主表 + {@code lwlocal/version.txt}，未压缩合计 438,036,025 B。
     * 这个数字只用于「进度条上限」和「条目被截断」的兜底判断，
     * 真正的完整性以解包结果（entries &gt; 0 且每个条目都写成功）为准。</p>
     */
    private static final int EXPECTED_ENTRIES = 761;
    private static final long EXPECTED_BYTES = 438036025L;

    /** 1 MiB 读写缓冲（需求指定）。 */
    private static final int BUFFER_SIZE = 1024 * 1024;
    /** 进度界面刷新周期，最多 100ms 一次。 */
    private static final int UI_PERIOD_MS = 100;

    private static final String DIR_TLW = "tlw_cn";
    private static final String MARKER_NAME = "installed.txt";
    private static final String HOOK_SKIP = "skip_extract";
    private static final String HOOK_NO_AUTO = "no_autolaunch";

    /**
     * 上一次安装写进 {@code files/cache} 的主表清单（一行一个文件名）。
     *
     * <p>存在的意义：数据包的 master 数量是会变的（v1.3 是 84 张，v1.4 砍到 70 张）。
     * 安装器只覆盖不删除的话，被砍掉的那批旧表会一直留在 cache 里，游戏用新版本代码去读
     * 旧结构的数据 → 典型表现就是商店面板 {@code ShopCategoryToggle.UpdateToggle()}
     * 抛 NullReferenceException、整个面板黑屏（2026-11-10 实测，见
     * docs/TROUBLESHOOT-shop-black-screen.md）。</p>
     *
     * <p>所以每次安装成功后记一份清单；下次安装前，把「清单里有、但这次数据包里没有」
     * 的条目删掉。<b>只删自己写过的</b>，游戏自己下载的表一律不碰。</p>
     */
    private static final String LIST_MASTER = "installed.list";
    private static final String LIST_BUNDLE = "installed.bundles";

    private static final int COLOR_BG = 0xFF0E1116;
    private static final int COLOR_TEXT = 0xFFF2F5F8;
    private static final int COLOR_SUB = 0xFFA9B7C6;
    private static final int COLOR_DIM = 0xFF6F8194;
    private static final int COLOR_ERROR = 0xFFFF6B6B;
    private static final int COLOR_ACCENT = 0xFF4FC3F7;

    // ---------------------------------------------------------------------
    // 安装会话状态。
    //
    // 解包只由进程里的一个后台线程负责；Activity 旋转/重建/被系统销毁后重建时，新实例靠这些
    // static 字段接上正在进行的安装，避免第二个线程同时写同一批目标文件。Activity 只做「读状态 +
    // 3000 刷新界面」，不持有解包线程，所以销毁 Activity 不会打断安装。
    // ---------------------------------------------------------------------
    private static final Object SESSION_LOCK = new Object();
    private static volatile boolean sRunning;
    private static volatile boolean sSucceeded;
    private static volatile boolean sFailed;
    private static volatile String sErrorMessage;
    private static volatile int sEntryCount;
    private static volatile long sByteCount;
    private static volatile long sStartElapsed;
    private static volatile long sElapsedMs;
    private static volatile String sInstalledVersion;

    private Handler ui;
    private LinearLayout root;
    private TextView titleView;
    private TextView statusView;
    private TextView percentView;
    private TextView detailView;
    private TextView errorView;
    private TextView hintView;
    private Button retryButton;
    private ProgressBar progressBar;

    private int pad;
    private boolean noAutolaunch;
    private boolean tickerStopped = true;
    private boolean doneUiShown;
    private boolean retryLaunchOnly;
    private volatile File diagLogFile;

    /** zip 是否存在（getAssets().open 成功过）与快速探测到的 version.txt 内容。 */
    private boolean zipPresent;
    private String probeVersion;

    // ---------------------------------------------------------------------
    // 生命周期
    // ---------------------------------------------------------------------

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // 主题要在 setContentView 之前设置；无 ActionBar + 深色窗口，避免白屏闪烁。
        setTheme(android.R.style.Theme_DeviceDefault_NoActionBar);
        super.onCreate(savedInstanceState);
        ui = new Handler(Looper.getMainLooper());
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        if (Build.VERSION.SDK_INT >= 21) {
            try {
                getWindow().setStatusBarColor(COLOR_BG);
                getWindow().setNavigationBarColor(COLOR_BG);
            } catch (Throwable ignored) {
            }
        }
        // 不动 requestedOrientation：build-cn.ps1 注入的 <activity> 已带 android:screenOrientation="portrait"；
        // 即使 Activity 被系统重建，static 安装会话也能让新实例接上进度，不需要在这里锁方向。

        final File filesDir = getFilesDir();
        final File cnDir = new File(filesDir, DIR_TLW);
        final File extRoot = externalFilesRoot();
        final File marker = new File(cnDir, MARKER_NAME);

        // 两个调试钩子都在 onCreate 里检查（外部目录优先，内部目录兼容旧写法）。
        final boolean skipExtract = hasHook(cnDir, extRoot, HOOK_SKIP);
        noAutolaunch = hasHook(cnDir, extRoot, HOOK_NO_AUTO);
        diag("onCreate filesDir=" + filesDir + " extRoot=" + extRoot
                + " skipExtract=" + skipExtract + " noAutolaunch=" + noAutolaunch);

        final String installedVersion = readSmallText(marker);
        final boolean hasMarker = installedVersion != null && installedVersion.length() > 0;
        probeAsset();
        final String zipVersion = probeVersion;

        // 钩子 1：skip_extract —— 视为已安装，直接启动游戏（跳过整个解包）。
        if (skipExtract) {
            diag("debug hook skip_extract found: skip extraction, trusted as installed");
            if (noAutolaunch) {
                buildUi();
                showInstalledUi(installedVersion, "调试钩子 skip_extract 生效：已跳过解包。");
            } else {
                launchGame();
            }
            return;
        }

        // 快路径：marker 与数据包内 version.txt 一致 -> 已经装好，立即拉起游戏，不构建界面（无闪烁）。
        // zipVersion == null 表示数据包里没找到 version.txt（或整个 assets 缺失）：此时若有 marker 就信任它，
        // 避免老 marker 把整包汉化数据每次启动重解一遍。
        if (hasMarker && (zipVersion == null || installedVersion.equals(zipVersion))) {
            diag("up-to-date: marker=" + installedVersion + " zipVersion=" + zipVersion);
            if (noAutolaunch) {
                buildUi();
                showInstalledUi(installedVersion, "调试钩子 no_autolaunch 生效：本次未自动启动游戏。");
            } else {
                launchGame();
            }
            return;
        }

        // 首次安装 / 数据包版本升级 / 上次安装被中断 / 缓存修复。
        buildUi();
        if (hasMarker && zipVersion != null) {
            statusView.setText("检测到汉化数据更新（" + installedVersion + " → " + zipVersion + "），正在重新安装…");
        } else if (!hasMarker && new File(cnDir, "install.log").isFile()) {
            // marker 被「缓存修复」删掉了，但之前装过：这是修复路径
            statusView.setText("检测到汉化资源需要修复，正在重新安装…");
        }
        if (sRunning) {
            // Activity 重建（旋转等），后台解包线程还在跑：接上进度即可。
            diag("activity re-created while extraction is running, attach to progress");
            startTicker();
            return;
        }
        if (startExtraction()) {
            startTicker();
        }
    }

    @Override
    protected void onDestroy() {
        tickerStopped = true;
        if (ui != null) {
            ui.removeCallbacksAndMessages(null);
        }
        super.onDestroy();
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        // 解包期间按返回键不退出 Activity（避免用户以为装完了）；只把任务挪到后台，进程继续解包。
        if (sRunning) {
            diag("back pressed while extracting -> moveTaskToBack");
            moveTaskToBack(true);
            return;
        }
        super.onBackPressed();
    }

    // ---------------------------------------------------------------------
    // 快速探测与文件读取工具
    // ---------------------------------------------------------------------

    /**
     * 快速探测 assets/lwlocal.zip：是否存在、version.txt 是什么。
     *
     * <p>version.txt 正常情况下是 zip 的第一个条目；这里仍然做了「最多 16 个条目 / 最多读 2 MB」的
     * 上限，防止有人重新打包后 version.txt 排在很后面时，快路径为了探测版本先扫掉整包。</p>
     */
    private void probeAsset() {
        zipPresent = false;
        probeVersion = null;
        InputStream raw = null;
        ZipInputStream zin = null;
        try {
            raw = getAssets().open(ASSET_ZIP);
            zipPresent = true;
            zin = new ZipInputStream(new BufferedInputStream(raw, 64 * 1024));
            byte[] tmp = new byte[16 * 1024];
            int scanned = 0;
            long consumed = 0L;
            final long probeLimit = 2L * 1024 * 1024;
            ZipEntry entry;
            while ((entry = zin.getNextEntry()) != null) {
                scanned++;
                String name = entry.getName();
                if (ENTRY_VERSION.equals(name)) {
                    probeVersion = readTextEntry(zin, 4096).trim();
                    break;
                }
                // version.txt 正常是第一条；这里做兜底扫描，但绝不为了探测版本把整包读一遍：
                // 累计读超过 2 MB 或条目数超过 16 就直接放弃（快路径回退成「信任已有 marker」）。
                int r;
                while ((r = zin.read(tmp)) != -1) {
                    consumed += r;
                    if (consumed > probeLimit) {
                        break;
                    }
                }
                if (consumed > probeLimit || scanned >= 16) {
                    Log.w(TAG, "version.txt not found in first " + scanned + " entries / 2MB of " + ASSET_ZIP);
                    break;
                }
            }
        } catch (Throwable t) {
            // 最可能是 assets/lwlocal.zip 不存在（还没内置数据包）：留 null，走后面的错误提示。
            if (t instanceof java.io.FileNotFoundException) {
                zipPresent = false;
            }
            Log.w(TAG, "probe assets/" + ASSET_ZIP + " failed: " + t);
        } finally {
            closeQuietly(zin);
            closeQuietly(raw);
        }
        // 发布版本优先：assets/tlw_cn.version 由 build-cn.ps1 按汉化 Release 写入。
        // lwlocal.zip 内的 version.txt 在 v1.3 包里还是旧的 v1.1-20261108，仅作兜底。
        String releaseVersion = readAssetText(ASSET_VERSION, 256);
        if (releaseVersion != null) {
            probeVersion = releaseVersion;
        }
        diag("probeAsset: zipPresent=" + zipPresent + " version=" + probeVersion);
    }

    /** 读 assets 里的小文本文件；不存在/读失败返回 null。 */
    private String readAssetText(String name, int maxBytes) {
        InputStream in = null;
        try {
            in = getAssets().open(name);
            String s = readTextEntry(in, maxBytes).trim();
            return s.length() == 0 ? null : s;
        } catch (Throwable t) {
            Log.w(TAG, "read assets/" + name + " failed: " + t);
            return null;
        } finally {
            closeQuietly(in);
        }
    }

    private static String readTextEntry(InputStream in, int maxBytes) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream(512);
        byte[] buf = new byte[1024];
        int total = 0;
        int r;
        while ((r = in.read(buf)) != -1) {
            if (total + r > maxBytes) {
                out.write(buf, 0, Math.max(0, maxBytes - total));
                break;
            }
            out.write(buf, 0, r);
            total += r;
        }
        return new String(out.toByteArray(), "UTF-8");
    }

    /** 读小文本文件（marker），不存在/读失败返回 null；内容 trim。 */
    private static String readSmallText(File f) {
        if (f == null || !f.isFile()) {
            return null;
        }
        InputStream in = null;
        try {
            in = new FileInputStream(f);
            String s = readTextEntry(in, 4096).trim();
            return s.length() == 0 ? null : s;
        } catch (Throwable t) {
            Log.w(TAG, "read " + f + " failed: " + t);
            return null;
        } finally {
            closeQuietly(in);
        }
    }

    private void writeMarkerAtomic(File marker, String version) throws IOException {
        File dir = marker.getParentFile();
        if (dir != null && !dir.isDirectory() && !dir.mkdirs() && !dir.isDirectory()) {
            throw new IOException("无法创建目录: " + dir);
        }
        File tmp = new File(dir, MARKER_NAME + ".tmp");
        byte[] data = (version + "\n").getBytes("UTF-8");
        FileOutputStream fos = new FileOutputStream(tmp, false);
        try {
            fos.write(data);
            fos.flush();
            try {
                fos.getFD().sync();
            } catch (Throwable ignored) {
            }
        } finally {
            closeQuietly(fos);
        }
        // Linux 上 rename 会覆盖同名文件（原子）；个别文件系统不支持覆盖时先删再 rename。
        boolean renamed = tmp.renameTo(marker);
        if (!renamed && marker.isFile()) {
            if (marker.delete()) {
                renamed = tmp.renameTo(marker);
            }
        }
        if (!renamed) {
            // 极端兜底：直接写 marker（进程被杀时最多退化为下次重装，不会出现「未装完却启动游戏」）。
            Log.w(TAG, "marker rename failed, writing directly: " + marker);
            FileOutputStream direct = new FileOutputStream(marker, false);
            try {
                direct.write(data);
                direct.flush();
                try {
                    direct.getFD().sync();
                } catch (Throwable ignored) {
                }
            } finally {
                closeQuietly(direct);
            }
        }
        diag("marker written: " + marker + " = " + version);
    }

    // ---------------------------------------------------------------------
    // 解包（后台线程）
    // ---------------------------------------------------------------------

    /**
     * 启动解包线程（幂等：会话已在跑则直接返回 true 让界面接上进度）。
     *
     * @return false 表示连线程都没起来（例如外部存储不可用），此时界面已显示错误。
     */
    private boolean startExtraction() {
        final File filesDir = getFilesDir();
        final File cnDir = new File(filesDir, DIR_TLW);
        final File extRoot = externalFilesRoot();
        if (extRoot == null) {
            // getExternalFilesDir(null) 为 null：外部存储不可用，bundles 无处可写，直接报错。
            retryLaunchOnly = false;
            buildUi();
            showFailureUi("无法访问外部存储（getExternalFilesDir(null) 返回 null）。请确认存储已挂载、空间可用后重试。");
            return false;
        }
        final File marker = new File(cnDir, MARKER_NAME);
        final File diagManifest = new File(cnDir, "lwlocal_manifest.json");

        synchronized (SESSION_LOCK) {
            if (sRunning) {
                return true;
            }
            sRunning = true;
            sSucceeded = false;
            sFailed = false;
            sErrorMessage = null;
            sEntryCount = 0;
            sByteCount = 0;
            sElapsedMs = 0L;
            sStartElapsed = SystemClock.elapsedRealtime();
            sInstalledVersion = null;
        }
        diag("extract start: filesDir=" + filesDir + " extRoot=" + extRoot);

        Thread worker = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    // 解包是长 I/O 任务：压到后台优先级，尽量不影响游戏主线程/系统 UI。
                    Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND);
                } catch (Throwable ignored) {
                }
                runExtraction(filesDir, cnDir, extRoot, marker, diagManifest);
            }
        }, "tlw-cn-extract");
        worker.setDaemon(false);
        try {
            worker.setPriority(Thread.MIN_PRIORITY);
        } catch (Throwable ignored) {
        }
        try {
            worker.start();
        } catch (Throwable t) {
            Log.e(TAG, "cannot start extraction thread", t);
            synchronized (SESSION_LOCK) {
                sRunning = false;
                sFailed = true;
                sErrorMessage = "无法创建解包线程: " + t;
            }
            return false;
        }
        return true;
    }

    /** 解包主流程。所有异常都转成 sErrorMessage，界面线程负责展示。 */
    private void runExtraction(File filesDir, File cnDir, File extRoot, File marker, File diagManifest) {
        boolean ok = false;
        try {
            ensureDir(cnDir);
            final File cacheDir = new File(filesDir, "cache");
            final File bundleRoot = new File(new File(extRoot, "UnityCache"), "Shared");
            ensureDir(cacheDir);
            ensureDir(bundleRoot);
            diag("targets: cache=" + cacheDir + " bundleRoot=" + bundleRoot);

            InputStream raw = null;
            ZipInputStream zin = null;
            byte[] buffer = new byte[BUFFER_SIZE];
            int entries = 0;
            int seen = 0;
            int masterFiles = 0;
            int bundleFiles = 0;
            int cacheInfoFiles = 0;
            int packagedInfo = 0;
            long bytes = 0L;
            String version = null;
            // 本次数据包里实际存在的条目名（用于跟上次的清单做差集，删掉被上游砍掉的旧表/旧包）
            final Set<String> nowMaster = new HashSet<String>();
            final Set<String> nowBundles = new HashSet<String>();
            try {
                raw = getAssets().open(ASSET_ZIP);
                zin = new ZipInputStream(new BufferedInputStream(raw, 128 * 1024));
                ZipEntry entry;
                while ((entry = zin.getNextEntry()) != null) {
                    final String name = entry.getName();
                    try {
                        if (name == null || entry.isDirectory()) {
                            continue;
                        }
                        seen++;
                        if (ENTRY_VERSION.equals(name)) {
                            version = readTextEntry(zin, 4096).trim();
                            entries++;
                            diag("data pack version.txt = [" + version + "]");
                        } else if (("lwlocal/" + MANIFEST_NAME).equals(name)) {
                            // 少数打包方式会把清单放在顶层 lwlocal/ 下；只做排查副本。
                            long n = copyEntry(zin, diagManifest, buffer, bytes);
                            bytes += n;
                            entries++;
                            diag("saved diagnostic manifest: " + diagManifest + " (" + n + " bytes)");
                        } else if (name.startsWith(PREFIX_MASTER)) {
                            final String rest = name.substring(PREFIX_MASTER.length());
                            // 参考实现（v1.0 apply.sh 的 `cp master/* $CACHE/` 与 LwLocal v1.3 的 unzip()）都是：
                            // master/ 下任何「不带 / 的条目」原样写进 filesDir/cache/ —— 包括补丁自带的
                            // manifest.json（补丁构建报告，非游戏数据）。v1.4 是 70 张表（任务/交换所暂不汉化）。
                            if (!isSafeSegment(rest)) {
                                Log.w(TAG, "skip unsafe master entry: " + name);
                            } else {
                                long n = copyEntry(zin, new File(cacheDir, rest), buffer, bytes);
                                bytes += n;
                                entries++;
                                masterFiles++;
                                nowMaster.add(rest);
                            }
                        } else if (name.startsWith(PREFIX_BUNDLES)) {
                            final String rest = name.substring(PREFIX_BUNDLES.length());
                            final String[] parts = rest.split("/");
                            if (parts.length == 3 && "__data".equals(parts[2])
                                    && isSafeSegment(parts[0]) && isSafeSegment(parts[1])) {
                                File dir = new File(new File(bundleRoot, parts[0]), parts[1]);
                                File dest = new File(dir, "__data");
                                long n = copyEntry(zin, dest, buffer, bytes);
                                // 必须同时补 __info：Unity 的 AssetBundle 缓存只认「有 __info 的目录」，
                                // 只有 __data、没有 __info 的条目在游戏初始化缓存时会当作垃圾清掉
                                // （实测：真机首启后 345 个预置包里 269 个被删、其余被重新下载的英文包覆盖）。
                                //
                                // v1.4 数据包自己也带了 __info（345 个），但里面的 mtime 是打包时的固定值，
                                // 与刚写出的 __data 对不上；这里仍然由安装器按 __data 的真实 mtime 重新生成，
                                // 数据包里的那份只当参考、不落盘（见下面的 __info 分支）。
                                writeCacheInfo(dir, dest);
                                bytes += n;
                                entries++;
                                bundleFiles++;
                                cacheInfoFiles++;
                                nowBundles.add(parts[0] + "/" + parts[1]);
                            } else if (parts.length == 3 && "__info".equals(parts[2])) {
                                // 数据包自带的 __info：读掉但不落盘，避免覆盖上面按真实 mtime 生成的那份。
                                skipEntry(zin, buffer);
                                packagedInfo++;
                            } else {
                                Log.w(TAG, "skip malformed bundle entry: " + name);
                            }
                        } else {
                            // 数据包里出现未知条目时不装、也不报错，只记录。
                            Log.w(TAG, "ignore unexpected entry: " + name);
                        }
                        sEntryCount = entries;
                        sByteCount = bytes;
                    } finally {
                        try {
                            zin.closeEntry();
                        } catch (Throwable ignored) {
                        }
                    }
                }
            } finally {
                closeQuietly(zin);
                closeQuietly(raw);
            }

            if (entries <= 0) {
                throw new IOException("lwlocal.zip 中没有可安装的条目（资源包损坏？）");
            }
            // 完整性检查：v1.4 数据包固定 761 个条目（345 __data + 345 __info + 70 主表 + version.txt）。
            // 若 APK 重打包时 asset 被截断，ZipInputStream 读到条目边界会「正常」结束，必须靠条目数识别，
            // 否则会写入不完整的汉化数据 + marker，导致游戏缺资源去联网下载。
            if (seen < EXPECTED_ENTRIES) {
                throw new IOException("内置汉化数据包不完整：只读到 " + seen + " / " + EXPECTED_ENTRIES
                        + " 个文件（APK 内 assets/lwlocal.zip 可能被截断）。");
            }
            // 版本标记优先级：构建时写入的发布版本(assets/tlw_cn.version) > zip 内 version.txt。
            // v1.3 数据包内部的 lwlocal/version.txt 是作者遗留的 v1.1-20261108，不能拿来做
            // 「是否需要重装」的唯一依据（否则将来数据包更新、内部标记没变时会漏装）。
            if (probeVersion != null && probeVersion.length() > 0) {
                version = probeVersion;
            } else if (version == null || version.length() == 0) {
                version = "unknown";
                Log.w(TAG, "version.txt missing in lwlocal.zip, marker uses fallback 'unknown'");
            }

            // 关键顺序：所有目标文件写完后，先清掉「上次写过、这次数据包里没有」的旧条目，
            // 再原子写 marker，之后才允许启动游戏。
            //
            // 为什么要清：数据包的主表数量会变（v1.3 84 张 → v1.4 70 张）。只覆盖不删除时，
            // 被上游砍掉的 14 张旧表会留在 cache 里，游戏用新代码读旧结构 → 商店面板空引用黑屏。
            // 只删「上次安装自己写过的」（清单里的），游戏自己下载的表一律不碰。
            final int prunedMaster = pruneStale(new File(cnDir, LIST_MASTER), nowMaster,
                    new Pruner() {
                        @Override
                        public boolean remove(String name) {
                            return deleteIfFile(new File(cacheDir, name));
                        }
                    });
            final int prunedBundles = pruneStale(new File(cnDir, LIST_BUNDLE), nowBundles,
                    new Pruner() {
                        @Override
                        public boolean remove(String ab) {
                            final int slash = ab.indexOf('/');
                            if (slash <= 0 || slash >= ab.length() - 1) {
                                return false;
                            }
                            File dir = new File(new File(bundleRoot, ab.substring(0, slash)),
                                    ab.substring(slash + 1));
                            boolean any = deleteIfFile(new File(dir, "__data"));
                            any |= deleteIfFile(new File(dir, "__info"));
                            // 目录空了才删，避免误删游戏自己放进来的东西
                            try {
                                String[] left = dir.list();
                                if (left != null && left.length == 0) {
                                    dir.delete();
                                }
                            } catch (Throwable ignored) {
                            }
                            return any;
                        }
                    });
            if (prunedMaster > 0 || prunedBundles > 0) {
                diag("pruned stale entries: master=" + prunedMaster + " bundles=" + prunedBundles);
            }
            writeNameList(new File(cnDir, LIST_MASTER), nowMaster);
            writeNameList(new File(cnDir, LIST_BUNDLE), nowBundles);

            writeMarkerAtomic(marker, version);
            sInstalledVersion = version;
            sEntryCount = entries;
            sByteCount = bytes;
            sElapsedMs = SystemClock.elapsedRealtime() - sStartElapsed;
            diag("extract done: entries=" + entries + " seen=" + seen + " master=" + masterFiles
                    + " bundles=" + bundleFiles + " cacheInfo=" + cacheInfoFiles
                    + " packagedInfo=" + packagedInfo + " prunedMaster=" + prunedMaster
                    + " prunedBundles=" + prunedBundles + " bytes=" + bytes
                    + " elapsedMs=" + sElapsedMs + " version=" + version);
            ok = true;
        } catch (Throwable t) {
            sErrorMessage = friendlyError(t);
            Log.e(TAG, "extraction failed: " + t, t);
            diag("ERROR extraction failed: " + sErrorMessage + " / " + t.getClass().getName() + ": " + t.getMessage());
        } finally {
            synchronized (SESSION_LOCK) {
                if (ok) {
                    sSucceeded = true;
                } else {
                    sFailed = true;
                }
                sRunning = false;
            }
        }
    }

    /** 逐条目写文件（覆盖写，幂等）；返回该条目字节数。 */
    private long copyEntry(ZipInputStream zin, File dest, byte[] buffer, long baseBytes) throws IOException {
        File parent = dest.getParentFile();
        if (parent != null && !parent.isDirectory() && !parent.mkdirs() && !parent.isDirectory()) {
            throw new IOException("无法创建目录: " + parent);
        }
        long written = 0L;
        FileOutputStream fos = new FileOutputStream(dest, false);
        try {
            int r;
            while ((r = zin.read(buffer)) != -1) {
                fos.write(buffer, 0, r);
                written += r;
                // 供进度界面读取；大条目（最大 9 MB）期间进度条也能平滑推进。
                sByteCount = baseBytes + written;
            }
            fos.flush();
        } finally {
            closeQuietly(fos);
        }
        return written;
    }

    /**
     * 读掉一个条目但不落盘（v1.4 数据包里自带的 {@code __info} 用这个跳过）。
     *
     * <p>ZipInputStream 必须把当前条目的数据流读完才能走到下一个条目，
     * 所以不能直接 continue，得把字节读掉丢掉。</p>
     */
    private static void skipEntry(ZipInputStream zin, byte[] buffer) throws IOException {
        while (zin.read(buffer) != -1) {
            // discard
        }
    }

    // ---------------------------------------------------------------------
    // 旧条目清理（installed.list / installed.bundles）
    // ---------------------------------------------------------------------

    /** 单个旧条目的删除动作；返回是否真的删掉了东西。 */
    private interface Pruner {
        boolean remove(String name);
    }

    /**
     * 按上次的清单清掉这次数据包里已经不存在的条目。
     *
     * @return 实际删除的条目数
     */
    private static int pruneStale(File listFile, Set<String> nowPresent, Pruner pruner) {
        List<String> old = readNameList(listFile);
        if (old.isEmpty()) {
            return 0;
        }
        int removed = 0;
        for (String name : old) {
            if (name == null || name.length() == 0 || nowPresent.contains(name)) {
                continue;
            }
            try {
                if (pruner.remove(name)) {
                    removed++;
                    Log.i(TAG, "pruned stale entry: " + name);
                }
            } catch (Throwable t) {
                // 删不掉不算失败：留着最多是旧数据，比中断安装好。
                Log.w(TAG, "prune failed: " + name + " / " + t);
            }
        }
        return removed;
    }

    /** 读一行一个名字的清单；不存在/读失败返回空表。 */
    private static List<String> readNameList(File f) {
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
            Log.w(TAG, "read list " + f + " failed: " + t);
        } finally {
            closeQuietly(r);
        }
        return out;
    }

    /** 原子写清单（tmp → rename）；失败只记日志，不影响安装结果。 */
    private static void writeNameList(File f, Set<String> names) {
        if (f == null) {
            return;
        }
        File tmp = new File(f.getParentFile(), f.getName() + ".tmp");
        FileOutputStream fos = null;
        try {
            StringBuilder sb = new StringBuilder(names.size() * 40);
            for (String n : names) {
                sb.append(n).append('\n');
            }
            fos = new FileOutputStream(tmp, false);
            fos.write(sb.toString().getBytes("UTF-8"));
            fos.flush();
            try {
                fos.getFD().sync();
            } catch (Throwable ignored) {
            }
            closeQuietly(fos);
            fos = null;
            if (!tmp.renameTo(f)) {
                if (f.isFile()) {
                    f.delete();
                }
                if (!tmp.renameTo(f)) {
                    Log.w(TAG, "cannot write list " + f);
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "write list " + f + " failed: " + t);
        } finally {
            closeQuietly(fos);
        }
    }

    /** 是普通文件才删；返回是否删掉了。 */
    private static boolean deleteIfFile(File f) {
        try {
            if (f != null && f.isFile() && f.delete()) {
                return true;
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

    /**
     * 给 Unity AssetBundle 缓存条目补 __info。
     *
     * <p>真机上游戏自己下载的每个缓存条目都是 <code>&lt;A&gt;/&lt;B&gt;/__data</code> +
     * <code>__info</code> 两件套，而没有 __info 的目录在游戏初始化/下载资源时会被当成垃圾
     * （实测：345 个预置包在真机首次下载后 269 个被删、其余被英文原包覆盖，导致角色名/UI 回退英文）。
     * 这个格式是从真机下载产生的文件里读出来的纯文本：</p>
     *
     * <pre>-1
     * &lt;epoch 秒 = __data 的 mtime&gt;
     * 1
     * __data
     * </pre>
     *
     * <p>-1 = 未计算 CRC；1 = 完成标记；最后一行是数据文件名。</p>
     */
    private static void writeCacheInfo(File dir, File dataFile) throws IOException {
        long ts = dataFile.lastModified() / 1000L;
        if (ts <= 0L) {
            ts = System.currentTimeMillis() / 1000L;
        }
        byte[] info = ("-1\n" + ts + "\n1\n__data\n").getBytes("UTF-8");
        File tmp = new File(dir, "__info.tmp");
        File dst = new File(dir, "__info");
        FileOutputStream fos = new FileOutputStream(tmp, false);
        try {
            fos.write(info);
            fos.flush();
            try {
                fos.getFD().sync();
            } catch (Throwable ignored) {
            }
        } finally {
            closeQuietly(fos);
        }
        if (!tmp.renameTo(dst)) {
            if (dst.isFile()) {
                dst.delete();
            }
            if (!tmp.renameTo(dst)) {
                throw new IOException("无法写入 __info: " + dst);
            }
        }
    }

    // ---------------------------------------------------------------------
    // 界面（纯代码构建，无 res/XML）
    // ---------------------------------------------------------------------

    private void buildUi() {
        if (root != null) {
            return;
        }
        pad = dp(22);
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(COLOR_BG);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.setPadding(pad, pad, pad, pad);
        // Android 15+ 强制 edge-to-edge：用 insets 监听把状态栏/导航栏高度补进 padding。
        root.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
            @Override
            public WindowInsets onApplyWindowInsets(View v, WindowInsets insets) {
                int top = 0;
                int bottom = 0;
                try {
                    top = insets.getSystemWindowInsetTop();
                    bottom = insets.getSystemWindowInsetBottom();
                } catch (Throwable ignored) {
                }
                v.setPadding(pad, pad + top, pad, pad + bottom);
                return insets;
            }
        });
        getWindow().getDecorView().setBackgroundColor(COLOR_BG);

        titleView = new TextView(this);
        titleView.setText("东方归言录 汉化安装");
        titleView.setTextColor(COLOR_TEXT);
        titleView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24.0f);
        titleView.setTypeface(Typeface.DEFAULT_BOLD);
        titleView.setGravity(Gravity.CENTER);
        addRow(titleView, LinearLayout.LayoutParams.WRAP_CONTENT, 0);

        statusView = new TextView(this);
        statusView.setText("首次启动正在安装汉化资源（约 418 MB），请勿退出…");
        statusView.setTextColor(COLOR_SUB);
        statusView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15.0f);
        statusView.setGravity(Gravity.CENTER);
        statusView.setLineSpacing(dp(4), 1.0f);
        addRow(statusView, LinearLayout.LayoutParams.WRAP_CONTENT, dp(16));

        progressBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progressBar.setMax(EXPECTED_ENTRIES);
        progressBar.setProgress(0);
        if (Build.VERSION.SDK_INT >= 21) {
            try {
                progressBar.setProgressTintList(ColorStateList.valueOf(COLOR_ACCENT));
                progressBar.setProgressBackgroundTintList(ColorStateList.valueOf(0xFF26313E));
            } catch (Throwable ignored) {
            }
        }
        addRow(progressBar, dp(14), dp(20));

        percentView = new TextView(this);
        percentView.setText("0%");
        percentView.setTextColor(COLOR_TEXT);
        percentView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 34.0f);
        percentView.setTypeface(Typeface.DEFAULT_BOLD);
        percentView.setGravity(Gravity.CENTER);
        addRow(percentView, LinearLayout.LayoutParams.WRAP_CONTENT, dp(8));

        detailView = new TextView(this);
        detailView.setText("文件 0 / " + EXPECTED_ENTRIES + " · 0.0 MB / 约 " + (EXPECTED_BYTES >> 20) + " MB");
        detailView.setTextColor(COLOR_SUB);
        detailView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.0f);
        detailView.setGravity(Gravity.CENTER);
        addRow(detailView, LinearLayout.LayoutParams.WRAP_CONTENT, dp(4));

        hintView = new TextView(this);
        hintView.setText("首次安装约需 1~3 分钟，完成后会自动进入游戏。\n安装过程中请勿退出应用。");
        hintView.setTextColor(COLOR_DIM);
        hintView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.0f);
        hintView.setGravity(Gravity.CENTER);
        hintView.setLineSpacing(dp(3), 1.0f);
        addRow(hintView, LinearLayout.LayoutParams.WRAP_CONTENT, dp(22));

        errorView = new TextView(this);
        errorView.setTextColor(COLOR_ERROR);
        errorView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14.0f);
        errorView.setGravity(Gravity.CENTER);
        errorView.setLineSpacing(dp(2), 1.0f);
        errorView.setVisibility(View.GONE);
        addRow(errorView, LinearLayout.LayoutParams.WRAP_CONTENT, dp(12));

        retryButton = new Button(this);
        retryButton.setText("重试");
        retryButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15.0f);
        retryButton.setVisibility(View.GONE);
        retryButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                onRetryClicked();
            }
        });
        addRow(retryButton, LinearLayout.LayoutParams.WRAP_CONTENT, dp(14));

        setContentView(root);
    }

    private void addRow(View v, int heightPx, int topMarginPx) {
        LinearLayout.LayoutParams lp =
                new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, heightPx);
        lp.topMargin = topMarginPx;
        root.addView(v, lp);
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private void onRetryClicked() {
        if (sRunning) {
            return;
        }
        if (retryLaunchOnly) {
            retryLaunchOnly = false;
            hideError();
            launchGame();
            return;
        }
        doneUiShown = false;
        hideError();
        progressBar.setMax(EXPECTED_ENTRIES);
        progressBar.setProgress(0);
        percentView.setText("0%");
        detailView.setText("文件 0 / " + EXPECTED_ENTRIES + " · 0.0 MB / 约 " + (EXPECTED_BYTES >> 20) + " MB");
        statusView.setText("首次启动正在安装汉化资源（约 418 MB），请勿退出…");
        hintView.setText("首次安装约需 1~3 分钟，完成后会自动进入游戏。\n安装过程中请勿退出应用。");
        synchronized (SESSION_LOCK) {
            sFailed = false;
            sSucceeded = false;
            sErrorMessage = null;
        }
        diag("retry clicked");
        if (startExtraction()) {
            startTicker();
        }
    }

    private void hideError() {
        errorView.setVisibility(View.GONE);
        retryButton.setVisibility(View.GONE);
    }

    private void startTicker() {
        tickerStopped = false;
        ui.removeCallbacks(uiTicker);
        ui.postDelayed(uiTicker, 60);
    }

    /**
     * 主线程定时器：最多每 100ms 从 static 会话状态取一次进度刷新界面。
     * 解包线程只改 volatile 字段，不直接碰 View，避免 ANR / 跨线程异常。
     */
    private final Runnable uiTicker = new Runnable() {
        @Override
        public void run() {
            if (tickerStopped) {
                return;
            }
            if (isFinishing() || isDestroyed()) {
                tickerStopped = true;
                return;
            }
            if (sRunning) {
                updateProgressUi();
                ui.postDelayed(this, UI_PERIOD_MS);
                return;
            }
            if (sFailed) {
                retryLaunchOnly = false;
                showFailureUi(sErrorMessage == null ? "未知错误" : sErrorMessage);
                return;
            }
            if (sSucceeded) {
                showSuccessUi();
                return;
            }
            // 会话状态意外为空（例如进程状态被重置）：重新开始一次安装。
            retryLaunchOnly = false;
            if (startExtraction()) {
                ui.postDelayed(this, UI_PERIOD_MS);
            }
        }
    };

    private void updateProgressUi() {
        if (root == null) {
            return;
        }
        final long bytes = Math.min(sByteCount, EXPECTED_BYTES);
        final int entries = sEntryCount;
        final int barValue;
        final int pct;
        if (EXPECTED_BYTES > 0) {
            pct = (int) Math.min(99L, bytes * 100L / EXPECTED_BYTES);
            barValue = (int) Math.min((long) EXPECTED_ENTRIES,
                    bytes * (long) EXPECTED_ENTRIES / EXPECTED_BYTES);
        } else {
            pct = Math.min(99, entries * 100 / EXPECTED_ENTRIES);
            barValue = entries;
        }
        progressBar.setMax(EXPECTED_ENTRIES);
        progressBar.setProgress(barValue);
        percentView.setText(pct + "%");
        detailView.setText(String.format(Locale.US, "文件 %d / %d · %s / 约 %s",
                entries, EXPECTED_ENTRIES, formatSize(bytes), formatSize(EXPECTED_BYTES)));
    }

    /** 解包成功（且非 no_autolaunch 时会立即拉起游戏）。 */
    private void showSuccessUi() {
        if (doneUiShown) {
            return;
        }
        doneUiShown = true;
        tickerStopped = true;
        if (root != null) {
            hideError();
            int n = Math.max(1, sEntryCount);
            progressBar.setMax(n);
            progressBar.setProgress(n);
            percentView.setText("100%");
            statusView.setText("汉化资源安装完成");
            detailView.setText(String.format(Locale.US, "已安装 %d 个文件（%s），耗时 %s",
                    sEntryCount, formatSize(sByteCount), formatDuration(sElapsedMs)));
            StringBuilder hint = new StringBuilder();
            hint.append("资源版本：").append(sInstalledVersion == null ? "未知" : sInstalledVersion);
            if (noAutolaunch) {
                hint.append("\n调试钩子 no_autolaunch 生效：本次未自动启动游戏。");
            } else {
                hint.append("\n正在启动游戏…");
            }
            hintView.setText(hint.toString());
        }
        if (!noAutolaunch) {
            launchGame();
        } else {
            diag("no_autolaunch hook: stay on done screen");
        }
    }

    /** 已安装（skip_extract / 快路径 no_autolaunch）时的「完成」界面。 */
    private void showInstalledUi(String installedVersion, String note) {
        doneUiShown = true;
        tickerStopped = true;
        hideError();
        progressBar.setMax(100);
        progressBar.setProgress(100);
        percentView.setText("100%");
        statusView.setText("汉化资源已安装");
        detailView.setText("无需安装：版本标记与内置数据包一致或已跳过解包。");
        StringBuilder hint = new StringBuilder();
        hint.append("资源版本：").append(installedVersion == null ? "未知" : installedVersion);
        hint.append("\n").append(note);
        if (noAutolaunch && note.indexOf(HOOK_NO_AUTO) < 0) {
            hint.append("\n调试钩子 no_autolaunch 生效：本次未自动启动游戏。");
        }
        if (!noAutolaunch) {
            hint.append("\n正在启动游戏…");
        }
        hintView.setText(hint.toString());
        if (!noAutolaunch) {
            launchGame();
        }
    }

    private void showFailureUi(String message) {
        tickerStopped = true;
        if (root == null) {
            buildUi();
        }
        statusView.setText("安装失败");
        errorView.setText("错误：" + message);
        errorView.setVisibility(View.VISIBLE);
        retryButton.setText(retryLaunchOnly ? "重试启动" : "重试");
        retryButton.setVisibility(View.VISIBLE);
        detailView.setText(String.format(Locale.US, "已写入 %d / %d 个文件（%s）",
                sEntryCount, EXPECTED_ENTRIES, formatSize(sByteCount)));
        hintView.setText("可以清理存储空间/确认存储可用后点「重试」。\n重新安装会覆盖已写入的文件，可安全重跑。");
        diag("failure UI: " + message);
    }

    /** 显式拉起游戏真正的启动 Activity。 */
    private void launchGame() {
        try {
            Intent intent = new Intent(Intent.ACTION_MAIN);
            intent.addCategory(Intent.CATEGORY_LAUNCHER);
            intent.setClassName(getPackageName(), GAME_ACTIVITY);
            startActivity(intent);
            diag("game activity started: " + GAME_ACTIVITY);
        } catch (Throwable t) {
            Log.e(TAG, "failed to start game activity " + GAME_ACTIVITY, t);
            diag("ERROR failed to start game activity: " + t);
            retryLaunchOnly = true;
            buildUi();
            showFailureUi("无法启动游戏（" + GAME_ACTIVITY + "）：" + t);
            return;
        }
        try {
            finish();
        } catch (Throwable ignored) {
        }
    }

    // ---------------------------------------------------------------------
    // 小工具
    // ---------------------------------------------------------------------

    private File externalFilesRoot() {
        try {
            return getExternalFilesDir(null);
        } catch (Throwable t) {
            Log.w(TAG, "getExternalFilesDir(null) failed: " + t);
            return null;
        }
    }

    /**
     * 调试钩子：外部目录 getExternalFilesDir(null)/tlw_cn/&lt;name&gt; 优先（adb shell 无 root 可建），
     * 同时兼容旧脚本会用的内部目录 getFilesDir()/tlw_cn/&lt;name&gt;。
     */
    private boolean hasHook(File cnDir, File extRoot, String name) {
        if (extRoot != null) {
            File external = new File(new File(extRoot, DIR_TLW), name);
            if (external.exists()) {
                diag("debug hook (external): " + external);
                return true;
            }
        }
        File internal = new File(cnDir, name);
        if (internal.exists()) {
            diag("debug hook (internal legacy): " + internal);
            return true;
        }
        return false;
    }

    private static boolean isSafeSegment(String name) {
        if (name == null || name.length() == 0 || name.length() > 128) {
            return false;
        }
        return !name.contains("/") && !name.contains("\\") && !name.equals(".")
                && !name.equals("..");
    }

    private static void ensureDir(File dir) throws IOException {
        if (dir == null) {
            throw new IOException("目录不可用: null");
        }
        if (!dir.isDirectory() && !dir.mkdirs() && !dir.isDirectory()) {
            throw new IOException("无法创建目录: " + dir);
        }
    }

    private static void closeQuietly(java.io.Closeable c) {
        if (c == null) {
            return;
        }
        try {
            c.close();
        } catch (Throwable ignored) {
        }
    }

    private static String formatSize(long bytes) {
        if (bytes < 0) {
            bytes = 0;
        }
        if (bytes >= 1000L * 1000L * 1000L) {
            return String.format(Locale.US, "%.2f GB", bytes / 1000000000.0);
        }
        return String.format(Locale.US, "%.1f MB", bytes / 1000000.0);
    }

    private static String formatDuration(long ms) {
        if (ms <= 0) {
            return "0.0 秒";
        }
        if (ms < 60000L) {
            return String.format(Locale.US, "%.1f 秒", ms / 1000.0);
        }
        long totalSec = ms / 1000L;
        return String.format(Locale.US, "%d 分 %02d 秒", totalSec / 60L, totalSec % 60L);
    }

    /** 把异常转成给用户看的中文错误文案。 */
    private static String friendlyError(Throwable t) {
        if (t == null) {
            return "未知错误";
        }
        Throwable root = t;
        for (int i = 0; i < 4 && root.getCause() != null && root.getCause() != root; i++) {
            root = root.getCause();
        }
        String all = String.valueOf(t.getMessage()) + " " + String.valueOf(root.getMessage())
                + " " + root.getClass().getName();
        String lower = all.toLowerCase(Locale.US);
        if (lower.contains("enospc") || lower.contains("no space left")) {
            return "存储空间不足。安装需要约 425 MB 可用空间，请清理后重试。";
        }
        if (t instanceof java.io.FileNotFoundException) {
            return "找不到内置资源 assets/" + ASSET_ZIP + "（APK 构建时可能没有打入汉化数据）。";
        }
        if (t instanceof SecurityException || lower.contains("permission denied")
                || lower.contains("eacces")) {
            return "没有写入目标目录的权限（存储不可用或应用数据目录被限制）。";
        }
        String msg = t.getMessage();
        if (msg == null || msg.length() == 0) {
            msg = t.getClass().getName();
        }
        return msg;
    }

    /** 关键日志同时写 logcat（tag TlwCn）和 files/tlw_cn/install.log，方便模拟器取证据。 */
    private void diag(String message) {
        Log.i(TAG, message);
        try {
            File cnDir = new File(getFilesDir(), DIR_TLW);
            if (!cnDir.isDirectory() && !cnDir.mkdirs() && !cnDir.isDirectory()) {
                return;
            }
            File logFile = diagLogFile;
            if (logFile == null) {
                logFile = new File(cnDir, "install.log");
                diagLogFile = logFile;
            }
            FileOutputStream fos = new FileOutputStream(logFile, true);
            try {
                String line = new SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US).format(new Date())
                        + " [" + Thread.currentThread().getName() + "] " + message + "\n";
                fos.write(line.getBytes("UTF-8"));
            } finally {
                closeQuietly(fos);
            }
        } catch (Throwable ignored) {
        }
    }
}
