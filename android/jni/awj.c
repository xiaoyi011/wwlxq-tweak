// AWJ Android tweak core: il2cpp runtime calls for the GM panel
#include <jni.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>
#include <dirent.h>
#include <pthread.h>
#include <unistd.h>
#include <android/log.h>

#define TAG "AWJ"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// ---------------- il2cpp ----------------
static void* (*x_domain_get)(void);
static void** (*x_domain_get_assemblies)(void*, size_t*);
static void* (*x_assembly_get_image)(void*);
static const char* (*x_image_get_name)(void*);
static void* (*x_class_from_name)(void*, const char*, const char*);
static void* (*x_class_get_method_from_name)(void*, const char*, int);
static void* (*x_object_get_class)(void*);
static void* (*x_class_get_field_from_name)(void*, const char*);
static size_t (*x_field_get_offset)(void*);
static void (*x_field_static_get_value)(void*, void*);
static void (*x_field_get_value)(void*, void*, void*);
static void (*x_field_set_value)(void*, void*, void*);
static void* (*x_runtime_invoke)(void*, void*, void**, void**);
static void* (*x_string_new)(const char*);
static void* (*x_thread_attach)(void*);
static void* (*x_domain_assembly_open)(void*, const char*);

static void* g_lib;

static void* sym(const char* n) {
    if (!g_lib) g_lib = dlopen("libil2cpp.so", RTLD_NOW);
    if (!g_lib) return NULL;
    return dlsym(g_lib, n);
}

#define RESOLVE(v, n) do { v = (void*)sym(n); if (!v) LOGE("missing %s", n); } while (0)

static int resolve_api(void) {
    RESOLVE(x_domain_get, "il2cpp_domain_get");
    RESOLVE(x_domain_get_assemblies, "il2cpp_domain_get_assemblies");
    RESOLVE(x_assembly_get_image, "il2cpp_assembly_get_image");
    RESOLVE(x_image_get_name, "il2cpp_image_get_name");
    RESOLVE(x_class_from_name, "il2cpp_class_from_name");
    RESOLVE(x_class_get_method_from_name, "il2cpp_class_get_method_from_name");
    RESOLVE(x_object_get_class, "il2cpp_object_get_class");
    RESOLVE(x_class_get_field_from_name, "il2cpp_class_get_field_from_name");
    RESOLVE(x_field_get_offset, "il2cpp_field_get_offset");
    RESOLVE(x_field_static_get_value, "il2cpp_field_static_get_value");
    RESOLVE(x_field_get_value, "il2cpp_field_get_value");
    RESOLVE(x_field_set_value, "il2cpp_field_set_value");
    RESOLVE(x_runtime_invoke, "il2cpp_runtime_invoke");
    RESOLVE(x_string_new, "il2cpp_string_new");
    RESOLVE(x_thread_attach, "il2cpp_thread_attach");
    RESOLVE(x_domain_assembly_open, "il2cpp_domain_assembly_open");
    return x_domain_get && x_runtime_invoke && x_class_from_name;
}

// ---------------- game objects ----------------
static void* g_image;
static void* g_dv_class;
static void* g_main_panel_field;
static void* g_view_field;
static void* g_m_kill_monster;
static void* g_m_cheat;
static void* g_m_kill_robot;
static void* g_m_exec_lua;
static void* g_m_sp;
static void* g_m_inv;
static void* g_lua_input_field;
static void* g_bpvp_field;
static void* g_m_set_result;
static void* g_bproxy_field;
static void* g_m_is_pvp;
static void* g_level_field;
static void* g_maxround_field;
static void* g_round_field;
static void* g_ls_field;
static void* g_m_set_speed;
static void* g_maxframes_field;

static void* class_of(void* image, const char* name) {
    return x_class_from_name(image, "Game.Bussiness", name);
}

static void* find_image(const char* prefix) {
    void* d = x_domain_get();
    if (!d) return NULL;
    if (x_domain_assembly_open) {
        LOGI("opening assembly by name");
        void* a = x_domain_assembly_open(d, "Assembly-CSharp");
        LOGI("assembly=%p", a);
        if (a) {
            void* img = x_assembly_get_image(a);
            LOGI("image=%p", img);
            if (img) return img;
        }
    }
    LOGI("assembly open failed");
    (void)prefix;
    return NULL;
}

static int resolve_game(void) {
    if (!g_image) {
        g_image = find_image("Assembly-CSharp");
        if (!g_image) return 0;
        LOGI("image found");
    }
    void* dv = class_of(g_image, "BattleDebugActionView");
    void* bd = class_of(g_image, "BattleDefine");
    void* mp = class_of(g_image, "BattleMainPanel");
    void* bve = class_of(g_image, "BaseViewExtend");
    void* bpp = class_of(g_image, "BattlePvpProxy");
    void* bp  = class_of(g_image, "BattleProxy");
    void* blp = class_of(g_image, "BattleLevelProxy");
    void* lsc = class_of(g_image, "BattleLockStepCtrl");
    if (!dv || !bd || !mp || !bve || !bpp) return 0;

    g_dv_class = dv;
    g_main_panel_field = x_class_get_field_from_name(bd, "mainPanel");
    g_view_field = x_class_get_field_from_name(mp, "battleDebugActionView");
    g_m_kill_monster = x_class_get_method_from_name(dv, "OnKillMonster", 0);
    g_m_cheat = x_class_get_method_from_name(dv, "OnCheatClick", 0);
    g_m_kill_robot = x_class_get_method_from_name(dv, "OnKillRobotClick", 1);
    g_m_exec_lua = x_class_get_method_from_name(dv, "OnExecuteLuaClick", 0);
    g_m_sp = x_class_get_method_from_name(dv, "OnSpClick", 0);
    g_m_inv = x_class_get_method_from_name(dv, "OnSelfInvulnerableStationClick", 0);
    g_lua_input_field = x_class_get_field_from_name(dv, "luaCodeInput");
    g_bpvp_field = x_class_get_field_from_name(bve, "battlePvpProxy");
    if (bpp) {
        g_m_set_result = x_class_get_method_from_name(bpp, "SetBattleResult", 2);
        g_bproxy_field = x_class_get_field_from_name(bpp, "battleProxy");
        g_round_field = x_class_get_field_from_name(bpp, "round");
    }
    if (bp) g_m_is_pvp = x_class_get_method_from_name(bp, "IsPvp", 0);
    if (bve) g_level_field = x_class_get_field_from_name(bve, "battleLevelProxy");
    if (blp) g_maxround_field = x_class_get_field_from_name(blp, "maxRound");
    if (bve) g_ls_field = x_class_get_field_from_name(bve, "battleLockStepCtrl");
    if (lsc) {
        g_m_set_speed = x_class_get_method_from_name(lsc, "SetSpeedUpRate", 1);
        g_maxframes_field = x_class_get_field_from_name(lsc, "maxLogicFramesPerTick");
    }
    LOGI("resolved: kill=%d cheat=%d win=%d lua=%d speed=%d",
         g_m_kill_monster != NULL, g_m_cheat != NULL, g_m_kill_robot != NULL,
         g_m_exec_lua != NULL, g_m_set_speed != NULL);
    return g_m_kill_monster && g_m_cheat && g_main_panel_field && g_view_field;
}

static void* view(void) {
    if (!g_main_panel_field) return NULL;
    void* panel = NULL;
    x_field_static_get_value(g_main_panel_field, &panel);
    if (!panel) return NULL;
    void* v = NULL;
    x_field_get_value(panel, g_view_field, &v);
    return v;
}

static void invoke0(void* m, void* obj) {
    if (!m || !obj) return;
    void* exc = NULL;
    x_runtime_invoke(m, obj, NULL, &exc);
    if (exc) LOGE("invoke exception");
}

static int is_pvp(void) {
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

static void do_clear(void) {
    invoke0(g_m_kill_monster, view());
}

static void do_win(void) {
    int pvp = is_pvp();
    LOGI("win pvp=%d", pvp);
    if (pvp != 0) {
        void* proxy = NULL;
        x_field_static_get_value(g_bpvp_field, &proxy);
        if (proxy && g_m_set_result) {
            int32_t r = 1;
            uint8_t force = 1;
            void* params[2] = { &r, &force };
            void* exc = NULL;
            x_runtime_invoke(g_m_set_result, proxy, params, &exc);
            if (!exc) return;
        }
    }
    // PVE: 把当前回合设为最后一回合再清场
    if (g_level_field && g_maxround_field && g_round_field && x_field_set_value) {
        void* pp = NULL, *lp = NULL;
        x_field_static_get_value(g_bpvp_field, &pp);
        x_field_static_get_value(g_level_field, &lp);
        if (pp && lp) {
            int32_t cur = 0;
            x_field_get_value(pp, g_round_field, &cur);
            if (cur > 0) x_field_set_value(lp, g_maxround_field, &cur);
        }
    }
    do_clear();
}

static void do_speed(float rate) {
    if (rate < 1) rate = 1;
    if (rate > 10) rate = 10;
    if (!g_ls_field || !g_m_set_speed) return;
    void* ls = NULL;
    x_field_static_get_value(g_ls_field, &ls);
    if (!ls) return;
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
}

// 通过游戏命令台修改属性 / 怪物血量
static int exec_cmd(const char* cmd) {
    void* v = view();
    if (!v || !g_lua_input_field || !g_m_exec_lua || !x_string_new) return 0;
    void* inp = NULL;
    x_field_get_value(v, g_lua_input_field, &inp);
    if (!inp) return 0;
    void* cls = x_object_get_class(inp);
    void* setter = cls ? x_class_get_method_from_name(cls, "set_text", 1) : NULL;
    if (!setter) return 0;
    void* s = x_string_new(cmd);
    void* params[1] = { s };
    void* exc = NULL;
    x_runtime_invoke(setter, inp, params, &exc);
    if (exc) return 0;
    exc = NULL;
    x_runtime_invoke(g_m_exec_lua, v, NULL, &exc);
    return exc == NULL;
}

// ---------------- JNI ----------------
static void* g_java_vm;

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_java_vm = vm;
    return JNI_VERSION_1_6;
}

static int unity_ready(void) {
    DIR* d = opendir("/proc/self/task");
    if (!d) return 0;
    struct dirent* e;
    int ok = 0;
    char path[256], buf[64];
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        snprintf(path, sizeof(path), "/proc/self/task/%s/comm", e->d_name);
        FILE* f = fopen(path, "r");
        if (!f) continue;
        if (fgets(buf, sizeof(buf), f) && strstr(buf, "UnityMain")) ok = 1;
        fclose(f);
        if (ok) break;
    }
    closedir(d);
    return ok;
}

JNIEXPORT jint JNICALL
Java_com_awj_Native_init(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    static time_t g_ready_at = 0;
    if (!unity_ready()) { g_ready_at = 0; return -3; }
    if (g_ready_at == 0) { g_ready_at = time(NULL); LOGI("unity main seen"); }
    if (time(NULL) - g_ready_at < 5) return -4;
    LOGI("resolving api");
    if (!resolve_api()) { LOGE("api resolve failed"); return -1; }
    LOGI("api ok");
    void* dom = x_domain_get();
    if (!dom) { LOGE("domain null"); return -2; }
    LOGI("domain ok");
    if (x_thread_attach) { x_thread_attach(dom); LOGI("thread attached"); }
    int r = resolve_game() ? 1 : 0;
    LOGI("game resolve r=%d", r);
    return r;
}

JNIEXPORT jint JNICALL
Java_com_awj_Native_ready(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    return (g_main_panel_field && g_m_kill_monster) ? 1 : 0;
}

JNIEXPORT void JNICALL
Java_com_awj_Native_clear(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    do_clear();
}

JNIEXPORT void JNICALL
Java_com_awj_Native_cheat(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    invoke0(g_m_cheat, view());
}

JNIEXPORT void JNICALL
Java_com_awj_Native_win(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    do_win();
}

JNIEXPORT void JNICALL
Java_com_awj_Native_speed(JNIEnv* env, jclass cls, jfloat rate) {
    (void)env; (void)cls;
    do_speed(rate);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_sp(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    invoke0(g_m_sp, view());
}

JNIEXPORT void JNICALL
Java_com_awj_Native_inv(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    invoke0(g_m_inv, view());
}

JNIEXPORT void JNICALL
Java_com_awj_Native_stopMove(JNIEnv* env, jclass cls) {
    (void)env; (void)cls;
    exec_cmd("停止怪物移动");
}

JNIEXPORT void JNICALL
Java_com_awj_Native_monsterHp(JNIEnv* env, jclass cls, jint pct) {
    (void)env; (void)cls;
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "设置怪物血量百分比 %d", (int)pct);
    exec_cmd(cmd);
}

JNIEXPORT void JNICALL
Java_com_awj_Native_attr(JNIEnv* env, jclass cls, jstring name, jlong value) {
    if (!name) return;
    const char* n = (*env)->GetStringUTFChars(env, name, NULL);
    if (!n) return;
    char cmd[128];
    snprintf(cmd, sizeof(cmd), "修改英雄属性 %s %lld", n, (long long)value);
    exec_cmd(cmd);
    (*env)->ReleaseStringUTFChars(env, name, n);
}

// ---------------- 无 smali 注入：由 libmain.so 的 DT_NEEDED 自动加载 ----------------
static JavaVM* g_vm;

static int ensure_vm(void) {
    if (g_vm) return 1;
    jint (*getvms)(JavaVM**, jsize, jsize*) = (void*)dlsym(RTLD_DEFAULT, "JNI_GetCreatedJavaVMs");
    if (!getvms) {
        const char* libs[] = {"libart.so", "libnativehelper.so", "libnativebridge.so"};
        for (int i = 0; i < 3 && !getvms; i++) {
            void* h = dlopen(libs[i], RTLD_NOW);
            if (h) getvms = (void*)dlsym(h, "JNI_GetCreatedJavaVMs");
            LOGI("vm lib %s handle=%p sym=%p", libs[i], h, getvms);
        }
    }
    if (!getvms) { LOGE("no JNI_GetCreatedJavaVMs"); return 0; }
    JavaVM* vm = NULL;
    jsize n = 0;
    if (getvms(&vm, 1, &n) != 0 || !vm) { LOGE("no vm yet n=%d", (int)n); return 0; }
    g_vm = vm;
    LOGI("vm acquired");
    return 1;
}

static jobject current_app(JNIEnv* env) {
    jclass at = (*env)->FindClass(env, "android/app/ActivityThread");
    if (!at) return NULL;
    jmethodID m = (*env)->GetStaticMethodID(env, at, "currentApplication", "()Landroid/app/Application;");
    if (!m) return NULL;
    return (*env)->CallStaticObjectMethod(env, at, m);
}

static void* boot_thread(void* arg) {
    (void)arg;
    LOGI("boot thread start");
    for (int i = 0; i < 600; i++) {
        if ((i % 20) == 0) LOGI("boot tick %d", i);
        if (ensure_vm()) {
            JNIEnv* env = NULL;
            if ((*g_vm)->AttachCurrentThread(g_vm, &env, NULL) == JNI_OK && env) {
                jobject app = current_app(env);
                if (app) {
                    jclass ac = (*env)->GetObjectClass(env, app);
                    jmethodID gl = (*env)->GetMethodID(env, ac, "getClassLoader", "()Ljava/lang/ClassLoader;");
                    jobject cl = gl ? (*env)->CallObjectMethod(env, app, gl) : NULL;
                    if (cl) {
                        jclass clc = (*env)->FindClass(env, "java/lang/ClassLoader");
                        jmethodID load = (*env)->GetMethodID(env, clc, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;");
                        jstring nm = (*env)->NewStringUTF(env, "com.awj.Launcher");
                        jclass launcher = load ? (jclass)(*env)->CallObjectMethod(env, cl, load, nm) : NULL;
                        if (launcher) {
                            jmethodID mi = (*env)->GetStaticMethodID(env, launcher, "init", "(Landroid/content/Context;)V");
                            if (mi) {
                                (*env)->CallStaticVoidMethod(env, launcher, mi, app);
                                LOGI("launcher invoked");
                                (*g_vm)->DetachCurrentThread(g_vm);
                                return NULL;
                            }
                        }
                    }
                }
                (*g_vm)->DetachCurrentThread(g_vm);
            }
        }
        usleep(500 * 1000);
    }
    LOGE("boot timeout");
    return NULL;
}

__attribute__((constructor)) static void awj_ctor(void) {
    LOGI("ctor fired");
    pthread_t t;
    if (pthread_create(&t, NULL, boot_thread, NULL) == 0) pthread_detach(t);
    else LOGE("boot thread create failed");
}
