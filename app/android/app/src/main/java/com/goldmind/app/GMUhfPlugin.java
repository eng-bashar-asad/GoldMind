package com.goldmind.app;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.lang.reflect.Method;

/**
 * UHF RFID on Chainway handhelds (C72 and similar) through Chainway's DeviceAPI,
 * on Urovo handhelds (DT50P / Tagway THS 3.0) through UrovoUhf, and on a Zebra Bluetooth sled
 * (RFD4031, paired with the phone) through ZebraRfd — same JS API for all three.
 * Chainway part:
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
    private final UrovoUhf uro = new UrovoUhf();
    private boolean isUro;
    private RfidSled sled;          // Zebra sled (ZebraRfd, only in builds that bundle the Zebra SDK)

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
        if (uro.open(getContext())) { isUro = true; return true; }
        return openSled();
    }

    // Zebra RFD4031 over Bluetooth: the SDK needs Android 10+, and Android 12+ asks once for "nearby devices".
    private boolean openSled() {
        if (Build.VERSION.SDK_INT < 29) return false;
        try {
            if (sled == null) sled = (RfidSled) Class.forName("com.goldmind.app.ZebraRfd").getDeclaredConstructor().newInstance();
        } catch (Throwable notBundled) { return false; }
        if (Build.VERSION.SDK_INT >= 31 && ContextCompat.checkSelfPermission(getContext(), Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
            if (getActivity() != null) ActivityCompat.requestPermissions(getActivity(), new String[]{Manifest.permission.BLUETOOTH_CONNECT}, 7311);
            return false; // asked; the page's next try connects
        }
        return sled.open(getContext(), GMUhfPlugin::onTrigger);
    }
    private boolean isSled() { return reader == null && !isUro && sled != null; }

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

    // Urovo: same steps as Chainway — read the nearest label at low power, write, read back to verify
    private void writeUrovo(PluginCall c, String epc) throws Exception {
        int p = c.getInt("power", 5);
        String old = uro.readOne(p);
        if (old == null) { c.reject("لم تُقرأ أي شريحة — قرّب الملصقة من ظهر الجهاز"); return; }
        if (!uro.writeEpc(old, epc)) { c.reject("فشلت الكتابة على الشريحة — أعد المحاولة"); return; }
        String now = uro.readOne(p);
        if (now == null || !now.startsWith(epc)) { c.reject("كُتبت الشريحة لكن تعذّر التحقق منها — أعد المحاولة"); return; }
        JSObject o = new JSObject(); o.put("oldEpc", old); o.put("epc", now); c.resolve(o);
    }

    // Zebra sled: same steps — nearest label at low power, write, read back to verify
    private void writeSled(PluginCall c, String epc) throws Exception {
        int p = c.getInt("power", 5);
        String old = sled.readOne(p);
        if (old == null) { c.reject("لم تُقرأ أي شريحة — قرّب الملصقة من مقدمة الجهاز"); return; }
        if (!sled.writeEpc(old, epc, p)) { c.reject("فشلت الكتابة على الشريحة — أعد المحاولة"); return; }
        String now = sled.readOne(p);
        if (now == null || !now.startsWith(epc)) { c.reject("كُتبت الشريحة لكن تعذّر التحقق منها — أعد المحاولة"); return; }
        JSObject o = new JSObject(); o.put("oldEpc", old); o.put("epc", now); c.resolve(o);
    }

    @PluginMethod
    public void available(PluginCall c) {
        JSObject o = new JSObject();
        o.put("available", open());
        c.resolve(o);
    }

    // For the device settings page: which reader this phone has, and the sled's name.
    @PluginMethod
    public void status(PluginCall c) {
        boolean ok = open();
        JSObject o = new JSObject();
        o.put("available", ok);
        o.put("kind", !ok ? "none" : reader != null ? "chainway" : isUro ? "urovo" : "zebra");
        o.put("name", ok && isSled() ? sled.name() : "");
        c.resolve(o);
    }

    @PluginMethod
    public void disconnect(PluginCall c) {
        stopReading();
        if (sled != null) sled.close();
        c.resolve();
    }

    @PluginMethod
    public void readOne(PluginCall c) {
        if (!open()) { c.reject("لا يوجد قارئ RFID في هذا الجهاز"); return; }
        try {
            String epc;
            if (isUro) epc = uro.readOne(c.getInt("power", 10));
            else if (isSled()) epc = sled.readOne(c.getInt("power", 10));
            else { power(c, 10); epc = epcOf(call("inventorySingleTag", new Class<?>[]{})); }
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
            if (isUro) { writeUrovo(c, epc); return; }
            if (isSled()) { writeSled(c, epc); return; }
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
            if (isUro) {
                if (!uro.start(c.getInt("power", 0), (epc, rssi) -> {
                    JSObject o = new JSObject(); o.put("epc", epc); o.put("rssi", String.valueOf(rssi)); notifyListeners("tag", o);
                })) { c.reject("تعذّر بدء القراءة"); return; }
                running = true; c.resolve(); return;
            }
            if (isSled()) {
                if (!sled.start(c.getInt("power", 0), (epc, rssi) -> {
                    JSObject o = new JSObject(); o.put("epc", epc); o.put("rssi", String.valueOf(rssi)); notifyListeners("tag", o);
                })) { c.reject("تعذّر بدء القراءة"); return; }
                running = true; c.resolve(); return;
            }
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
        if (isUro) { uro.stop(); return; }
        if (isSled()) { sled.stop(); return; }
        try { if (reader != null) call("stopInventory", new Class<?>[]{}); } catch (Throwable ignored) { }
    }

    @Override
    protected void handleOnDestroy() {
        stopReading();
        try { if (reader != null) call("free", new Class<?>[]{}); } catch (Throwable ignored) { }
        if (isUro) uro.close();
        if (sled != null) sled.close();
        reader = null;
        instance = null;
    }
}
