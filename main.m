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
#include <mach-o/loader.h>
#include <dispatch/dispatch.h>
#import <UIKit/UIKit.h>

#ifndef RTLD_NOLOAD
#define RTLD_NOLOAD 0x10
#endif

static UIButton* g_awj_ball;
static UIView*   g_awj_panel;
static void awj_build_ui(void);
static void gm_call2(int idx, int quiet);
static void lic_activate_dialog(UIViewController* vc, void (^done)(BOOL, NSString*));

static volatile int g_t_sp  = 0;   // 无限银币/SP（持续，按钮 0）
static volatile int g_t_inv = 0;   // 无敌（持续，按钮 1）

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
static void*            (*x_string_new)(const char*);
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
    RESOLVE(x_string_new, "il2cpp_string_new");
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
static void* g_lua_input_field;    // BattleDebugActionView.luaCodeInput
static void* g_m_exec_lua;         // BattleDebugActionView.OnExecuteLuaClick
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

    g_lua_input_field = x_class_get_field_from_name(dv, "luaCodeInput");
    g_m_exec_lua = x_class_get_method_from_name(dv, "OnExecuteLuaClick", 0);
    LOG("cmd box: field=%d method=%d strnew=%d", g_lua_input_field != NULL,
        g_m_exec_lua != NULL, x_string_new != NULL);

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
            run_on_main(^{ gm_call2(0, 1); });      // 无限银币
        }
        if (tick % 4 == 0) {                         // 每 2 秒
            if (g_t_inv) run_on_main(^{ gm_call2(1, 1); });   // 无敌
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

static UIImage* awj_thumb(void) {
    static UIImage* img = nil;
    if (img) return img;
    CGFloat d = 14;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(d, d), NO, 0);
    [[UIColor whiteColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)] fill];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// ---------------- 卡密 ----------------
static int g_lic_ok = 0;
static NSString* g_lic_exp = nil;
static NSString* g_lock_msg = nil;
static int g_lock_alerted = 0;
static int g_unbind_left = -1;

static NSString* awj_device_id(void) {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    NSString* s = [d stringForKey:@"awj_device_id"];
    if (s.length == 0) {
        s = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        if (s.length == 0) s = [[NSUUID UUID] UUIDString];
        [d setObject:s forKey:@"awj_device_id"];
    }
    return s;
}

static NSString* awj_base_url(void) {
    static NSString* cached = nil;
    if (cached) return cached;
    static volatile unsigned char enc[25] = {
        50,21,28,31,76,113,74,93,70,111,76,80,68,89,109,85,84,90,110,86,80,73,72,89,87
    };
    static volatile unsigned char seed = 0x5A;
    char buf[26];
    for (int i = 0; i < 25; i++) {
        unsigned char k = (unsigned char)(seed + (i * 7) % 31);
        buf[i] = (char)(enc[i] ^ k);
    }
    buf[25] = 0;
    cached = [NSString stringWithUTF8String:buf];
    return cached;
}

static void lic_post(NSString* path, NSDictionary* body, void (^cb)(NSDictionary*)) {
    NSString* urlStr = [awj_base_url() stringByAppendingString:path];
    NSURL* url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    req.timeoutInterval = 8;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData* data, NSURLResponse* resp, NSError* err) {
        NSDictionary* j = nil;
        if (data) {
            id o = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([o isKindOfClass:NSDictionary.class]) j = o;
        }
        NSDictionary* r = j ?: @{@"ok": @NO, @"msg": @"网络错误"};
        dispatch_async(dispatch_get_main_queue(), ^{ cb(r); });
    }] resume];
}

static uint64_t awj_self_hash(void) {
    Dl_info info;
    if (!dladdr((void*)awj_self_hash, &info) || !info.dli_fbase) return 0;
    const struct mach_header_64* hdr = (const struct mach_header_64*)info.dli_fbase;
    const struct load_command* lc = (const struct load_command*)(hdr + 1);
    for (uint32_t i = 0; i < hdr->ncmds; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64* seg = (const struct segment_command_64*)lc;
            if (strcmp(seg->segname, "__TEXT") == 0) {
                const uint8_t* p = (const uint8_t*)hdr;
                uint64_t n = seg->vmsize;
                uint64_t h = 1469598103934665603ULL;
                for (uint64_t k = 0; k < n; k++) {
                    h ^= p[k];
                    h *= 1099511628211ULL;
                }
                return h;
            }
        }
        lc = (const struct load_command*)((const uint8_t*)lc + lc->cmdsize);
    }
    return 0;
}

static void lic_heartbeat(void) {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    NSString* tok = [d stringForKey:@"awj_license_key"];
    if (tok.length == 0) tok = @"";   // 未授权也上报，便于发现破解设备
    NSString* ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    char hb[32];
    snprintf(hb, sizeof(hb), "%016llx", (unsigned long long)awj_self_hash());
    NSString* hashStr = [NSString stringWithUTF8String:hb];
    lic_post(@"/api/heartbeat",
             @{@"token": tok, @"device": awj_device_id(), @"ver": ver, @"hash": hashStr},
             ^(NSDictionary* r){
        if ([r[@"ok"] boolValue]) {
            if (!g_lic_ok) LOG("license restored by heartbeat");
            g_lic_ok = 1;
            g_lock_msg = nil;
            g_lock_alerted = 0;
            return;
        }
        if (![r[@"ok"] boolValue] && [r[@"lock"] boolValue]) {
            g_lic_ok = 0;
            NSString* msg = r[@"msg"] ?: @"授权已失效";
            g_lock_msg = msg;
            LOG("heartbeat lock: %s", [msg UTF8String]);
            if (!g_lock_alerted) {
                g_lock_alerted = 1;
                dispatch_async(dispatch_get_main_queue(), ^{
                    // 关闭已打开的面板，停掉所有持续功能
                    if (g_awj_panel) { [g_awj_panel removeFromSuperview]; g_awj_panel = nil; }
                    g_auto = 0;
                    g_t_sp = 0;
                    g_t_inv = 0;
                    UIViewController* vc = g_awj_host.rootViewController;
                    if (!vc) return;
                    UIAlertController* ac = [UIAlertController alertControllerWithTitle:@"提示"
                                                                               message:g_lock_msg
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                    [ac addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                    [ac addAction:[UIAlertAction actionWithTitle:@"输入卡密" style:UIAlertActionStyleDefault handler:^(UIAlertAction* a){
                        lic_activate_dialog(vc, ^(BOOL ok, NSString* m){ });
                    }]];
                    [vc presentViewController:ac animated:YES completion:nil];
                });
            }
        }
    });
}

static void lic_check(void) {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    NSString* tok = [d stringForKey:@"awj_license_key"];
    if (tok.length == 0) { g_lic_ok = 0; return; }
    lic_post(@"/api/check", @{@"token": tok, @"device": awj_device_id()}, ^(NSDictionary* r){
        if ([r[@"ok"] boolValue]) {
            g_lic_ok = 1;
            g_lic_exp = r[@"expire_text"];
            if (r[@"unbind_left"]) g_unbind_left = [r[@"unbind_left"] intValue];
            [d setObject:g_lic_exp ?: @"" forKey:@"awj_license_expire"];
        } else {
            g_lic_ok = 0;
            g_lock_msg = r[@"msg"] ?: @"授权已失效，请重新激活";
        }
        LOG("license check ok=%d", g_lic_ok);
    });
}

static void lic_activate_dialog(UIViewController* vc, void (^done)(BOOL, NSString*)) {
    if (!vc) return;
    UIAlertController* ac = [UIAlertController alertControllerWithTitle:@"输入卡密"
                                                               message:@"格式：XY-XXXX-XXXX-XXXX-XXXX"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField* tf){
        tf.placeholder = @"卡密";
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"激活" style:UIAlertActionStyleDefault handler:^(UIAlertAction* a){
        NSString* key = [ac.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (key.length == 0) return;
        LOG("activate try");
        lic_post(@"/api/activate", @{@"key": key, @"device": awj_device_id()}, ^(NSDictionary* r){
            BOOL ok = [r[@"ok"] boolValue];
            if (ok) {
                NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
                [d setObject:r[@"token"] ?: @"" forKey:@"awj_license_key"];
                [d setObject:r[@"expire_text"] ?: @"" forKey:@"awj_license_expire"];
                g_lic_ok = 1;
                g_lic_exp = r[@"expire_text"];
                if (r[@"unbind_left"]) g_unbind_left = [r[@"unbind_left"] intValue];
                lic_heartbeat();
            }
            LOG("activate ok=%d", ok);
            done(ok, ok ? nil : (r[@"msg"] ?: @"激活失败"));
        });
    }]];
    [vc presentViewController:ac animated:YES completion:nil];
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

static void exec_cmd(const char* cmd) {
    void* v = view();
    if (!v) { LOG("cmd: no view"); return; }
    if (!g_lua_input_field || !g_m_exec_lua || !x_string_new) { LOG("cmd: api missing"); return; }
    void* inp = NULL;
    x_field_get_value(v, g_lua_input_field, &inp);
    if (!inp) { LOG("cmd: no input field"); return; }
    void* cls = x_object_get_class(inp);
    void* setter = cls ? x_class_get_method_from_name(cls, "set_text", 1) : NULL;
    if (!setter) { LOG("cmd: no set_text"); return; }
    void* s = x_string_new(cmd);
    void* params[1] = { s };
    void* exc = NULL;
    x_runtime_invoke(setter, inp, params, &exc);
    if (exc) { LOG("cmd: set text exc"); return; }
    exc = NULL;
    x_runtime_invoke(g_m_exec_lua, v, NULL, &exc);
    LOG("cmd: %s exc=%d", cmd, exc != NULL);
}

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

static UIColor* awj_off_color(void) { return [UIColor colorWithRed:34/255.0 green:48/255.0 blue:74/255.0 alpha:1]; }
static UIColor* awj_on_color(void)  { return [UIColor colorWithRed:31/255.0 green:174/255.0 blue:140/255.0 alpha:1]; }

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
    CGFloat footerH = 36;
    CGFloat gridH = (CGFloat)gridRows * 46.0f;
    CGFloat rowH = 40.0f;
    CGFloat attrRowH = 46.0f;
    CGFloat attrH = 6 * attrRowH;
    CGFloat contentH = gridH + 16 + rowH + attrH + attrRowH + 12;
    CGFloat sw = g_awj_host.bounds.size.width;
    CGFloat sh = g_awj_host.bounds.size.height;
    // 只露出 1 个属性行，其余靠滚动
    CGFloat hgt = MIN(36 + gridH + 16 + rowH + 1 * attrRowH + footerH + 8, sh * 0.8f);

    UIView* p = [[UIView alloc] initWithFrame:CGRectMake((sw - w) / 2, (sh - hgt) / 2, w, hgt)];
    p.backgroundColor = [UIColor colorWithRed:14/255.0 green:27/255.0 blue:46/255.0 alpha:0.94];
    p.layer.cornerRadius = 14;
    p.layer.borderWidth = 1;
    p.layer.borderColor = [UIColor colorWithRed:90/255.0 green:150/255.0 blue:220/255.0 alpha:0.5].CGColor;

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

    CGFloat listH = hgt - 36 - footerH;
    UIScrollView* sv = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 36, w, listH)];
    sv.showsVerticalScrollIndicator = YES;
    sv.contentSize = CGSizeMake(w, contentH);
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

    UIButton* winBtn = awj_btn(@"PVP直接判胜", awj_off_color(), ^{
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

    volatile int* tflags[2] = { &g_t_sp, &g_t_inv };

    for (int i = 0; i < GM_BTN_COUNT; i++) {
        int idx = i;
        volatile int* flag = (i < 2) ? tflags[i] : NULL;
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

    // ---- 命令输入行 ----
    CGFloat extraY = 6 + gridH + 16;

    // 加速滑条（第 7 项）
    UILabel* spdLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, extraY + 8, 100, 24)];
    spdLabel.text = @"加速: 1x";
    spdLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
    spdLabel.font = [UIFont boldSystemFontOfSize:13];
    [sv addSubview:spdLabel];

    UISlider* spdSlider = [[UISlider alloc] initWithFrame:CGRectMake(116, extraY + 11, w - 126, 18)];
    spdSlider.minimumValue = 1.0f;
    spdSlider.maximumValue = 20.0f;
    float savedSpd = [[NSUserDefaults standardUserDefaults] floatForKey:@"awj_speed"];
    if (savedSpd < 1.0f || savedSpd > 20.0f) savedSpd = 1.0f;
    spdSlider.value = roundf(savedSpd);
    spdLabel.text = [NSString stringWithFormat:@"加速: %.0fx", spdSlider.value];
    spdSlider.minimumTrackTintColor = [UIColor colorWithRed:0.15 green:0.6 blue:0.5 alpha:1];
    [spdSlider setThumbImage:awj_thumb() forState:UIControlStateNormal];
    [spdSlider setThumbImage:awj_thumb() forState:UIControlStateHighlighted];
    [spdSlider addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        float v = roundf(spdSlider.value);
        if (v < 1) v = 1;
        if (v > 20) v = 20;
        spdSlider.value = v;
        spdLabel.text = [NSString stringWithFormat:@"加速: %.0fx", v];
        [[NSUserDefaults standardUserDefaults] setFloat:v forKey:@"awj_speed"];
        run_on_main(^{ do_set_speed(v); });
    }] forControlEvents:UIControlEventValueChanged];
    [spdSlider addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        LOG("speed set %.0f", spdSlider.value);
    }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [sv addSubview:spdSlider];

    NSArray* attrs = @[@"暴击", @"爆伤", @"伤害加成", @"最终攻击力千分比",
                       @"物理攻击", @"攻速"];

    for (int a = 0; a < (int)attrs.count; a++) {
        NSString* name = attrs[a];
        CGFloat ry = extraY + rowH + 6 + a * attrRowH;

        UILabel* nameLab = [[UILabel alloc] initWithFrame:CGRectMake(10, ry + 2, 170, 18)];
        nameLab.text = name;
        nameLab.textColor = [UIColor colorWithWhite:0.9 alpha:1];
        nameLab.font = [UIFont boldSystemFontOfSize:12];
        nameLab.adjustsFontSizeToFitWidth = YES;
        nameLab.minimumScaleFactor = 0.65;
        [sv addSubview:nameLab];

        UILabel* valLab = [[UILabel alloc] initWithFrame:CGRectMake(w - 92, ry + 2, 72, 18)];
        valLab.text = @"0";
        valLab.textColor = [UIColor colorWithWhite:0.85 alpha:1];
        valLab.font = [UIFont systemFontOfSize:12];
        valLab.textAlignment = NSTextAlignmentRight;
        [sv addSubview:valLab];

        UISlider* sl = [[UISlider alloc] initWithFrame:CGRectMake(10, ry + 22, w - 20, 18)];
        sl.minimumValue = 0;
        sl.maximumValue = 1000;
        sl.minimumTrackTintColor = [UIColor colorWithRed:0.15 green:0.6 blue:0.5 alpha:1];
        [sl setThumbImage:awj_thumb() forState:UIControlStateNormal];
        [sl setThumbImage:awj_thumb() forState:UIControlStateHighlighted];

        NSString* keepKey = [NSString stringWithFormat:@"awj_attr_%@", name];
        NSUserDefaults* ud = [NSUserDefaults standardUserDefaults];
        float savedVal = [ud floatForKey:keepKey];
        if (savedVal > 0 && savedVal <= 1000) {
            sl.value = roundf(savedVal);
            valLab.text = [NSString stringWithFormat:@"%d", (int)(roundf(savedVal)) * 1000];
        } else {
            sl.value = 0;
            valLab.text = @"0";
        }

        [sl addAction:[UIAction actionWithHandler:^(__kindof UIAction* a2){
            int v = (int)(roundf(sl.value)) * 1000;
            sl.value = v / 1000;
            valLab.text = [NSString stringWithFormat:@"%d", v];
            [[NSUserDefaults standardUserDefaults] setFloat:sl.value forKey:keepKey];
        }] forControlEvents:UIControlEventValueChanged];
        [sl addAction:[UIAction actionWithHandler:^(__kindof UIAction* a2){
            int v = (int)(roundf(sl.value)) * 1000;
            if (v <= 0) return;
            NSString* c = [NSString stringWithFormat:@"修改英雄属性 %@ %d", name, v];
            LOG("cmd attr %@ %d", name, v);
            run_on_main(^{ exec_cmd([c UTF8String]); });
        }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [sv addSubview:sl];
    }

    // 怪物血量滑条（放到最下面）
    CGFloat hy = extraY + rowH + attrH + 12;
    UILabel* hpLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, hy + 2, 200, 18)];
    hpLabel.text = @"怪物血量: 100%";
    hpLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
    hpLabel.font = [UIFont boldSystemFontOfSize:12];
    hpLabel.adjustsFontSizeToFitWidth = YES;
    hpLabel.minimumScaleFactor = 0.7;
    [sv addSubview:hpLabel];

    UISlider* hpSlider = [[UISlider alloc] initWithFrame:CGRectMake(10, hy + 22, w - 20, 18)];
    hpSlider.minimumValue = 1;
    hpSlider.maximumValue = 100;
    hpSlider.value = 100;
    hpSlider.minimumTrackTintColor = [UIColor colorWithRed:0.75 green:0.45 blue:0.15 alpha:1];
    [hpSlider setThumbImage:awj_thumb() forState:UIControlStateNormal];
    [hpSlider setThumbImage:awj_thumb() forState:UIControlStateHighlighted];
    [hpSlider addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        int pct = (int)roundf(hpSlider.value);
        hpSlider.value = pct;
        hpLabel.text = [NSString stringWithFormat:@"怪物血量: %d%%", pct];
    }] forControlEvents:UIControlEventValueChanged];
    [hpSlider addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        int pct = (int)roundf(hpSlider.value);
        NSString* c = [NSString stringWithFormat:@"设置怪物血量百分比 %d", pct];
        LOG("cmd hp %d", pct);
        run_on_main(^{ exec_cmd([c UTF8String]); });
    }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [sv addSubview:hpSlider];

    // ---- 卡密区域（预留） ----
    UIView* footer = [[UIView alloc] initWithFrame:CGRectMake(0, hgt - footerH, w, footerH)];
    footer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.22];
    [p addSubview:footer];

    UIButton* licBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    licBtn.frame = CGRectMake(10, 8, w - 92, 20);
    licBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    licBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    [licBtn setTitleColor:[UIColor colorWithWhite:0.85 alpha:1] forState:UIControlStateNormal];
    if (g_lic_ok) {
        [licBtn setTitle:[NSString stringWithFormat:@"卡密到期: %@", g_lic_exp ?: @""]
                forState:UIControlStateNormal];
    } else {
        [licBtn setTitle:@"未激活，点此输入卡密" forState:UIControlStateNormal];
    }
    [footer addSubview:licBtn];

    __weak UIButton* weakLic = licBtn;
    [licBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        if (g_lic_ok) return;
        lic_activate_dialog(g_awj_host.rootViewController, ^(BOOL ok, NSString* msg){
            if (ok) {
                [weakLic setTitle:[NSString stringWithFormat:@"卡密到期: %@", g_lic_exp ?: @""]
                         forState:UIControlStateNormal];
            } else {
                LOG("activation failed: %s", msg.UTF8String);
            }
        });
    }] forControlEvents:UIControlEventTouchUpInside];

    NSString* unbindTitle = g_unbind_left >= 0
        ? [NSString stringWithFormat:@"解绑(%d)", g_unbind_left]
        : @"解绑";
    UIButton* unbindBtn = awj_btn(unbindTitle, awj_off_color(), ^{});
    unbindBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    unbindBtn.layer.cornerRadius = 6;
    unbindBtn.frame = CGRectMake(w - 86, 6, 74, 24);
    [footer addSubview:unbindBtn];

    [unbindBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
        NSString* tok = [d stringForKey:@"awj_license_key"];
        if (tok.length == 0) return;
        lic_post(@"/api/unbind", @{@"token": tok}, ^(NSDictionary* r){
            if ([r[@"ok"] boolValue]) {
                [d removeObjectForKey:@"awj_license_key"];
                [d removeObjectForKey:@"awj_license_expire"];
                g_lic_ok = 0;
                g_lic_exp = nil;
                if (r[@"unbind_left"]) {
                    g_unbind_left = [r[@"unbind_left"] intValue];
                    [unbindBtn setTitle:[NSString stringWithFormat:@"解绑(%d)", g_unbind_left]
                               forState:UIControlStateNormal];
                }
                [weakLic setTitle:@"未激活，点此输入卡密" forState:UIControlStateNormal];
                LOG("license unbound");
            } else {
                LOG("unbind failed: %s", [r[@"msg"] ?: @"?" UTF8String]);
            }
        });
    }] forControlEvents:UIControlEventTouchUpInside];

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
    ball.frame = CGRectMake(sw - 60, 240, 44, 44);
    ball.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:1 alpha:0.9];
    [ball setTitle:@"逸" forState:UIControlStateNormal];
    [ball setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    ball.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    ball.layer.cornerRadius = 22;
    ball.layer.borderWidth = 1.5;
    ball.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
    [ball addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        if (!g_lic_ok) {
            UIViewController* vc = g_awj_host.rootViewController;
            if (g_lock_msg.length > 0 && vc) {
                UIAlertController* ac = [UIAlertController alertControllerWithTitle:@"提示"
                                                                           message:g_lock_msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
                [ac addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                [ac addAction:[UIAlertAction actionWithTitle:@"输入卡密" style:UIAlertActionStyleDefault handler:^(UIAlertAction* a){
                    lic_activate_dialog(vc, ^(BOOL ok, NSString* msg){
                        if (ok) awj_toggle_panel();
                    });
                }]];
                [vc presentViewController:ac animated:YES completion:nil];
                return;
            }
            lic_activate_dialog(vc, ^(BOOL ok, NSString* msg){
                if (ok) awj_toggle_panel();
                else LOG("activation failed: %s", msg.UTF8String);
            });
            return;
        }
        awj_toggle_panel();
    }] forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:ball];
    awj_make_draggable(ball, ball);
    g_awj_ball = ball;

    LOG("ui built on game window");
}

__attribute__((constructor))
static void awj_init(void) {
    const char* home = getenv("HOME");
    LOG("loaded pid=%d home=%s", getpid(), home ? home : "?");
    lic_check();
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        usleep(12 * 1000000);
        for (;;) {
            lic_heartbeat();
            usleep(300 * 1000000);
        }
    });
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
