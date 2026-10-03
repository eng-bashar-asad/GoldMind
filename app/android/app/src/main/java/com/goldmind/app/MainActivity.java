package com.goldmind.app;

import android.os.Bundle;
import android.view.KeyEvent;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    // Scan trigger / side keys on Chainway handhelds (C72: 139 on the pistol grip, 280/293/294 side keys)
    static boolean isTrigger(int code) {
        return code == 139 || code == 280 || code == 291 || code == 293 || code == 294 || code == 311;
    }

    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(GMPrintPlugin.class); // printing from the app (see GMPrintPlugin)
        registerPlugin(GMUhfPlugin.class);   // RFID on Chainway handhelds (see GMUhfPlugin)
        super.onCreate(savedInstanceState);
        if (webViewTooOld()) {
            // the pages need a modern WebView; on old handhelds (C72, Android 6,
            // WebView 44 that can't be updated) the app becomes the chip programmer
            startActivity(new android.content.Intent(this, RfidWriterActivity.class));
            finish();
        }
    }

    // Capacitor 6 needs WebView 60+; GoldMind's pages need newer (async, CSS variables...)
    private boolean webViewTooOld() {
        try {
            java.util.regex.Matcher m = java.util.regex.Pattern.compile("Chrome/(\\d+)")
                    .matcher(android.webkit.WebSettings.getDefaultUserAgent(this));
            return m.find() && Integer.parseInt(m.group(1)) < 70;
        } catch (Throwable e) { return false; }
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (isTrigger(event.getKeyCode()) && event.getRepeatCount() == 0
                && (event.getAction() == KeyEvent.ACTION_DOWN || event.getAction() == KeyEvent.ACTION_UP)) {
            if (GMUhfPlugin.onTrigger(event.getAction() == KeyEvent.ACTION_DOWN)) return true;
        }
        return super.dispatchKeyEvent(event);
    }
}
