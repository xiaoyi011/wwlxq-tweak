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
    RESOLVE(x_runtime_invoke, "il2cpp_runtime_invoke");
    return x_domain_get && x_runtime_invoke && x_class_from_name;
}

// ---------------- 游戏对象 ----------------
static void* g_image;
static void* g_main_panel_field;   // BattleDefine.mainPanel (static)
static void* g_view_field;         // BattleMainPanel.battleDebugActionView
static size_t g_view_offset;
static void* g_m_kill_monster;     // BattleDebugActionView.OnKillMonster
static void* g_m_cheat;            // BattleDebugActionView.OnCheatClick
static void* g_m_kill_robot;       // BattleDebugActionView.OnKillRobotClick
static void* g_m_get_entity;       // BattleEntityProxy.GetEntity
static void* g_proxy_field;        // BattleReduceHpCtrl.battleEntityProxy
static size_t g_proxy_offset;

static void* class_of(void* image, const char* name) {
    return x_class_from_name(image, "Game.Bussiness", name);
}

static char  g_img_hint[64];
static int   g_img_count = 0;

static void* find_image(const char* prefix) {
    void* d = x_domain_get();
    if (!d) return NULL;
    size_t cnt = 0;
    void** asms = x_domain_get_assemblies(d, &cnt);
    if (!asms) return NULL;
    g_img_count = (int)cnt;
    g_img_hint[0] = 0;
    for (size_t i = 0; i < cnt; i++) {
        void* img = x_assembly_get_image(asms[i]);
        if (!img) continue;
        const char* nm = x_image_get_name(img);
        if (!nm) continue;
        if (strstr(nm, "CSharp") && strlen(g_img_hint) < 50) {
            if (g_img_hint[0]) strncat(g_img_hint, ",", sizeof(g_img_hint)-strlen(g_img_hint)-1);
            strncat(g_img_hint, nm, sizeof(g_img_hint)-strlen(g_img_hint)-1);
        }
        if (strncmp(nm, prefix, strlen(prefix)) == 0) return img;
    }
    return NULL;
}

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

static void do_win(void) {
    void* v = view();
    if (!v) { LOG("win: no view"); return; }
    int star = 3;
    void* params[1] = { &star };
    void* exc = NULL;
    x_runtime_invoke(g_m_kill_robot, v, params, &exc);
    if (exc) LOG("win exception"); else LOG("win done");
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
    while (1) {
        if (g_auto) {
            // 500ms 一次，主线程执行
            g_pending = 1;
            run_on_main(^{
                if (g_pending) { g_pending = 0; do_clear(); }
            });
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
static UIWindow* g_awj_window;
static UIView*   g_awj_panel;

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

static void awj_toggle_panel(void) {
    UIViewController* vc = g_awj_window.rootViewController;
    if (g_awj_panel) {
        [g_awj_panel removeFromSuperview];
        g_awj_panel = nil;
        return;
    }

    CGFloat w = 200, hgt = 320;
    UIView* p = [[UIView alloc] initWithFrame:CGRectMake(12, 180, w, hgt)];
    p.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.93];
    p.layer.cornerRadius = 14;
    p.layer.borderWidth = 1;
    p.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;

    UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, w-24, 22)];
    title.text = @"GM 面板";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:16];
    [p addSubview:title];

    UIButton* autoBtn = nil;

    UIButton* b1 = awj_btn(@"清场（秒杀全部怪）", [UIColor colorWithRed:0.75 green:0.2 blue:0.2 alpha:1], ^{
        reply("panel:clear"); run_on_main(^{ do_clear(); });
    });
    b1.frame = CGRectMake(12, 38, w-24, 44);
    [p addSubview:b1];

    UIButton* b2 = awj_btn(@"全体攻速 +100000", [UIColor colorWithRed:0.2 green:0.45 blue:0.75 alpha:1], ^{
        reply("panel:cheat"); run_on_main(^{ do_cheat(); });
    });
    b2.frame = CGRectMake(12, 88, w-24, 44);
    [p addSubview:b2];

    UIButton* b3 = awj_btn(@"直接判胜（3星）", [UIColor colorWithRed:0.2 green:0.6 blue:0.3 alpha:1], ^{
        reply("panel:win"); run_on_main(^{ do_win(); });
    });
    b3.frame = CGRectMake(12, 138, w-24, 44);
    [p addSubview:b3];

    autoBtn = awj_btn(g_auto ? @"自动清场：开" : @"自动清场：关",
                      [UIColor colorWithWhite:0.28 alpha:1], ^{});
    autoBtn.frame = CGRectMake(12, 188, w-24, 44);
    [p addSubview:autoBtn];
    [autoBtn addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){
        g_auto = !g_auto;
        [autoBtn setTitle:(g_auto ? @"自动清场：开" : @"自动清场：关") forState:UIControlStateNormal];
        reply(g_auto ? "panel:auto1" : "panel:auto0");
    }] forControlEvents:UIControlEventTouchUpInside];

    UIButton* close = awj_btn(@"关闭", [UIColor colorWithWhite:0.35 alpha:1], ^{
        awj_toggle_panel();
    });
    close.frame = CGRectMake(12, 238, w-24, 44);
    [p addSubview:close];

    UILabel* st = [[UILabel alloc] initWithFrame:CGRectMake(12, 286, w-24, 20)];
    st.text = [NSString stringWithFormat:@"ready=%d battle=%d",
               g_m_kill_monster != NULL, view() != NULL];
    st.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    st.font = [UIFont systemFontOfSize:11];
    [p addSubview:st];

    [vc.view addSubview:p];
    g_awj_panel = p;
}

static void awj_build_ui(void) {
    if (g_awj_window) return;
    UIWindowScene* sc = awj_scene();
    if (!sc) return;

    UIWindow* w = [[UIWindow alloc] initWithWindowScene:sc];
    w.windowLevel = UIWindowLevelAlert + 100;
    w.backgroundColor = UIColor.clearColor;
    UIViewController* vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    w.rootViewController = vc;
    w.hidden = NO;
    g_awj_window = w;

    CGFloat sw = sc.coordinateSpace.bounds.size.width;
    UIButton* ball = [UIButton buttonWithType:UIButtonTypeSystem];
    ball.frame = CGRectMake(sw - 74, 240, 58, 58);
    ball.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:1 alpha:0.9];
    [ball setTitle:@"GM" forState:UIControlStateNormal];
    [ball setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    ball.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    ball.layer.cornerRadius = 29;
    ball.layer.borderWidth = 1.5;
    ball.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
    [ball addAction:[UIAction actionWithHandler:^(__kindof UIAction* a){ awj_toggle_panel(); }]
        forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:ball];

    LOG("ui built");
}

__attribute__((constructor))
static void awj_init(void) {
    const char* home = getenv("HOME");
    LOG("loaded pid=%d home=%s", getpid(), home ? home : "?");
    pthread_t t;
    pthread_create(&t, NULL, udp_thread, NULL);
    pthread_create(&t, NULL, auto_thread, NULL);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        for (int i = 0; i < 600 && !g_awj_window; i++) {
            dispatch_async(dispatch_get_main_queue(), ^{ awj_build_ui(); });
            usleep(500000);
        }
    });
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        for (int i = 0; i < 600; i++) {          // 最多等 5 分钟
            if (!x_domain_get && !resolve_api()) { usleep(500000); continue; }
            if (x_domain_get() && resolve_game()) break;
            usleep(500000);
        }
        if (!g_m_kill_monster) LOG("init incomplete (will retry on command)");
        else LOG("ready");
    });
}
