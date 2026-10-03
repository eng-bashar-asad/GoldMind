package com.goldmind.app;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.media.AudioManager;
import android.media.ToneGenerator;
import android.net.Uri;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Chip programmer for handhelds whose system WebView is too old to run the
 * GoldMind pages (Chainway C72 on Android 6 ships WebView 44 and it cannot be
 * updated). MainActivity opens this screen instead of the web app there.
 *
 * Desk-encoder mode: the handheld is linked to a shop with the key from the
 * company settings page, then waits for "program chip" jobs that the piece page
 * queues from any computer/phone (rfid_write_jobs, RPCs rfid_device_*), writes
 * the label lying on its back and reports back; the server saves rfid_epc.
 *
 * Manual mode: type a barcode and write it here. Same EPC as GMZebra.buildEpcHex
 * (first 8 hex of the shop id + barcode padded to 16); the count page matches
 * that number to the barcode, so nothing needs saving.
 */
public class RfidWriterActivity extends Activity {
    private static final String SITE = "https://eng-bashar-asad.github.io/GoldMind/";
    private EditText keyField, barcodeField;
    private TextView linkInfo, status;
    private Button writeBtn;
    private SharedPreferences prefs;
    private Object reader;
    private Class<?> rc;
    private volatile boolean busy = false, polling = false;
    private String apiUrl, apiKey;
    private ToneGenerator tone;
    private Thread poller;

    static String buildEpc(String shop, String barcode) {
        String s = shop.replaceAll("[^0-9A-Fa-f]", "");
        if (s.length() > 8) s = s.substring(0, 8);
        while (s.length() < 8) s = "0" + s;
        String b = barcode.trim();
        if (!b.matches("[0-9]{1,16}")) return null; // GoldMind piece barcodes are digits
        while (b.length() < 16) b = "0" + b;
        return (s + b).toUpperCase();
    }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        // ponytail: one-line self-check, same as the JS assert in zebra-rfid.js
        if (!"A15F496A0000000000000805".equals(buildEpc("a15f496a-a4b5", "000805"))) throw new AssertionError("buildEpc");
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        prefs = getSharedPreferences("gm_rfid", MODE_PRIVATE);
        readApiConfig();
        try { tone = new ToneGenerator(AudioManager.STREAM_NOTIFICATION, 90); } catch (Throwable ignored) { }

        int pad = dp(16);
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        box.setPadding(pad, pad, pad, pad);

        TextView title = text("جهاز برمجة الشرائح", 22, true);
        TextView note = text("ضع الجهاز على الطاولة واترك هذه الشاشة مفتوحة. عند الضغط على زر الشريحة في صفحة القطعة "
                + "(من الكمبيوتر أو الموبايل) يبرمج الجهاز الملصقة الموضوعة على ظهره.", 14, false);
        note.setTextColor(Color.DKGRAY);

        keyField = field("رمز الربط من إعدادات الشركة", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS);
        keyField.setText(prefs.getString("key", ""));
        Button linkBtn = new Button(this);
        linkBtn.setText("ربط الجهاز");
        linkBtn.setOnClickListener(v -> link());
        linkInfo = text("", 14, true);

        status = text("", 18, true);
        status.setPadding(0, dp(16), 0, dp(16));
        status.setGravity(Gravity.CENTER);

        barcodeField = field("باركود القطعة", InputType.TYPE_CLASS_NUMBER);
        barcodeField.setImeOptions(EditorInfo.IME_ACTION_DONE);
        barcodeField.setOnEditorActionListener((v, id, e) -> { writeManual(); return true; });
        writeBtn = new Button(this);
        writeBtn.setText("برمجة يدوية");
        writeBtn.setOnClickListener(v -> writeManual());

        Button chrome = new Button(this);
        chrome.setText("فتح GoldMind في المتصفح");
        chrome.setOnClickListener(v -> {
            try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(SITE))); } catch (Exception ignored) { }
        });

        for (View v : new View[]{title, note, label("رمز الربط"), keyField, linkBtn, linkInfo, status,
                label("برمجة يدوية بالباركود"), barcodeField, writeBtn, chrome}) box.addView(v);
        ScrollView sv = new ScrollView(this);
        sv.addView(box);
        setContentView(sv);
        showLink();
    }

    // --- shop link ---------------------------------------------------------

    /** URL + publishable key from the bundled supabase-config.js (public values). */
    private void readApiConfig() {
        try (InputStream in = getAssets().open("public/supabase-config.js")) {
            String js = readAll(in);
            Matcher u = Pattern.compile("GOLDMIND_SUPABASE_URL\\s*=\\s*'([^']+)'").matcher(js);
            Matcher k = Pattern.compile("GOLDMIND_SUPABASE_KEY\\s*=\\s*'([^']+)'").matcher(js);
            if (u.find()) apiUrl = u.group(1);
            if (k.find()) apiKey = k.group(1);
        } catch (Exception ignored) { }
    }

    private void showLink() {
        String store = prefs.getString("store", "");
        if (store.isEmpty()) {
            linkInfo.setText("الجهاز غير مربوط بأي محل بعد");
            linkInfo.setTextColor(Color.rgb(180, 30, 30));
            say("أدخل رمز الربط ثم اضغط «ربط الجهاز»", false);
        } else {
            linkInfo.setText("مربوط بمحل: " + store);
            linkInfo.setTextColor(Color.rgb(0, 120, 60));
            idle();
        }
    }

    private void idle() { say("بانتظار أمر برمجة…", true); }

    private void link() {
        final String key = keyField.getText().toString().trim().toUpperCase();
        if (key.length() < 12) { say("رمز الربط 12 خانة", false); return; }
        say("جارٍ الربط…", true);
        new Thread(() -> {
            try {
                String r = rpc("rfid_device_hello", new JSONObject().put("p_key", key));
                if (r == null || r.equals("null")) throw new Exception("رمز الربط غير صحيح");
                JSONObject o = new JSONObject(r);
                prefs.edit().putString("key", key).putString("store", o.getString("store")).putString("prefix", o.getString("prefix")).apply();
                runOnUiThread(this::showLink);
            } catch (Exception e) {
                runOnUiThread(() -> say(msg(e), false));
            }
        }).start();
    }

    // --- desk-encoder loop -------------------------------------------------

    @Override
    protected void onResume() {
        super.onResume();
        polling = true;
        if (poller == null || !poller.isAlive()) { poller = new Thread(this::pollLoop); poller.start(); }
    }

    @Override
    protected void onPause() {
        polling = false;
        super.onPause();
    }

    private void pollLoop() {
        while (polling) {
            String key = prefs.getString("key", "");
            if (!key.isEmpty() && !prefs.getString("store", "").isEmpty() && !busy) {
                try {
                    String r = rpc("rfid_device_next", new JSONObject().put("p_key", key));
                    if (r != null && !r.equals("null")) runJob(key, new JSONObject(r));
                } catch (Exception e) {
                    final String m = "لا اتصال بالخادم: " + msg(e);
                    runOnUiThread(() -> say(m, false));
                }
            }
            try { Thread.sleep(1500); } catch (InterruptedException e) { return; }
        }
    }

    /** Runs on the poll thread: keep trying for 40 s until a label is on the back. */
    private void runJob(String key, JSONObject job) throws Exception {
        busy = true;
        final String barcode = job.getString("barcode");
        runOnUiThread(() -> say("ضع ملصقة القطعة " + barcode + " على ظهر الجهاز…", true));
        String err = "لم تُقرأ أي شريحة";
        long until = System.currentTimeMillis() + 40000;
        while (polling && System.currentTimeMillis() < until) {
            err = doWrite(job.getString("epc"));
            if (err == null || !err.startsWith("لم تُقرأ")) break;
            Thread.sleep(700);
        }
        boolean ok = err == null;
        try {
            rpc("rfid_device_done", new JSONObject().put("p_key", key).put("p_job", job.getString("id")).put("p_ok", ok).put("p_msg", ok ? "" : err));
        } catch (Exception e) {
            err = "كُتبت الشريحة لكن تعذّر إبلاغ البرنامج: " + msg(e);
        }
        beep(ok);
        final String m = ok ? "✓ تمت برمجة شريحة القطعة " + barcode : err;
        runOnUiThread(() -> say(m, ok));
        Thread.sleep(2500);
        busy = false;
        runOnUiThread(this::idle);
    }

    // --- manual ------------------------------------------------------------

    private void writeManual() {
        if (busy) return;
        final String code = barcodeField.getText().toString().trim();
        String prefix = prefs.getString("prefix", "");
        if (prefix.isEmpty()) { say("اربط الجهاز بالمحل أولاً", false); return; }
        final String epc = buildEpc(prefix, code);
        if (epc == null) { say("أدخل باركود القطعة (أرقام فقط)", false); return; }
        busy = true;
        writeBtn.setEnabled(false);
        say("جارٍ البرمجة…", true);
        new Thread(() -> {
            String r = doWrite(epc);
            boolean ok = r == null;
            beep(ok);
            final String m = ok ? "✓ تمت برمجة شريحة القطعة " + code : r;
            runOnUiThread(() -> {
                busy = false;
                writeBtn.setEnabled(true);
                say(m, ok);
                if (ok) barcodeField.setText("");
                barcodeField.requestFocus();
            });
        }).start();
    }

    // --- reader ------------------------------------------------------------

    /** null = done, otherwise the Arabic error. */
    private synchronized String doWrite(String epc) {
        try {
            if (reader == null) {
                rc = Class.forName("com.rscja.deviceapi.RFIDWithUHFUART");
                Object r = rc.getMethod("getInstance").invoke(null);
                Boolean ok = (Boolean) rc.getMethod("init", android.content.Context.class).invoke(r, this);
                if (ok == null || !ok) return "تعذّر تشغيل قارئ RFID — أوقف «Enable Scanner» في Keyboard Emulator ثم أعد المحاولة";
                reader = r;
            }
            // low power so only the label lying on the device is reached
            rc.getMethod("setPower", int.class).invoke(reader, 5);
            if (epcOf(rc.getMethod("inventorySingleTag").invoke(reader)) == null) return "لم تُقرأ أي شريحة — ضع الملصقة على ظهر الجهاز";
            Boolean ok = (Boolean) rc.getMethod("writeDataToEpc", String.class, String.class).invoke(reader, "00000000", epc);
            if (ok == null || !ok) return "فشلت الكتابة على الشريحة — أعد المحاولة";
            String now = epcOf(rc.getMethod("inventorySingleTag").invoke(reader));
            if (now == null || !now.startsWith(epc)) return "كُتبت الشريحة لكن تعذّر التحقق منها — أعد المحاولة";
            return null;
        } catch (ClassNotFoundException e) {
            return "لا يوجد قارئ RFID في هذا الجهاز";
        } catch (Throwable e) {
            return "تعذّرت الكتابة: " + e;
        }
    }

    private static String epcOf(Object tag) throws Exception {
        if (tag == null) return null;
        Object e = tag.getClass().getMethod("getEPC").invoke(tag);
        String s = e == null ? "" : e.toString().replaceAll("[^0-9A-Fa-f]", "").toUpperCase();
        return s.isEmpty() ? null : s;
    }

    // --- http ----------------------------------------------------------------

    private String rpc(String fn, JSONObject body) throws Exception {
        if (apiUrl == null || apiKey == null) throw new Exception("إعدادات الخادم غير موجودة في التطبيق");
        HttpURLConnection c = (HttpURLConnection) new URL(apiUrl + "/rest/v1/rpc/" + fn).openConnection();
        c.setConnectTimeout(10000);
        c.setReadTimeout(15000);
        c.setRequestMethod("POST");
        c.setDoOutput(true);
        c.setRequestProperty("apikey", apiKey);
        c.setRequestProperty("Content-Type", "application/json");
        try (OutputStream o = c.getOutputStream()) { o.write(body.toString().getBytes("UTF-8")); }
        int code = c.getResponseCode();
        InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
        String res = in == null ? "" : readAll(in);
        c.disconnect();
        if (code >= 400) {
            String m = res;
            try { m = new JSONObject(res).optString("message", res); } catch (Exception ignored) { }
            throw new Exception(m);
        }
        return res.trim();
    }

    private static String readAll(InputStream in) throws Exception {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        int n;
        while ((n = in.read(buf)) > 0) b.write(buf, 0, n);
        return b.toString("UTF-8");
    }

    private static String msg(Exception e) { return e.getMessage() == null ? e.toString() : e.getMessage(); }

    // --- ui ----------------------------------------------------------------

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (MainActivity.isTrigger(event.getKeyCode())) {
            if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) writeManual();
            return true;
        }
        return super.dispatchKeyEvent(event);
    }

    @Override
    protected void onDestroy() {
        polling = false;
        try { if (reader != null) rc.getMethod("free").invoke(reader); } catch (Throwable ignored) { }
        reader = null;
        if (tone != null) tone.release();
        super.onDestroy();
    }

    private void beep(boolean ok) {
        try { if (tone != null) tone.startTone(ok ? ToneGenerator.TONE_PROP_ACK : ToneGenerator.TONE_PROP_NACK, 250); } catch (Throwable ignored) { }
    }

    private void say(String s, boolean good) {
        status.setText(s);
        status.setTextColor(good ? Color.rgb(0, 120, 60) : Color.rgb(180, 30, 30));
    }

    private int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    private TextView text(String s, int sp, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(Color.BLACK);
        t.setGravity(Gravity.START);
        if (bold) t.setTypeface(null, android.graphics.Typeface.BOLD);
        t.setPadding(0, 0, 0, dp(10));
        return t;
    }

    private TextView label(String s) {
        TextView t = text(s, 14, true);
        t.setPadding(0, dp(8), 0, 0);
        return t;
    }

    private EditText field(String hint, int type) {
        EditText e = new EditText(this);
        e.setHint(hint);
        e.setInputType(type);
        e.setSingleLine(true);
        e.setTextSize(20);
        return e;
    }
}
