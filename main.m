// awj tweak: 清场 / 攻速 / 直接判胜，通过 UDP 端口 27043 控制
// 编译: xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=13.0 \
//         -dynamiclib -O2 -fblocks -o awj.dylib main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <dlfcn.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <mach-o/dyld.h>
#include <dispatch/dispatch.h>
#import <UIKit/UIKit.h>

#ifndef RTLD_NOLOAD
#define RTLD_NOLOAD 0x10
#endif

static UIButton* g_awj_ball;
static UIView*   g_awj_panel;
static void awj_build_ui(void);
static void gm_call2(int idx, int quiet);

static volatile int g_t_atk = 0;   // 增加攻速（持续）
static volatile int g_t_sp  = 0;   // 无限银币/SP（持续）
static volatile int g_t_inv = 0;   // 无敌（持续）

#define TAG "[AWJ] "
static FILE* g_log;
static void log_file(void) {
    if (g_log) return;
    const char* home = getenv("HOME");
    char path[512];
    if (home) snprintf(path, sizeof(path), "%s/Documents/awj.log", home);
    else snprintf(path, sizeof(path), "/tmp/awj.log");
    g_log = fopen(path, "a");
}

#define LOGRING 10
static char g_ring[LOGRING][80];
static int g_ring_n = 0;

static void ring_add(const char* s) {
    strncpy(g_ring[g_ring_n % LOGRING], s, 79);
    g_ring[g_ring_n % LOGRING][79] = 0;
    g_ring_n++;
}

#include <stdarg.h>
static void log_msg(const char* fmt, ...) {
    char buf[80];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    log_file();
    if (g_log) { fprintf(g_log, TAG "%s\n", buf); fflush(g_log); }
    NSLog(@"[AWJ] %s", buf);
    ring_add(buf);
}
#define LOG(...) log_msg(__VA_ARGS__)

// ---------------- il2cpp 接口 ----------------
static void*            (*x_domain_get)(void);
static void**           (*x_domain_get_assemblies)(void*, size_t*);
static void*            (*x_assembly_get_image)(void*);
static const char*      (*x_image_get_name)(void*);
static void*            (*x_class_from_name)(void*, const char*, const char*);
static void*            (*x_class_get_method_from_name)(void*, const char*, int);
static const char*      (*x_class_get_name)(void*);
static void*            (*x_object_get_class)(void*);
static void*            (*x_class_get_field_from_name)(void*, const char*);
static size_t           (*x_field_get_offset)(void*);
static void             (*x_field_static_get_value)(void*, void*);
static void             (*x_field_get_value)(void*, void*, void*);
static void             (*x_field_set_value)(void*, void*, void*);
static void*            (*x_runtime_invoke)(void*, void*, void**, void**);

static void* sym(const char* name) {
    void* p = dlsym(RTLD_DEFAULT, name);
    if (p) return p;
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char* in = _dyld_get_image_name(i);
        if (!in || !strstr(in, "UnityFramework")) continue;
        void* h = dlopen(in, RTLD_LAZY | RTLD_NOLOAD);
        if (!h) h = dlopen(in, RTLD_LAZY);
        if (!h) continue;
        p = dlsym(h, name);
        if (p) return p;
    }
    return NULL;
}

#define RESOLVE(var, name) do { var = (void*)sym(name); if (!var) { LOG("missing %s", name); } } while (0)

static int resolve_api(void) {
    RESOLVE(x_domain_get, "il2cpp_domain_get");
    RESOLVE(x_domain_get_assemblies, "il2cpp_domain_get_assemblies");
    RESOLVE(x_assembly_get_image, "il2cpp_assembly_get_image");
    RESOLVE(x_image_get_name, "il2cpp_image_get_name");
    RESOLVE(x_class_from_name, "il2cpp_class_from_name");
    RESOLVE(x_class_get_method_from_name, "il2cpp_class_get_method_from_name");
    RESOLVE(x_class_get_name, "il2cpp_class_get_name");
    RESOLVE(x_object_get_class, "il2cpp_object_get_class");
    RESOLVE(x_class_get_field_from_name, "il2cpp_class_get_field_from_name");
    RESOLVE(x_field_get_offset, "il2cpp_field_get_offset");
    RESOLVE(x_field_static_get_value, "il2cpp_field_static_get_value");
    RESOLVE(x_field_get_value, "il2cpp_field_get_value");
    RESOLVE(x_field_set_value, "il2cpp_field_set_value");
    RESOLVE(x_runtime_invoke, "il2cpp_runtime_invoke");
    return x_domain_get && x_runtime_invoke && x_class_from_name;
}

// ---------------- 游戏对象 ----------------
static void* g_image;
static void* g_dv_class;           // BattleDebugActionView 类
static void* g_main_panel_field;   // BattleDefine.mainPanel (static)
static void* g_view_field;         // BattleMainPanel.battleDebugActionView
static size_t g_view_offset;
static void* g_m_kill_monster;     // BattleDebugActionView.OnKillMonster
static void* g_m_cheat;            // BattleDebugActionView.OnCheatClick
static void* g_m_kill_robot;       // BattleDebugActionView.OnKillRobotClick
static void* g_bpvp_field;         // BaseViewExtend.battlePvpProxy (static)
static void* g_m_set_result;       // BattlePvpProxy.SetBattleResult(BattleResult, bool)
static void* g_bproxy_field;       // BattlePvpProxy.battleProxy (instance)
static void* g_m_is_pvp;           // BattleProxy.IsPvp()
static void* g_level_field;        // BaseViewExtend.battleLevelProxy (static)
static void* g_maxround_field;     // BattleLevelProxy.maxRound
static void* g_round_field;        // BattlePvpProxy.round
static void* g_ls_field;           // BaseViewExtend.battleLockStepCtrl (static)
static void* g_m_set_speed;        // BattleLockStepCtrl.SetSpeedUpRate(float)
static void* g_maxframes_field;    // BattleLockStepCtrl.maxLogicFramesPerTick
static void* g_speed_field;        // BattleLockStepCtrl.speedUpRate
static void* g_m_get_entity;       // BattleEntityProxy.GetEntity
static void* g_proxy_field;        // BattleReduceHpCtrl.battleEntityProxy
static size_t g_proxy_offset;

static void* class_of(void* image, const char* name) {
    return x_class_from_name(image, "Game.Bussiness", name);
}

static char  g_img_hint[150];
static int   g_img_count = 0;

static void* find_image(const char* prefix) {
    void* d = x_domain_get();
    if (!d) return NULL;
    size_t cnt = 0;
    void** asms = x_domain_get_assemblies(d, &cnt);
    if (!asms) return NULL;
    g_img_count = (int)cnt;
    g_img_hint[0] = 0;

    void* exact = NULL;
    void* loose = NULL;
    for (size_t i = 0; i < cnt; i++) {
        void* img = x_assembly_get_image(asms[i]);
        if (!img) continue;
        const char* nm = x_image_get_name(img);
        if (!nm) continue;

        if (strstr(nm, "CSharp") && strlen(g_img_hint) < 120) {
            if (g_img_hint[0]) strncat(g_img_hint, ",", sizeof(g_img_hint)-strlen(g_img_hint)-1);
            strncat(g_img_hint, nm, sizeof(g_img_hint)-strlen(g_img_hint)-1);
        }

        if (strcmp(nm, "Assembly-CSharp.dll") == 0) exact = img;
        else if (!loose && !strstr(nm, "firstpass") &&
                 strncmp(nm, prefix, strlen(prefix)) == 0) loose = img;
    }
    return exact ? exact : loose;
}

// ---------------- GM 方法表 ----------------
typedef struct {
    const char* title;
    const char* method;
    int argc;
    int arg;
} GmBtn;

static const GmBtn kGmBtns[] = {
    {"增加攻速",              "OnCheatClick", 0, 0},
    {"无限银币",              "OnSpClick", 0, 0},
    {"无敌",                  "OnSelfInvulnerableStationClick", 0, 0},
    {"停止移动",              "OnStopMonsterMoveClicked", 0, 0},
};

#define GM_BTN_COUNT ((int)(sizeof(kGmBtns) / sizeof(kGmBtns[0])))
static void* g_gm_fn[GM_BTN_COUNT];

static int g_miss_logged = 0;
static int g_img_logged = 0;
static unsigned g_cls_mask = 0;

static int resolve_game(void) {
    g_image = find_image("Assembly-CSharp");
    if (!g_image) {
        if (g_miss_logged < 3) { g_miss_logged++; LOG("miss: no Assembly-CSharp image"); }
        return 0;
    }

    if (!g_img_logged) {
        g_img_logged = 1;
        LOG("img ok n=%d hint=%s", g_img_count, g_img_hint);
    }

    void* bd  = class_of(g_image, "BattleDefine");
    void* mp  = class_of(g_image, "BattleMainPanel");
    void* dv  = class_of(g_image, "BattleDebugActionView");
    void* rc  = class_of(g_image, "BattleReduceHpCtrl");
    void* ep  = class_of(g_image, "BattleEntityProxy");
    g_cls_mask = (bd?1:0) | (mp?2:0) | (dv?4:0) | (rc?8:0) | (ep?16:0);
    if (!bd || !mp || !dv || !rc || !ep) {
        if (g_miss_logged < 3) {
            g_miss_logged++;
            LOG("miss class mask=%u hint=%s", g_cls_mask, g_img_hint);
        }
        return 0;
    }

    g_main_panel_field = x_class_get_field_from_name(bd, "mainPanel");
    g_view_field       = x_class_get_field_from_name(mp, "battleDebugActionView");
    g_proxy_field      = x_class_get_field_from_name(rc, "battleEntityProxy");
    if (!g_main_panel_field || !g_view_field || !g_proxy_field) return 0;
    g_view_offset      = x_field_get_offset(g_view_field);
    g_proxy_offset     = x_field_get_offset(g_proxy_field);

    void* m1 = x_class_get_method_from_name(dv, "OnKillMonster", 0);
    void* m2 = x_class_get_method_from_name(dv, "OnCheatClick", 0);
    void* m3 = x_class_get_method_from_name(dv, "OnKillRobotClick", 1);
    void* m4 = x_class_get_method_from_name(ep, "GetEntity", 1);
    if (!m1 || !m2 || !m3 || !m4) return 0;
    g_m_kill_monster = m1; g_m_cheat = m2; g_m_kill_robot = m3; g_m_get_entity = m4;
    g_dv_class = dv;

    void* bve = class_of(g_image, "BaseViewExtend");
    void* bpp = class_of(g_image, "BattlePvpProxy");
    void* bp  = class_of(g_image, "BattleProxy");
    if (bve) g_bpvp_field = x_class_get_field_from_name(bve, "battlePvpProxy");
    if (bpp) {
        g_m_set_result = x_class_get_method_from_name(bpp, "SetBattleResult", 2);
        g_bproxy_field = x_class_get_field_from_name(bpp, "battleProxy");
    }
    if (bp) g_m_is_pvp = x_class_get_method_from_name(bp, "IsPvp", 0);

    void* lsc = class_of(g_image, "BattleLockStepCtrl");
    if (bve) g_ls_field = x_class_get_field_from_name(bve, "battleLockStepCtrl");
    if (lsc) {
        g_m_set_speed = x_class_get_method_from_name(lsc, "SetSpeedUpRate", 1);
        g_maxframes_field = x_class_get_field_from_name(lsc, "maxLogicFramesPerTick");
        g_speed_field = x_class_get_field_from_name(lsc, "speedUpRate");
    }
    LOG("speed api: ls=%d m=%d rate=%d max=%d", g_ls_field != NULL,
        g_m_set_speed != NULL, g_speed_field != NULL, g_maxframes_field != NULL);

    void* blp = class_of(g_image, "BattleLevelProxy");
    if (bve) g_level_field = x_class_get_field_from_name(bve, "battleLevelProxy");
    if (blp) g_maxround_field = x_class_get_field_from_name(blp, "maxRound");
    if (bpp) g_round_field = x_class_get_field_from_name(bpp, "round");
    int gm_ok = 0;
    for (int i = 0; i < GM_BTN_COUNT; i++) {
        g_gm_fn[i] = x_class_get_method_from_name(dv, kGmBtns[i].method, kGmBtns[i].argc);
        if (g_gm_fn[i]) gm_ok++;
    }
    LOG("set_result=%d is_pvp=%d gm=%d/%d", g_m_set_result != NULL,
        g_m_is_pvp != NULL, gm_ok, GM_BTN_COUNT);

    LOG("game resolved");
    return 1;
}

static void* view(void) {
    if (!g_main_panel_field) return NULL;
    void* panel = NULL;
    x_field_static_get_value(g_main_panel_field, &panel);
    if (!panel) return NULL;
    void* v = NULL;
    x_field_get_value(panel, g_view_field, &v);   // (obj, field, out)
    return v;
}

static void invoke0(void* method, void* obj, const char* what) {
    if (!method) return;
    void* exc = NULL;
    x_runtime_invoke(method, obj, NULL, &exc);
    if (exc) LOG("%s exception", what);
}

// ---------------- 命令 ----------------
static volatile int g_auto = 0;
static volatile int g_pending = 0;

static int g_udp_fd = -1;
static struct sockaddr_in g_peer;
static socklen_t g_peer_len = 0;

static void reply(const char* msg) {
    if (g_udp_fd >= 0 && g_peer_len > 0)
        sendto(g_udp_fd, msg, strlen(msg), 0, (struct sockaddr*)&g_peer, g_peer_len);
}

static void do_clear(void) {
    void* v = view();
    if (!v) { LOG("clear: no view (not in battle?)"); return; }
    invoke0(g_m_kill_monster, v, "clear");
    LOG("clear done");
}

static void do_cheat(void) {
    void* v = view();
    if (!v) { LOG("cheat: no view"); return; }
    invoke0(g_m_cheat, v, "cheat");
    LOG("cheat done");
}

static int is_pvp_battle(void) {
    // 返回 1=PVP, 0=非PVP, -1=无法判断
    if (!g_bpvp_field || !g_bproxy_field || !g_m_is_pvp) return -1;
    void* proxy = NULL;
    x_field_static_get_value(g_bpvp_field, &proxy);
    if (!proxy) return -1;
    void* bp = NULL;
    x_field_get_value(proxy, g_bproxy_field, &bp);
    if (!bp) return -1;
    void* exc = NULL;
    void* r = x_runtime_invoke(g_m_is_pvp, bp, NULL, &exc);
    if (exc || !r) return -1;
    return *(uint8_t*)r ? 1 : 0;
}

static void do_win(void) {
    int pvp = is_pvp_battle();
    LOG("win: pvp=%d", pvp);

    if (pvp != 0) {
        // PVP：直接设置结果为胜利
        void* proxy = NULL;
        x_field_static_get_value(g_bpvp_field, &proxy);
        if (proxy && g_m_set_result) {
            int32_t r = 1;
            uint8_t force = 1;
            void* params[2] = { &r, &force };
            void* exc = NULL;
            x_runtime_invoke(g_m_set_result, proxy, params, &exc);
            if (!exc) { LOG("win done (pvp set_result)"); return; }
            LOG("win: set_result exception");
        }
    }

    // 非 PVP：把当前回合设为最后一回合，再清场，让游戏走正常结算
    if (g_level_field && g_maxround_field && g_round_field && x_field_set_value) {
        void* pp = NULL;
        void* lp = NULL;
        x_field_static_get_value(g_bpvp_field, &pp);
        x_field_static_get_value(g_level_field, &lp);
        if (pp && lp) {
            int32_t cur = 0;
            x_field_get_value(pp, g_round_field, &cur);
            int32_t mr = 9999;
            x_field_get_value(lp, g_maxround_field, &mr);
            if (cur > 0 && cur != mr) {
                int32_t set = cur;
                x_field_set_value(lp, g_maxround_field, &set);
                LOG("win: maxRound %d -> %d", mr, cur);
            } else {
                LOG("win: round=%d maxRound=%d (no change)", cur, mr);
            }
        }
    }

    void* v = view();
    if (!v) { LOG("win: no view"); return; }
    invoke0(g_m_kill_monster, v, "win-clear");
    LOG("win done (pve clear)");
}

// 主线程执行游戏调用
static void run_on_main(void (^block)(void)) {
    dispatch_async(dispatch_get_main_queue(), block);
}

static void handle(const char* cmd) {
    if (!g_m_kill_monster) { resolve_api(); resolve_game(); }
    if (!strcmp(cmd, "1")) { reply("ok:clear"); run_on_main(^{ do_clear(); }); }
    else if (!strcmp(cmd, "2")) { reply("ok:cheat"); run_on_main(^{ do_cheat(); }); }
    else if (!strcmp(cmd, "3")) { reply("ok:win"); run_on_main(^{ do_win(); }); }
    else if (!strcmp(cmd, "a1")) { g_auto = 1; LOG("auto on"); reply("ok:auto1"); }
    else if (!strcmp(cmd, "a0")) { g_auto = 0; LOG("auto off"); reply("ok:auto0"); }
    else if (!strcmp(cmd, "s")) {
        char b[160];
        snprintf(b, sizeof(b), "ready=%d mask=%u img=%d n=%d auto=%d battle=%d",
                 g_m_kill_monster != NULL, g_cls_mask, g_image != NULL,
                 g_img_count, g_auto, view() != NULL);
        LOG("status %s", b);
        reply(b);
    }
    else if (!strcmp(cmd, "i")) {
        reply(g_img_hint[0] ? g_img_hint : "no-csharp-image");
    }
    else if (!strcmp(cmd, "u1")) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (g_awj_ball) { g_awj_ball.hidden = NO; } else { awj_build_ui(); }
        });
        reply("ok:ui1");
    }
    else if (!strcmp(cmd, "u0")) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (g_awj_ball) g_awj_ball.hidden = YES;
            if (g_awj_panel) { [g_awj_panel removeFromSuperview]; g_awj_panel = nil; }
        });
        reply("ok:ui0");
    }
    else if (!strcmp(cmd, "l")) {
        char b[300];
        b[0] = 0;
        int total = g_ring_n < LOGRING ? g_ring_n : LOGRING;
        for (int k = 0; k < total; k++) {
            int idx = (g_ring_n - 1 - k + LOGRING * 4) % LOGRING;
            strncat(b, g_ring[idx], sizeof(b) - strlen(b) - 2);
            strncat(b, "|", sizeof(b) - strlen(b) - 1);
            if (strlen(b) > 200) break;
        }
        reply(b[0] ? b : "empty");
    }
    else { LOG("unknown cmd: %s", cmd); reply("err:unknown"); }
}

static void* auto_thread(void* arg) {
    (void)arg;
    int tick = 0;
    while (1) {
        tick++;
        if (g_auto) {
            g_pending = 1;
            run_on_main(^{
                if (g_pending) { g_pending = 0; do_clear(); }
            });
        }
        if (g_t_sp) {
            run_on_main(^{ gm_call2(1, 1); });      // 无限银币
        }
        if (tick % 4 == 0) {                         // 每 2 秒
            if (g_t_atk) run_on_main(^{ gm_call2(0, 1); });   // 增加攻速
            if (g_t_inv) run_on_main(^{ gm_call2(2, 1); });   // 无敌
        }
        usleep(500000);
    }
    return NULL;
}

static void* udp_thread(void* arg) {
    (void)arg;
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) { LOG("socket failed"); return NULL; }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons(27043);
    a.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr*)&a, sizeof(a)) != 0) {
        LOG("udp bind 27043 failed");
        close(fd);
        return NULL;
    }
    LOG("udp listening on 27043");
    g_udp_fd = fd;
    char buf[64];
    for (;;) {
        struct sockaddr_in peer;
        socklen_t pl = sizeof(peer);
        ssize_t n = recvfrom(fd, buf, sizeof(buf)-1, 0, (struct sockaddr*)&peer, &pl);
        if (n <= 0) continue;
        g_peer = peer;
        g_peer_len = pl;
        buf[n] = 0;
        while (n > 0 && (buf[n-1] == '\n' || buf[n-1] == '\r' || buf[n-1] == ' ')) buf[--n] = 0;
        LOG("cmd: %s", buf);
        handle(buf);
    }
    return NULL;
}

// ---------------- 游戏内悬浮面板 ----------------
static UIWindow* g_awj_host;

static UIWindowScene* awj_scene(void) {
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] &&
            s.activationState == UISceneActivationStateForegroundActive)
            return (UIWindowScene*)s;
    }
    return nil;
}

static UIButton* awj_btn(NSString* title, UIColor* bg, void (^h)(void)) {
    UIButton* b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = bg;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    b.layer.cornerRadius = 8;
    [b addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){ h(); }]
        forControlEvents:UIControlEventTouchUpInside];
    return b;
}

static int unity_loaded(void) {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char* nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "UnityFramework")) return 1;
    }
    return 0;
}

static void ensure_resolved(void) {
    if (!unity_loaded()) return;
    if (!x_domain_get) resolve_api();
    if (!g_m_kill_monster && x_domain_get) resolve_game();
}

static void gm_call2(int idx, int quiet) {
    ensure_resolved();
    if (!g_gm_fn[idx] && g_dv_class)
        g_gm_fn[idx] = x_class_get_method_from_name(g_dv_class, kGmBtns[idx].method, kGmBtns[idx].argc);
    void* v = view();
    if (!v) { LOG("gm %s: no view", kGmBtns[idx].method); return; }
    void* fn = g_gm_fn[idx];
    if (!fn) { LOG("gm %s: missing", kGmBtns[idx].method); return; }
    void* exc = NULL;
    if (kGmBtns[idx].argc > 0) {
        int32_t a = kGmBtns[idx].arg;
        void* params[1] = { &a };
        x_runtime_invoke(fn, v, params, &exc);
    } else {
        x_runtime_invoke(fn, v, NULL, &exc);
    }
    if (exc) LOG("gm %s exc", kGmBtns[idx].method);
    else if (!quiet) LOG("gm: %s ok", kGmBtns[idx].method);
}

static void gm_call(int idx) { gm_call2(idx, 0); }

static void do_set_speed(float rate) {
    if (rate <= 0) rate = 1;
    if (!g_ls_field || !g_m_set_speed) { LOG("speed: missing api"); return; }
    void* ls = NULL;
    x_field_static_get_value(g_ls_field, &ls);
    if (!ls) { LOG("speed: no lockstep ctrl"); return; }
    float r = rate;
    void* params[1] = { &r };
    void* exc = NULL;
    x_runtime_invoke(g_m_set_speed, ls, params, &exc);
    if (g_maxframes_field && x_field_set_value) {
        int32_t mf = (int)(rate * 8);
        if (mf < 8) mf = 8;
        if (mf > 64) mf = 64;
        x_field_set_value(ls, g_maxframes_field, &mf);
    }
    float back = -1;
    if (g_speed_field && x_field_get_value) x_field_get_value(ls, g_speed_field, &back);
    LOG("speed set %.1f -> readback %.1f exc=%d", rate, back, exc != NULL);
}

// ---- 拖动支持 ----
@interface AWJPan : NSObject
@property (nonatomic, weak) UIView* target;
- (void)handlePan:(UIPanGestureRecognizer*)g;
@end

@implementation AWJPan
- (void)handlePan:(UIPanGestureRecognizer*)g {
    UIView* v = self.target;
    if (!v) return;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];
}
@end

static NSMutableArray* g_panKeep;

static void awj_make_draggable(UIView* handle, UIView* target) {
    if (!g_panKeep) g_panKeep = [NSMutableArray array];
    AWJPan* ph = [AWJPan new];
    ph.target = target;
    [g_panKeep addObject:ph];
    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc] initWithTarget:ph action:@selector(handlePan:)];
    [handle addGestureRecognizer:pan];
}

static UIColor* awj_off_color(void) { return [UIColor colorWithWhite:0.24 alpha:1]; }
static UIColor* awj_on_color(void)  { return [UIColor colorWithRed:0.15 green:0.58 blue:0.45 alpha:1]; }

static void awj_flash(UIButton* b) {
    b.backgroundColor = awj_on_color();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ b.backgroundColor = awj_off_color(); });
}

static void awj_toggle_panel(void) {
    if (!g_awj_host) return;
    ensure_resolved();
    LOG("panel open ready=%d battle=%d", g_m_kill_monster != NULL, view() != NULL);
    if (g_awj_panel) {
        [g_awj_panel removeFromSuperview];
        g_awj_panel = nil;
        return;
    }

    CGFloat w = 300;
    int gridItems = GM_BTN_COUNT + 2;
    int gridRows = (gridItems + 1) / 2;
    CGFloat rowsH = gridRows * 46 + 66 + 14;
    CGFloat hgt = MIN(600, 44 + rowsH);
    CGFloat sw = g_awj_host.bounds.size.width;
    CGFloat sh = g_awj_host.bounds.size.height;

    UIView* p = [[UIView alloc] initWithFrame:CGRectMake((sw - w) / 2, (sh - hgt) / 2, w, hgt)];
    p.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    p.layer.cornerRadius = 14;
    p.layer.borderWidth = 1;
    p.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;

    UIView* bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 36)];
    [p addSubview:bar];
    awj_make_draggable(bar, p);

    UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(0, 6, w, 24)];
    title.text = @"小逸";
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    [bar addSubview:title];

    UIButton* xBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    xBtn.frame = CGRectMake(w - 38, 3, 32, 30);
    [xBtn setTitle:@"×" forState:UIControlStateNormal];
    [xBtn setTitleColor:[UIColor colorWithWhite:0.85 alpha:1] forState:UIControlStateNormal];
    xBtn.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightLight];
    [xBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){ awj_toggle_panel(); }]
        forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:xBtn];

    CGFloat listH = hgt - 44;
    UIScrollView* sv = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 36, w, listH)];
    sv.showsVerticalScrollIndicator = YES;
    sv.contentSize = CGSizeMake(w, gridRows * 46 + 66 + 8);
    [p addSubview:sv];

    __block int gr = 0, gc = 0;
    CGFloat bw = (w - 28) / 2.0f;
    void (^place)(UIButton*) = ^(UIButton* b){
        b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumScaleFactor = 0.75;
        b.frame = CGRectMake(10 + gc * (bw + 8), 6 + gr * 46, bw, 40);
        gc++;
        if (gc == 2) { gc = 0; gr++; }
        [sv addSubview:b];
    };

    UIButton* autoBtn = awj_btn(@"自动清场", awj_off_color(), ^{});
    autoBtn.backgroundColor = g_auto ? awj_on_color() : awj_off_color();
    place(autoBtn);
    [autoBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        g_auto = !g_auto;
        autoBtn.backgroundColor = g_auto ? awj_on_color() : awj_off_color();
        LOG("auto=%d", g_auto);
    }] forControlEvents:UIControlEventTouchUpInside];

    UIButton* winBtn = awj_btn(@"直接判胜", awj_off_color(), ^{
        ensure_resolved();
        LOG("tap: win");
        run_on_main(^{ do_win(); });
    });
    winBtn.backgroundColor = awj_off_color();
    place(winBtn);
    [winBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ awj_flash(winBtn); });
    }] forControlEvents:UIControlEventTouchUpInside];

    volatile int* tflags[3] = { &g_t_atk, &g_t_sp, &g_t_inv };

    for (int i = 0; i < GM_BTN_COUNT; i++) {
        int idx = i;
        volatile int* flag = (i < 3) ? tflags[i] : NULL;
        UIButton* b = awj_btn([NSString stringWithUTF8String:kGmBtns[i].title], awj_off_color(), ^{});
        b.backgroundColor = (flag && *flag) ? awj_on_color() : awj_off_color();
        place(b);

        if (flag) {
            [b addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
                *flag = *flag ? 0 : 1;
                b.backgroundColor = (*flag) ? awj_on_color() : awj_off_color();
                LOG("toggle %s -> %d", kGmBtns[idx].method, *flag);
                if (*flag) run_on_main(^{ gm_call(idx); });
            }] forControlEvents:UIControlEventTouchUpInside];
        } else {
            [b addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
                LOG("tap: %s", kGmBtns[idx].method);
                run_on_main(^{ gm_call(idx); });
            }] forControlEvents:UIControlEventTouchUpInside];
            [b addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ awj_flash(b); });
            }] forControlEvents:UIControlEventTouchUpInside];
        }
    }

    // 自定义加速滑条 1x - 32x
    CGFloat sliderTop = 6 + gr * 46 + 4;
    UILabel* spdLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, sliderTop, w - 20, 18)];
    spdLabel.text = @"加速: 1.0x";
    spdLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
    spdLabel.font = [UIFont boldSystemFontOfSize:13];
    [sv addSubview:spdLabel];

    UISlider* spdSlider = [[UISlider alloc] initWithFrame:CGRectMake(10, sliderTop + 22, w - 20, 20)];
    spdSlider.minimumValue = 1.0f;
    spdSlider.maximumValue = 32.0f;
    spdSlider.value = 1.0f;
    spdSlider.minimumTrackTintColor = [UIColor colorWithRed:0.15 green:0.6 blue:0.5 alpha:1];
    [spdSlider addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        float v = spdSlider.value;
        spdLabel.text = [NSString stringWithFormat:@"加速: %.1fx", v];
        run_on_main(^{ do_set_speed(v); });
    }] forControlEvents:UIControlEventValueChanged];
    [spdSlider addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        LOG("speed set %.1f", spdSlider.value);
    }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [sv addSubview:spdSlider];

    [g_awj_host addSubview:p];
    g_awj_panel = p;
}

static void awj_build_ui(void) {
    if (g_awj_ball) return;
    UIWindowScene* sc = awj_scene();
    if (!sc) return;

    UIWindow* host = nil;
    for (UIWindow* w in sc.windows) {
        if (w.isKeyWindow) { host = w; break; }
    }
    if (!host) host = sc.windows.firstObject;
    if (!host) return;
    g_awj_host = host;

    CGFloat sw = host.bounds.size.width;
    UIButton* ball = [UIButton buttonWithType:UIButtonTypeSystem];
    ball.frame = CGRectMake(sw - 74, 240, 58, 58);
    ball.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:1 alpha:0.9];
    [ball setTitle:@"逸" forState:UIControlStateNormal];
    [ball setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    ball.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    ball.layer.cornerRadius = 29;
    ball.layer.borderWidth = 1.5;
    ball.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
    [ball addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){ awj_toggle_panel(); }]
        forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:ball];
    awj_make_draggable(ball, ball);
    g_awj_ball = ball;

    LOG("ui built on game window");
}

__attribute__((constructor))
static void awj_init(void) {
    const char* home = getenv("HOME");
    LOG("loaded pid=%d home=%s", getpid(), home ? home : "?");
    pthread_t t;
    pthread_create(&t, NULL, udp_thread, NULL);
    pthread_create(&t, NULL, auto_thread, NULL);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        usleep(15 * 1000000);   // 等游戏加载完再建窗口，避免挡住启动阶段触摸
        for (int i = 0; i < 600 && !g_awj_ball; i++) {
            dispatch_async(dispatch_get_main_queue(), ^{ awj_build_ui(); });
            usleep(500000);
        }
    });
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        usleep(10 * 1000000);   // 等 Unity 运行时初始化稳定
        for (int i = 0; i < 600; i++) {          // 最多等 5 分钟
            if (!unity_loaded()) { usleep(500000); continue; }
            if (!x_domain_get && !resolve_api()) { usleep(500000); continue; }
            if (x_domain_get() && resolve_game()) break;
            usleep(500000);
        }
        if (!g_m_kill_monster) LOG("init incomplete (will retry on command)");
        else LOG("ready");
    });
}
