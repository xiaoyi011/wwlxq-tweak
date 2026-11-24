package com.awj;

import android.app.Activity;
import android.app.Application;
import android.app.Dialog;
import android.view.WindowManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.lang.reflect.Proxy;
import java.net.HttpURLConnection;
import java.net.URL;

public final class Launcher {

    static final int C_BG = 0xFF16233A;
    static final int C_BTN = 0xFF22304A;
    static final int C_ON = 0xFF1FAE8C;
    static final int C_TEXT = 0xFFFFFFFF;
    static final int C_DIM = 0xFFB8C6DA;
    static final int C_ERR = 0xFFFF6B6B;
    static final String BASE = "http://154.94.239.25:8090";
    // 调试开关：发布前改为 false
    static final boolean DEBUG_UNLOCK = true;

    static Context app;
    static SharedPreferences sp;
    static Handler H = new Handler(Looper.getMainLooper());

    static volatile boolean licensed = false;
    static String expireText = "";
    static int unbindLeft = -1;
    static String lockMsg = "";
    static boolean alertShown = false;

    static View ball;
    static View panel;
    static Activity curActivity;
    static volatile boolean autoClear = false;
    static volatile boolean autoSp = false;
    static volatile boolean autoInv = false;
    static volatile boolean autoWin = false;
    static volatile boolean autoWinLoopStarted = false;
    static float savedSpeed = 1f;

    // ---------------- 初始化 ----------------
    public static void init(Context ctx) {
        app = ctx.getApplicationContext();
        sp = app.getSharedPreferences("awj", Context.MODE_PRIVATE);
        savedSpeed = sp.getFloat("speed", 1f);
        if (savedSpeed < 1f || savedSpeed > 10f) savedSpeed = 1f;

        if (ctx instanceof Application) {
            ((Application) ctx).registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
                public void onActivityCreated(Activity a, Bundle b) { attach(a); }
                public void onActivityStarted(Activity a) {}
                public void onActivityResumed(Activity a) { attach(a); }
                public void onActivityPaused(Activity a) {}
                public void onActivityStopped(Activity a) {}
                public void onActivitySaveInstanceState(Activity a, Bundle b) {}
                public void onActivityDestroyed(Activity a) {}
            });
        }

        H.postDelayed(new Runnable() {
            public void run() { startInit("fallback"); }
        }, 120000);
    }

    static volatile boolean initStarted = false;

    static void startInit(final String why) {
        if (initStarted) return;
        initStarted = true;
        logger("start init: " + why);
        new Thread(new Runnable() {
            public void run() {
                int r = 0;
                for (int i = 0; i < 900; i++) {
                    r = Native.init();
                    if (r == 1) break;
                    try { Thread.sleep(2000); } catch (Exception ignored) {}
                }
                logger("native init=" + r);
                licenseCheck();
                startAutoWinLoop();
                H.postDelayed(hbTask, 15000);
            }
        }).start();
    }

    static void logger(String s) {
        android.util.Log.i("AWJ", s);
    }

    static int dp(int v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                app.getResources().getDisplayMetrics()));
    }

    static GradientDrawable bg(int color, int radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(dp(radiusDp));
        return g;
    }

    static String deviceId() {
        String d = sp.getString("device", "");
        if (d == null || d.length() == 0) {
            try {
                d = Settings.Secure.getString(app.getContentResolver(), Settings.Secure.ANDROID_ID);
            } catch (Exception ignored) {}
            if (d == null || d.length() == 0) d = "android-" + System.currentTimeMillis();
            sp.edit().putString("device", d).apply();
        }
        return d;
    }

    // ---------------- 悬浮球 ----------------
    static Dialog ballDlg;
    static Activity ballAct;
    static Window ballWin;

    static void attach(Activity a) {
        try {
            curActivity = a;
            String cn = a.getClass().getName();
            if (cn.contains("GameMainActivity")) startInit(cn);
        } catch (Throwable t) {
            logger("attach err " + t);
        }
    }

    static void dismissBall() {
        if (overlayBall != null && wm != null) {
            try { wm.removeView(overlayBall); } catch (Throwable ignored) {}
            overlayBall = null;
            ball = null;
        }
        if (ballDlg != null) {
            try { ballDlg.dismiss(); } catch (Throwable ignored) {}
            ballDlg = null;
            ballWin = null;
        }
    }

    static WindowManager wm;
    static View overlayBall;
    static WindowManager.LayoutParams ovLp;

    static void ensureBall(final Activity act) {
        if (!licensed) { dismissBall(); return; }
        if (overlayBall != null) return;
        try {
            if (!Settings.canDrawOverlays(app)) {
                logger("no overlay permission");
                return;
            }
            wm = (WindowManager) app.getSystemService(Context.WINDOW_SERVICE);
            final TextView b = new TextView(app);
            b.setText("逸");
            b.setTextColor(C_TEXT);
            b.setGravity(Gravity.CENTER);
            b.setTextSize(15);
            b.setBackground(bg(0xE61A8CFF, 22));
            ovLp = new WindowManager.LayoutParams(
                    dp(48), dp(48),
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                            | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                    android.graphics.PixelFormat.TRANSLUCENT);
            ovLp.gravity = Gravity.TOP | Gravity.START;
            ovLp.x = app.getResources().getDisplayMetrics().widthPixels - dp(72);
            ovLp.y = dp(240);
            b.setOnTouchListener(new View.OnTouchListener() {
                float downX, downY;
                int startX, startY;
                boolean moved;
                long downAt;
                public boolean onTouch(View v, MotionEvent e) {
                    switch (e.getActionMasked()) {
                        case MotionEvent.ACTION_DOWN:
                            downAt = System.currentTimeMillis();
                            downX = e.getRawX();
                            downY = e.getRawY();
                            startX = ovLp.x;
                            startY = ovLp.y;
                            moved = false;
                            return true;
                        case MotionEvent.ACTION_MOVE: {
                            float dx = e.getRawX() - downX;
                            float dy = e.getRawY() - downY;
                            if (Math.abs(dx) > dp(6) || Math.abs(dy) > dp(6)) moved = true;
                            ovLp.x = startX + (int) dx;
                            ovLp.y = startY + (int) dy;
                            if (wm != null) wm.updateViewLayout(v, ovLp);
                            return true;
                        }
                        case MotionEvent.ACTION_UP:
                            logger("ball up moved=" + moved);
                            if (!moved) {
                                Activity act = topActivity() != null ? topActivity() : curActivity;
                                if (System.currentTimeMillis() - downAt > 600) {
                                    if (!licensed) showLicenseDialog(act, lockMsg.length() > 0 ? lockMsg : null);
                                    else Native.openGm();
                                } else {
                                    if (!licensed) showLicenseDialog(act, lockMsg.length() > 0 ? lockMsg : null);
                                    else togglePanel(act);
                                }
                            }
                            return true;
                    }
                    return false;
                }
            });
            wm.addView(b, ovLp);
            overlayBall = b;
            ball = b;
            logger("ball overlay added");
        } catch (Throwable t) {
            logger("ball overlay err " + t);
        }
    }

    static void installVolumeKeys(Window w) {
        try {
            final Window.Callback orig = w.getCallback();
            if (orig == null || orig.getClass().getName().contains("Proxy")) return;
            Window.Callback proxy = (Window.Callback) Proxy.newProxyInstance(
                    Window.Callback.class.getClassLoader(),
                    new Class[]{Window.Callback.class},
                    new java.lang.reflect.InvocationHandler() {
                        public Object invoke(Object p, java.lang.reflect.Method m, Object[] args) throws Throwable {
                            if ("dispatchKeyEvent".equals(m.getName()) && args != null && args.length == 1
                                    && args[0] instanceof KeyEvent) {
                                KeyEvent e = (KeyEvent) args[0];
                                if (e.getAction() == KeyEvent.ACTION_DOWN) {
                                    if (e.getKeyCode() == KeyEvent.KEYCODE_VOLUME_UP) {
                                        logger("volume up");
                                        H.post(new Runnable() {
                                            public void run() {
                                                Activity act = topActivity();
                                                if (act == null) act = curActivity;
                                                togglePanel(act);
                                            }
                                        });
                                        return Boolean.TRUE;
                                    } else if (e.getKeyCode() == KeyEvent.KEYCODE_VOLUME_DOWN) {
                                        logger("volume down");
                                        H.post(new Runnable() {
                                            public void run() { closePanel(); }
                                        });
                                        return Boolean.TRUE;
                                    }
                                }
                            }
                            try { return m.invoke(orig, args); }
                            catch (java.lang.reflect.InvocationTargetException ite) { throw ite.getCause(); }
                        }
                    });
            w.setCallback(proxy);
        } catch (Throwable ignored) {}
    }

    static void setBallVisible(final boolean v) {
        H.post(new Runnable() {
            public void run() {
                if (v) {
                    Activity a = topActivity();
                    if (a == null) a = curActivity;
                    ensureBall(a);
                } else {
                    dismissBall();
                }
            }
        });
    }

    static void updateBallVisibility() {
        if (licensed) {
            if (!Settings.canDrawOverlays(app)) {
                try {
                    android.content.Intent i = new android.content.Intent(
                            android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:" + app.getPackageName()));
                    i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
                    app.startActivity(i);
                } catch (Throwable ignored) {}
                return;
            }
            Activity a = topActivity();
            if (a == null) a = curActivity;
            ensureBall(a);
        } else {
            dismissBall();
        }
    }

    static void onBallClick(final Activity a) {
        logger("ball click licensed=" + licensed);
        if (!licensed) {
            showLicenseDialog(a, lockMsg.length() > 0 ? lockMsg : null);
            return;
        }
        togglePanel(a);
    }

    // ---------------- 面板 ----------------
    static android.app.Dialog panelDlg;

    static Activity topActivity() {
        try {
            Class<?> at = Class.forName("android.app.ActivityThread");
            Object thread = at.getMethod("currentActivityThread").invoke(null);
            java.lang.reflect.Field f = at.getDeclaredField("mActivities");
            f.setAccessible(true);
            java.util.Map<?, ?> acts = (java.util.Map<?, ?>) f.get(thread);
            if (acts != null) {
                for (Object rec : acts.values()) {
                    java.lang.reflect.Field pf = rec.getClass().getDeclaredField("paused");
                    pf.setAccessible(true);
                    if (!((Boolean) pf.get(rec))) {
                        java.lang.reflect.Field af = rec.getClass().getDeclaredField("activity");
                        af.setAccessible(true);
                        Object a = af.get(rec);
                        if (a instanceof Activity) return (Activity) a;
                    }
                }
            }
        } catch (Throwable ignored) {}
        return null;
    }

    static void togglePanel(final Activity a) {
        H.post(new Runnable() {
            public void run() {
                if (panelDlg != null) {
                    try { panelDlg.dismiss(); } catch (Throwable ignored) {}
                    panelDlg = null;
                    panel = null;
                    return;
                }
                Activity act = topActivity();
                if (act == null || act.isFinishing()) act = a;
                if (act == null || act.isFinishing()) return;
                logger("panel activity=" + act.getClass().getName());
                panel = buildPanel2(act);
                try {
                    android.app.Dialog d = new android.app.Dialog(act, android.R.style.Theme_Translucent_NoTitleBar);
                    FrameLayout holder = new FrameLayout(act);
                    holder.addView(panel, new FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
                    android.widget.ScrollView sc = new android.widget.ScrollView(act);
                    sc.addView(holder, new android.widget.ScrollView.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
                    FrameLayout outer = new FrameLayout(act);
                    outer.addView(sc, new FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
                    FrameLayout.LayoutParams olp = new FrameLayout.LayoutParams(
                            dp(320), (int) (app.getResources().getDisplayMetrics().heightPixels * 0.8f));
                    olp.gravity = Gravity.CENTER;
                    d.setContentView(outer, olp);
                    android.view.Window w = d.getWindow();
                    if (w != null) {
                        w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
                        w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));
                    }
                    d.show();
                    panelDlg = d;
                    logger("panel shown");
                } catch (Throwable t) {
                    logger("panel err " + t);
                }
            }
        });
    }

    static void closePanel() {
        if (panelDlg != null) {
            try { panelDlg.dismiss(); } catch (Throwable ignored) {}
            panelDlg = null;
        }
        panel = null;
    }

    static TextView mkBtn(String text, int color) {
        TextView t = new TextView(app);
        t.setText(text);
        t.setTextColor(C_TEXT);
        t.setTextSize(13);
        t.setGravity(Gravity.CENTER);
        t.setBackground(bg(color, 8));
        t.setPadding(dp(6), dp(12), dp(6), dp(12));
        return t;
    }

    // 新版面板（安卓自身能力，8 项功能）
    static View buildPanel2(final Activity a) {
        final LinearLayout p = new LinearLayout(app);
        p.setOrientation(LinearLayout.VERTICAL);
        p.setBackground(bg(0xF216233A, 14));
        p.setPadding(dp(12), dp(8), dp(12), dp(10));

        LinearLayout titleRow = new LinearLayout(app);
        titleRow.setOrientation(LinearLayout.HORIZONTAL);
        TextView title = new TextView(app);
        title.setText("小逸");
        title.setTextColor(C_TEXT);
        title.setTextSize(18);
        title.setGravity(Gravity.CENTER);
        titleRow.addView(title, new LinearLayout.LayoutParams(0, dp(34), 1));
        TextView close = new TextView(app);
        close.setText("×");
        close.setTextColor(C_TEXT);
        close.setTextSize(22);
        close.setGravity(Gravity.CENTER);
        close.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { closePanel(); }
        });
        titleRow.addView(close, new LinearLayout.LayoutParams(dp(40), dp(34)));
        p.addView(titleRow);

        final TextView bClear = mkBtn("击杀全部怪物", C_BTN);
        final TextView bAutoWin = mkBtn("直接判胜：自动", C_BTN);
        final TextView bStop = mkBtn("停止怪物移动", C_BTN);
        final TextView bSpAdd = mkBtn("加 SP", C_BTN);
        final TextView bSpSet = mkBtn("设置 SP 数值", C_BTN);
        final TextView bWall = mkBtn("城墙999999999（我方）", C_BTN);
        final TextView bHint = mkBtn("点悬浮球开关面板", 0xFF1C283C);
        bHint.setTextSize(9);
        bHint.setTextColor(C_DIM);

        View[] rows = new View[]{bClear, bAutoWin, bStop, bSpAdd, bSpSet, bWall, bHint};
        for (int i = 0; i < rows.length; i += 2) {
            LinearLayout row = new LinearLayout(app);
            row.setOrientation(LinearLayout.HORIZONTAL);
            LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            rp.topMargin = dp(8);
            row.setLayoutParams(rp);
            row.addView(rows[i], new LinearLayout.LayoutParams(0, dp(40), 1));
            if (i + 1 < rows.length) {
                LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(0, dp(40), 1);
                rlp.leftMargin = dp(8);
                row.addView(rows[i + 1], rlp);
            } else {
                View sp2 = new View(app);
                LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(0, dp(40), 1);
                slp.leftMargin = dp(8);
                row.addView(sp2, slp);
            }
            p.addView(row);
        }

        // 加速（战斗）
        final int gsp = Math.max(1, Math.min(10, (int) savedSpeed));
        p.addView(makeLabel("加速（主线推荐3倍）: " + gsp + "x"));
        SeekBar speedBar = new SeekBar(app);
        speedBar.setMax(9);
        speedBar.setProgress(gsp - 1);
        final TextView speedLabel = (TextView) p.getChildAt(p.getChildCount() - 1);
        speedBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            public void onProgressChanged(SeekBar sb, int prog, boolean fromUser) {
                speedLabel.setText("加速（主线推荐3倍）: " + (prog + 1) + "x");
            }
            public void onStartTrackingTouch(SeekBar sb) {}
            public void onStopTrackingTouch(SeekBar sb) {
                final float v = sb.getProgress() + 1;
                savedSpeed = v;
                sp.edit().putFloat("speed", v).apply();
                Native.speed(v);
            }
        });
        p.addView(speedBar);

        // 底部
        LinearLayout foot = new LinearLayout(app);
        foot.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams flp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(36));
        flp.topMargin = dp(10);
        foot.setLayoutParams(flp);
        TextView exp = new TextView(app);
        exp.setText("卡密到期: " + (expireText.length() > 0 ? expireText : "-"));
        exp.setTextColor(C_DIM);
        exp.setTextSize(11);
        exp.setGravity(Gravity.CENTER_VERTICAL);
        foot.addView(exp, new LinearLayout.LayoutParams(0, dp(36), 1));
        final TextView unbind = mkBtn(unbindLeft >= 0 ? ("解绑(" + unbindLeft + ")") : "解绑", C_BTN);
        unbind.setTextSize(10);
        unbind.setPadding(dp(10), 0, dp(10), 0);
        unbind.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { doUnbind(unbind); }
        });
        foot.addView(unbind, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, dp(28)));
        p.addView(foot);

        bClear.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                Toast.makeText(app, "清场 已执行", Toast.LENGTH_SHORT).show();
                Native.clear();
            }
        });
        bStop.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                Toast.makeText(app, "停止移动 已执行", Toast.LENGTH_SHORT).show();
                Native.stopMove();
            }
        });
        bSpAdd.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                Toast.makeText(app, "加 SP 已执行", Toast.LENGTH_SHORT).show();
                Native.sp();
            }
        });
        bSpSet.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                Toast.makeText(app, "设置 SP 已执行", Toast.LENGTH_SHORT).show();
                Native.setSp(999999);
            }
        });
        bWall.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                Toast.makeText(app, "城墙血量 已执行", Toast.LENGTH_SHORT).show();
                Native.wallHp(999999999L);
            }
        });
        bAutoWin.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                autoWin = !autoWin;
                bAutoWin.setBackground(bg(autoWin ? C_ON : C_BTN, 8));
            }
        });

        if (gsp > 1) {
            final int applySp = gsp;
            Native.speed(applySp);
        }
        return p;
    }

    static TextView makeLabel(String s) {
        TextView t = new TextView(app);
        t.setText(s);
        t.setTextColor(C_DIM);
        t.setTextSize(12);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(22));
        lp.topMargin = dp(8);
        t.setLayoutParams(lp);
        return t;
    }

    static void addAttrSlider(LinearLayout parent, String label, final String attrName) {
        final String key = "attr_" + attrName;
        final TextView lab = makeLabel(label + ": " + sp.getInt(key, 0));
        parent.addView(lab);
        SeekBar sb = new SeekBar(app);
        sb.setMax(1000);
        sb.setProgress(sp.getInt(key, 0));
        lab.setText(label + ": " + (sb.getProgress() * 1000));
        sb.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            public void onProgressChanged(SeekBar s, int prog, boolean fromUser) {
                lab.setText(label + ": " + (prog * 1000));
            }
            public void onStartTrackingTouch(SeekBar s) {}
            public void onStopTrackingTouch(SeekBar s) {
                int v = s.getProgress();
                sp.edit().putInt(key, v).apply();
                if (v > 0) Native.attr(attrName, (long) v * 1000L);
            }
        });
        parent.addView(sb);
    }

    // ---------------- 常驻循环 ----------------
    static final Runnable hbTask = new Runnable() {
        public void run() {
            heartbeat();
            H.postDelayed(this, 300000);
        }
    };

    static void startAutoWinLoop() {
        if (autoWinLoopStarted) return;
        autoWinLoopStarted = true;
        new Thread(new Runnable() {
            public void run() {
                while (true) {
                    try { Thread.sleep(3000); } catch (Exception ignored) {}
                    if (licensed && autoWin) {
                        H.post(new Runnable() {
                            public void run() {
                                try { Native.win(); } catch (Throwable ignored) {}
                            }
                        });
                    }
                }
            }
        }).start();
    }

    static volatile boolean gmLoopStarted = false;

    static void startGmLoop() {
        if (gmLoopStarted) return;
        gmLoopStarted = true;
        new Thread(new Runnable() {
            public void run() {
                while (true) {
                    try { Thread.sleep(1200); } catch (Exception ignored) {}
                    if (!licensed) continue;
                    try {
                        if (autoSp) Native.sp();
                        if (autoInv) Native.inv();
                        if (savedSpeed > 1f) Native.speed(savedSpeed);
                    } catch (Throwable ignored) {}
                }
            }
        }).start();
    }

    // ---------------- 卡密 ----------------
    static void licenseCheck() {
        if (DEBUG_UNLOCK) {
            licensed = true;
            expireText = "DEBUG";
            unbindLeft = 3;
            lockMsg = "";
            H.post(new Runnable() { public void run() { updateBallVisibility(); } });
            return;
        }
        String tok = sp.getString("token", "");
        if (tok == null || tok.length() == 0) { licensed = false; return; }
        try {
            JSONObject req = new JSONObject();
            req.put("token", tok);
            req.put("device", deviceId());
            JSONObject r = post("/api/check", req);
            if (r.optBoolean("ok")) {
                licensed = true;
                expireText = r.optString("expire_text", "");
                unbindLeft = r.optInt("unbind_left", -1);
                lockMsg = "";
            } else {
                licensed = false;
                lockMsg = r.optString("msg", "");
            }
        } catch (Exception e) {
            logger("check err " + e);
        }
        H.post(new Runnable() { public void run() { updateBallVisibility(); } });
    }

    static void showLicenseDialog(final Activity a, final String err) {
        H.post(new Runnable() {
            public void run() {
                if (a == null || a.isFinishing()) return;
                final FrameLayout root = (FrameLayout) a.getWindow().getDecorView();

                final LinearLayout d = new LinearLayout(app);
                d.setOrientation(LinearLayout.VERTICAL);
                d.setBackground(bg(0xFA16233A, 14));
                d.setPadding(dp(16), dp(12), dp(16), dp(12));
                FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(dp(300), ViewGroup.LayoutParams.WRAP_CONTENT);
                lp.gravity = Gravity.CENTER;
                d.setLayoutParams(lp);

                TextView t = new TextView(app);
                t.setText("输入卡密");
                t.setTextColor(C_TEXT);
                t.setTextSize(17);
                t.setGravity(Gravity.CENTER);
                d.addView(t, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(32)));

                final EditText et = new EditText(app);
                et.setHint("卡密");
                et.setSingleLine(true);
                et.setTextColor(C_TEXT);
                et.setHintTextColor(C_DIM);
                et.setTextSize(14);
                et.setBackground(bg(0xFF0D1729, 8));
                et.setInputType(InputType.TYPE_CLASS_TEXT);
                d.addView(et, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(44)));

                final TextView errView = new TextView(app);
                errView.setText(err != null ? err : "");
                errView.setTextColor(C_ERR);
                errView.setTextSize(12);
                errView.setVisibility(err != null ? View.VISIBLE : View.GONE);
                LinearLayout.LayoutParams elp = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                elp.topMargin = dp(6);
                d.addView(errView, elp);

                TextView qq = new TextView(app);
                qq.setText("正版QQ群：996078023");
                qq.setTextColor(C_DIM);
                qq.setTextSize(11);
                qq.setGravity(Gravity.CENTER);
                LinearLayout.LayoutParams qlp = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, dp(24));
                qlp.topMargin = dp(4);
                d.addView(qq, qlp);

                LinearLayout btns = new LinearLayout(app);
                btns.setOrientation(LinearLayout.HORIZONTAL);
                LinearLayout.LayoutParams blp = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, dp(44));
                blp.topMargin = dp(10);
                btns.setLayoutParams(blp);

                TextView cancel = mkBtn("关闭", 0xFF2E3238);
                cancel.setOnClickListener(new View.OnClickListener() {
                    public void onClick(View v) { root.removeView(d); }
                });
                btns.addView(cancel, new LinearLayout.LayoutParams(0, dp(44), 1));

                final TextView ok = mkBtn("激活", C_ON);
                LinearLayout.LayoutParams olp = new LinearLayout.LayoutParams(0, dp(44), 1);
                olp.leftMargin = dp(10);
                ok.setOnClickListener(new View.OnClickListener() {
                    public void onClick(View v) {
                        final String key = et.getText().toString().trim();
                        if (key.length() == 0) {
                            errView.setText("请输入卡密");
                            errView.setVisibility(View.VISIBLE);
                            return;
                        }
                        errView.setVisibility(View.GONE);
                        ok.setText("激活中…");
                        new Thread(new Runnable() {
                            public void run() {
                                try {
                                    JSONObject req = new JSONObject();
                                    req.put("key", key);
                                    req.put("device", deviceId());
                                    final JSONObject r = post("/api/activate", req);
                                    H.post(new Runnable() {
                                        public void run() {
                                            ok.setText("激活");
                                            if (r.optBoolean("ok")) {
                                                sp.edit().putString("token", r.optString("token", ""))
                                                        .putString("expire", r.optString("expire_text", "")).apply();
                                                licensed = true;
                                                expireText = r.optString("expire_text", "");
                                                unbindLeft = r.optInt("unbind_left", -1);
                                                lockMsg = "";
                                                root.removeView(d);
                                                updateBallVisibility();
                                                Toast.makeText(app, "激活成功", Toast.LENGTH_SHORT).show();
                                                heartbeat();
                                            } else {
                                                errView.setText(r.optString("msg", "激活失败"));
                                                errView.setVisibility(View.VISIBLE);
                                            }
                                        }
                                    });
                                } catch (Exception e) {
                                    H.post(new Runnable() {
                                        public void run() {
                                            ok.setText("激活");
                                            errView.setText("网络错误");
                                            errView.setVisibility(View.VISIBLE);
                                        }
                                    });
                                }
                            }
                        }).start();
                    }
                });
                btns.addView(ok, olp);
                d.addView(btns);

                root.addView(d);
            }
        });
    }

    static void doUnbind(final TextView btn) {
        final String tok = sp.getString("token", "");
        if (tok == null || tok.length() == 0) return;
        new Thread(new Runnable() {
            public void run() {
                try {
                    JSONObject req = new JSONObject();
                    req.put("token", tok);
                    final JSONObject r = post("/api/unbind", req);
                    H.post(new Runnable() {
                        public void run() {
                            if (r.optBoolean("ok")) {
                                sp.edit().remove("token").remove("expire").apply();
                                licensed = false;
                                expireText = "";
                                int left = r.optInt("unbind_left", -1);
                                if (left >= 0) {
                                    unbindLeft = left;
                                    btn.setText("解绑(" + left + ")");
                                }
                                closePanel();
                                updateBallVisibility();
                                Toast.makeText(app, "已解绑", Toast.LENGTH_SHORT).show();
                            } else {
                                Toast.makeText(app, r.optString("msg", "解绑失败"), Toast.LENGTH_SHORT).show();
                            }
                        }
                    });
                } catch (Exception ignored) {}
            }
        }).start();
    }

    static void heartbeat() {
        if (DEBUG_UNLOCK) return;
        final String tok = sp.getString("token", "");
        new Thread(new Runnable() {
            public void run() {
                try {
                    JSONObject req = new JSONObject();
                    req.put("token", tok == null ? "" : tok);
                    req.put("device", deviceId());
                    req.put("ver", "1.0.0");
                    req.put("hash", "android");
                    JSONObject r = post("/api/heartbeat", req);
                    if (r.optBoolean("ok")) {
                        licensed = tok != null && tok.length() > 0;
                        lockMsg = "";
                        alertShown = false;
                    } else if (r.optBoolean("lock")) {
                        licensed = false;
                        lockMsg = r.optString("msg", "授权已失效");
                        H.post(new Runnable() {
                            public void run() {
                                updateBallVisibility();
                                closePanel();
                                if (!alertShown) {
                                    alertShown = true;
                                    Toast.makeText(app, lockMsg, Toast.LENGTH_LONG).show();
                                }
                            }
                        });
                    }
                } catch (Exception ignored) {}
            }
        }).start();
    }

    static JSONObject post(String path, JSONObject body) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(BASE + path).openConnection();
        c.setRequestMethod("POST");
        c.setConnectTimeout(8000);
        c.setReadTimeout(8000);
        c.setDoOutput(true);
        c.setRequestProperty("Content-Type", "application/json");
        OutputStream os = c.getOutputStream();
        os.write(body.toString().getBytes("UTF-8"));
        os.close();
        InputStream is = c.getInputStream();
        BufferedReader br = new BufferedReader(new InputStreamReader(is, "UTF-8"));
        StringBuilder sb = new StringBuilder();
        String line;
        while ((line = br.readLine()) != null) sb.append(line);
        br.close();
        return new JSONObject(sb.toString());
    }
}
