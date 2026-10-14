package com.goldmind.app;

import android.content.Context;

import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/**
 * UHF RFID on Urovo handhelds (DT50P, sold also as Tagway THS 3.0) through Urovo's
 * URFIDLibrary (com.ubx.usdk). Like the Chainway SDK, the .aar is fetched at build
 * time (build-apk.yml, from github.com/urovosamples/RFIDSDKSample) and used by
 * reflection, so the app builds and runs without it.
 *
 * API used (URFIDLibrary v2.5.0718): RFIDSDKManager.getInstance().init(ctx, InitListener),
 * getRfidManager(): registerCallback(IRfidCallback{onInventoryTag(epc, data, rssi), onInventoryTagEnd()}),
 * startInventory(), stopInventory(), inventorySingle(), setOutputPower(dBm 0..30),
 * writeTagEpc(targetEpc, password, newEpc) — all int results, 0 = ok.
 */
final class UrovoUhf {
    interface TagSink { void onTag(String epc, int rssi); }

    private Object sdk, rm;           // RFIDSDKManager, RfidManager
    private boolean failed;           // tried once this launch and there is no Urovo reader: don't wait again
    private Class<?> rmClass;
    private volatile TagSink sink;    // continuous reading
    private volatile AtomicReference<String> single; // one-shot read
    private volatile CountDownLatch singleDone;

    static String clean(Object e) { return e == null ? null : e.toString().replaceAll("[^0-9A-Fa-f]", "").toUpperCase(); }

    synchronized boolean open(Context ctx) {
        if (rm != null) return true;
        if (failed) return false;
        try {
            Class<?> sdkClass = Class.forName("com.ubx.usdk.RFIDSDKManager");
            sdk = sdkClass.getMethod("getInstance").invoke(null);
            Object m = sdkClass.getMethod("getRfidManager").invoke(sdk);
            if (m == null || !connected(m)) {
                Class<?> initL = Class.forName("com.ubx.usdk.listener.InitListener");
                final CountDownLatch done = new CountDownLatch(1);
                final boolean[] ok = { false };
                Object listener = Proxy.newProxyInstance(initL.getClassLoader(), new Class<?>[]{ initL }, (p, method, args) -> {
                    if ("onStatus".equals(method.getName())) { ok[0] = args != null && Boolean.TRUE.equals(args[0]); done.countDown(); }
                    return null;
                });
                sdkClass.getMethod("init", Context.class, initL).invoke(sdk, ctx.getApplicationContext(), listener);
                if (!done.await(5, TimeUnit.SECONDS) || !ok[0]) { failed = true; return false; }
                m = sdkClass.getMethod("getRfidManager").invoke(sdk);
                if (m == null) { failed = true; return false; }
            }
            rm = m; rmClass = m.getClass();
            Class<?> cbI = Class.forName("com.ubx.usdk.rfid.aidl.IRfidCallback");
            Object cb = Proxy.newProxyInstance(cbI.getClassLoader(), new Class<?>[]{ cbI }, (p, method, args) -> {
                if ("onInventoryTag".equals(method.getName()) && args != null) {
                    String epc = clean(args[0]);
                    int rssi = args.length > 2 && args[2] instanceof Integer ? (Integer) args[2] : 0;
                    if (epc != null && !epc.isEmpty()) {
                        AtomicReference<String> s = single;
                        CountDownLatch d = singleDone;
                        if (s != null) { s.compareAndSet(null, epc); if (d != null) d.countDown(); }
                        TagSink k = sink;
                        if (k != null) k.onTag(epc, rssi);
                    }
                }
                // onInventoryTagEnd is ignored on purpose: a late "end" from the previous read could
                // otherwise finish the next read before its tag arrives; readOne() waits for a tag or times out.
                return null;
            });
            rmClass.getMethod("registerCallback", cbI).invoke(rm, cb);
            return true;
        } catch (Throwable e) { rm = null; failed = true; return false; } // not a Urovo device, or SDK not bundled
    }

    private static boolean connected(Object m) {
        try { return Boolean.TRUE.equals(m.getClass().getMethod("isConnected").invoke(m)); } catch (Throwable e) { return false; }
    }

    private int callInt(String name, Class<?>[] types, Object... args) throws Exception {
        Method m = rmClass.getMethod(name, types);
        Object r = m.invoke(rm, args);
        return r instanceof Integer ? (Integer) r : -1;
    }

    void power(int dbm) throws Exception {
        if (dbm > 0) callInt("setOutputPower", new Class<?>[]{ int.class }, Math.min(30, dbm));
    }

    /** Nearest tag, or null. */
    String readOne(int dbm) throws Exception {
        power(dbm);
        AtomicReference<String> got = new AtomicReference<>();
        singleDone = new CountDownLatch(1);
        single = got;
        try {
            if (callInt("inventorySingle", new Class<?>[]{}) != 0) return null;
            singleDone.await(1500, TimeUnit.MILLISECONDS);
            return got.get();
        } finally { single = null; singleDone = null; }
    }

    /** Writes newEpc on the tag whose EPC is oldEpc (password 0). true on success. */
    boolean writeEpc(String oldEpc, String newEpc) throws Exception {
        return callInt("writeTagEpc", new Class<?>[]{ String.class, String.class, String.class }, oldEpc, "00000000", newEpc) == 0;
    }

    boolean start(int dbm, TagSink s) throws Exception {
        power(dbm);
        sink = s;
        if (callInt("startInventory", new Class<?>[]{}) != 0) { sink = null; return false; }
        return true;
    }

    void stop() {
        sink = null;
        try { if (rm != null) callInt("stopInventory", new Class<?>[]{}); } catch (Throwable ignored) { }
    }

    void close() {
        stop();
        try { if (sdk != null) sdk.getClass().getMethod("release").invoke(sdk); } catch (Throwable ignored) { }
        rm = null; sdk = null;
    }
}
