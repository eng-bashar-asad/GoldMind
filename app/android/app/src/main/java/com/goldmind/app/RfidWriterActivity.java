package com.goldmind.app;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * Chip programmer for handhelds whose system WebView is too old to run the
 * GoldMind pages (Chainway C72 on Android 6 ships WebView 44 and it cannot be
 * updated). MainActivity opens this screen instead of the web app there.
 *
 * It writes the same EPC as GMZebra.buildEpcHex (zebra-rfid.js): first 8 hex of
 * the shop id + the barcode digits padded to 16. The count page matches that
 * number to the barcode itself, so nothing has to be saved to the database here.
 *
 * ponytail: the shop code (first 8 hex of the store id) is typed once by hand;
 * upgrade path = sign-in here, if more shops end up on such devices.
 */
public class RfidWriterActivity extends Activity {
    private static final String SITE = "https://eng-bashar-asad.github.io/GoldMind/";
    private EditText shopField, barcodeField;
    private TextView status;
    private Button writeBtn;
    private Object reader;
    private Class<?> rc;
    private volatile boolean busy = false;

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

        SharedPreferences prefs = getSharedPreferences("gm_rfid", MODE_PRIVATE);
        int pad = dp(16);
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        box.setPadding(pad, pad, pad, pad);

        TextView title = text("برمجة شرائح RFID", 22, true);
        TextView note = text("متصفح النظام في هذا الجهاز قديم ولا يشغّل صفحات GoldMind، لذلك يعمل التطبيق هنا لبرمجة الشرائح فقط. "
                + "للجرد وباقي البرنامج افتح GoldMind من متصفح Chrome.", 14, false);
        note.setTextColor(Color.DKGRAY);

        shopField = field("رمز المحل (8 خانات)", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS);
        shopField.setText(prefs.getString("shop", ""));
        barcodeField = field("باركود القطعة", InputType.TYPE_CLASS_NUMBER);
        barcodeField.setImeOptions(EditorInfo.IME_ACTION_DONE);
        // a barcode scanner in keyboard mode ends with Enter -> write straight away
        barcodeField.setOnEditorActionListener((v, id, e) -> { write(); return true; });

        writeBtn = new Button(this);
        writeBtn.setText("برمجة الشريحة");
        writeBtn.setTextSize(18);
        writeBtn.setOnClickListener(v -> write());

        status = text("قرّب ملصقة القطعة من ظهر الجهاز وأبعد الملصقات الأخرى، ثم اضغط «برمجة الشريحة» أو زر المسح.", 16, false);
        status.setPadding(0, dp(12), 0, dp(12));

        Button chrome = new Button(this);
        chrome.setText("فتح GoldMind في المتصفح");
        chrome.setOnClickListener(v -> {
            try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(SITE))); } catch (Exception ignored) { }
        });

        for (View v : new View[]{title, note, label("رمز المحل"), shopField, label("باركود القطعة"), barcodeField, writeBtn, status, chrome}) box.addView(v);
        ScrollView sv = new ScrollView(this);
        sv.addView(box);
        setContentView(sv);
        if (shopField.getText().length() > 0) barcodeField.requestFocus();
    }

    private void write() {
        if (busy) return;
        final String shop = shopField.getText().toString().trim();
        final String code = barcodeField.getText().toString().trim();
        if (shop.replaceAll("[^0-9A-Fa-f]", "").length() != 8) { say("أدخل رمز المحل (8 خانات)", false); return; }
        final String epc = buildEpc(shop, code);
        if (epc == null) { say("أدخل باركود القطعة (أرقام فقط)", false); return; }
        getSharedPreferences("gm_rfid", MODE_PRIVATE).edit().putString("shop", shop.toUpperCase()).apply();
        busy = true;
        writeBtn.setEnabled(false);
        say("جارٍ البرمجة…", true);
        new Thread(() -> {
            final String msg; final boolean ok;
            String r = doWrite(epc);
            ok = r == null;
            msg = ok ? "✓ تمت برمجة شريحة القطعة " + code + "\n" + epc : r;
            runOnUiThread(() -> {
                busy = false;
                writeBtn.setEnabled(true);
                say(msg, ok);
                if (ok) barcodeField.setText("");
                barcodeField.requestFocus();
            });
        }).start();
    }

    /** null = done, otherwise the Arabic error. */
    private String doWrite(String epc) {
        try {
            if (reader == null) {
                rc = Class.forName("com.rscja.deviceapi.RFIDWithUHFUART");
                Object r = rc.getMethod("getInstance").invoke(null);
                Boolean ok = (Boolean) rc.getMethod("init", android.content.Context.class).invoke(r, this);
                if (ok == null || !ok) return "تعذّر تشغيل قارئ RFID — أوقف «Enable Scanner» في Keyboard Emulator ثم أعد المحاولة";
                reader = r;
            }
            // low power so only the label held against the device is reached
            rc.getMethod("setPower", int.class).invoke(reader, 5);
            if (epcOf(rc.getMethod("inventorySingleTag").invoke(reader)) == null) return "لم تُقرأ أي شريحة — قرّب الملصقة من ظهر الجهاز";
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

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (MainActivity.isTrigger(event.getKeyCode())) {
            if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) write();
            return true;
        }
        return super.dispatchKeyEvent(event);
    }

    @Override
    protected void onDestroy() {
        try { if (reader != null) rc.getMethod("free").invoke(reader); } catch (Throwable ignored) { }
        reader = null;
        super.onDestroy();
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
