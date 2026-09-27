package com.goldmind.app;

import android.os.Bundle;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(GMPrintPlugin.class); // printing from the app (see GMPrintPlugin)
        super.onCreate(savedInstanceState);
    }
}
