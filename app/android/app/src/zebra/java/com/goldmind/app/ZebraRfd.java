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
    private volatile AtomicReference<String> single;
    private int[] powerLevels; // dBm x 10, by index
    private String deviceName = "";

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
                AtomicReference<String> one = single;
                if (one != null) { one.compareAndSet(null, epc); continue; }
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
            if (list == null || list.isEmpty()) return false;
            ReaderDevice dev = list.get(0);
            RFIDReader r = dev.getRFIDReader();
            deviceName = dev.getName() == null ? "" : dev.getName();
            if (!r.isConnected()) r.connect();
            r.Events.addEventsListener(events);
            r.Events.setHandheldEvent(true);
            r.Events.setTagReadEvent(true);
            r.Events.setAttachTagDataWithReadEvent(false);
            r.Events.setReaderDisconnectEvent(true);
            // the trigger reads RFID (not the barcode scanner); GoldMind decides what a press does
            r.Config.setTriggerMode(ENUM_TRIGGER_MODE.RFID_MODE, true);
            powerLevels = r.ReaderCapabilities.getTransmitPowerLevelValues();
            reader = r;
            return true;
        } catch (Throwable e) {
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
        AtomicReference<String> got = new AtomicReference<>(null);
        single = got;
        try {
            reader.Actions.Inventory.perform();
            for (int i = 0; i < 30 && got.get() == null; i++) Thread.sleep(50); // up to 1.5 s
            reader.Actions.Inventory.stop();
        } finally {
            single = null;
        }
        return got.get();
    }

    @Override
    public boolean writeEpc(String oldEpc, String newEpc, int powerDbm) throws Exception {
        if (reader == null) return false;
        setPower(powerDbm);
        TagAccess.WriteAccessParams p = reader.Actions.TagAccess.new WriteAccessParams();
        p.setMemoryBank(MEMORY_BANK.MEMORY_BANK_EPC);
        p.setOffset(2);                       // words: after CRC + PC
        p.setWriteData(newEpc);
        p.setWriteDataLength(newEpc.length() / 4); // in 16-bit words
        p.setAccessPassword(0);
        p.setWriteRetries(3);
        reader.Actions.TagAccess.writeWait(oldEpc, p, null, null);
        return true;
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
