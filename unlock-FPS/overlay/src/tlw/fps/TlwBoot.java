package tlw.fps;

import android.app.Application;
import android.content.Context;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.util.Log;

/**
 * Injected entry point.
 *
 * Declared in AndroidManifest as a ContentProvider, so the system instantiates
 * it BEFORE Application.onCreate() -- earlier than any Unity code runs.
 * No smali patch of the Unity activity is needed.
 */
public class TlwBoot extends ContentProvider {

    @Override
    public boolean onCreate() {
        try {
            TlwCore.install(getContext());
        } catch (Throwable t) {
            Log.e(TlwCore.TAG, "boot failed", t);
        }
        return true;
    }

    @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
    @Override public String getType(Uri u) { return null; }
    @Override public Uri insert(Uri u, ContentValues v) { return null; }
    @Override public int delete(Uri u, String s, String[] a) { return 0; }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }
}
