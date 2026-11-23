// awj tweak: 娓呭満 / 鏀婚€?/ 鐩存帴鍒よ儨锛岄€氳繃 UDP 绔彛 27043 鎺у埗
// 缂栬瘧: xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=13.0 \
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
#define LOG(...) do { \
    log_file(); \
    if (g_log) { fprintf(g_log, TAG __VA_ARGS__); fprintf(g_log, "\n"); fflush(g_log); } \
    fprintf(stderr, TAG __VA_ARGS__); fprintf(stderr, "\n"); \
} while (0)

// ---------------- il2cpp 鎺ュ彛 ----------------
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

// ---------------- 娓告垙瀵硅薄 ----------------
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

static void* find_image(const char* prefix) {
    void* d = x_domain_get();
    if (!d) return NULL;
    size_t cnt = 0;
    void** asms = x_domain_get_assemblies(d, &cnt);
    if (!asms) return NULL;
    for (size_t i = 0; i < cnt; i++) {
        void* img = x_assembly_get_image(asms[i]);
        if (!img) continue;
        const char* nm = x_image_get_name(img);
        if (nm && strncmp(nm, prefix, strlen(prefix)) == 0) return img;
    }
    return NULL;
}

static int g_miss_logged = 0;

static int resolve_game(void) {
    g_image = find_image("Assembly-CSharp");
    if (!g_image) {
        if (g_miss_logged < 3) { g_miss_logged++; LOG("miss: no Assembly-CSharp image"); }
        return 0;
    }

    void* bd  = class_of(g_image, "BattleDefine");
    void* mp  = class_of(g_image, "BattleMainPanel");
    void* dv  = class_of(g_image, "BattleDebugActionView");
    void* rc  = class_of(g_image, "BattleReduceHpCtrl");
    void* ep  = class_of(g_image, "BattleEntityProxy");
    if (!bd || !mp || !dv || !rc || !ep) {
        if (g_miss_logged < 3) {
            g_miss_logged++;
            LOG("miss class: bd=%d mp=%d dv=%d rc=%d ep=%d", bd!=NULL, mp!=NULL, dv!=NULL, rc!=NULL, ep!=NULL);
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

// ---------------- 鍛戒护 ----------------
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

// 涓荤嚎绋嬫墽琛屾父鎴忚皟鐢?static void run_on_main(void (^block)(void)) {
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
        char b[128];
        snprintf(b, sizeof(b), "ready=%d auto=%d battle=%d",
                 g_m_kill_monster != NULL, g_auto, view() != NULL);
        LOG("status %s", b);
        reply(b);
    }
    else { LOG("unknown cmd: %s", cmd); reply("err:unknown"); }
}

static void* auto_thread(void* arg) {
    (void)arg;
    while (1) {
        if (g_auto) {
            // 500ms 涓€娆★紝涓荤嚎绋嬫墽琛?            g_pending = 1;
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

__attribute__((constructor))
static void awj_init(void) {
    const char* home = getenv("HOME");
    LOG("loaded pid=%d home=%s", getpid(), home ? home : "?");
    pthread_t t;
    pthread_create(&t, NULL, udp_thread, NULL);
    pthread_create(&t, NULL, auto_thread, NULL);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        for (int i = 0; i < 600; i++) {          // 鏈€澶氱瓑 5 鍒嗛挓
            if (!x_domain_get && !resolve_api()) { usleep(500000); continue; }
            if (x_domain_get() && resolve_game()) break;
            usleep(500000);
        }
        if (!g_m_kill_monster) LOG("init incomplete (will retry on command)");
        else LOG("ready");
    });
}
