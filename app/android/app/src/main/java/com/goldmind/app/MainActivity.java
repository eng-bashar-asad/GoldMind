package com.goldmind.app;

import android.os.Bundle;
import android.view.KeyEvent;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    // Scan trigger / side keys on Chainway handhelds (C72: 139 on the pistol grip, 280/293/294 side keys)
    private static boolean isTrigger(int code) {
        return code == 139 || code == 280 || code == 291 || code == 293 || code == 294 || code == 311;
    }

    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(GMPrintPlugin.class); // printing from the app (see GMPrintPlugin)
        registerPlugin(GMUhfPlugin.class);   // RFID on Chainway handhelds (see GMUhfPlugin)
        super.onCreate(savedInstanceState);
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
