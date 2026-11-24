package com.awj;

public final class Native {
    static {
        System.loadLibrary("awj");
    }
    public static native int init();
    public static native int ready();
    public static native void clear();
    public static native void cheat();
    public static native void brute();
    public static native void win();
    public static native void sp();
    public static native void inv();
    public static native void speed(float rate);
    public static native void stopMove();
    public static native void monsterHp(int pct);
    public static native void attr(String name, long value);
    public static native void lua(String code);
}
