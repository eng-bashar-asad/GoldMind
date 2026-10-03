package com.goldmind.app;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.lang.reflect.Method;

/**
 * UHF RFID on Chainway handhelds (C72 and similar) through Chainway's DeviceAPI
 * (com.rscja.deviceapi.RFIDWithUHFUART). The SDK .aar is downloaded from
 * chainway.net at build time (see build-apk.yml) and is never in the repo, so it
 * is used by reflection: the app still builds and runs without it, and on any
 * other phone available() simply returns false.
 *
 * JS: Capacitor.Plugins.GMUhf — see gm-uhf.js.
 *   available() -> {available}
 *   readOne({power}) -> {epc}            nearest tag
 *   writeEpc({epc, power}) -> {oldEpc, epc}  writes the EPC of the single nearest tag, then reads it back
 *   start({power}) / stop()              continuous reading, each tag -> "tag" event {epc, rssi}
 *   hardware trigger -> "trigger" event {down}
 */
@CapacitorPlugin(name = "GMUhf")
public class GMUhfPlugin extends Plugin {
    private static GMUhfPlugin instance;
    private Object reader;          // RFIDWithUHFUART
    private Class<?> readerClass;
    private volatile boolean running = false;
    private Thread loop;

    @Override
    public void load() { instance = this; }

    /** Called by MainActivity for the scan trigger keys. */
    static boolean onTrigger(boolean down) {
        if (instance == null || !instance.hasListeners("trigger")) return false;
        JSObject o = new JSObject();
        o.put("down", down);
        instance.notifyListeners("trigger", o);
        return true;
    }

    private synchronized boolean open() {
        if (reader != null) return true;
        try {
            readerClass = Class.forName("com.rscja.deviceapi.RFIDWithUHFUART");
            Object r = readerClass.getMethod("getInstance").invoke(null);
            Boolean ok = (Boolean) readerClass.getMethod("init", android.content.Context.class).invoke(r, getContext());
            if (ok != null && ok) { reader = r; return true; }
        } catch (Throwable ignored) { /* not a Chainway device, or SDK not bundled */ }
        return false;
    }

    private Object call(String name, Class<?>[] types, Object... args) throws Exception {
        Method m = readerClass.getMethod(name, types);
        return m.invoke(reader, args);
    }

    private void power(PluginCall c, int def) throws Exception {
        int p = c.getInt("power", def);
        if (p > 0) call("setPower", new Class<?>[]{int.class}, p);
    }

    private static String epcOf(Object tag) throws Exception {
        if (tag == null) return null;
        Object e = tag.getClass().getMethod("getEPC").invoke(tag);
        return e == null ? null : e.toString().replaceAll("[^0-9A-Fa-f]", "").toUpperCase();
    }

    @PluginMethod
    public void available(PluginCall c) {
        JSObject o = new JSObject();
        o.put("available", open());
        c.resolve(o);
    }

    @PluginMethod
    public void readOne(PluginCall c) {
        if (!open()) { c.reject("لا يوجد قارئ RFID في هذا الجهاز"); return; }
        try {
            power(c, 10);
            String epc = epcOf(call("inventorySingleTag", new Class<?>[]{}));
            if (epc == null || epc.isEmpty()) { c.reject("لم تُقرأ أي شريحة — قرّب الملصقة من الجهاز"); return; }
            JSObject o = new JSObject(); o.put("epc", epc); c.resolve(o);
        } catch (Throwable e) { c.reject("تعذّرت القراءة: " + e.getMessage()); }
    }

    @PluginMethod
    public void writeEpc(PluginCall c) {
        String epc = c.getString("epc", "").replaceAll("[^0-9A-Fa-f]", "").toUpperCase();
        if (epc.length() == 0 || epc.length() % 4 != 0) { c.reject("رقم الشريحة غير صالح"); return; }
        if (!open()) { c.reject("لا يوجد قارئ RFID في هذا الجهاز"); return; }
        if (running) { c.reject("أوقف القراءة المستمرة أولاً"); return; }
        try {
            // low power so only the label held against the device is reached
            power(c, 5);
            String old = epcOf(call("inventorySingleTag", new Class<?>[]{}));
            if (old == null) { c.reject("لم تُقرأ أي شريحة — قرّب الملصقة من ظهر الجهاز"); return; }
            Boolean ok = (Boolean) call("writeDataToEpc", new Class<?>[]{String.class, String.class}, "00000000", epc);
            if (ok == null || !ok) { c.reject("فشلت الكتابة على الشريحة — أعد المحاولة"); return; }
            String now = epcOf(call("inventorySingleTag", new Class<?>[]{}));
            if (now == null || !now.startsWith(epc)) { c.reject("كُتبت الشريحة لكن تعذّر التحقق منها — أعد المحاولة"); return; }
            JSObject o = new JSObject(); o.put("oldEpc", old); o.put("epc", now); c.resolve(o);
        } catch (Throwable e) { c.reject("تعذّرت الكتابة: " + e.getMessage()); }
    }

    @PluginMethod
    public void start(PluginCall c) {
        if (!open()) { c.reject("لا يوجد قارئ RFID في هذا الجهاز"); return; }
        if (running) { c.resolve(); return; }
        try {
            power(c, 0);
            Boolean ok = (Boolean) call("startInventoryTag", new Class<?>[]{});
            if (ok == null || !ok) { c.reject("تعذّر بدء القراءة"); return; }
            running = true;
            loop = new Thread(() -> {
                while (running) {
                    try {
                        Object tag = call("readTagFromBuffer", new Class<?>[]{});
                        if (tag == null) { Thread.sleep(5); continue; }
                        JSObject o = new JSObject();
                        o.put("epc", epcOf(tag));
                        Object rssi = tag.getClass().getMethod("getRssi").invoke(tag);
                        o.put("rssi", rssi == null ? "" : rssi.toString());
                        notifyListeners("tag", o);
                    } catch (Throwable e) { running = false; }
                }
            });
            loop.start();
            c.resolve();
        } catch (Throwable e) { c.reject("تعذّر بدء القراءة: " + e.getMessage()); }
    }

    @PluginMethod
    public void stop(PluginCall c) {
        stopReading();
        c.resolve();
    }

    private void stopReading() {
        running = false;
        try { if (reader != null) call("stopInventory", new Class<?>[]{}); } catch (Throwable ignored) { }
    }

    @Override
    protected void handleOnDestroy() {
        stopReading();
        try { if (reader != null) call("free", new Class<?>[]{}); } catch (Throwable ignored) { }
        reader = null;
        instance = null;
    }
}
