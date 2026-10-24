package com.goldmind.app;

import android.content.Context;

/**
 * A Bluetooth RFID sled (Zebra RFD4031...) used through GMUhfPlugin with the same JS API as the
 * built-in readers. The real code (ZebraRfd) lives in src/zebra/java and is compiled only when the
 * Zebra SDK .aar is present at build time (build.gradle); it is loaded by name, so the app builds
 * and runs without it.
 */
interface RfidSled {
    interface TagSink { void onTag(String epc, int rssi); }
    interface TriggerSink { void onTrigger(boolean down); }

    /** Connects to the paired sled (blocks a few seconds the first time). */
    boolean open(Context ctx, TriggerSink trigger);
    /** Nearest single tag at this power (dBm, 0 = the sled's maximum), or null. */
    String readOne(int powerDbm) throws Exception;
    /** Writes newEpc on the tag whose EPC is oldEpc. */
    boolean writeEpc(String oldEpc, String newEpc, int powerDbm) throws Exception;
    boolean start(int powerDbm, TagSink sink) throws Exception;
    void stop();
    void close();
    /** Name of the connected sled (e.g. RFD4031-...), or "" when not connected. */
    String name();
}
