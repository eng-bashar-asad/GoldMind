package com.goldmind.app;

import android.content.Context;
import android.print.PrintDocumentAdapter;
import android.print.PrintManager;
import android.webkit.WebView;

import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

/**
 * window.print() does nothing inside an Android WebView. This plugin hands the
 * current page to Android's own print service (the same dialog Chrome uses:
 * pick a printer, "Save as PDF", paper size...). The page's @media print CSS is
 * applied, so invoices and labels print exactly like in the browser.
 * JS side: supabase-config.js replaces window.print() with GMPrint.print().
 */
@CapacitorPlugin(name = "GMPrint")
public class GMPrintPlugin extends Plugin {

    @PluginMethod
    public void print(PluginCall call) {
        final String name = call.getString("name", "GoldMind");
        getActivity().runOnUiThread(() -> {
            try {
                WebView webView = getBridge().getWebView();
                PrintManager printManager = (PrintManager) getActivity().getSystemService(Context.PRINT_SERVICE);
                PrintDocumentAdapter adapter = webView.createPrintDocumentAdapter(name);
                printManager.print(name, adapter, null);
                call.resolve();
            } catch (Exception e) {
                call.reject("print failed: " + e.getMessage());
            }
        });
    }
}
