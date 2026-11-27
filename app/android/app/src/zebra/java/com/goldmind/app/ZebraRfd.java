package com.goldmind.app;

import android.content.Context;

import com.zebra.rfid.api3.Antennas;
import com.zebra.rfid.api3.ENUM_TRANSPORT;
import com.zebra.rfid.api3.ENUM_TRIGGER_MODE;
import com.zebra.rfid.api3.HANDHELD_TRIGGER_EVENT_TYPE;
import com.zebra.rfid.api3.MEMORY_BANK;
import com.zebra.rfid.api3.ReaderDevice;
import com.zebra.rfid.api3.Readers;
import com.zebra.rfid.api3.RFIDReader;
import com.zebra.rfid.api3.RfidEventsListener;
import com.zebra.rfid.api3.RfidReadEvents;
import com.zebra.rfid.api3.RfidStatusEvents;
import com.zebra.rfid.api3.STATUS_EVENT_TYPE;
import com.zebra.rfid.api3.TagAccess;
import com.zebra.rfid.api3.TagData;

import java.util.ArrayList;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Zebra RFD4031 (and other Zebra RFID sleds) over Bluetooth, with the Zebra RFID SDK
 * (rfidapi3lib .aar, fetched at build time — never in the repo). Compiled only when that
 * .aar is in app/libs (see build.gradle); GMUhfPlugin loads this class by name.
 *
 * The sled must be paired with the phone first (Android Bluetooth settings). The first
 * paired Zebra reader is used.
 *  - writing: low power, so only the label held against the sled is reached
 *  - fast inventory: the sled's highest power
 *  - the sled's trigger -> GMUhfPlugin "trigger" event
 */
final class ZebraRfd implements RfidSled {
    private Readers readers;
    private RFIDReader reader;
    private TriggerSink trigger;
    private volatile TagSink sink;
    private volatile java.util.concurrent.ConcurrentHashMap<String, Integer> single; // readOne: EPC -> best RSSI
    private int[] powerLevels; // dBm x 10, by index
    private String deviceName = "";
    private volatile String lastError = "";

    @Override
    public String lastError() { return lastError; }

    @Override
    public String name() { return reader != null && reader.isConnected() ? deviceName : ""; }

    private static String clean(String e) { return e == null ? null : e.replaceAll("[^0-9A-Fa-f]", "").toUpperCase(); }

    private final RfidEventsListener events = new RfidEventsListener() {
        @Override
        public void eventReadNotify(RfidReadEvents e) {
            RFIDReader r = reader;
            if (r == null) return;
            TagData[] tags = r.Actions.getReadTags(100);
            if (tags == null) return;
            for (TagData t : tags) {
                String epc = clean(t.getTagID());
                if (epc == null || epc.isEmpty()) continue;
                java.util.concurrent.ConcurrentHashMap<String, Integer> one = single;
                if (one != null) { one.merge(epc, (int) t.getPeakRSSI(), Math::max); continue; }
                TagSink s = sink;
                if (s != null) s.onTag(epc, t.getPeakRSSI());
            }
        }

        @Override
        public void eventStatusNotify(RfidStatusEvents e) {
            if (e == null || e.StatusEventData == null) return;
            STATUS_EVENT_TYPE type = e.StatusEventData.getStatusEventType();
            if (type == STATUS_EVENT_TYPE.HANDHELD_TRIGGER_EVENT && trigger != null && e.StatusEventData.HandheldTriggerEventData != null) {
                HANDHELD_TRIGGER_EVENT_TYPE h = e.StatusEventData.HandheldTriggerEventData.getHandheldEvent();
                if (h == HANDHELD_TRIGGER_EVENT_TYPE.HANDHELD_TRIGGER_PRESSED) trigger.onTrigger(true);
                else if (h == HANDHELD_TRIGGER_EVENT_TYPE.HANDHELD_TRIGGER_RELEASED) trigger.onTrigger(false);
            } else if (type == STATUS_EVENT_TYPE.DISCONNECTION_EVENT) {
                close(); // reconnects on the next call
            }
        }
    };

    @Override
    public synchronized boolean open(Context ctx, TriggerSink trigger) {
        this.trigger = trigger;
        if (reader != null && reader.isConnected()) return true;
        try {
            if (readers == null) readers = new Readers(ctx, ENUM_TRANSPORT.BLUETOOTH);
            ArrayList<ReaderDevice> list = readers.GetAvailableRFIDReaderList();
            if (list == null || list.isEmpty()) { lastError = "لا يوجد جهاز زيبرا مقترن بهذا الهاتف (إعدادات البلوتوث)"; return false; }
            ReaderDevice dev = list.get(0);
            RFIDReader r = dev.getRFIDReader();
            deviceName = dev.getName() == null ? "" : dev.getName();
            if (!r.isConnected()) r.connect();
            r.Events.addEventsListener(events);
            r.Events.setHandheldEvent(true);
            r.Events.setTagReadEvent(true);
            r.Events.setAttachTagDataWithReadEvent(false);
            r.Events.setReaderDisconnectEvent(true);
            // the trigger reads RFID (not the barcode scanner); GoldMind decides what a press does.
            // Sleds without a scanner reject this — not a reason to drop the connection.
            try { r.Config.setTriggerMode(ENUM_TRIGGER_MODE.RFID_MODE, true); } catch (Throwable ignored) {}
            powerLevels = r.ReaderCapabilities.getTransmitPowerLevelValues();
            reader = r;
            lastError = "";
            return true;
        } catch (Throwable e) {
            // the SDK's own reason (e.g. reader busy with another host) — shown on the page for support
            String m = e.getMessage();
            try { java.lang.reflect.Method d = e.getClass().getMethod("getVendorMessage"); Object v = d.invoke(e); if (v != null) m = m + " / " + v; } catch (Throwable ignored) {}
            lastError = "تعذّر الاتصال بجهاز الزيبرا: " + e.getClass().getSimpleName() + (m != null ? " — " + m : "");
            close();
            return false;
        }
    }

    /** dBm (5 = labels held against the sled, 0 = maximum) -> the nearest power index of this sled. */
    private void setPower(int dbm) throws Exception {
        if (powerLevels == null || powerLevels.length == 0) return;
        int idx = powerLevels.length - 1;
        if (dbm > 0) {
            int want = dbm * 10, best = 0;
            for (int i = 1; i < powerLevels.length; i++)
                if (Math.abs(powerLevels[i] - want) < Math.abs(powerLevels[best] - want)) best = i;
            idx = best;
        }
        Antennas.AntennaRfConfig cfg = reader.Config.Antennas.getAntennaRfConfig(1);
        if (cfg.getTransmitPowerIndex() != idx) {
            cfg.setTransmitPowerIndex(idx);
            reader.Config.Antennas.setAntennaRfConfig(1, cfg);
        }
    }

    @Override
    public String readOne(int powerDbm) throws Exception {
        if (reader == null) return null;
        setPower(powerDbm);
        // the strongest label wins (the one held against the sled), not merely the first one heard
        java.util.concurrent.ConcurrentHashMap<String, Integer> got = new java.util.concurrent.ConcurrentHashMap<>();
        single = got;
        try {
            reader.Actions.Inventory.perform();
            for (int i = 0; i < 30 && got.isEmpty(); i++) Thread.sleep(50); // up to 1.5 s for a first label
            if (!got.isEmpty()) Thread.sleep(400);                          // then a moment to compare
            reader.Actions.Inventory.stop();
        } finally {
            single = null;
        }
        String best = null; int rssi = Integer.MIN_VALUE;
        for (java.util.Map.Entry<String, Integer> en : got.entrySet()) if (en.getValue() > rssi) { rssi = en.getValue(); best = en.getKey(); }
        return best;
    }

    // every label heard at this power with its best RSSI (dBm)
    private java.util.Map<String, Integer> hearAll(int powerDbm) throws Exception {
        setPower(powerDbm);
        java.util.concurrent.ConcurrentHashMap<String, Integer> got = new java.util.concurrent.ConcurrentHashMap<>();
        single = got;
        try {
            reader.Actions.Inventory.perform();
            for (int i = 0; i < 20 && got.isEmpty(); i++) Thread.sleep(50);
            if (!got.isEmpty()) Thread.sleep(500);
            reader.Actions.Inventory.stop();
        } finally { single = null; }
        return got;
    }

    /** بشار 2026-11-24: low power missed the label, high power took one further away. Step up from the
     *  set power (+3, +6, +9 dBm, capped at 20 — never the sled's maximum) until a label answers, and
     *  only accept it when it is clearly stronger (6 dB) than any other label heard. */
    @Override
    public String readNearest(int powerDbm) throws Exception {
        if (reader == null) return null;
        int base = powerDbm <= 0 ? 10 : powerDbm;
        for (int step = 0; step <= 9; step += 3) {
            int pw = Math.min(base + step, 20);
            java.util.Map<String, Integer> got = hearAll(pw);
            if (got.isEmpty()) { if (pw >= 20) break; continue; }
            String best = null; int b1 = Integer.MIN_VALUE, b2 = Integer.MIN_VALUE;
            for (java.util.Map.Entry<String, Integer> en : got.entrySet()) {
                int v = en.getValue();
                if (v > b1) { b2 = b1; b1 = v; best = en.getKey(); } else if (v > b2) b2 = v;
            }
            if (got.size() > 1 && b1 - b2 < 6)
                throw new Exception("يسمع الجهاز أكثر من ملصقة قريبة (" + got.size() + ") — أبعد الملصقات والقطع الأخرى عن مقدمة الجهاز وأعد المحاولة");
            return best;
        }
        return null;
    }

    @Override
    public boolean writeEpc(String oldEpc, String newEpc, int powerDbm) throws Exception {
        if (reader == null) return false;
        TagAccess.WriteAccessParams p = reader.Actions.TagAccess.new WriteAccessParams();
        p.setMemoryBank(MEMORY_BANK.MEMORY_BANK_EPC);
        p.setOffset(2);                       // words: after CRC + PC
        p.setWriteData(newEpc);
        p.setWriteDataLength(newEpc.length() / 4); // in 16-bit words
        p.setAccessPassword(0);
        p.setWriteRetries(3);
        // writing needs much more power than reading. بشار 2026-11-27: capped at 20–22 dBm (from the 24th)
        // the writes kept failing — staff tried 15+ times per label. The write is addressed to oldEpc only
        // (readNearest made sure it is the one label held against the sled), so step up to the sled's
        // maximum as before the 24th: about 17 dBm, then 24, then full power.
        int base = powerDbm <= 0 ? 10 : powerDbm;
        int[] tries = { Math.max(base + 8, 17), 24, 0 }; // 0 = the sled's maximum
        Exception last = null;
        for (int pw : tries) {
            try { setPower(pw); reader.Actions.TagAccess.writeWait(oldEpc, p, null, null); return true; }
            catch (Exception e) { last = e; }
        }
        throw last;
    }

    @Override
    public boolean start(int powerDbm, TagSink s) throws Exception {
        if (reader == null) return false;
        setPower(powerDbm);
        sink = s;
        reader.Actions.Inventory.perform();
        return true;
    }

    @Override
    public void stop() {
        sink = null;
        try { if (reader != null) reader.Actions.Inventory.stop(); } catch (Throwable ignored) { }
    }

    @Override
    public synchronized void close() {
        sink = null;
        RFIDReader r = reader;
        reader = null;
        try { if (r != null) { r.Events.removeEventsListener(events); r.disconnect(); } } catch (Throwable ignored) { }
        try { if (readers != null) readers.Dispose(); } catch (Throwable ignored) { }
        readers = null;
    }
}
