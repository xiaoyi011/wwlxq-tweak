package com.awj;

import android.app.Activity;
import android.app.Application;
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
    static volatile boolean autoClear = false;
    static volatile boolean autoSp = false;
    static volatile boolean autoInv = false;
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

        new Thread(new Runnable() {
            public void run() {
                int r = 0;
                for (int i = 0; i < 150; i++) {
                    r = Native.init();
                    if (r == 1) break;
                    try { Thread.sleep(2000); } catch (Exception ignored) {}
                }
                logger("native init=" + r);
                licenseCheck();
                H.postDelayed(hbTask, 15000);
                H.postDelayed(loopTask, 3000);
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
    static void attach(Activity a) {
        try {
            Window w = a.getWindow();
            if (w == null) return;
            final FrameLayout root = (FrameLayout) w.getDecorView();
            if (root.findViewById(0xA1A1) != null) return;

            final TextView b = new TextView(a);
            b.setId(0xA1A1);
            b.setText("逸");
            b.setTextColor(C_TEXT);
            b.setGravity(Gravity.CENTER);
            b.setTextSize(15);
            b.setBackground(bg(0xE61A8CFF, 22));
            FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(dp(44), dp(44));
            lp.gravity = Gravity.TOP | Gravity.END;
            lp.topMargin = dp(240);
            lp.rightMargin = dp(16);
            b.setLayoutParams(lp);
            b.setOnClickListener(new View.OnClickListener() {
                public void onClick(View v) { onBallClick(a); }
            });
            // 拖动
            b.setOnTouchListener(new View.OnTouchListener() {
                float dx, dy;
                public boolean onTouch(View v, MotionEvent e) {
                    switch (e.getActionMasked()) {
                        case MotionEvent.ACTION_DOWN:
                            dx = v.getX() - e.getRawX();
                            dy = v.getY() - e.getRawY();
                            return false;
                        case MotionEvent.ACTION_MOVE:
                            v.setX(e.getRawX() + dx);
                            v.setY(e.getRawY() + dy);
                            return true;
                    }
                    return false;
                }
            });
            root.addView(b);
            ball = b;
            updateBallVisibility();
        } catch (Throwable t) {
            logger("attach err " + t);
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
                                    if (e.getKeyCode() == KeyEvent.KEYCODE_VOLUME_UP) setBallVisible(true);
                                    else if (e.getKeyCode() == KeyEvent.KEYCODE_VOLUME_DOWN) setBallVisible(false);
                                }
                            }
                            try { return m.invoke(orig, args); }
                            catch (java.lang.reflect.InvocationTargetException ite) { throw ite.getCause(); }
                        }
                    });
            w.setCallback(proxy);
        } catch (Throwable ignored) {}
    }

    static void setBallVisible(boolean v) {
        final boolean vis = v;
        H.post(new Runnable() {
            public void run() {
                if (ball != null) ball.setVisibility(vis ? View.VISIBLE : View.GONE);
            }
        });
    }

    static void updateBallVisibility() {
        if (ball != null) ball.setVisibility(licensed ? View.VISIBLE : View.GONE);
    }

    static void onBallClick(final Activity a) {
        if (!licensed) {
            showLicenseDialog(a, lockMsg.length() > 0 ? lockMsg : null);
            return;
        }
        togglePanel(a);
    }

    // ---------------- 面板 ----------------
    static void togglePanel(final Activity a) {
        H.post(new Runnable() {
            public void run() {
                if (panel != null) {
                    ViewGroup parent = (ViewGroup) panel.getParent();
                    if (parent != null) parent.removeView(panel);
                    panel = null;
                    return;
                }
                if (a == null || a.getWindow() == null) return;
                final FrameLayout root = (FrameLayout) a.getWindow().getDecorView();
                panel = buildPanel(a);
                root.addView(panel);
            }
        });
    }

    static void closePanel() {
        if (panel != null) {
            ViewGroup parent = (ViewGroup) panel.getParent();
            if (parent != null) parent.removeView(panel);
            panel = null;
        }
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

    static View buildPanel(final Activity a) {
        final LinearLayout p = new LinearLayout(app);
        p.setOrientation(LinearLayout.VERTICAL);
        p.setBackground(bg(0xF216233A, 14));
        p.setPadding(dp(12), dp(8), dp(12), dp(8));
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(dp(300), ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.gravity = Gravity.CENTER;
        p.setLayoutParams(lp);

        // 标题行
        LinearLayout titleRow = new LinearLayout(app);
        titleRow.setOrientation(LinearLayout.HORIZONTAL);
        TextView title = new TextView(app);
        title.setText("小逸");
        title.setTextColor(C_TEXT);
        title.setTextSize(18);
        title.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(0, dp(34), 1);
        title.setLayoutParams(tlp);
        titleRow.addView(title);
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

        // 按钮网格
        LinearLayout grid = new LinearLayout(app);
        grid.setOrientation(LinearLayout.VERTICAL);
        p.addView(grid);

        final TextView bAuto = mkBtn("自动清场", C_BTN);
        final TextView bWin = mkBtn("PVP直接判胜", C_BTN);
        final TextView bSp = mkBtn("无限银币", C_BTN);
        final TextView bInv = mkBtn("无敌", C_BTN);
        final TextView bStop = mkBtn("停止移动", C_BTN);
        final TextView bClear = mkBtn("清场", C_BTN);
        final TextView bHint = mkBtn("音量上打开 / 音量下隐藏", 0xFF1C283C);
        bHint.setTextSize(9);
        bHint.setTextColor(C_DIM);

        View[] rows = new View[]{bAuto, bWin, bSp, bInv, bStop, bHint};
        for (int i = 0; i < rows.length; i += 2) {
            LinearLayout row = new LinearLayout(app);
            row.setOrientation(LinearLayout.HORIZONTAL);
            LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            rp.topMargin = dp(8);
            row.setLayoutParams(rp);
            View l = rows[i];
            row.addView(l, new LinearLayout.LayoutParams(0, dp(40), 1));
            if (i + 1 < rows.length) {
                View r = rows[i + 1];
                LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(0, dp(40), 1);
                rlp.leftMargin = dp(8);
                row.addView(r, rlp);
            } else {
                View spacer = new View(app);
                LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(0, dp(40), 1);
                slp.leftMargin = dp(8);
                row.addView(spacer, slp);
            }
            grid.addView(row);
        }

        // 清场按钮单独加（放在网格后，作为整行）
        // 说明：上面 6 个格子已包含“清场”位（bClear 未使用），把 bClear 换成停止移动下方的独立行
        // 简化：不使用 bClear，保持 6 格布局

        // 加速滑条
        p.addView(makeLabel("加速: " + ((int) savedSpeed) + "x"));
        SeekBar speedBar = new SeekBar(app);
        speedBar.setMax(9);
        speedBar.setProgress(Math.max(0, Math.min(9, ((int) savedSpeed) - 1)));
        final TextView speedLabel = (TextView) p.getChildAt(p.getChildCount() - 1);
        speedBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            public void onProgressChanged(SeekBar sb, int prog, boolean fromUser) {
                speedLabel.setText("加速: " + (prog + 1) + "x");
            }
            public void onStartTrackingTouch(SeekBar sb) {}
            public void onStopTrackingTouch(SeekBar sb) {
                float v = sb.getProgress() + 1;
                savedSpeed = v;
                sp.edit().putFloat("speed", v).apply();
                Native.speed(v);
            }
        });
        p.addView(speedBar);

        // 怪物血量滑条
        p.addView(makeLabel("怪物血量: 100%"));
        final TextView hpLabel = (TextView) p.getChildAt(p.getChildCount() - 1);
        SeekBar hpBar = new SeekBar(app);
        hpBar.setMax(99);
        hpBar.setProgress(99);
        hpBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            public void onProgressChanged(SeekBar sb, int prog, boolean fromUser) {
                hpLabel.setText("怪物血量: " + (prog + 1) + "%");
            }
            public void onStartTrackingTouch(SeekBar sb) {}
            public void onStopTrackingTouch(SeekBar sb) {
                Native.monsterHp(sb.getProgress() + 1);
            }
        });
        p.addView(hpBar);

        // 属性滑条（暴击 / 爆伤 / 伤害加成）
        addAttrSlider(p, "暴击", "暴击");
        addAttrSlider(p, "爆伤", "爆伤");
        addAttrSlider(p, "伤害加成", "伤害加成");

        // 底部：到期 + 解绑
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
        unbind.setTextSize(11);
        unbind.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { doUnbind(unbind); }
        });
        foot.addView(unbind, new LinearLayout.LayoutParams(dp(76), dp(30)));
        p.addView(foot);

        // 事件绑定
        bAuto.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                autoClear = !autoClear;
                bAuto.setBackground(bg(autoClear ? C_ON : C_BTN, 8));
            }
        });
        bSp.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                autoSp = !autoSp;
                bSp.setBackground(bg(autoSp ? C_ON : C_BTN, 8));
                if (autoSp) Native.sp();
            }
        });
        bInv.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                autoInv = !autoInv;
                bInv.setBackground(bg(autoInv ? C_ON : C_BTN, 8));
                if (autoInv) Native.inv();
            }
        });
        bWin.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { Native.win(); }
        });
        bStop.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { Native.stopMove(); }
        });
        bClear.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) { Native.clear(); }
        });
        // 应用记忆的加速
        if (savedSpeed > 1f) Native.speed(savedSpeed);

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

    static final Runnable loopTask = new Runnable() {
        public void run() {
            if (licensed) {
                if (autoClear) Native.clear();
                if (autoSp) Native.sp();
                if (autoInv) Native.inv();
                if (savedSpeed > 1f) Native.speed(savedSpeed);
            }
            H.postDelayed(this, 2000);
        }
    };

    // ---------------- 卡密 ----------------
    static void licenseCheck() {
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
