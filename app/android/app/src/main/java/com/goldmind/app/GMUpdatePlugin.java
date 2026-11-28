package com.goldmind.app;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.core.content.FileProvider;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * Update the app from inside it (Settings › «تنزيل آخر إصدار», and the update bar): downloads the newest
 * GoldMind.apk into the app's own cache, then opens Android's installer on it. No browser, no Downloads
 * folder. Only GoldMind's own release address is accepted. JS side: gmAppUpdateInstall() in theme.js.
 * The first time, Android asks to allow "install unknown apps" for GoldMind; we open that screen and the
 * user taps the button again after allowing it.
 */
@CapacitorPlugin(name = "GMUpdate")
public class GMUpdatePlugin extends Plugin {
    private static final String ALLOWED = "https://github.com/eng-bashar-asad/GoldMind/releases/download/";

    @PluginMethod
    public void install(PluginCall call) {
        final String url = call.getString("url", "");
        if (!url.startsWith(ALLOWED)) { call.reject("not a GoldMind release address"); return; }
        final Context ctx = getContext();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !ctx.getPackageManager().canRequestPackageInstalls()) {
            Intent allow = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + ctx.getPackageName()));
            allow.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            ctx.startActivity(allow);
            call.reject("allow installing apps first", "NEED_PERMISSION");
            return;
        }
        new Thread(() -> {
            File dir = new File(ctx.getCacheDir(), "updates");
            File part = new File(dir, "GoldMind.apk.part"), apk = new File(dir, "GoldMind.apk");
            HttpURLConnection c = null;
            try {
                if (!dir.exists() && !dir.mkdirs()) throw new Exception("no cache folder");
                c = (HttpURLConnection) new URL(url).openConnection(); // follows GitHub's https redirect to its file host
                c.setConnectTimeout(20000);
                c.setReadTimeout(30000);
                if (c.getResponseCode() != 200) throw new Exception("HTTP " + c.getResponseCode());
                long total = c.getContentLengthLong(), done = 0;
                int lastPct = -1;
                try (InputStream in = c.getInputStream(); OutputStream out = new FileOutputStream(part)) {
                    byte[] buf = new byte[64 * 1024];
                    for (int n; (n = in.read(buf)) > 0; ) {
                        out.write(buf, 0, n);
                        done += n;
                        int pct = total > 0 ? (int) (done * 100 / total) : -1;
                        if (pct != lastPct) {
                            lastPct = pct;
                            JSObject p = new JSObject();
                            p.put("percent", pct);
                            p.put("bytes", done);
                            notifyListeners("progress", p);
                        }
                    }
                }
                // a cut-off download must never reach the installer
                if (done == 0 || (total > 0 && done != total)) throw new Exception("incomplete download");
                if (apk.exists() && !apk.delete()) throw new Exception("old file locked");
                if (!part.renameTo(apk)) throw new Exception("could not save the file");
                Uri uri = FileProvider.getUriForFile(ctx, ctx.getPackageName() + ".fileprovider", apk);
                Intent install = new Intent(Intent.ACTION_VIEW);
                install.setDataAndType(uri, "application/vnd.android.package-archive");
                install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                ctx.startActivity(install);
                call.resolve();
            } catch (Exception e) {
                //noinspection ResultOfMethodCallIgnored
                part.delete();
                call.reject("download failed: " + e.getMessage());
            } finally {
                if (c != null) c.disconnect();
            }
        }).start();
    }
}
